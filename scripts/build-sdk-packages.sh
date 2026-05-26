#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

: "${OPENWRT_VERSION:=25.12.4}"
: "${OPENWRT_GCC_VERSION:=14.3.0}"
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
CONFIG_PACKAGE_ipregion=m
CONFIG_PACKAGE_luci-app-ipregion=m
CONFIG_PACKAGE_luci-i18n-ipregion-ru=m
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
