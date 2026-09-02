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

FAKE_BIN="$OUT_DIR/fake-bin"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/curl" <<'EOF'
#!/bin/sh
url=''
for arg in "$@"; do
	case "$arg" in
		https://*) url=$arg ;;
	esac
done

if [ -n "${IPREGION_FAKE_CURL_LOG:-}" ]; then
	printf '%s\n' "$*" >>"$IPREGION_FAKE_CURL_LOG"
fi

ai_response() {
	code=$1
	status=$2
	body=$3
	printf 'HTTP/1.1 %s %s\r\ncontent-type: application/json\r\n\r\n%s\n__IPREGION_HTTP_CODE:%s\n__IPREGION_REMOTE_IP:203.0.113.11\n__IPREGION_TIME_NAMELOOKUP:0.001\n__IPREGION_TIME_CONNECT:0.002\n__IPREGION_TIME_APPCONNECT:0.003\n__IPREGION_TIME_TOTAL:0.010' "$code" "$status" "$body" "$code"
}

case "$url" in
	https://api64.ipify.org|https://ifconfig.co/ip|https://ifconfig.me|https://ident.me)
		printf '203.0.113.42\n__IPREGION_HTTP_CODE:200\n__IPREGION_TIME_TOTAL:0.010'
		;;
	https://geoip.maxmind.com/geoip/v2.1/city/me)
		printf '{"country":{"iso_code":"DE"}}\n__IPREGION_HTTP_CODE:200\n__IPREGION_TIME_TOTAL:0.010'
		;;
	https://gemini.google.com/app)
		case "${IPREGION_FAKE_GEMINI:-ok}" in
			web_blocked) ai_response 200 OK 'Gemini is not available in your country' ;;
			web_auth) ai_response 401 Unauthorized 'Sign in required' ;;
			web_rate) ai_response 429 TooManyRequests 'Gemini is not available in your country due to rate limits' ;;
			web_server) ai_response 500 ServerError 'Gemini is not available in your country due to server maintenance' ;;
			*) ai_response 200 OK 'Gemini' ;;
		esac
		;;
	https://generativelanguage.googleapis.com/v1beta/models)
		case "${IPREGION_FAKE_GEMINI:-auth}" in
			timeout)
				printf '\n__IPREGION_HTTP_CODE:0\n__IPREGION_REMOTE_IP:\n__IPREGION_TIME_NAMELOOKUP:0.001\n__IPREGION_TIME_CONNECT:0.000\n__IPREGION_TIME_APPCONNECT:0.000\n__IPREGION_TIME_TOTAL:5.000'
				exit 28
				;;
			partial_timeout)
				ai_response 200 OK 'partial response'
				exit 28
				;;
			invalid_key)
				ai_response 400 BadRequest '{"error":{"status":"INVALID_ARGUMENT","message":"API key not valid"}}'
				;;
			region)
				ai_response 400 BadRequest '{"error":{"status":"FAILED_PRECONDITION","message":"User location is not supported for the API use"}}'
				;;
			rate)
				ai_response 429 TooManyRequests '{"error":{"message":"API key quota exceeded"}}'
				;;
			server)
				ai_response 500 ServerError '{"error":{"message":"API key service unavailable"}}'
				;;
			*)
				ai_response 403 Forbidden '{"error":{"message":"Method does not allow unregistered callers. Please use API key."}}'
				;;
		esac
		;;
	*)
		printf '\n__IPREGION_HTTP_CODE:0\n__IPREGION_TIME_TOTAL:0.001'
		exit 6
		;;
esac
EOF
chmod 0755 "$FAKE_BIN/curl"

expect_failure() {
	if "$@" >/dev/null 2>&1; then
		printf 'expected command to fail: %s\n' "$*" >&2
		exit 1
	fi
}

run_fake_ai() {
	provider=$1
	mode=$2
	name=$3
	PATH="$FAKE_BIN:$PATH" \
	IPREGION_FAKE_GEMINI="$mode" \
	IPREGION_CATALOG_PATH="$ROOT_DIR/ipregion/files/usr/share/ipregion/services.json" \
	IPREGION_AI_CATALOG_PATH="$ROOT_DIR/ipregion/files/usr/share/ipregion/services-ai.json" \
	IPREGION_RUNTIME_DIR="$OUT_DIR/runtime-$name" \
		"$UCODE" "$ROOT_DIR/ipregion/files/usr/share/ipregion/ipregion.uc" ai --no-uci --provider "$provider" --ip-mode ipv4 --retries 0 --json >"$OUT_DIR/$name.json"
}

"$UCODE" -c -o "$OUT_DIR/ipregion-core.uc.out" "$ROOT_DIR/ipregion/files/usr/share/ipregion/ipregion.uc"
"$UCODE" -c -o "$OUT_DIR/ipregion-jsonpath.uc.out" "$ROOT_DIR/ipregion/files/usr/share/ipregion/jsonpath.uc"
"$UCODE" -c -o "$OUT_DIR/ipregion-http.uc.out" "$ROOT_DIR/ipregion/files/usr/share/ipregion/http.uc"
"$UCODE" -c -o "$OUT_DIR/ipregion-handlers.uc.out" "$ROOT_DIR/ipregion/files/usr/share/ipregion/handlers.uc"
"$UCODE" -c -o "$OUT_DIR/luci-ipregion-rpcd.uc.out" "$ROOT_DIR/luci-app-ipregion/root/usr/share/rpcd/ucode/ipregion.uc"

"$UCODE" "$ROOT_DIR/ipregion/files/usr/share/ipregion/ipregion.uc" --help >/dev/null
IPREGION_CATALOG_PATH="$ROOT_DIR/ipregion/files/usr/share/ipregion/services.json" \
IPREGION_RUNTIME_DIR="$OUT_DIR/runtime" \
	"$UCODE" "$ROOT_DIR/ipregion/files/usr/share/ipregion/ipregion.uc" --no-uci --list-services --json >/dev/null
IPREGION_CATALOG_PATH="$ROOT_DIR/ipregion/files/usr/share/ipregion/services.json" \
IPREGION_DNS_CATALOG_PATH="$ROOT_DIR/ipregion/files/usr/share/ipregion/services-dns.json" \
IPREGION_RUNTIME_DIR="$OUT_DIR/runtime" \
	"$UCODE" "$ROOT_DIR/ipregion/files/usr/share/ipregion/ipregion.uc" --no-uci --list-dns-providers --json >/dev/null
expect_failure env IPREGION_CATALOG_PATH="$ROOT_DIR/ipregion/files/usr/share/ipregion/services.json" \
	IPREGION_DNS_CATALOG_PATH="$ROOT_DIR/ipregion/files/usr/share/ipregion/services-dns.json" \
	IPREGION_RUNTIME_DIR="$OUT_DIR/runtime" \
	"$UCODE" "$ROOT_DIR/ipregion/files/usr/share/ipregion/ipregion.uc" dns --no-uci --provider unknown --transport doh --ip-mode ipv4 --json
expect_failure env IPREGION_CATALOG_PATH="$ROOT_DIR/ipregion/files/usr/share/ipregion/services.json" \
	IPREGION_DNS_CATALOG_PATH="$ROOT_DIR/ipregion/files/usr/share/ipregion/services-dns.json" \
	IPREGION_RUNTIME_DIR="$OUT_DIR/runtime" \
	"$UCODE" "$ROOT_DIR/ipregion/files/usr/share/ipregion/ipregion.uc" dns --no-uci --dns-name bad/name --transport doh --ip-mode ipv4 --json
expect_failure env IPREGION_CATALOG_PATH="$ROOT_DIR/ipregion/files/usr/share/ipregion/services.json" \
	IPREGION_DNS_CATALOG_PATH="$ROOT_DIR/ipregion/files/usr/share/ipregion/services-dns.json" \
	IPREGION_RUNTIME_DIR="$OUT_DIR/runtime" \
	"$UCODE" "$ROOT_DIR/ipregion/files/usr/share/ipregion/ipregion.uc" dns --no-uci --proxy 127.0.0.1:1080 --transport doh --ip-mode ipv4 --json
expect_failure env IPREGION_CATALOG_PATH="$ROOT_DIR/ipregion/files/usr/share/ipregion/services.json" \
	IPREGION_DNS_CATALOG_PATH="$ROOT_DIR/ipregion/files/usr/share/ipregion/services-dns.json" \
	IPREGION_RUNTIME_DIR="$OUT_DIR/runtime" \
	"$UCODE" "$ROOT_DIR/ipregion/files/usr/share/ipregion/ipregion.uc" dns --no-uci --provider interface_dns --transport doh --ip-mode ipv4 --json

run_fake_ai google_gemini_web ok ai-web
run_fake_ai google_gemini_web web_blocked ai-web-blocked
run_fake_ai google_gemini_web web_auth ai-web-auth
run_fake_ai google_gemini_web web_rate ai-web-rate
run_fake_ai google_gemini_web web_server ai-web-server
run_fake_ai google_gemini auth ai-api
run_fake_ai google_gemini timeout ai-timeout
run_fake_ai google_gemini partial_timeout ai-partial-timeout
run_fake_ai google_gemini invalid_key ai-invalid-key
run_fake_ai google_gemini region ai-region
run_fake_ai google_gemini rate ai-rate
run_fake_ai google_gemini server ai-server
PATH="$FAKE_BIN:$PATH" \
IPREGION_FAKE_CURL_LOG="$OUT_DIR/regular-gemini.log" \
IPREGION_FAKE_GEMINI=web_blocked \
IPREGION_CATALOG_PATH="$ROOT_DIR/ipregion/files/usr/share/ipregion/services.json" \
IPREGION_RUNTIME_DIR="$OUT_DIR/runtime-regular-gemini" \
	"$UCODE" "$ROOT_DIR/ipregion/files/usr/share/ipregion/ipregion.uc" --no-uci --service GEMINI_SUPPORTED --ipv4 --retries 0 --json >"$OUT_DIR/regular-gemini.json"

python3 - "$OUT_DIR" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
def row(name):
    return json.loads((root / f'{name}.json').read_text(encoding='utf-8'))['providers'][0]

web, api, timeout = row('ai-web'), row('ai-api'), row('ai-timeout')
assert (web['id'], web['endpoint_role'], web['status']) == ('google_gemini_web', 'web', 'ok'), web
assert (api['id'], api['endpoint_role'], api['status']) == ('google_gemini', 'api', 'reachable_auth_required'), api
assert timeout['status'] == 'timeout', timeout
assert timeout['curl_exit_code'] != 0 and timeout['failure_stage'] == 'TCP connection', timeout
assert 'generativelanguage.googleapis.com' in timeout['diagnosis'], timeout
assert row('ai-web-blocked')['status'] == 'blocked_by_provider_region'
assert row('ai-web-auth')['status'] == 'reachable'
assert row('ai-web-rate')['status'] == 'rate_limited'
assert row('ai-web-server')['status'] == 'server_error'
assert row('ai-partial-timeout')['status'] == 'timeout'
assert row('ai-invalid-key')['status'] == 'reachable_auth_required'
assert row('ai-region')['status'] == 'blocked_by_provider_region'
assert row('ai-rate')['status'] == 'rate_limited'
assert row('ai-server')['status'] == 'server_error'
regular = json.loads((root / 'regular-gemini.json').read_text(encoding='utf-8'))['results']['custom'][0]
regular_log = (root / 'regular-gemini.log').read_text(encoding='utf-8')
assert (regular['id'], regular['service'], regular['ipv4']['status']) == ('GEMINI_SUPPORTED', 'Gemini Web Endpoint', 'denied'), regular
assert 'https://gemini.google.com/app' in regular_log, regular_log
assert 'generativelanguage.googleapis.com' not in regular_log, regular_log
print('Gemini classification checks OK')
PY

UCI_DIR="$OUT_DIR/uci"
mkdir -p "$UCI_DIR"

run_uci_ai() {
	name=$1
	shift
	PATH="$FAKE_BIN:$PATH" \
	IPREGION_FAKE_CURL_LOG="$OUT_DIR/$name.log" \
	IPREGION_UCI_CONFIG_DIR="$UCI_DIR" \
	IPREGION_CATALOG_PATH="$ROOT_DIR/ipregion/files/usr/share/ipregion/services.json" \
	IPREGION_AI_CATALOG_PATH="$ROOT_DIR/ipregion/files/usr/share/ipregion/services-ai.json" \
	IPREGION_RUNTIME_DIR="$OUT_DIR/runtime-$name" \
		"$UCODE" "$ROOT_DIR/ipregion/files/usr/share/ipregion/ipregion.uc" ai --provider google_gemini_web --ip-mode ipv4 --retries 0 --json "$@" >"$OUT_DIR/$name.json"
}

cat >"$UCI_DIR/ipregion" <<'EOF'
config ipregion 'main'
	option proxy_profile 'europe'

config proxy 'europe'
	option label 'Europe'
	option address 'proxy-europe.test:6000'
	option proxy_dns 'local'

config proxy 'america'
	option label 'America'
	option address 'proxy-america.test:7000'
	option proxy_dns 'remote'
EOF
run_uci_ai proxy-profile-local

cat >"$UCI_DIR/ipregion" <<'EOF'
config ipregion 'main'
	option proxy_profile 'america'

config proxy 'america'
	option address 'proxy-america.test:7000'
	option proxy_dns 'remote'

config proxy 'europe'
	option address 'proxy-europe.test:6000'
	option proxy_dns 'local'
EOF
run_uci_ai proxy-profile-remote

cat >"$UCI_DIR/ipregion" <<'EOF'
config ipregion 'main'
	option proxy_profile 'none'
	option proxy 'legacy-proxy.test:8000'
	option proxy_dns 'remote'
EOF
run_uci_ai proxy-profile-none

cat >"$UCI_DIR/ipregion" <<'EOF'
config ipregion 'main'
	option proxy 'legacy-proxy.test:8000'
	option proxy_dns 'remote'
EOF
run_uci_ai proxy-profile-legacy

cat >"$UCI_DIR/ipregion" <<'EOF'
config ipregion 'main'
	option proxy_profile 'europe'

config proxy 'europe'
	option address 'proxy-europe.test:6000'
	option proxy_dns 'local'
EOF
run_uci_ai proxy-cli-override --proxy override-proxy.test:9000 --proxy-dns remote

cat >"$UCI_DIR/ipregion" <<'EOF'
config ipregion 'main'
	option proxy_profile 'missing'
EOF
expect_failure env PATH="$FAKE_BIN:$PATH" \
	IPREGION_UCI_CONFIG_DIR="$UCI_DIR" \
	IPREGION_CATALOG_PATH="$ROOT_DIR/ipregion/files/usr/share/ipregion/services.json" \
	IPREGION_AI_CATALOG_PATH="$ROOT_DIR/ipregion/files/usr/share/ipregion/services-ai.json" \
	IPREGION_RUNTIME_DIR="$OUT_DIR/runtime-proxy-missing" \
	"$UCODE" "$ROOT_DIR/ipregion/files/usr/share/ipregion/ipregion.uc" ai --provider google_gemini_web --ip-mode ipv4 --json

cat >"$UCI_DIR/ipregion" <<'EOF'
config ipregion 'main'
	option proxy_profile 'broken'

config proxy 'broken'
	option proxy_dns 'remote'
EOF
expect_failure env PATH="$FAKE_BIN:$PATH" \
	IPREGION_UCI_CONFIG_DIR="$UCI_DIR" \
	IPREGION_CATALOG_PATH="$ROOT_DIR/ipregion/files/usr/share/ipregion/services.json" \
	IPREGION_AI_CATALOG_PATH="$ROOT_DIR/ipregion/files/usr/share/ipregion/services-ai.json" \
	IPREGION_RUNTIME_DIR="$OUT_DIR/runtime-proxy-broken" \
	"$UCODE" "$ROOT_DIR/ipregion/files/usr/share/ipregion/ipregion.uc" ai --provider google_gemini_web --ip-mode ipv4 --json

python3 - "$OUT_DIR" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
def log(name):
    return (root / f'{name}.log').read_text(encoding='utf-8')

assert 'socks5://proxy-europe.test:6000' in log('proxy-profile-local')
assert 'socks5h://proxy-america.test:7000' in log('proxy-profile-remote')
assert '--proxy' not in log('proxy-profile-none')
assert 'socks5h://legacy-proxy.test:8000' in log('proxy-profile-legacy')
assert 'socks5h://override-proxy.test:9000' in log('proxy-cli-override')
assert 'proxy-europe.test:6000' not in log('proxy-cli-override')
print('proxy profile checks OK')
PY

"$UCODE" "$ROOT_DIR/ipregion/files/usr/share/ipregion/http.uc" >/dev/null
"$UCODE" "$ROOT_DIR/ipregion/files/usr/share/ipregion/handlers.uc" >/dev/null
"$UCODE" "$ROOT_DIR/ipregion/files/usr/share/ipregion/jsonpath.uc" >/dev/null
"$UCODE" "$ROOT_DIR/luci-app-ipregion/root/usr/share/rpcd/ucode/ipregion.uc" >/dev/null

printf 'ucode checks OK\n'
