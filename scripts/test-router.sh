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
remote_cmd="mkdir -p /tmp/run/ipregion; ipregion --self-test --json; ipregion --list-services --json >/tmp/run/ipregion/services.json; ipregion --group primary --ipv4 --json >/tmp/run/ipregion/smoke.json"

password_ssh() {
	if command -v sshpass >/dev/null 2>&1; then
		SSHPASS=$OPENWRT_SSH_PASSWORD sshpass -e ssh $ssh_opts -p "$OPENWRT_SSH_PORT" "$ssh_target" "$remote_cmd"
	else
		command -v setsid >/dev/null 2>&1 || { printf '%s\n' 'setsid or sshpass is required when OPENWRT_SSH_PASSWORD is set' >&2; exit 1; }
		DISPLAY=${DISPLAY:-ipregion} SSH_ASKPASS_REQUIRE=force SSH_ASKPASS="$ROOT_DIR/scripts/ssh-askpass.sh" OPENWRT_SSH_PASSWORD=$OPENWRT_SSH_PASSWORD setsid -w ssh $ssh_opts -p "$OPENWRT_SSH_PORT" "$ssh_target" "$remote_cmd"
	fi
}

if [ -n "$OPENWRT_SSH_KEY" ]; then
	ssh $ssh_opts -i "$OPENWRT_SSH_KEY" -p "$OPENWRT_SSH_PORT" "$ssh_target" "$remote_cmd"
elif [ -n "$OPENWRT_SSH_PASSWORD" ]; then
	password_ssh
else
	ssh $ssh_opts -p "$OPENWRT_SSH_PORT" "$ssh_target" "$remote_cmd"
fi

printf 'Router smoke commands completed on %s\n' "$ssh_target"
