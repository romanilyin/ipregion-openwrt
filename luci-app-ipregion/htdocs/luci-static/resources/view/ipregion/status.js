'use strict';
'require view';
'require rpc';
'require ui';

var regionPollTimer = null;
var aiPollTimer = null;
var dnsPollTimer = null;
var currentGeneratedAt = null;
var aiGeneratedAt = null;
var dnsGeneratedAt = null;
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
var callDnsProviders = rpc.declare({ object: 'luci.ipregion', method: 'list_dns_providers', expect: { '': {} } });
var callDnsStart = rpc.declare({ object: 'luci.ipregion', method: 'dns_start', params: [ 'options' ], expect: { '': {} } });
var callDnsStop = rpc.declare({ object: 'luci.ipregion', method: 'dns_stop', expect: { '': {} } });
var callDnsStatus = rpc.declare({ object: 'luci.ipregion', method: 'dns_status', expect: { '': {} } });
var callDnsResult = rpc.declare({ object: 'luci.ipregion', method: 'dns_result', expect: { '': {} } });
var callDnsLog = rpc.declare({ object: 'luci.ipregion', method: 'dns_log', expect: { '': {} } });
var callDnsClear = rpc.declare({ object: 'luci.ipregion', method: 'dns_clear', expect: { '': {} } });

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

function dnsBadge(row) {
	var status = row && row.status || 'unavailable';
	var labels = {
		ok: _('OK'),
		degraded: _('Fallback address'),
		timeout: _('Timeout'),
		certificate_failed: _('Certificate failed'),
		tls_failed: _('TLS failed'),
		connection_failed: _('Connection failed'),
		http_failed: _('HTTP error'),
		dns_nxdomain: _('NXDOMAIN'),
		dns_servfail: _('SERVFAIL'),
		dns_error: _('DNS error'),
		no_answer: _('No answer'),
		truncated: _('Truncated'),
		malformed_response: _('Malformed response'),
		unavailable: _('Unavailable')
	};
	var label = labels[status] || row && row.label || _('N/A');
	var cls = 'ipregion-badge';

	if (status === 'ok')
		cls += ' ipregion-ok';
	else if (status === 'degraded' || status === 'dns_nxdomain' || status === 'dns_servfail' || status === 'dns_error' || status === 'no_answer' || status === 'truncated')
		cls += ' ipregion-warn';
	else if (status === 'unavailable')
		cls += ' ipregion-na';
	else
		cls += ' ipregion-error';

	return E('span', { 'class': cls }, [ label ]);
}

function dnsDiagnosis(row) {
	var transport = row && (row.transport_label || row.transport) || _('DNS transport');
	switch (row && row.status) {
	case 'ok': return transport + ' ' + (row.encrypted ? _('returned a valid authenticated DNS response.') : _('returned a valid direct DNS response.'));
	case 'degraded': return transport + ' ' + _('succeeded through a fallback resolver address.');
	case 'timeout': return transport + ' ' + _('did not respond before timeout; the endpoint or transport may be dropped.');
	case 'certificate_failed': return transport + ' ' + _('certificate validation failed; check system time or possible TLS interception.');
	case 'tls_failed': return transport + ' ' + _('TLS handshake failed.');
	case 'connection_failed': return transport + ' ' + _('Connection failed or was reset.');
	case 'http_failed': return _('DoH returned an HTTP error.');
	case 'dns_nxdomain': return _('The resolver returned NXDOMAIN for the probe name.');
	case 'dns_servfail': return _('The resolver returned SERVFAIL for the probe name.');
	case 'dns_error': return _('The resolver returned a DNS error response.');
	case 'no_answer': return _('The resolver returned NOERROR without a usable answer.');
	case 'truncated': return _('The UDP response was truncated and was not retried over TCP.');
	case 'malformed_response': return _('The endpoint returned a malformed or mismatched DNS response.');
	case 'unavailable': return _('The requested DNS transport is unavailable.');
	default: return row && row.diagnosis || _('Unknown error');
	}
}

function dnsFinding(finding) {
	var prefix = (finding.name || finding.id || '') + ' ' + (finding.ip_label || '') + ': ';
	switch (finding.code) {
	case 'rcode_mismatch': return prefix + _('DoH and DoT returned different DNS response codes.');
	case 'answer_mismatch': return prefix + _('DoH and DoT returned different answers; resolver or CDN variation may be legitimate.');
	case 'dot_unavailable': return prefix + _('DoH works while DoT fails; TCP/853 may be filtered.');
	case 'doh_unavailable': return prefix + _('DoT works while DoH fails; the DoH endpoint may be filtered.');
	case 'both_unavailable': return prefix + _('both encrypted DNS transports are unavailable.');
	case 'udp_unavailable': return prefix + _('UDP/53 is unavailable.');
	case 'tcp_unavailable': return prefix + _('TCP/53 is unavailable.');
	case 'plain_answer_mismatch': return prefix + _('Plain and authenticated DNS returned different answers; resolver or CDN variation may be legitimate.');
	case 'likely_udp_dns_interception': return prefix + _('UDP/53 returned a different DNS response code while TCP/53 matched authenticated DNS; UDP interception is likely.');
	case 'likely_tcp_dns_interception': return prefix + _('TCP/53 returned a different DNS response code while UDP/53 matched authenticated DNS; TCP interception is likely.');
	case 'likely_plain_dns_interception': return prefix + _('UDP/53 and TCP/53 agree with each other but differ from authenticated DNS; plain DNS interception is likely.');
	default: return finding.message || finding.code || '';
	}
}

function dnsInterceptionText(summary) {
	var status = summary && summary.interception && summary.interception.status || 'not_run';
	if (status === 'likely') return _('Likely DNS interception');
	if (status === 'no_mismatch_detected') return _('No DNS response mismatch detected');
	if (status === 'inconclusive') return _('Interception check inconclusive');
	if (status === 'pending') return _('Interception comparison pending');
	return _('Interception comparison not run');
}

function dnsStartError(result) {
	switch (result && result.error) {
	case 'invalid_dns_name': return _('DNS query name is invalid');
	case 'invalid_dns_provider': return _('DNS provider is invalid');
	case 'invalid_interface': return _('Network interface is invalid');
	case 'dns_stop_failed': return _('DNS worker did not stop');
	default: return result && (result.message || result.error) || _('Unknown error');
	}
}

function dnsErrorText(error) {
	switch (error && error.code) {
	case 'no_dns_providers': return error.code + ': ' + _('No DNS providers matched the requested filters');
	case 'no_compatible_dns_transports': return error.code + ': ' + _('No selected DNS provider supports the requested transport');
	case 'kdig_missing': return error.code + ': ' + _('kdig is required for UDP, TCP and DNS-over-TLS checks');
	default: return error && (error.code + ': ' + (error.message || _('Unknown error'))) || _('Unknown error');
	}
}

function dnsAnswers(row) {
	var answers = row && row.answers || [];
	return answers.length ? answers.map(function(answer) { return answer.value; }).join(', ') : _('N/A');
}

function dnsTlsStatus(row) {
	if (!row || row.tls_verified == null)
		return _('N/A');
	return row.tls_verified ? _('Verified') : _('Not verified');
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

function dnsRowId(row) {
	return safeId(row.row_id || ((row.id || row.name) + '-' + (row.transport || '') + '-' + (row.ip_label || row.ip_version || '')));
}

function renderDnsRow(row) {
	var id = dnsRowId(row);

	return E('tr', { 'class': 'tr ipregion-dns-data-row', 'id': 'ipregion-dns-row-' + id }, [
		E('td', { 'class': 'td' }, [ row.name || row.id ]),
		E('td', { 'class': 'td' }, [ row.transport_label || row.transport || '' ]),
		E('td', { 'class': 'td' }, [ row.ip_label || ('IPv' + row.ip_version) ]),
		E('td', { 'class': 'td', 'id': 'ipregion-dns-endpoint-' + id }, [ row.endpoint || _('N/A') ]),
		E('td', { 'class': 'td', 'id': 'ipregion-dns-tls-' + id }, [ dnsTlsStatus(row) ]),
		E('td', { 'class': 'td', 'id': 'ipregion-dns-status-' + id }, [ dnsBadge(row), row.rcode ? ' ' + row.rcode : '' ]),
		E('td', { 'class': 'td', 'id': 'ipregion-dns-answer-' + id }, [ dnsAnswers(row) ]),
		E('td', { 'class': 'td', 'id': 'ipregion-dns-time-' + id }, [ row.latency_ms != null ? row.latency_ms + ' ms' : _('N/A') ]),
		E('td', { 'class': 'td', 'id': 'ipregion-dns-diagnosis-' + id }, [ dnsDiagnosis(row) ])
	]);
}

function renderDnsTable(rows) {
	rows = rows || [];
	var tableRows = [
		E('tr', { 'class': 'tr table-titles' }, [
			E('th', { 'class': 'th' }, [ _('Provider') ]),
			E('th', { 'class': 'th' }, [ _('Transport') ]),
			E('th', { 'class': 'th' }, [ _('Network') ]),
			E('th', { 'class': 'th' }, [ _('Endpoint') ]),
			E('th', { 'class': 'th' }, [ _('TLS') ]),
			E('th', { 'class': 'th' }, [ _('DNS status') ]),
			E('th', { 'class': 'th' }, [ _('Answer') ]),
			E('th', { 'class': 'th' }, [ _('Time') ]),
			E('th', { 'class': 'th' }, [ _('Diagnosis') ])
		])
	];

	if (rows.length)
		rows.forEach(function(row) { tableRows.push(renderDnsRow(row)); });
	else
		tableRows.push(E('tr', { 'class': 'tr ipregion-dns-empty-row', 'id': 'ipregion-dns-empty' }, [ E('td', { 'class': 'td', 'colspan': 9 }, [ _('No results yet') ]) ]));

	return E('div', { 'class': 'ipregion-card ipregion-table-card' }, [
		E('h3', {}, [ _('DNS results') ]),
		E('p', { 'class': 'ipregion-muted' }, [ _('One run checks direct UDP/53, TCP/53, DoH and DoT responses in the same table. TLS hostnames are verified for encrypted transports.') ]),
		E('table', { 'class': 'table', 'id': 'ipregion-dns-table' }, tableRows)
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

function clearDnsRows() {
	var table = document.getElementById('ipregion-dns-table');
	if (!table)
		return;

	Array.prototype.slice.call(table.querySelectorAll('.ipregion-dns-data-row')).forEach(function(row) { row.remove(); });
	if (!document.getElementById('ipregion-dns-empty'))
		table.appendChild(E('tr', { 'class': 'tr ipregion-dns-empty-row', 'id': 'ipregion-dns-empty' }, [ E('td', { 'class': 'td', 'colspan': 9 }, [ _('No results yet') ]) ]));
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

function resetDnsUi() {
	dnsGeneratedAt = null;
	clearDnsRows();
	setContent('ipregion-dns-summary', '');
	setContent('ipregion-dns-interception', '');
	setContent('ipregion-dns-findings', '');
	setContent('ipregion-dns-errors', '');
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

function updateDnsRows(rows) {
	rows = rows || [];
	var table = document.getElementById('ipregion-dns-table');
	if (!table)
		return;

	var empty = document.getElementById('ipregion-dns-empty');
	if (rows.length && empty)
		empty.remove();

	rows.forEach(function(row) {
		var id = dnsRowId(row);
		var existing = document.getElementById('ipregion-dns-row-' + id);
		if (!existing) {
			table.appendChild(renderDnsRow(row));
			return;
		}
		setContent('ipregion-dns-endpoint-' + id, row.endpoint || _('N/A'));
		setContent('ipregion-dns-tls-' + id, dnsTlsStatus(row));
		setContent('ipregion-dns-status-' + id, [ dnsBadge(row), row.rcode ? ' ' + row.rcode : '' ]);
		setContent('ipregion-dns-answer-' + id, dnsAnswers(row));
		setContent('ipregion-dns-time-' + id, row.latency_ms != null ? row.latency_ms + ' ms' : _('N/A'));
		setContent('ipregion-dns-diagnosis-' + id, dnsDiagnosis(row));
	});

	if (!rows.length && !document.getElementById('ipregion-dns-empty'))
		table.appendChild(E('tr', { 'class': 'tr ipregion-dns-empty-row', 'id': 'ipregion-dns-empty' }, [ E('td', { 'class': 'td', 'colspan': 9 }, [ _('No results yet') ]) ]));
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

function renderDnsOptions(providers, result) {
	providers = providers || [];
	var request = result && result.request || {};

	return E('div', { 'class': 'ipregion-card ipregion-options' }, [
		E('label', {}, [ _('DNS provider'), E('select', { 'id': 'ipregion-dns-provider' }, [
			E('option', { 'value': '' }, [ _('All providers') ])
		].concat(providers.map(function(provider) {
			return E('option', { 'value': provider.id }, [ provider.name || provider.id ]);
		}))) ]),
		E('label', {}, [ _('Probe name'), E('input', { 'id': 'ipregion-dns-name', 'type': 'text', 'value': request.name || 'example.com' }) ]),
		E('label', {}, [ _('Record type'), E('select', { 'id': 'ipregion-dns-type' }, [
			E('option', { 'value': 'A', 'selected': request.type !== 'AAAA' ? 'selected' : null }, [ 'A' ]),
			E('option', { 'value': 'AAAA', 'selected': request.type === 'AAAA' ? 'selected' : null }, [ 'AAAA' ])
		]) ]),
		E('p', { 'class': 'ipregion-muted ipregion-group-help' }, [ _('The single DNS run checks UDP/53, TCP/53, DoH and DoT using the IP mode, interface and timeout controls above. SOCKS5 proxy routing is not used.') ]),
		E('p', { 'class': 'ipregion-muted ipregion-group-help' }, [ _('Matching responses mean no mismatch was detected; they do not prove that interception is absent.') ])
	]);
}

function renderDnsSummary(result) {
	var summary = result && result.summary || {};
	var findings = (summary.finding_details || []).length ? summary.finding_details.map(dnsFinding) : summary.findings || [];
	return E('div', { 'class': 'ipregion-card' }, [
		E('h3', {}, [ _('DNS security summary') ]),
		E('p', { 'id': 'ipregion-dns-summary' }, [ _('Passed'), ': ', String(summary.passed || 0), ' / ', _('Failed'), ': ', String(summary.failed || 0) ]),
		E('p', { 'id': 'ipregion-dns-interception' }, [ dnsInterceptionText(summary) ]),
		E('div', { 'id': 'ipregion-dns-findings' }, findings.length ? [
			E('h4', {}, [ _('Findings') ]),
			E('ul', {}, findings.map(function(finding) { return E('li', {}, [ finding ]); }))
		] : [])
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

function updateDnsState(state) {
	state = state || {};
	setContent('ipregion-dns-state-running', state.running ? _('Running') : _('Idle'));
	setContent('ipregion-dns-state-current', state.current ? [ _('Current check'), ': ', state.current ] : '');
	setContent('ipregion-dns-state-progress', state.total ? [ _('Progress'), ': ', String(state.finished || 0), ' / ', String(state.total) ] : '');

	var stop = document.getElementById('ipregion-dns-stop');
	if (stop)
		stop.disabled = state.running ? false : true;
	var run = document.getElementById('ipregion-dns-run');
	if (run)
		run.disabled = state.running ? true : false;
	var clear = document.getElementById('ipregion-dns-clear');
	if (clear)
		clear.disabled = state.running ? true : false;
}

function updateErrors(id, errors, formatter) {
	var node = document.getElementById(id);
	if (!node)
		return;

	setContent(node, (errors || []).length ? [
		E('h3', {}, [ _('Errors') ]),
		E('ul', {}, errors.map(function(err) { return E('li', {}, [ formatter ? formatter(err) : err.code + ': ' + err.message ]); }))
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

function applyDnsResult(result) {
	result = result || {};
	var summary = result.summary || {};

	if (result.generated_at && dnsGeneratedAt && result.generated_at !== dnsGeneratedAt)
		clearDnsRows();
	if (result.generated_at)
		dnsGeneratedAt = result.generated_at;

	updateDnsRows(result.probes || []);
	updateErrors('ipregion-dns-errors', result.errors, dnsErrorText);
	setContent('ipregion-dns-summary', [ _('Passed'), ': ', String(summary.passed || 0), ' / ', _('Failed'), ': ', String(summary.failed || 0) ]);
	setContent('ipregion-dns-interception', dnsInterceptionText(summary));
	var findings = (summary.finding_details || []).length ? summary.finding_details.map(dnsFinding) : summary.findings || [];
	setContent('ipregion-dns-findings', findings.length ? [
		E('h4', {}, [ _('Findings') ]),
		E('ul', {}, findings.map(function(finding) { return E('li', {}, [ finding ]); }))
	] : '');
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

function pollDnsOnce() {
	return Promise.all([ callDnsStatus(), callDnsResult() ]).then(function(data) {
		var state = data[0] || {};
		var result = data[1] || {};
		updateDnsState(state);
		applyDnsResult(result);

		if (state.running) {
			if (dnsPollTimer)
				window.clearTimeout(dnsPollTimer);
			dnsPollTimer = window.setTimeout(pollDnsOnce, 1500);
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

function dnsRouteOptions() {
	return {
		ip_mode: fieldValue('ipregion-ip-mode'),
		interface: fieldValue('ipregion-interface'),
		timeout: fieldValue('ipregion-timeout')
	};
}

return view.extend({
	load: function() {
		return Promise.all([ callGetConfig(), callInterfaces(), callStatus(), callResult(), callVersion(), callAiProviders(), callAiStatus(), callAiResult(), callDnsProviders(), callDnsStatus(), callDnsResult() ]);
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
		var dnsProviders = data[8] && data[8].providers || [];
		var dnsState = data[9] || {};
		var dnsResult = data[10] || {};
		var results = result.results || {};
		referenceCountry = normalizeCountryCode(config.reference_country);

		currentGeneratedAt = result.generated_at || null;
		aiGeneratedAt = aiResult.generated_at || null;
		dnsGeneratedAt = dnsResult.generated_at || null;

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
			E('div', { 'class': 'ipregion-hero' }, [
				E('div', {}, [
					E('h2', {}, [ _('DNS Security') ]),
					E('p', {}, [ _('Compare UDP/53, TCP/53, DoH and DoT responses from public and active-interface DNS resolvers in one check.') ])
				])
			]),
			renderDnsOptions(dnsProviders, dnsResult),
			E('div', { 'class': 'ipregion-actions' }, [
				E('button', { 'id': 'ipregion-dns-run', 'class': 'btn cbi-button cbi-button-apply', 'disabled': dnsState.running ? 'disabled' : null, 'click': ui.createHandlerFn(this, function() {
					var provider = fieldValue('ipregion-dns-provider');
					resetDnsUi();
					return callDnsStart(Object.assign(dnsRouteOptions(), {
						transport: 'all',
						name: fieldValue('ipregion-dns-name'),
						type: fieldValue('ipregion-dns-type'),
						providers: provider ? [ provider ] : []
					})).then(function(res) {
						if (res && res.error) {
							ui.addNotification(null, E('p', {}, [ _('DNS security check failed to start') + ': ' + dnsStartError(res) ]), 'error');
							return;
						}
						updateDnsState(res || {});
						ui.addNotification(null, E('p', {}, [ _('DNS security check started') ]));
						return pollDnsOnce();
					});
				}) }, [ _('Run DNS check') ]),
				E('button', { 'id': 'ipregion-dns-stop', 'class': 'btn cbi-button cbi-button-remove', 'disabled': dnsState.running ? null : 'disabled', 'click': ui.createHandlerFn(this, function() {
					return callDnsStop().then(function(res) {
						if (res && res.error)
							ui.addNotification(null, E('p', {}, [ _('DNS security check failed to stop') + ': ' + dnsStartError(res) ]), 'error');
						return pollDnsOnce();
					});
				}) }, [ _('Stop') ]),
				E('button', { 'class': 'btn cbi-button', 'click': pollDnsOnce }, [ _('Refresh result') ]),
				E('button', { 'class': 'btn cbi-button', 'click': function() { callDnsResult().then(function(res) { downloadJson(res, 'ipregion-dns-result.json'); }); } }, [ _('Download JSON') ]),
				E('button', { 'class': 'btn cbi-button', 'click': ui.createHandlerFn(this, function() { return callDnsLog().then(function(res) { ui.showModal(_('Runtime log'), [ E('pre', {}, [ res.log || _('Log is empty') ]), E('div', { 'class': 'right' }, [ E('button', { 'class': 'btn cbi-button', 'click': ui.hideModal }, [ _('Close') ]) ]) ]); }); }) }, [ _('Show log') ]),
				E('button', { 'id': 'ipregion-dns-clear', 'class': 'btn cbi-button cbi-button-reset', 'disabled': dnsState.running ? 'disabled' : null, 'click': ui.createHandlerFn(this, function() {
					return callDnsClear().then(function(res) {
						if (res && res.error) {
							ui.addNotification(null, E('p', {}, [ _('Stop the DNS security check before clearing its results') ]), 'error');
							return;
						}
						resetDnsUi();
						return pollDnsOnce();
					});
				}) }, [ _('Clear results') ])
			]),
			E('div', { 'class': 'ipregion-card' }, [
				E('h3', {}, [ _('Runtime state') ]),
				E('p', { 'id': 'ipregion-dns-state-running' }, [ dnsState.running ? _('Running') : _('Idle') ]),
				E('p', { 'id': 'ipregion-dns-state-current' }, dnsState.current ? [ _('Current check'), ': ', dnsState.current ] : []),
				E('p', { 'id': 'ipregion-dns-state-progress' }, dnsState.total ? [ _('Progress'), ': ', String(dnsState.finished || 0), ' / ', String(dnsState.total) ] : [])
			]),
			renderDnsSummary(dnsResult),
			E('div', { 'id': 'ipregion-dns-errors', 'class': 'ipregion-card ipregion-error-card' }, (dnsResult.errors || []).length ? [
				E('h3', {}, [ _('Errors') ]),
				E('ul', {}, dnsResult.errors.map(function(err) { return E('li', {}, [ dnsErrorText(err) ]); }))
			] : []),
			renderDnsTable(dnsResult.probes),

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

		if (dnsState.running)
			dnsPollTimer = window.setTimeout(pollDnsOnce, 1500);

		return page;
	}
});
