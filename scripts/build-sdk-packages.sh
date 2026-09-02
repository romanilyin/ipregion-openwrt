#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

: "${OPENWRT_VERSION:=25.12.4}"
if [ -z "${OPENWRT_GCC_VERSION+x}" ]; then
	case "$OPENWRT_VERSION" in
		24.10.*) OPENWRT_GCC_VERSION=13.3.0 ;;
		*) OPENWRT_GCC_VERSION=14.3.0 ;;
	esac
fi
: "${OPENWRT_DOWNLOAD_BASE:=https://downloads.openwrt.org/releases}"
: "${OPENWRT_SDK_WORKDIR:=/tmp/opencode/openwrt-sdk-builds}"
: "${IPREGION_FEEDS_UPDATE:=1}"
: "${IPREGION_SKIP_PREREQ:=0}"

target=${1:-${OPENWRT_TARGET:-mediatek/filogic}}
target_slug=$(printf '%s' "$target" | tr '/' '-')
sdk_name="openwrt-sdk-${OPENWRT_VERSION}-${target_slug}_gcc-${OPENWRT_GCC_VERSION}_musl.Linux-x86_64"
archive="${OPENWRT_SDK_WORKDIR}/${sdk_name}.tar.zst"
sdk_dir="${OPENWRT_SDK_WORKDIR}/${sdk_name}"
url="${OPENWRT_DOWNLOAD_BASE}/${OPENWRT_VERSION}/targets/${target}/${sdk_name}.tar.zst"

download() {
	if command -v wget >/dev/null 2>&1; then
		wget -O "$archive.tmp" "$url"
	elif command -v curl >/dev/null 2>&1; then
		curl -fL -o "$archive.tmp" "$url"
	else
		printf '%s\n' 'wget or curl is required to download the OpenWrt SDK' >&2
		exit 1
	fi
	mv "$archive.tmp" "$archive"
}

zstd_command() {
	if command -v zstd >/dev/null 2>&1; then
		command -v zstd
	elif [ -x /tmp/opencode/zstd-src/programs/zstd ]; then
		printf '%s\n' /tmp/opencode/zstd-src/programs/zstd
	else
		return 1
	fi
}

skip_prereq_stamps() {
	mkdir -p staging_dir/host
	touch staging_dir/host/.prereq-build
	for target_dir in staging_dir/target-*; do
		[ -d "$target_dir" ] || continue
		mkdir -p "$target_dir/stamp"
		touch "$target_dir/stamp/.package_prereq"
	done
}

mkdir -p "$OPENWRT_SDK_WORKDIR"

if [ ! -f "$archive" ]; then
	printf 'Downloading %s\n' "$url"
	download
fi

if [ ! -d "$sdk_dir" ]; then
	printf 'Extracting %s\n' "$archive"
	if zstd_bin=$(zstd_command); then
		tar --use-compress-program="$zstd_bin -d" -xf "$archive" -C "$OPENWRT_SDK_WORKDIR"
	else
		tar -xf "$archive" -C "$OPENWRT_SDK_WORKDIR"
	fi
fi

if [ ! -d "$sdk_dir" ]; then
	printf 'SDK directory was not found after extraction: %s\n' "$sdk_dir" >&2
	exit 1
fi

cd "$sdk_dir"
PATH="$sdk_dir/staging_dir/hostpkg/bin:$PATH"
export PATH
ln -sfn "$ROOT_DIR" package/ipregion-openwrt

if [ "$IPREGION_FEEDS_UPDATE" = 1 ]; then
	./scripts/feeds update -a
	./scripts/feeds install -a
fi

if [ "$IPREGION_SKIP_PREREQ" = 1 ]; then
	skip_prereq_stamps
fi

cat > .config <<'EOF'
CONFIG_HAVE_DOT_CONFIG=y
# CONFIG_ALL is not set
# CONFIG_ALL_NONSHARED is not set
# CONFIG_ALL_KMODS is not set
CONFIG_PACKAGE_ipregion=m
CONFIG_PACKAGE_luci-app-ipregion=m
CONFIG_LUCI_LANG_ru=y
EOF

make defconfig
if [ "$IPREGION_SKIP_PREREQ" = 1 ]; then
	skip_prereq_stamps
fi
make package/ipregion/clean V=s
make package/ipregion/compile V=s
make package/luci-app-ipregion/clean V=s
make package/luci-app-ipregion/compile V=s

printf 'Built packages for %s:\n' "$target"
ls -1 bin/packages/*/base/*ipregion*.apk 2>/dev/null || true
ls -1 bin/packages/*/base/*ipregion*.ipk 2>/dev/null || true

latest_package() {
	latest=
	for package in "$@"; do
		[ -f "$package" ] || continue
		if [ -z "$latest" ] || [ "$package" -nt "$latest" ]; then
			latest=$package
		fi
	done
	[ -n "$latest" ] || { printf 'Expected package was not built\n' >&2; return 1; }
	printf '%s\n' "$latest"
}

copy_common_package() {
	package=$1
	alias=$2
	name=${package##*/}
	cp "$package" "$IPREGION_ARTIFACT_DIR/$name"
	cp "$package" "$IPREGION_ARTIFACT_DIR/$alias.apk"
}

if [ -n "${IPREGION_ARTIFACT_DIR:-}" ]; then
	mkdir -p "$IPREGION_ARTIFACT_DIR"
	core_package=$(latest_package bin/packages/*/base/ipregion-[0-9]*.apk)
	helper_package=$(latest_package bin/packages/*/base/ipregion-dns-helper-[0-9]*.apk)
	luci_package=$(latest_package bin/packages/*/base/luci-app-ipregion-[0-9]*.apk)
	i18n_package=$(latest_package bin/packages/*/base/luci-i18n-ipregion-ru-[0-9]*.apk)

	copy_common_package "$core_package" ipregion
	copy_common_package "$luci_package" luci-app-ipregion
	copy_common_package "$i18n_package" luci-i18n-ipregion-ru

	helper_name=${helper_package##*/}
	helper_root=${helper_package%/base/*}
	helper_arch=${helper_root##*/}
	case "$helper_arch" in
		''|*[!A-Za-z0-9._-]*) printf 'Invalid helper package architecture: %s\n' "$helper_arch" >&2; exit 1 ;;
	esac
	helper_version=${helper_name#ipregion-dns-helper-}
	cp "$helper_package" "$IPREGION_ARTIFACT_DIR/ipregion-dns-helper-$helper_arch.apk"
	cp "$helper_package" "$IPREGION_ARTIFACT_DIR/ipregion-dns-helper-$helper_arch-$helper_version"
fi
