#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu

PREFIX=${1:-/tmp/ipregion-ucode-install}
WORK_DIR=${UCODE_BUILD_DIR:-/tmp/ipregion-ucode-build}
JOBS=${JOBS:-2}
CMAKE=${CMAKE:-cmake}

for tool in git make "$CMAKE"; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		printf 'missing required build tool: %s\n' "$tool" >&2
		exit 1
	fi
done

rm -rf "$WORK_DIR" "$PREFIX"
mkdir -p "$WORK_DIR" "$PREFIX"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig:${PKG_CONFIG_PATH:-}"

git clone --depth 1 https://github.com/openwrt/libubox.git "$WORK_DIR/libubox"
git clone --depth 1 https://github.com/openwrt/uci.git "$WORK_DIR/uci"
git clone --depth 1 https://github.com/jow-/ucode.git "$WORK_DIR/ucode"

"$CMAKE" -S "$WORK_DIR/libubox" -B "$WORK_DIR/libubox-build" \
	-DCMAKE_INSTALL_PREFIX="$PREFIX" \
	-DBUILD_EXAMPLES=OFF \
	-DBUILD_LUA=OFF
make -C "$WORK_DIR/libubox-build" -j"$JOBS" install

LD_LIBRARY_PATH="$PREFIX/lib:${LD_LIBRARY_PATH:-}" "$CMAKE" -S "$WORK_DIR/uci" -B "$WORK_DIR/uci-build" \
	-DCMAKE_INSTALL_PREFIX="$PREFIX" \
	-DCMAKE_PREFIX_PATH="$PREFIX" \
	-DCMAKE_LIBRARY_PATH="$PREFIX/lib" \
	-DCMAKE_INCLUDE_PATH="$PREFIX/include" \
	-DBUILD_LUA=OFF
LD_LIBRARY_PATH="$PREFIX/lib:${LD_LIBRARY_PATH:-}" make -C "$WORK_DIR/uci-build" -j"$JOBS" install

LD_LIBRARY_PATH="$PREFIX/lib:${LD_LIBRARY_PATH:-}" "$CMAKE" -S "$WORK_DIR/ucode" -B "$WORK_DIR/ucode-build" \
	-DCMAKE_INSTALL_PREFIX="$PREFIX" \
	-DCMAKE_PREFIX_PATH="$PREFIX" \
	-DCMAKE_LIBRARY_PATH="$PREFIX/lib" \
	-DCMAKE_INCLUDE_PATH="$PREFIX/include" \
	-DUBUS_SUPPORT=OFF \
	-DUCI_SUPPORT=ON \
	-DULOOP_SUPPORT=OFF \
	-DRTNL_SUPPORT=OFF \
	-DNL80211_SUPPORT=OFF
LD_LIBRARY_PATH="$PREFIX/lib:${LD_LIBRARY_PATH:-}" make -C "$WORK_DIR/ucode-build" -j"$JOBS" install

printf '%s\n' "$PREFIX/bin/ucode"
