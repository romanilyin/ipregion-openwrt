#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
UCODE=${1:-ucode}
UCODE_DIR=$(dirname -- "$UCODE")
PREFIX=$(CDPATH= cd -- "$UCODE_DIR/.." && pwd)
OUT_DIR=${TMPDIR:-/tmp}/ipregion-ucode-checks

mkdir -p "$OUT_DIR"
export LD_LIBRARY_PATH="$PREFIX/lib:${LD_LIBRARY_PATH:-}"

"$UCODE" -c -o "$OUT_DIR/ipregion-core.uc.out" "$ROOT_DIR/ipregion/files/usr/share/ipregion/ipregion.uc"
"$UCODE" -c -o "$OUT_DIR/ipregion-jsonpath.uc.out" "$ROOT_DIR/ipregion/files/usr/share/ipregion/jsonpath.uc"
"$UCODE" -c -o "$OUT_DIR/ipregion-http.uc.out" "$ROOT_DIR/ipregion/files/usr/share/ipregion/http.uc"
"$UCODE" -c -o "$OUT_DIR/ipregion-handlers.uc.out" "$ROOT_DIR/ipregion/files/usr/share/ipregion/handlers.uc"
"$UCODE" -c -o "$OUT_DIR/luci-ipregion-rpcd.uc.out" "$ROOT_DIR/luci-app-ipregion/root/usr/share/rpcd/ucode/ipregion.uc"

"$UCODE" "$ROOT_DIR/ipregion/files/usr/share/ipregion/ipregion.uc" --help >/dev/null
IPREGION_CATALOG_PATH="$ROOT_DIR/ipregion/files/usr/share/ipregion/services.json" \
IPREGION_RUNTIME_DIR="$OUT_DIR/runtime" \
	"$UCODE" "$ROOT_DIR/ipregion/files/usr/share/ipregion/ipregion.uc" --no-uci --list-services --json >/dev/null

"$UCODE" "$ROOT_DIR/ipregion/files/usr/share/ipregion/http.uc" >/dev/null
"$UCODE" "$ROOT_DIR/ipregion/files/usr/share/ipregion/handlers.uc" >/dev/null
"$UCODE" "$ROOT_DIR/ipregion/files/usr/share/ipregion/jsonpath.uc" >/dev/null
"$UCODE" "$ROOT_DIR/luci-app-ipregion/root/usr/share/rpcd/ucode/ipregion.uc" >/dev/null

printf 'ucode checks OK\n'
