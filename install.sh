#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu

REPO=${IPREGION_REPO:-romanilyin/ipregion-openwrt}
RELEASE=${IPREGION_RELEASE:-latest}
INSTALL_LUCI=${IPREGION_INSTALL_LUCI:-1}
APK_UPDATE=${IPREGION_APK_UPDATE:-1}
APK_FLAGS=${IPREGION_APK_FLAGS:---allow-untrusted}
GITHUB_API=${IPREGION_GITHUB_API:-https://api.github.com}
GITHUB_DOWNLOAD_BASE=${IPREGION_GITHUB_DOWNLOAD_BASE:-https://github.com}
DOWNLOAD_RETRIES=${IPREGION_DOWNLOAD_RETRIES:-3}
DOWNLOAD_RETRY_DELAY=${IPREGION_DOWNLOAD_RETRY_DELAY:-2}
TMP_DIR=${TMPDIR:-/tmp}/ipregion-install.$$
RELEASE_JSON=$TMP_DIR/release.json
DOWNLOAD_ERR=$TMP_DIR/download.err

GITHUB_API=${GITHUB_API%/}
GITHUB_DOWNLOAD_BASE=${GITHUB_DOWNLOAD_BASE%/}

log() {
	printf '%s\n' "ipregion-install: $*"
}

die() {
	printf '%s\n' "ipregion-install: error: $*" >&2
	exit 1
}

cleanup() {
	rm -rf "$TMP_DIR"
}

trap cleanup EXIT HUP INT TERM

need_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

is_luci_enabled() {
	case "$INSTALL_LUCI" in
		0|false|FALSE|no|NO) return 1 ;;
		*) return 0 ;;
	esac
}

version_ge() {
	left=$1
	right=$2

	old_ifs=$IFS
	IFS=.
	set -- $left
	l1=${1:-0}; l2=${2:-0}; l3=${3:-0}
	set -- $right
	r1=${1:-0}; r2=${2:-0}; r3=${3:-0}
	IFS=$old_ifs

	[ "$l1" -gt "$r1" ] && return 0
	[ "$l1" -lt "$r1" ] && return 1
	[ "$l2" -gt "$r2" ] && return 0
	[ "$l2" -lt "$r2" ] && return 1
	[ "$l3" -ge "$r3" ]
}

check_target() {
	need_cmd id
	need_cmd sed
	need_cmd awk
	[ "$(id -u)" = 0 ] || die "run this script as root on the router"
	need_cmd apk

	if [ -r /etc/openwrt_release ]; then
		release=$(sed -n "s/^DISTRIB_RELEASE='\([^']*\)'.*/\1/p" /etc/openwrt_release | sed 's/-.*$//' || true)
		case "$release" in
			''|SNAPSHOT) ;;
			*[!0-9.]*) log "warning: could not parse OpenWrt release; expected 24.10.0+ with apk" ;;
			*)
				version_ge "$release" 24.10.0 || die "OpenWrt $release is unsupported; expected 24.10.0+ with apk"
				case "$release" in
					24.10.*) log "warning: OpenWrt 24.10 support is experimental until router smoke validation" ;;
				esac
				;;
		esac
	else
		log "warning: /etc/openwrt_release not found; continuing because apk is available"
	fi
}

validate_inputs() {
	case "$DOWNLOAD_RETRIES" in
		''|*[!0-9]*) DOWNLOAD_RETRIES=3 ;;
	esac

	case "$DOWNLOAD_RETRY_DELAY" in
		''|*[!0-9]*) DOWNLOAD_RETRY_DELAY=2 ;;
	esac

	[ "$DOWNLOAD_RETRIES" -ge 1 ] || DOWNLOAD_RETRIES=1

	case "$REPO" in
		*/*) ;;
		*) die "IPREGION_REPO must look like owner/repo" ;;
	esac

	case "$REPO" in
		*[!A-Za-z0-9._/-]*) die "IPREGION_REPO contains unsupported characters" ;;
	esac

	case "$RELEASE" in
		*[!A-Za-z0-9._-]*) die "IPREGION_RELEASE contains unsupported characters" ;;
	esac

	case "$GITHUB_API" in
		http://*|https://*) ;;
		*) die "IPREGION_GITHUB_API must start with http:// or https://" ;;
	esac

	case "$GITHUB_DOWNLOAD_BASE" in
		http://*|https://*) ;;
		*) die "IPREGION_GITHUB_DOWNLOAD_BASE must start with http:// or https://" ;;
	esac
}

select_downloader() {
	if command -v wget >/dev/null 2>&1; then
		DOWNLOADER=wget
	elif command -v uclient-fetch >/dev/null 2>&1; then
		DOWNLOADER=uclient-fetch
	else
		die "missing downloader: install wget or uclient-fetch"
	fi
}

download_once() {
	url=$1
	out=$2
	rm -f "$DOWNLOAD_ERR"

	case "$DOWNLOADER" in
		wget) wget -q -O "$out" "$url" 2>"$DOWNLOAD_ERR" ;;
		uclient-fetch) uclient-fetch -q -O "$out" "$url" 2>"$DOWNLOAD_ERR" ;;
		*) die "internal downloader error" ;;
	esac
}

download_error() {
	sed -n '1p' "$DOWNLOAD_ERR" 2>/dev/null || true
}

download() {
	url=$1
	out=$2
	label=$3
	attempt=1

	rm -f "$out"
	while [ "$attempt" -le "$DOWNLOAD_RETRIES" ]; do
		if [ "$DOWNLOAD_RETRIES" -gt 1 ]; then
			log "downloading $label (attempt $attempt/$DOWNLOAD_RETRIES)"
		fi

		if download_once "$url" "$out"; then
			return 0
		fi

		err=$(download_error)
		if [ -n "$err" ]; then
			log "download failed for $label: $err"
		else
			log "download failed for $label"
		fi

		rm -f "$out"
		if [ "$attempt" -lt "$DOWNLOAD_RETRIES" ] && [ "$DOWNLOAD_RETRY_DELAY" -gt 0 ]; then
			sleep "$DOWNLOAD_RETRY_DELAY"
		fi
		attempt=$((attempt + 1))
	done

	return 1
}

release_api_url() {
	if [ "$RELEASE" = latest ]; then
		printf '%s/repos/%s/releases/latest\n' "$GITHUB_API" "$REPO"
	else
		printf '%s/repos/%s/releases/tags/%s\n' "$GITHUB_API" "$REPO" "$RELEASE"
	fi
}

direct_release_asset_url() {
	pkg=$1

	if [ "$RELEASE" = latest ]; then
		printf '%s/%s/releases/latest/download/%s.apk\n' "$GITHUB_DOWNLOAD_BASE" "$REPO" "$pkg"
	else
		printf '%s/%s/releases/download/%s/%s.apk\n' "$GITHUB_DOWNLOAD_BASE" "$REPO" "$RELEASE" "$pkg"
	fi
}

metadata_has_assets() {
	awk '/"browser_download_url"[[:space:]]*:/ { found = 1 } END { exit found ? 0 : 1 }' "$RELEASE_JSON"
}

metadata_error_message() {
	awk '
		match($0, /"message"[[:space:]]*:[[:space:]]*"[^"]*"/) {
			msg = substr($0, RSTART, RLENGTH)
			sub(/^"message"[[:space:]]*:[[:space:]]*"/, "", msg)
			sub(/"$/, "", msg)
			print msg
			exit
		}
	' "$RELEASE_JSON"
}

remove_downloaded_packages() {
	rm -f "$TMP_DIR/ipregion.apk" "$TMP_DIR/luci-app-ipregion.apk" "$TMP_DIR/luci-i18n-ipregion-ru.apk"
}

asset_url_for() {
	pkg=$1
	awk -v pkg="$pkg" '
		function basename(url, name) {
			name = url
			sub(/[?#].*$/, "", name)
			sub(/^.*\//, "", name)
			return name
		}
		function wanted(name) {
			return name == pkg ".apk" || name ~ ("^" pkg "[-_].*\\.apk$")
		}
		function consider(url, name) {
			gsub(/\\\//, "/", url)
			name = basename(url)
			if (name == pkg ".apk") {
				print url
				found = 1
				exit
			}
			if (fallback == "" && wanted(name))
				fallback = url
		}
		{
			line = $0
			while (match(line, /"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
				url = substr(line, RSTART, RLENGTH)
				sub(/^"browser_download_url"[[:space:]]*:[[:space:]]*"/, "", url)
				sub(/"$/, "", url)
				consider(url)
				line = substr(line, RSTART + RLENGTH)
			}
		}
		END {
			if (!found && fallback != "")
				print fallback
		}
	' "$RELEASE_JSON"
}

fetch_release_metadata() {
	url=$(release_api_url)
	log "reading release metadata from $url"
	download "$url" "$RELEASE_JSON" "GitHub release metadata" || return 1

	if ! metadata_has_assets; then
		message=$(metadata_error_message)
		if [ -n "$message" ]; then
			log "GitHub API response: $message"
		else
			log "GitHub API response did not contain release assets"
		fi
		return 1
	fi
}

fetch_package() {
	pkg=$1
	out=$TMP_DIR/$pkg.apk
	url=$(asset_url_for "$pkg")
	[ -n "$url" ] || { log "release asset not found in metadata: $pkg*.apk"; return 1; }

	log "downloading $pkg"
	download "$url" "$out" "$pkg" || return 1
	[ -s "$out" ] || { log "downloaded empty package: $pkg"; return 1; }
}

fetch_direct_package() {
	pkg=$1
	out=$TMP_DIR/$pkg.apk
	url=$(direct_release_asset_url "$pkg")

	log "downloading $pkg from direct release asset"
	download "$url" "$out" "$pkg direct release asset" || return 1
	[ -s "$out" ] || { log "downloaded empty package: $pkg"; return 1; }
}

fetch_metadata_packages() {
	fetch_release_metadata || return 1
	fetch_package ipregion || return 1
	if is_luci_enabled; then
		fetch_package luci-app-ipregion || return 1
		fetch_package luci-i18n-ipregion-ru || return 1
	fi
}

fetch_direct_packages() {
	fetch_direct_package ipregion || return 1
	if is_luci_enabled; then
		fetch_direct_package luci-app-ipregion || return 1
		fetch_direct_package luci-i18n-ipregion-ru || return 1
	fi
}

probe_url() {
	label=$1
	url=$2

	if download_once "$url" /dev/null; then
		log "$label reachable"
	else
		err=$(download_error)
		if [ -n "$err" ]; then
			log "$label not reachable: $err"
		else
			log "$label not reachable"
		fi
	fi
}

diagnose_github_access() {
	log "checking GitHub connectivity from this router"
	probe_url "GitHub release page" "$GITHUB_DOWNLOAD_BASE/$REPO/releases"
	probe_url "GitHub API" "$GITHUB_API"
	probe_url "GitHub raw content" "https://raw.githubusercontent.com/$REPO/main/install.sh"
	log "if GitHub is blocked or rate-limited, retry later or install downloaded APK files manually"
}

install_packages() {
	if [ "$APK_UPDATE" = 1 ]; then
		log "updating apk repositories"
		apk update
	fi

	if is_luci_enabled; then
		log "installing ipregion, luci-app-ipregion and Russian translation"
		apk add $APK_FLAGS "$TMP_DIR/ipregion.apk" "$TMP_DIR/luci-app-ipregion.apk" "$TMP_DIR/luci-i18n-ipregion-ru.apk"
	else
		log "installing ipregion"
		apk add $APK_FLAGS "$TMP_DIR/ipregion.apk"
	fi
}

post_install() {
	if command -v ipregion >/dev/null 2>&1; then
		ipregion --help >/dev/null || die "ipregion command was installed but did not start"
	fi

	if is_luci_enabled && [ -x /etc/init.d/rpcd ]; then
		log "restarting rpcd"
		/etc/init.d/rpcd restart || log "warning: rpcd restart failed"
	fi

	if is_luci_enabled && [ -x /etc/init.d/uhttpd ]; then
		log "reloading uhttpd"
		/etc/init.d/uhttpd reload >/dev/null 2>&1 || true
	fi

	log "installed successfully"
	log "run 'ipregion --self-test --json' to verify router connectivity"
}

mkdir -p "$TMP_DIR"
check_target
validate_inputs
select_downloader
if ! fetch_metadata_packages; then
	log "GitHub release metadata path failed; trying direct release asset URLs"
	remove_downloaded_packages
	if ! fetch_direct_packages; then
		diagnose_github_access
		die "failed to download GitHub release assets"
	fi
fi
install_packages
post_install
