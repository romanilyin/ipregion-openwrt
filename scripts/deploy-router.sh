#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if [ -f "$ROOT_DIR/.env" ]; then
	. "$ROOT_DIR/.env"
fi

: "${OPENWRT_HOST:=192.168.2.1}"
: "${OPENWRT_USER:=root}"
: "${OPENWRT_SSH_PORT:=22}"
: "${OPENWRT_SSH_KEY:=}"
: "${OPENWRT_SSH_PASSWORD:=}"

ssh_target="$OPENWRT_USER@$OPENWRT_HOST"
ssh_opts="-o BatchMode=no -o NumberOfPasswordPrompts=1 -o StrictHostKeyChecking=accept-new"
scp_opts="-O $ssh_opts"

password_ssh() {
	if command -v sshpass >/dev/null 2>&1; then
		SSHPASS=$OPENWRT_SSH_PASSWORD sshpass -e ssh $ssh_opts -p "$OPENWRT_SSH_PORT" "$ssh_target" "$@"
	else
		command -v setsid >/dev/null 2>&1 || { printf '%s\n' 'setsid or sshpass is required when OPENWRT_SSH_PASSWORD is set' >&2; exit 1; }
		DISPLAY=${DISPLAY:-ipregion} SSH_ASKPASS_REQUIRE=force SSH_ASKPASS="$ROOT_DIR/scripts/ssh-askpass.sh" OPENWRT_SSH_PASSWORD=$OPENWRT_SSH_PASSWORD setsid -w ssh $ssh_opts -p "$OPENWRT_SSH_PORT" "$ssh_target" "$@"
	fi
}

password_scp() {
	if command -v sshpass >/dev/null 2>&1; then
		SSHPASS=$OPENWRT_SSH_PASSWORD sshpass -e scp $scp_opts -P "$OPENWRT_SSH_PORT" "$1" "$ssh_target:$2"
	else
		command -v setsid >/dev/null 2>&1 || { printf '%s\n' 'setsid or sshpass is required when OPENWRT_SSH_PASSWORD is set' >&2; exit 1; }
		DISPLAY=${DISPLAY:-ipregion} SSH_ASKPASS_REQUIRE=force SSH_ASKPASS="$ROOT_DIR/scripts/ssh-askpass.sh" OPENWRT_SSH_PASSWORD=$OPENWRT_SSH_PASSWORD setsid -w scp $scp_opts -P "$OPENWRT_SSH_PORT" "$1" "$ssh_target:$2"
	fi
}

ssh_run() {
	if [ -n "$OPENWRT_SSH_KEY" ]; then
		ssh $ssh_opts -i "$OPENWRT_SSH_KEY" -p "$OPENWRT_SSH_PORT" "$ssh_target" "$@"
	elif [ -n "$OPENWRT_SSH_PASSWORD" ]; then
		password_ssh "$@"
	else
		ssh $ssh_opts -p "$OPENWRT_SSH_PORT" "$ssh_target" "$@"
	fi
}

scp_to() {
	if [ -n "$OPENWRT_SSH_KEY" ]; then
		scp $scp_opts -i "$OPENWRT_SSH_KEY" -P "$OPENWRT_SSH_PORT" "$1" "$ssh_target:$2"
	elif [ -n "$OPENWRT_SSH_PASSWORD" ]; then
		password_scp "$1" "$2"
	else
		scp $ssh_opts -P "$OPENWRT_SSH_PORT" "$1" "$ssh_target:$2"
	fi
}

ssh_run "mkdir -p /usr/share/ipregion /tmp/run/ipregion /usr/share/rpcd/acl.d /usr/share/rpcd/ucode /usr/share/luci/menu.d /www/luci-static/resources/view/ipregion /www/luci-static/resources/ipregion"
ssh_run "rm -f /usr/share/rpcd/ucode/luci.ipregion.uc"
ssh_run "rm -f /www/luci-static/resources/view/ipregion/ai.js"

scp_to "$ROOT_DIR/ipregion/files/usr/bin/ipregion" "/usr/bin/ipregion"
scp_to "$ROOT_DIR/ipregion/files/usr/share/ipregion/ipregion.uc" "/usr/share/ipregion/ipregion.uc"
scp_to "$ROOT_DIR/ipregion/files/usr/share/ipregion/http.uc" "/usr/share/ipregion/http.uc"
scp_to "$ROOT_DIR/ipregion/files/usr/share/ipregion/handlers.uc" "/usr/share/ipregion/handlers.uc"
scp_to "$ROOT_DIR/ipregion/files/usr/share/ipregion/jsonpath.uc" "/usr/share/ipregion/jsonpath.uc"
scp_to "$ROOT_DIR/ipregion/files/usr/share/ipregion/services.json" "/usr/share/ipregion/services.json"
scp_to "$ROOT_DIR/ipregion/files/usr/share/ipregion/services-ai.json" "/usr/share/ipregion/services-ai.json"
scp_to "$ROOT_DIR/ipregion/files/etc/config/ipregion" "/etc/config/ipregion"
scp_to "$ROOT_DIR/luci-app-ipregion/root/usr/share/rpcd/acl.d/luci-app-ipregion.json" "/usr/share/rpcd/acl.d/luci-app-ipregion.json"
scp_to "$ROOT_DIR/luci-app-ipregion/root/usr/share/rpcd/ucode/ipregion.uc" "/usr/share/rpcd/ucode/ipregion.uc"
scp_to "$ROOT_DIR/luci-app-ipregion/root/usr/share/luci/menu.d/luci-app-ipregion.json" "/usr/share/luci/menu.d/luci-app-ipregion.json"
scp_to "$ROOT_DIR/luci-app-ipregion/htdocs/luci-static/resources/view/ipregion/status.js" "/www/luci-static/resources/view/ipregion/status.js"
scp_to "$ROOT_DIR/luci-app-ipregion/htdocs/luci-static/resources/view/ipregion/settings.js" "/www/luci-static/resources/view/ipregion/settings.js"
scp_to "$ROOT_DIR/luci-app-ipregion/htdocs/luci-static/resources/ipregion/ipregion.css" "/www/luci-static/resources/ipregion/ipregion.css"

if [ -f "$ROOT_DIR/luci-app-ipregion/htdocs/luci-static/resources/ipregion/logo.png" ]; then
	scp_to "$ROOT_DIR/luci-app-ipregion/htdocs/luci-static/resources/ipregion/logo.png" "/www/luci-static/resources/ipregion/logo.png"
fi

ssh_run "chmod +x /usr/bin/ipregion; /etc/init.d/rpcd restart 2>/dev/null || true"

printf 'Deployed IPRegion files to %s\n' "$ssh_target"
