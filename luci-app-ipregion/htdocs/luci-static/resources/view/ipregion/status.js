'use strict';
'require view';
'require rpc';
'require ui';

var regionPollTimer = null;
var aiPollTimer = null;
var currentGeneratedAt = null;
var aiGeneratedAt = null;
var referenceCountry = '';

var callGetConfig = rpc.declare({ object: 'luci.ipregion', method: 'get_config', expect: { '': {} } });
var callInterfaces = rpc.declare({ object: 'luci.ipregion', method: 'list_interfaces', expect: { '': {} } });
var callStart = rpc.declare({ object: 'luci.ipregion', method: 'start', params: [ 'options' ], expect: { '': {} } });
var callStop = rpc.declare({ object: 'luci.ipregion', method: 'stop', expect: { '': {} } });
var callStatus = rpc.declare({ object: 'luci.ipregion', method: 'status', expect: { '': {} } });
var callResult = rpc.declare({ object: 'luci.ipregion', method: 'result', expect: { '': {} } });
var callLog = rpc.declare({ object: 'luci.ipregion', method: 'log', expect: { '': {} } });
var callClear = rpc.declare({ object: 'luci.ipregion', method: 'clear', expect: { '': {} } });
var callSelftest = rpc.declare({ object: 'luci.ipregion', method: 'selftest', expect: { '': {} } });
var callVersion = rpc.declare({ object: 'luci.ipregion', method: 'version', expect: { '': {} } });
var callUpdate = rpc.declare({ object: 'luci.ipregion', method: 'update', expect: { '': {} } });
var callAiProviders = rpc.declare({ object: 'luci.ipregion', method: 'list_ai_providers', expect: { '': {} } });
var callAiStart = rpc.declare({ object: 'luci.ipregion', method: 'ai_start', params: [ 'options' ], expect: { '': {} } });
var callAiStop = rpc.declare({ object: 'luci.ipregion', method: 'ai_stop', expect: { '': {} } });
var callAiStatus = rpc.declare({ object: 'luci.ipregion', method: 'ai_status', expect: { '': {} } });
var callAiResult = rpc.declare({ object: 'luci.ipregion', method: 'ai_result', expect: { '': {} } });
var callAiLog = rpc.declare({ object: 'luci.ipregion', method: 'ai_log', expect: { '': {} } });
var callAiClear = rpc.declare({ object: 'luci.ipregion', method: 'ai_clear', expect: { '': {} } });

function fieldValue(id) {
	var node = document.getElementById(id);
	return node ? node.value : '';
}

function safeId(value) {
	return String(value || '').replace(/[^A-Za-z0-9_-]/g, '-');
}

function normalizeCountryCode(value) {
	value = String(value || '').trim().toUpperCase();
	return /^[A-Z]{2}$/.test(value) ? value : '';
}

function countryFromValue(value) {
	var match = String(value || '').trim().toUpperCase().match(/^([A-Z]{2})(?:$|[^A-Z])/);
	return match ? match[1] : '';
}

function appendValue(parent, value) {
	if (value == null || value === '')
		return;

	if (Array.isArray(value)) {
		value.forEach(function(item) { appendValue(parent, item); });
		return;
	}

	if (typeof value === 'string' || typeof value === 'number')
		parent.appendChild(document.createTextNode(String(value)));
	else
		parent.appendChild(value);
}

function setContent(nodeOrId, value) {
	var node = typeof nodeOrId === 'string' ? document.getElementById(nodeOrId) : nodeOrId;
	if (!node)
		return;

	while (node.firstChild)
		node.removeChild(node.firstChild);

	appendValue(node, value);
}

function badge(result) {
	var status = result && result.status || 'na';
	var label = result && result.label || _('N/A');
	var cls = 'ipregion-badge';

	if (status === 'ok')
		cls += ' ipregion-ok';
	else if (status === 'rate_limit')
		cls += ' ipregion-warn';
	else if (status === 'denied' || status === 'server_error' || status === 'error')
		cls += ' ipregion-error';
	else
		cls += ' ipregion-na';

	return E('span', { 'class': cls }, [ label ]);
}

function aiBadge(row) {
	var status = row && row.status || 'skipped';
	var label = row && row.label || _('N/A');
	var cls = 'ipregion-badge';

	if (status === 'ok' || status === 'reachable' || status === 'reachable_auth_required')
		cls += ' ipregion-ok';
	else if (status === 'forbidden' || status === 'rate_limited' || status === 'endpoint_reached_wrong_method' || status === 'server_error')
		cls += ' ipregion-warn';
	else if (status === 'skipped' || status === 'unavailable')
		cls += ' ipregion-na';
	else
		cls += ' ipregion-error';

	return E('span', { 'class': cls }, [ label ]);
}

function resultCell(result) {
	if (!result)
		return E('span', {}, [ badge(null) ]);

	var valueNodes = [];
	if (result.value) {
		var country = result.status === 'ok' ? countryFromValue(result.value) : '';

		if (country && referenceCountry)
			valueNodes = [ ' ', E('span', {
				'class': 'ipregion-country-badge ' + (country === referenceCountry ? 'ipregion-country-match' : 'ipregion-country-mismatch'),
				'title': _('Reference country') + ': ' + referenceCountry
			}, [ result.value ]) ];
		else
			valueNodes = [ ' ' + result.value ];
	}

	return E('span', {}, [ badge(result) ].concat(valueNodes, [
		result.latency_ms != null ? E('span', { 'class': 'ipregion-muted' }, [ ' ', result.latency_ms + ' ms' ]) : '',
		result.http_code ? E('span', { 'class': 'ipregion-muted' }, [ ' HTTP ', result.http_code ]) : '',
		result.error ? E('span', { 'class': 'ipregion-muted' }, [ ' ', result.error ]) : ''
	]));
}

function groupDescription(group) {
	if (group === 'all')
		return _('All groups run every enabled GeoIP, popular service and CDN check.');

	if (group === 'primary')
		return _('GeoIP services query public geolocation APIs and registries to see what country they assign to the router IP.');

	if (group === 'custom')
		return _('Popular services contact major platforms to see which region, access state or country their web/API endpoints report for this route.');

	if (group === 'cdn')
		return _('CDN services check which CDN edge or region the router reaches, for example Cloudflare, YouTube or Netflix.');

	return '';
}

function updateGroupDescription(group) {
	setContent('ipregion-group-description', groupDescription(group));
}

function renderRow(group, row) {
	var id = safeId(group + '-' + (row.id || row.service));

	return E('tr', { 'class': 'tr ipregion-data-row', 'id': 'ipregion-row-' + id }, [
		E('td', { 'class': 'td' }, [ row.service || row.id ]),
		E('td', { 'class': 'td', 'id': 'ipregion-v4-' + id }, [ resultCell(row.ipv4) ]),
		E('td', { 'class': 'td', 'id': 'ipregion-v6-' + id }, [ resultCell(row.ipv6) ])
	]);
}

function renderGroup(title, group, rows, description) {
	rows = rows || [];
	var tableRows = [
		E('tr', { 'class': 'tr table-titles' }, [
			E('th', { 'class': 'th' }, [ _('Service') ]),
			E('th', { 'class': 'th' }, [ _('IPv4 value/status') ]),
			E('th', { 'class': 'th' }, [ _('IPv6 value/status') ])
		])
	];

	if (rows.length)
		rows.forEach(function(row) { tableRows.push(renderRow(group, row)); });
	else
		tableRows.push(E('tr', { 'class': 'tr ipregion-empty-row', 'id': 'ipregion-empty-' + group }, [ E('td', { 'class': 'td', 'colspan': 3 }, [ _('No results yet') ]) ]));

	return E('div', { 'class': 'ipregion-card' }, [
		E('h3', {}, [ title ]),
		description ? E('p', { 'class': 'ipregion-muted' }, [ description ]) : '',
		E('table', { 'class': 'table', 'id': 'ipregion-table-' + group }, tableRows)
	]);
}

function aiRowId(row) {
	return safeId(row.row_id || ((row.id || row.name) + '-' + (row.transport || row.ip_version || '')));
}

function renderAiRow(row) {
	var id = aiRowId(row);

	return E('tr', { 'class': 'tr ipregion-ai-data-row', 'id': 'ipregion-ai-row-' + id }, [
		E('td', { 'class': 'td' }, [ row.name || row.id ]),
		E('td', { 'class': 'td', 'id': 'ipregion-ai-transport-' + id }, [ row.transport_label || row.transport || _('N/A') ]),
		E('td', { 'class': 'td' }, [ row.category_label || row.category || '' ]),
		E('td', { 'class': 'td', 'id': 'ipregion-ai-http-' + id }, [ String(row.http_code || 0) ]),
		E('td', { 'class': 'td', 'id': 'ipregion-ai-status-' + id }, [ aiBadge(row) ]),
		E('td', { 'class': 'td', 'id': 'ipregion-ai-time-' + id }, [ row.latency_ms != null ? row.latency_ms + ' ms' : _('N/A') ]),
		E('td', { 'class': 'td', 'id': 'ipregion-ai-diagnosis-' + id }, [ row.diagnosis || '' ])
	]);
}

function renderAiTable(rows) {
	rows = rows || [];
	var tableRows = [
		E('tr', { 'class': 'tr table-titles' }, [
			E('th', { 'class': 'th' }, [ _('Provider') ]),
			E('th', { 'class': 'th' }, [ _('Transport') ]),
			E('th', { 'class': 'th' }, [ _('Category') ]),
			E('th', { 'class': 'th' }, [ _('HTTP') ]),
			E('th', { 'class': 'th' }, [ _('Status') ]),
			E('th', { 'class': 'th' }, [ _('Time') ]),
			E('th', { 'class': 'th' }, [ _('Diagnosis') ])
		])
	];

	if (rows.length)
		rows.forEach(function(row) { tableRows.push(renderAiRow(row)); });
	else
		tableRows.push(E('tr', { 'class': 'tr ipregion-ai-empty-row', 'id': 'ipregion-ai-empty' }, [ E('td', { 'class': 'td', 'colspan': 7 }, [ _('No results yet') ]) ]));

	return E('div', { 'class': 'ipregion-card' }, [
		E('h3', {}, [ _('AI provider endpoint results') ]),
		E('p', { 'class': 'ipregion-muted' }, [ _('Each row checks the actual provider endpoint domain. With split routing, this can differ from the generic egress check below.') ]),
		E('p', { 'class': 'ipregion-muted' }, [ _('When IPv4 and IPv6 mode is selected, each provider gets separate IPv4 and IPv6 rows; unavailable transports are shown explicitly.') ]),
		E('table', { 'class': 'table', 'id': 'ipregion-ai-table' }, tableRows)
	]);
}

function clearGroupRows(group) {
	var table = document.getElementById('ipregion-table-' + group);
	if (!table)
		return;

	Array.prototype.slice.call(table.querySelectorAll('.ipregion-data-row')).forEach(function(row) { row.remove(); });
	if (!document.getElementById('ipregion-empty-' + group))
		table.appendChild(E('tr', { 'class': 'tr ipregion-empty-row', 'id': 'ipregion-empty-' + group }, [ E('td', { 'class': 'td', 'colspan': 3 }, [ _('No results yet') ]) ]));
}

function clearAiRows() {
	var table = document.getElementById('ipregion-ai-table');
	if (!table)
		return;

	Array.prototype.slice.call(table.querySelectorAll('.ipregion-ai-data-row')).forEach(function(row) { row.remove(); });
	if (!document.getElementById('ipregion-ai-empty'))
		table.appendChild(E('tr', { 'class': 'tr ipregion-ai-empty-row', 'id': 'ipregion-ai-empty' }, [ E('td', { 'class': 'td', 'colspan': 7 }, [ _('No results yet') ]) ]));
}

function resetResultUi() {
	currentGeneratedAt = null;
	[ 'primary', 'custom', 'cdn' ].forEach(clearGroupRows);
	setContent('ipregion-network-ipv4', [ _('IPv4'), ': ', _('N/A') ]);
	setContent('ipregion-network-ipv6', [ _('IPv6'), ': ', _('N/A') ]);
	setContent('ipregion-network-asn', [ _('ASN'), ': ', _('N/A') ]);
	setContent('ipregion-network-last', '');
	setContent('ipregion-errors', '');
}

function resetAiUi() {
	aiGeneratedAt = null;
	clearAiRows();
	setContent('ipregion-ai-egress-ipv4', [ _('IPv4'), ': ', _('N/A') ]);
	setContent('ipregion-ai-egress-ipv6', [ _('IPv6'), ': ', _('N/A') ]);
	setContent('ipregion-ai-egress-country', [ _('Country'), ': ', _('N/A') ]);
	setContent('ipregion-ai-egress-asn', [ _('ASN'), ': ', _('N/A') ]);
	setContent('ipregion-ai-errors', '');
}

function updateGroupRows(group, rows) {
	rows = rows || [];
	var table = document.getElementById('ipregion-table-' + group);
	if (!table)
		return;

	var empty = document.getElementById('ipregion-empty-' + group);
	if (rows.length && empty)
		empty.remove();

	rows.forEach(function(row) {
		var id = safeId(group + '-' + (row.id || row.service));
		var existing = document.getElementById('ipregion-row-' + id);

		if (!existing) {
			table.appendChild(renderRow(group, row));
			return;
		}

		setContent('ipregion-v4-' + id, [ resultCell(row.ipv4) ]);
		setContent('ipregion-v6-' + id, [ resultCell(row.ipv6) ]);
	});

	if (!rows.length && !document.getElementById('ipregion-empty-' + group))
		table.appendChild(E('tr', { 'class': 'tr ipregion-empty-row', 'id': 'ipregion-empty-' + group }, [ E('td', { 'class': 'td', 'colspan': 3 }, [ _('No results yet') ]) ]));
}

function updateAiRows(rows) {
	rows = rows || [];
	var table = document.getElementById('ipregion-ai-table');
	if (!table)
		return;

	var empty = document.getElementById('ipregion-ai-empty');
	if (rows.length && empty)
		empty.remove();

	rows.forEach(function(row) {
		var id = aiRowId(row);
		var existing = document.getElementById('ipregion-ai-row-' + id);

		if (!existing) {
			table.appendChild(renderAiRow(row));
			return;
		}

		setContent('ipregion-ai-transport-' + id, row.transport_label || row.transport || _('N/A'));
		setContent('ipregion-ai-http-' + id, String(row.http_code || 0));
		setContent('ipregion-ai-status-' + id, [ aiBadge(row) ]);
		setContent('ipregion-ai-time-' + id, row.latency_ms != null ? row.latency_ms + ' ms' : _('N/A'));
		setContent('ipregion-ai-diagnosis-' + id, row.diagnosis || '');
	});

	if (!rows.length && !document.getElementById('ipregion-ai-empty'))
		table.appendChild(E('tr', { 'class': 'tr ipregion-ai-empty-row', 'id': 'ipregion-ai-empty' }, [ E('td', { 'class': 'td', 'colspan': 7 }, [ _('No results yet') ]) ]));
}

function renderOptions(config, interfaces) {
	interfaces = interfaces && interfaces.interfaces || [];
	var group = config.group || 'all';
	var ipMode = config.ip_mode || 'auto';
	var geoipMode = config.geoip_mode || 'lookup';
	var iface = config.interface || '';
	var proxy = config.proxy || '';

	return E('div', { 'class': 'ipregion-card ipregion-options' }, [
		E('label', {}, [ _('Group'), E('select', { 'id': 'ipregion-group', 'change': function(ev) { updateGroupDescription(ev.target.value); } }, [
			E('option', { 'value': 'all', 'selected': group === 'all' ? 'selected' : null }, [ _('All') ]),
			E('option', { 'value': 'primary', 'selected': group === 'primary' ? 'selected' : null }, [ _('GeoIP services') ]),
			E('option', { 'value': 'custom', 'selected': group === 'custom' ? 'selected' : null }, [ _('Popular services') ]),
			E('option', { 'value': 'cdn', 'selected': group === 'cdn' ? 'selected' : null }, [ _('CDN services') ])
		]) ]),
		E('label', { 'class': 'ipregion-highlight-label' }, [ _('GeoIP mode'), E('select', { 'id': 'ipregion-geoip-mode' }, [
			E('option', { 'value': 'lookup', 'selected': geoipMode === 'lookup' ? 'selected' : null }, [ _('Check discovered IP') ]),
			E('option', { 'value': 'route', 'selected': geoipMode === 'route' ? 'selected' : null }, [ _('Check service-visible route') ])
		]) ]),
		E('label', {}, [ _('IP mode'), E('select', { 'id': 'ipregion-ip-mode' }, [
			E('option', { 'value': 'auto', 'selected': ipMode === 'auto' ? 'selected' : null }, [ _('Auto') ]),
			E('option', { 'value': 'ipv4', 'selected': ipMode === 'ipv4' ? 'selected' : null }, [ _('IPv4 only') ]),
			E('option', { 'value': 'ipv6', 'selected': ipMode === 'ipv6' ? 'selected' : null }, [ _('IPv6 only') ]),
			E('option', { 'value': 'both', 'selected': ipMode === 'both' ? 'selected' : null }, [ _('IPv4 and IPv6') ])
		]) ]),
		E('label', {}, [ _('Interface'), E('select', { 'id': 'ipregion-interface' }, interfaces.map(function(item) {
			return E('option', { 'value': item.name || '', 'selected': (item.name || '') === iface ? 'selected' : null }, [ item.label || item.name || _('Default route') ]);
		})) ]),
		E('label', {}, [ _('Proxy'), E('select', { 'id': 'ipregion-proxy' }, [
			E('option', { 'value': '', 'selected': !proxy ? 'selected' : null }, [ _('No proxy') ])
		].concat(proxy ? [ E('option', { 'value': proxy, 'selected': 'selected' }, [ _('Use saved SOCKS5 proxy') + ' (' + proxy + ')' ]) ] : [])) ]),
		E('label', {}, [ _('Timeout'), E('input', { 'id': 'ipregion-timeout', 'type': 'number', 'min': '1', 'max': '60', 'value': config.timeout || '5' }) ]),
		E('p', { 'class': 'ipregion-muted ipregion-group-help' }, [ _('Set the saved SOCKS5 proxy in Settings, then select it here for checks.') ]),
		E('a', { 'class': 'btn cbi-button', 'href': L.url('admin/services/ipregion') }, [ _('Open settings') ]),
		E('p', { 'id': 'ipregion-group-description', 'class': 'ipregion-muted ipregion-group-help' }, [ groupDescription(group) ]),
		E('p', { 'class': 'ipregion-muted ipregion-group-help' }, [ _('GeoIP lookup checks the discovered router IP. Service-visible route asks supported GeoIP APIs what country they see for this exact request path.') ])
	]);
}

function renderAiOptions(providers) {
	providers = providers || [];

	return E('div', { 'class': 'ipregion-card ipregion-options' }, [
		E('label', {}, [ _('AI category'), E('select', { 'id': 'ipregion-ai-category' }, [
			E('option', { 'value': 'all' }, [ _('All AI providers') ]),
			E('option', { 'value': 'ai' }, [ _('Global AI providers') ]),
			E('option', { 'value': 'ai_china' }, [ _('China and Asia AI providers') ])
		]) ]),
		E('label', {}, [ _('Provider'), E('select', { 'id': 'ipregion-ai-provider' }, [
			E('option', { 'value': '' }, [ _('All providers') ])
		].concat(providers.map(function(provider) {
			return E('option', { 'value': provider.id }, [ provider.name || provider.id ]);
		}))) ]),
		E('p', { 'class': 'ipregion-muted ipregion-group-help' }, [ _('AI provider checks use the same IP mode, interface, proxy and timeout controls above. IPv4 and IPv6 mode checks both transports separately.') ]),
		E('p', { 'class': 'ipregion-muted ipregion-group-help' }, [ _('Safe mode is used by default. It does not store API keys and only checks whether provider endpoint domains are reachable through their selected routes.') ])
	]);
}

function renderNetwork(result) {
	var network = result.network || {};
	return E('div', { 'class': 'ipregion-card ipregion-network' }, [
		E('h3', {}, [ _('Network') ]),
		E('p', { 'id': 'ipregion-network-ipv4' }, [ _('IPv4'), ': ', network.ipv4_masked || _('N/A') ]),
		E('p', { 'id': 'ipregion-network-ipv6' }, [ _('IPv6'), ': ', network.ipv6_masked || _('N/A') ]),
		E('p', { 'id': 'ipregion-network-asn' }, [ _('ASN'), ': ', network.asn ? network.asn + ' ' + (network.asn_name || '') : _('N/A') ]),
		E('p', { 'id': 'ipregion-network-last' }, result.generated_at ? [ _('Last check'), ': ', result.generated_at ] : [])
	]);
}

function renderAiEgress(result) {
	var egress = result.egress || {};
	return E('div', { 'class': 'ipregion-card' }, [
		E('h3', {}, [ _('Generic egress check') ]),
		E('p', { 'class': 'ipregion-muted' }, [ _('This is a generic IP/ASN check for the selected route. In domain-based split routing, individual AI provider endpoints may use a different VPN route; check the provider rows above.') ]),
		E('p', { 'id': 'ipregion-ai-egress-ipv4' }, [ _('IPv4'), ': ', egress.ipv4_masked || _('N/A') ]),
		E('p', { 'id': 'ipregion-ai-egress-ipv6' }, [ _('IPv6'), ': ', egress.ipv6_masked || _('N/A') ]),
		E('p', { 'id': 'ipregion-ai-egress-country' }, [ _('Country'), ': ', egress.country || _('N/A') ]),
		E('p', { 'id': 'ipregion-ai-egress-asn' }, [ _('ASN'), ': ', egress.asn ? egress.asn + ' ' + (egress.asn_name || '') : _('N/A') ])
	]);
}

function updateNetwork(result) {
	var network = result.network || {};
	setContent('ipregion-network-ipv4', [ _('IPv4'), ': ', network.ipv4_masked || _('N/A') ]);
	setContent('ipregion-network-ipv6', [ _('IPv6'), ': ', network.ipv6_masked || _('N/A') ]);
	setContent('ipregion-network-asn', [ _('ASN'), ': ', network.asn ? network.asn + ' ' + (network.asn_name || '') : _('N/A') ]);
	setContent('ipregion-network-last', result.generated_at ? [ _('Last check'), ': ', result.generated_at ] : '');
}

function updateAiEgress(result) {
	var egress = result.egress || {};
	setContent('ipregion-ai-egress-ipv4', [ _('IPv4'), ': ', egress.ipv4_masked || _('N/A') ]);
	setContent('ipregion-ai-egress-ipv6', [ _('IPv6'), ': ', egress.ipv6_masked || _('N/A') ]);
	setContent('ipregion-ai-egress-country', [ _('Country'), ': ', egress.country || _('N/A') ]);
	setContent('ipregion-ai-egress-asn', [ _('ASN'), ': ', egress.asn ? egress.asn + ' ' + (egress.asn_name || '') : _('N/A') ]);
}

function versionMessage(version) {
	var status = version && version.status;
	if (status === 'latest') return _('Latest version installed');
	if (status === 'update_available') return _('Update available');
	if (status === 'latest_is_older') return _('Installed version is newer than the latest GitHub release');
	if (status === 'version_mismatch') return _('Installed and GitHub versions differ');
	if (status === 'installed_not_found') return _('Installed version not found');
	return _('GitHub version not found');
}

function renderVersion(version) {
	version = version || {};
	var update = version.update || {};
	var canUpdate = version.status === 'update_available' && !update.running;
	var repo = version.github_repo || 'romanilyin/ipregion-openwrt';
	var repoUrl = 'https://github.com/' + repo;
	var latest = version.latest_normalized || version.latest || _('N/A');

	return E('div', { 'class': 'ipregion-card' }, [
		E('h3', {}, [ _('Package version') ]),
		E('p', {}, [ _('Installed version'), ': ', version.current_normalized || version.current || _('N/A') ]),
		E('p', {}, [ _('Latest GitHub version'), ': ', version.release_url ? E('a', { 'href': version.release_url, 'target': '_blank', 'rel': 'noreferrer noopener' }, [ latest ]) : latest ]),
		E('p', {}, [ _('GitHub repository'), ': ', E('a', { 'href': repoUrl, 'target': '_blank', 'rel': 'noreferrer noopener' }, [ repo ]) ]),
		E('p', {}, [ versionMessage(version) ]),
		E('p', { 'class': 'ipregion-muted' }, [ _('Update package installs APKs from GitHub Releases using the repository installer.') ]),
		update.running ? E('p', {}, [ _('Update is running') ]) : '',
		E('button', { 'class': 'btn cbi-button cbi-button-apply', 'disabled': canUpdate ? null : 'disabled', 'click': ui.createHandlerFn(this, function() {
			return callUpdate().then(function(res) {
				if (res && res.error)
					ui.addNotification(null, E('p', {}, [ _('Update failed to start') + ': ' + (res.message || res.error) ]), 'error');
				else
					ui.addNotification(null, E('p', {}, [ _('Update started') ]));
			});
		}) }, [ _('Update package') ])
	]);
}

function downloadJson(data, filename) {
	var blob = new Blob([ JSON.stringify(data, null, 2) ], { type: 'application/json' });
	var url = URL.createObjectURL(blob);
	var link = document.createElement('a');
	link.href = url;
	link.download = filename;
	link.click();
	URL.revokeObjectURL(url);
}

function updateState(state) {
	state = state || {};
	setContent('ipregion-state-running', state.running ? _('Running') : _('Idle'));
	setContent('ipregion-state-current', state.current ? [ _('Current check'), ': ', state.current ] : '');
	setContent('ipregion-state-progress', state.total ? [ _('Progress'), ': ', String(state.finished || 0), ' / ', String(state.total) ] : '');
	setContent('ipregion-state-pid', state.pid ? [ _('PID'), ': ', String(state.pid) ] : '');
	setContent('ipregion-state-group', state.group ? [ _('Group'), ': ', state.group, ' / ', state.ip_mode || '', ' / ', state.geoip_mode || '' ] : '');

	var stop = document.getElementById('ipregion-stop');
	if (stop)
		stop.disabled = state.running ? false : true;
}

function updateAiState(state) {
	state = state || {};
	setContent('ipregion-ai-state-running', state.running ? _('Running') : _('Idle'));
	setContent('ipregion-ai-state-current', state.current ? [ _('Current check'), ': ', state.current ] : '');
	setContent('ipregion-ai-state-progress', state.total ? [ _('Progress'), ': ', String(state.finished || 0), ' / ', String(state.total) ] : '');

	var stop = document.getElementById('ipregion-ai-stop');
	if (stop)
		stop.disabled = state.running ? false : true;
}

function updateErrors(id, errors) {
	var node = document.getElementById(id);
	if (!node)
		return;

	setContent(node, (errors || []).length ? [
		E('h3', {}, [ _('Errors') ]),
		E('ul', {}, errors.map(function(err) { return E('li', {}, [ err.code + ': ' + err.message ]); }))
	] : '');
}

function applyResult(result) {
	result = result || {};
	var results = result.results || {};

	if (result.generated_at && currentGeneratedAt && result.generated_at !== currentGeneratedAt)
		[ 'primary', 'custom', 'cdn' ].forEach(clearGroupRows);

	if (result.generated_at)
		currentGeneratedAt = result.generated_at;

	updateNetwork(result);
	updateErrors('ipregion-errors', result.errors);
	updateGroupRows('primary', results.primary || []);
	updateGroupRows('custom', results.custom || []);
	updateGroupRows('cdn', results.cdn || []);
}

function applyAiResult(result) {
	result = result || {};

	if (result.generated_at && aiGeneratedAt && result.generated_at !== aiGeneratedAt)
		clearAiRows();

	if (result.generated_at)
		aiGeneratedAt = result.generated_at;

	updateAiEgress(result);
	updateErrors('ipregion-ai-errors', result.errors);
	updateAiRows(result.providers || []);
}

function pollRegionOnce() {
	return Promise.all([ callStatus(), callResult() ]).then(function(data) {
		var state = data[0] || {};
		var result = data[1] || {};
		updateState(state);
		applyResult(result);

		if (state.running) {
			if (regionPollTimer)
				window.clearTimeout(regionPollTimer);
			regionPollTimer = window.setTimeout(pollRegionOnce, 1500);
		}
	});
}

function pollAiOnce() {
	return Promise.all([ callAiStatus(), callAiResult() ]).then(function(data) {
		var state = data[0] || {};
		var result = data[1] || {};
		updateAiState(state);
		applyAiResult(result);

		if (state.running) {
			if (aiPollTimer)
				window.clearTimeout(aiPollTimer);
			aiPollTimer = window.setTimeout(pollAiOnce, 1500);
		}
	});
}

function routeOptions() {
	return {
		ip_mode: fieldValue('ipregion-ip-mode'),
		interface: fieldValue('ipregion-interface'),
		proxy: fieldValue('ipregion-proxy'),
		timeout: fieldValue('ipregion-timeout')
	};
}

return view.extend({
	load: function() {
		return Promise.all([ callGetConfig(), callInterfaces(), callStatus(), callResult(), callVersion(), callAiProviders(), callAiStatus(), callAiResult() ]);
	},

	render: function(data) {
		var config = data[0] || {};
		var interfaces = data[1] || {};
		var state = data[2] || {};
		var result = data[3] || {};
		var version = data[4] || {};
		var providers = data[5] && data[5].providers || [];
		var aiState = data[6] || {};
		var aiResult = data[7] || {};
		var results = result.results || {};
		referenceCountry = normalizeCountryCode(config.reference_country);

		currentGeneratedAt = result.generated_at || null;
		aiGeneratedAt = aiResult.generated_at || null;

		var page = E('div', { 'class': 'ipregion-page' }, [
			E('link', { 'rel': 'stylesheet', 'href': L.resource('ipregion/ipregion.css') }),
			E('div', { 'class': 'ipregion-hero' }, [
				E('img', { 'src': L.resource('ipregion/logo.png'), 'class': 'ipregion-logo', 'alt': '' }),
				E('div', {}, [
					E('h2', {}, [ _('IP Region') ]),
					E('p', {}, [ _('Check how GeoIP, streaming, CDN and AI services detect this router.') ])
				])
			]),
			renderOptions(config, interfaces),
			E('div', { 'class': 'ipregion-actions' }, [
				E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': ui.createHandlerFn(this, function() {
					resetResultUi();
					return callStart(Object.assign(routeOptions(), {
						group: fieldValue('ipregion-group'),
						geoip_mode: fieldValue('ipregion-geoip-mode')
					})).then(function(res) {
						updateState(res || {});
						ui.addNotification(null, E('p', {}, [ _('IP Region check started') ]));
						return pollRegionOnce();
					});
				}) }, [ _('Run check') ]),
				E('button', { 'id': 'ipregion-stop', 'class': 'btn cbi-button cbi-button-remove', 'disabled': state.running ? null : 'disabled', 'click': ui.createHandlerFn(this, function() { return callStop().then(pollRegionOnce); }) }, [ _('Stop') ]),
				E('button', { 'class': 'btn cbi-button', 'click': pollRegionOnce }, [ _('Refresh result') ]),
				E('button', { 'class': 'btn cbi-button', 'click': function() { callResult().then(function(res) { downloadJson(res, 'ipregion-result.json'); }); } }, [ _('Download JSON') ]),
				E('button', { 'class': 'btn cbi-button', 'click': ui.createHandlerFn(this, function() { return callLog().then(function(res) { ui.showModal(_('Runtime log'), [ E('pre', {}, [ res.log || _('Log is empty') ]), E('div', { 'class': 'right' }, [ E('button', { 'class': 'btn cbi-button', 'click': ui.hideModal }, [ _('Close') ]) ]) ]); }); }) }, [ _('Show log') ]),
				E('button', { 'class': 'btn cbi-button', 'click': ui.createHandlerFn(this, function() { return callSelftest().then(function(res) { ui.showModal(_('Self-test'), [ E('pre', {}, [ JSON.stringify(res, null, 2) ]), E('div', { 'class': 'right' }, [ E('button', { 'class': 'btn cbi-button', 'click': ui.hideModal }, [ _('Close') ]) ]) ]); }); }) }, [ _('Self-test') ]),
				E('button', { 'class': 'btn cbi-button cbi-button-reset', 'click': ui.createHandlerFn(this, function() { resetResultUi(); return callClear().then(pollRegionOnce); }) }, [ _('Clear results') ])
			]),
			E('p', { 'class': 'ipregion-muted' }, [ _('Download JSON includes raw IP addresses.') ]),
			E('div', { 'class': 'ipregion-card' }, [
				E('h3', {}, [ _('Runtime state') ]),
				E('p', { 'id': 'ipregion-state-running' }, [ state.running ? _('Running') : _('Idle') ]),
				E('p', { 'id': 'ipregion-state-current' }, state.current ? [ _('Current check'), ': ', state.current ] : []),
				E('p', { 'id': 'ipregion-state-progress' }, state.total ? [ _('Progress'), ': ', String(state.finished || 0), ' / ', String(state.total) ] : []),
				E('p', { 'id': 'ipregion-state-pid' }, state.pid ? [ _('PID'), ': ', String(state.pid) ] : []),
				E('p', { 'id': 'ipregion-state-group' }, state.group ? [ _('Group'), ': ', state.group, ' / ', state.ip_mode || '', ' / ', state.geoip_mode || '' ] : [])
			]),
			renderVersion.call(this, version),
			renderNetwork(result),
			E('div', { 'id': 'ipregion-errors', 'class': 'ipregion-card ipregion-error-card' }, (result.errors || []).length ? [
				E('h3', {}, [ _('Errors') ]),
				E('ul', {}, result.errors.map(function(err) { return E('li', {}, [ err.code + ': ' + err.message ]); }))
			] : []),
			renderGroup(_('GeoIP services'), 'primary', results.primary, groupDescription('primary')),
			renderGroup(_('Popular services'), 'custom', results.custom, groupDescription('custom')),
			renderGroup(_('CDN services'), 'cdn', results.cdn, groupDescription('cdn')),

			E('hr'),
			E('div', { 'class': 'ipregion-hero ipregion-ai-hero' }, [
				E('div', {}, [
					E('h2', {}, [ _('AI Providers') ]),
					E('p', {}, [ _('Check whether popular AI API endpoints are reachable through the selected route.') ])
				])
			]),
			renderAiOptions(providers),
			E('div', { 'class': 'ipregion-actions' }, [
				E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': ui.createHandlerFn(this, function() {
					var provider = fieldValue('ipregion-ai-provider');
					resetAiUi();
					return callAiStart(Object.assign(routeOptions(), {
						category: fieldValue('ipregion-ai-category'),
						providers: provider ? [ provider ] : []
					})).then(function(res) {
						updateAiState(res || {});
						ui.addNotification(null, E('p', {}, [ _('AI provider check started') ]));
						return pollAiOnce();
					});
				}) }, [ _('Run AI check') ]),
				E('button', { 'id': 'ipregion-ai-stop', 'class': 'btn cbi-button cbi-button-remove', 'disabled': aiState.running ? null : 'disabled', 'click': ui.createHandlerFn(this, function() { return callAiStop().then(pollAiOnce); }) }, [ _('Stop') ]),
				E('button', { 'class': 'btn cbi-button', 'click': pollAiOnce }, [ _('Refresh result') ]),
				E('button', { 'class': 'btn cbi-button', 'click': function() { callAiResult().then(function(res) { downloadJson(res, 'ipregion-ai-result.json'); }); } }, [ _('Download JSON') ]),
				E('button', { 'class': 'btn cbi-button', 'click': ui.createHandlerFn(this, function() { return callAiLog().then(function(res) { ui.showModal(_('Runtime log'), [ E('pre', {}, [ res.log || _('Log is empty') ]), E('div', { 'class': 'right' }, [ E('button', { 'class': 'btn cbi-button', 'click': ui.hideModal }, [ _('Close') ]) ]) ]); }); }) }, [ _('Show log') ]),
				E('button', { 'class': 'btn cbi-button cbi-button-reset', 'click': ui.createHandlerFn(this, function() { resetAiUi(); return callAiClear().then(pollAiOnce); }) }, [ _('Clear results') ])
			]),
			E('p', { 'class': 'ipregion-muted' }, [ _('Download JSON includes raw IP addresses.') ]),
			E('div', { 'class': 'ipregion-card' }, [
				E('h3', {}, [ _('Runtime state') ]),
				E('p', { 'id': 'ipregion-ai-state-running' }, [ aiState.running ? _('Running') : _('Idle') ]),
				E('p', { 'id': 'ipregion-ai-state-current' }, aiState.current ? [ _('Current check'), ': ', aiState.current ] : []),
				E('p', { 'id': 'ipregion-ai-state-progress' }, aiState.total ? [ _('Progress'), ': ', String(aiState.finished || 0), ' / ', String(aiState.total) ] : [])
			]),
			renderAiEgress(aiResult),
			E('div', { 'id': 'ipregion-ai-errors', 'class': 'ipregion-card ipregion-error-card' }, (aiResult.errors || []).length ? [
				E('h3', {}, [ _('Errors') ]),
				E('ul', {}, aiResult.errors.map(function(err) { return E('li', {}, [ err.code + ': ' + err.message ]); }))
			] : []),
			renderAiTable(aiResult.providers)
		]);

		if (state.running)
			regionPollTimer = window.setTimeout(pollRegionOnce, 1500);

		if (aiState.running)
			aiPollTimer = window.setTimeout(pollAiOnce, 1500);

		return page;
	}
});
