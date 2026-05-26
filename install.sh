#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu

REPO=${IPREGION_REPO:-romanilyin/ipregion-openwrt}
RELEASE=${IPREGION_RELEASE:-latest}
INSTALL_LUCI=${IPREGION_INSTALL_LUCI:-1}
APK_UPDATE=${IPREGION_APK_UPDATE:-1}
APK_FLAGS=${IPREGION_APK_FLAGS:---allow-untrusted}
GITHUB_API=${IPREGION_GITHUB_API:-https://api.github.com}
TMP_DIR=${TMPDIR:-/tmp}/ipregion-install.$$
RELEASE_JSON=$TMP_DIR/release.json

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
			*[!0-9.]*) log "warning: could not parse OpenWrt release; expected 25.12.4+" ;;
			*) version_ge "$release" 25.12.4 || die "OpenWrt $release is unsupported; expected 25.12.4+" ;;
		esac
	else
		log "warning: /etc/openwrt_release not found; continuing because apk is available"
	fi
}

validate_inputs() {
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

download() {
	url=$1
	out=$2

	case "$DOWNLOADER" in
		wget) wget -q -O "$out" "$url" ;;
		uclient-fetch) uclient-fetch -q -O "$out" "$url" ;;
		*) die "internal downloader error" ;;
	esac
}

release_api_url() {
	if [ "$RELEASE" = latest ]; then
		printf '%s/repos/%s/releases/latest\n' "$GITHUB_API" "$REPO"
	else
		printf '%s/repos/%s/releases/tags/%s\n' "$GITHUB_API" "$REPO" "$RELEASE"
	fi
}

asset_url_for() {
	pkg=$1
	awk -v pkg="$pkg" '
		function basename(url, name) {
			name = url
			sub(/^.*\//, "", name)
			return name
		}
		function wanted(name) {
			return name == pkg ".apk" || name ~ ("^" pkg "[-_].*\\.apk$")
		}
		/"browser_download_url"/ {
			gsub(/[",]/, "")
			for (i = 1; i <= NF; i++) {
				if ($i ~ /^https:\/\//) {
					url = $i
					name = basename(url)
					if (name == pkg ".apk") {
						print url
						found = 1
						exit
					}
					if (fallback == "" && wanted(name))
						fallback = url
				}
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
	download "$url" "$RELEASE_JSON" || die "failed to read GitHub release metadata"
}

fetch_package() {
	pkg=$1
	out=$TMP_DIR/$pkg.apk
	url=$(asset_url_for "$pkg")
	[ -n "$url" ] || die "release asset not found: $pkg*.apk"

	log "downloading $pkg"
	download "$url" "$out" || die "failed to download $pkg"
	[ -s "$out" ] || die "downloaded empty package: $pkg"
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
fetch_release_metadata
fetch_package ipregion
if is_luci_enabled; then
	fetch_package luci-app-ipregion
	fetch_package luci-i18n-ipregion-ru
fi
install_packages
post_install
