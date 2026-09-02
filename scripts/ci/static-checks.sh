#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
export ROOT_DIR

python3 - <<'PY'
import json
import ipaddress
import os
import re
from pathlib import Path

root = Path(os.environ['ROOT_DIR'])

json_files = [
    root / 'ipregion/files/usr/share/ipregion/services.json',
    root / 'ipregion/files/usr/share/ipregion/services-ai.json',
    root / 'ipregion/files/usr/share/ipregion/services-dns.json',
    root / 'luci-app-ipregion/root/usr/share/luci/menu.d/luci-app-ipregion.json',
    root / 'luci-app-ipregion/root/usr/share/rpcd/acl.d/luci-app-ipregion.json',
]

for path in json_files:
    json.loads(path.read_text(encoding='utf-8'))
    print(f'JSON OK: {path}')

catalog = json.loads((root / 'ipregion/files/usr/share/ipregion/services.json').read_text(encoding='utf-8'))
services = catalog['services']

for group, ids in catalog['groups'].items():
    for service_id in ids:
        if service_id not in services:
            raise SystemExit(f'missing service {service_id} in group {group}')
        service = services[service_id]
        if service.get('group') != group:
            raise SystemExit(f'group mismatch for {service_id}: listed {group}, service says {service.get("group")}')
        if 'url' not in service and 'handler' not in service:
            raise SystemExit(f'service {service_id} has neither url nor handler')
        if 'extract' not in service:
            raise SystemExit(f'service {service_id} has no extract definition')

if services['GOOGLE_SEARCH_CAPTCHA'].get('default_enabled') is not False:
    raise SystemExit('GOOGLE_SEARCH_CAPTCHA must be disabled by default')

ai_catalog = json.loads((root / 'ipregion/files/usr/share/ipregion/services-ai.json').read_text(encoding='utf-8'))
ai_ids = set()
for provider in ai_catalog:
    provider_id = provider.get('id')
    if not provider_id or provider_id in ai_ids:
        raise SystemExit(f'invalid duplicate AI provider id: {provider_id}')
    ai_ids.add(provider_id)
    if provider.get('category') not in {'ai', 'ai_china'}:
        raise SystemExit(f'invalid AI provider category for {provider_id}')
    if not provider.get('url'):
        raise SystemExit(f'AI provider {provider_id} has no url')

ai_by_id = {provider['id']: provider for provider in ai_catalog}
gemini_web = ai_by_id.get('google_gemini_web', {})
gemini_api = ai_by_id.get('google_gemini', {})
if gemini_web.get('url') != 'https://gemini.google.com/app' or gemini_web.get('endpoint_role') != 'web':
    raise SystemExit('google_gemini_web must probe the Gemini Web endpoint')
if gemini_api.get('url') != 'https://generativelanguage.googleapis.com/v1beta/models' or gemini_api.get('endpoint_role') != 'api':
    raise SystemExit('google_gemini must preserve the Gemini API endpoint')
if services['GEMINI_SUPPORTED'].get('url') != gemini_web['url']:
    raise SystemExit('regular and AI Gemini Web checks must use the same endpoint')

dns_catalog = json.loads((root / 'ipregion/files/usr/share/ipregion/services-dns.json').read_text(encoding='utf-8'))
dns_ids = set()
for provider in dns_catalog.get('providers', []):
    provider_id = provider.get('id')
    if not provider_id or provider_id in dns_ids:
        raise SystemExit(f'invalid duplicate DNS provider id: {provider_id}')
    dns_ids.add(provider_id)
    if provider.get('dynamic') == 'interface':
        if provider.get('plain_only') is not True:
            raise SystemExit('dynamic interface DNS provider must be plain-only')
        continue
    if not provider.get('doh_url', '').startswith('https://'):
        raise SystemExit(f'DNS provider {provider_id} has no HTTPS DoH URL')
    if not provider.get('doh_hostname') or not provider.get('dot_hostname'):
        raise SystemExit(f'DNS provider {provider_id} has incomplete TLS hostnames')
    if not provider.get('ipv4') or not provider.get('ipv6'):
        raise SystemExit(f'DNS provider {provider_id} has incomplete endpoint addresses')
    for address in provider['ipv4']:
        if ipaddress.ip_address(address).version != 4:
            raise SystemExit(f'DNS provider {provider_id} has invalid IPv4 address: {address}')
    for address in provider['ipv6']:
        if ipaddress.ip_address(address).version != 6:
            raise SystemExit(f'DNS provider {provider_id} has invalid IPv6 address: {address}')

acl = json.loads((root / 'luci-app-ipregion/root/usr/share/rpcd/acl.d/luci-app-ipregion.json').read_text(encoding='utf-8'))
ubus_read = acl['luci-app-ipregion']['read']['ubus']
ubus_write = acl['luci-app-ipregion']['write']['ubus']
if 'luci.ipregion' not in ubus_read or 'luci.ipregion' not in ubus_write:
    raise SystemExit('ACL must grant only luci.ipregion ubus methods')

view_dir = root / 'luci-app-ipregion/htdocs/luci-static/resources/view/ipregion'
markdown_js = root / 'luci-app-ipregion/htdocs/luci-static/resources/ipregion/markdown.js'
js = ''.join(p.read_text(encoding='utf-8') for p in view_dir.glob('*.js')) + markdown_js.read_text(encoding='utf-8')
messages = set(re.findall(r"_\('([^']+)'\)", js))
pot = (root / 'luci-app-ipregion/po/templates/ipregion.pot').read_text(encoding='utf-8')
po = (root / 'luci-app-ipregion/po/ru/ipregion.po').read_text(encoding='utf-8')
missing_pot = sorted(m for m in messages if f'msgid "{m}"' not in pot)
missing_po = sorted(m for m in messages if f'msgid "{m}"' not in po)
if missing_pot or missing_po:
    raise SystemExit(f'missing gettext strings: pot={missing_pot} po={missing_po}')

pot_messages = set(re.findall(r'^msgid "(.*)"$', pot, re.MULTILINE)) - {''}
po_messages = set(re.findall(r'^msgid "(.*)"$', po, re.MULTILINE)) - {''}
extra_pot = sorted(pot_messages - messages)
extra_po = sorted(po_messages - messages)
if extra_pot or extra_po:
    raise SystemExit(f'obsolete gettext strings: pot={extra_pot} po={extra_po}')

settings_js = (view_dir / 'settings.js').read_text(encoding='utf-8')
if 'p.anonymous = false;' not in settings_js or 'p.anonymous = true;' in settings_js:
    raise SystemExit('proxy profiles must use stable named UCI sections')

core = (root / 'ipregion/files/usr/share/ipregion/ipregion.uc').read_text(encoding='utf-8')
ipregion_makefile = (root / 'ipregion/Makefile').read_text(encoding='utf-8')
luci_makefile = (root / 'luci-app-ipregion/Makefile').read_text(encoding='utf-8')
pkg_version = re.search(r'^PKG_VERSION:=(.+)$', ipregion_makefile, re.MULTILINE).group(1)
pkg_release = re.search(r'^PKG_RELEASE:=(.+)$', ipregion_makefile, re.MULTILINE).group(1)
runtime_version = re.search(r"^const VERSION = '([^']+)';$", core, re.MULTILINE).group(1)
if runtime_version != f'{pkg_version}-{pkg_release}':
    raise SystemExit(f'runtime/package version mismatch: {runtime_version} != {pkg_version}-{pkg_release}')
if f'PKG_VERSION:={pkg_version}' not in luci_makefile or f'PKG_RELEASE:={pkg_release}' not in luci_makefile:
    raise SystemExit('LuCI and core package versions differ')
if f'ipregion (>={pkg_version}-r{pkg_release})' not in luci_makefile:
    raise SystemExit('LuCI core dependency does not match the package version')
if '+knot-dig' in ipregion_makefile or '+ipregion-dns-helper' not in ipregion_makefile:
    raise SystemExit('core package must use the native DNS helper instead of knot-dig')
if 'define Package/ipregion-dns-helper' not in ipregion_makefile or '+libcurl' not in ipregion_makefile:
    raise SystemExit('native DNS helper package definition is incomplete')

dns_transports = "[ 'all', 'plain', 'udp', 'tcp', 'both', 'doh', 'dot' ]"
rpcd = (root / 'luci-app-ipregion/root/usr/share/rpcd/ucode/ipregion.uc').read_text(encoding='utf-8')
if f'const VALID_DNS_TRANSPORTS = {dns_transports};' not in core or core.count("dns_transport: 'all'") != 1:
    raise SystemExit('CLI DNS transport enum or default is out of sync')
if rpcd.count(dns_transports) != 2 or "'all');" not in rpcd:
    raise SystemExit('rpcd DNS transport enum or default is out of sync')
if 'kdig_probe' in core or "code: 'kdig_missing'" in core or 'dns_helper_missing' not in core:
    raise SystemExit('DNS transport implementation still requires kdig')

install_sh = (root / 'install.sh').read_text(encoding='utf-8')
install_ipk = (root / 'install-ipk.sh').read_text(encoding='utf-8')
if 'opkg' in install_sh:
    raise SystemExit('install.sh must stay APK-only; put opkg logic in install-ipk.sh')
if 'apk add' in install_ipk or '.apk' in install_ipk:
    raise SystemExit('install-ipk.sh must stay IPK-only; put apk package install logic in install.sh')
if 'ipregion-dns-helper-$package_arch' not in install_sh:
    raise SystemExit('APK installer must select the native DNS helper for DISTRIB_ARCH')

print(f'Service catalog OK: {len(services)} services')
print(f'AI provider catalog OK: {len(ai_catalog)} providers')
print(f'DNS provider catalog OK: {len(dns_ids)} providers')
print(f'gettext catalog OK: {len(messages)} UI strings')
PY

sh -n "$ROOT_DIR/scripts/deploy-router.sh"
sh -n "$ROOT_DIR/scripts/test-router.sh"
sh -n "$ROOT_DIR/scripts/ci/static-checks.sh"
sh -n "$ROOT_DIR/scripts/ci/build-ucode.sh"
sh -n "$ROOT_DIR/scripts/ci/ucode-checks.sh"
sh -n "$ROOT_DIR/scripts/build-sdk-packages.sh"
sh -n "$ROOT_DIR/install.sh"
sh -n "$ROOT_DIR/install-ipk.sh"
sh -n "$ROOT_DIR/ipregion/files/usr/bin/ipregion"
sh -n "$ROOT_DIR/ipregion/files/etc/uci-defaults/90_ipregion"

for js in "$ROOT_DIR"/luci-app-ipregion/htdocs/luci-static/resources/view/ipregion/*.js; do
	node --check "$js"
done
node --check "$ROOT_DIR/luci-app-ipregion/htdocs/luci-static/resources/ipregion/markdown.js"
node "$ROOT_DIR/scripts/ci/markdown-checks.js"

printf 'static checks OK\n'
