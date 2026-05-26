#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
export ROOT_DIR

python3 - <<'PY'
import json
import os
import re
from pathlib import Path

root = Path(os.environ['ROOT_DIR'])

json_files = [
    root / 'ipregion/files/usr/share/ipregion/services.json',
    root / 'ipregion/files/usr/share/ipregion/services-ai.json',
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

acl = json.loads((root / 'luci-app-ipregion/root/usr/share/rpcd/acl.d/luci-app-ipregion.json').read_text(encoding='utf-8'))
ubus_read = acl['luci-app-ipregion']['read']['ubus']
ubus_write = acl['luci-app-ipregion']['write']['ubus']
if 'luci.ipregion' not in ubus_read or 'luci.ipregion' not in ubus_write:
    raise SystemExit('ACL must grant only luci.ipregion ubus methods')

js = ''.join(p.read_text(encoding='utf-8') for p in (root / 'luci-app-ipregion/htdocs/luci-static/resources/view/ipregion').glob('*.js'))
messages = set(re.findall(r"_\('([^']+)'\)", js))
pot = (root / 'luci-app-ipregion/po/templates/ipregion.pot').read_text(encoding='utf-8')
po = (root / 'luci-app-ipregion/po/ru/ipregion.po').read_text(encoding='utf-8')
missing_pot = sorted(m for m in messages if f'msgid "{m}"' not in pot)
missing_po = sorted(m for m in messages if f'msgid "{m}"' not in po)
if missing_pot or missing_po:
    raise SystemExit(f'missing gettext strings: pot={missing_pot} po={missing_po}')

for doc in [root / 'README.md', root / 'docs/README.ru.md']:
    if 'opkg' in doc.read_text(encoding='utf-8'):
        raise SystemExit(f'{doc.name} must not contain opkg runtime instructions')

print(f'Service catalog OK: {len(services)} services')
print(f'AI provider catalog OK: {len(ai_catalog)} providers')
print(f'gettext catalog OK: {len(messages)} UI strings')
PY

sh -n "$ROOT_DIR/scripts/deploy-router.sh"
sh -n "$ROOT_DIR/scripts/test-router.sh"
sh -n "$ROOT_DIR/scripts/ci/static-checks.sh"
sh -n "$ROOT_DIR/scripts/ci/build-ucode.sh"
sh -n "$ROOT_DIR/scripts/ci/ucode-checks.sh"
sh -n "$ROOT_DIR/scripts/build-sdk-packages.sh"
sh -n "$ROOT_DIR/install.sh"
sh -n "$ROOT_DIR/ipregion/files/usr/bin/ipregion"
sh -n "$ROOT_DIR/ipregion/files/etc/uci-defaults/90_ipregion"

for js in "$ROOT_DIR"/luci-app-ipregion/htdocs/luci-static/resources/view/ipregion/*.js; do
	node --check "$js"
done

printf 'static checks OK\n'
