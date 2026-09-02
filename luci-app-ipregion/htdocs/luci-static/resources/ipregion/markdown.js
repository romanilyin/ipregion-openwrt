'use strict';
'require baseclass';

function isIpv6(value) {
	if (value.indexOf(':') < 0 || /[^A-Fa-f0-9:.]/.test(value) || value.indexOf(':::') >= 0)
		return false;

	var embedded = value.match(/(?:^|:)((?:[0-9]{1,3}\.){3}[0-9]{1,3})$/);
	if (embedded) {
		if (!isIpv4(embedded[1]))
			return false;
		value = value.substring(0, value.length - embedded[1].length) + '0:0';
	}

	var halves = value.split('::');
	if (halves.length > 2)
		return false;

	var parts = [];
	halves.forEach(function(half) {
		half.split(':').forEach(function(part) {
			if (part)
				parts.push(part);
		});
	});

	if (!parts.every(function(part) { return /^[A-Fa-f0-9]{1,4}$/.test(part); }))
		return false;

	return halves.length === 2 ? parts.length < 8 : parts.length === 8;
}

function isIpv4(value) {
	var parts = value.split('.');
	return parts.length === 4 && parts.every(function(part) {
		return /^[0-9]{1,3}$/.test(part) && Number(part) <= 255;
	});
}

function escapeRegExp(value) {
	return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function redactSensitive(text, sensitive) {
	var values = (sensitive || []).filter(function(value) { return value !== ''; });
	values.sort(function(left, right) { return right.length - left.length; });
	if (!values.length)
		return text;

	var pattern = values.map(escapeRegExp).join('|');
	return text.replace(new RegExp('(^|[^A-Za-z0-9_-])(' + pattern + ')(?=$|[^A-Za-z0-9_-])', 'gi'), '$1[' + _('route detail omitted') + ']');
}

function redactAddresses(text) {
	text = text.replace(/\[([A-Fa-f0-9:.]+)\](?::[0-9]{1,5})?/g, function(full, address) {
		return isIpv4(address) || isIpv6(address) ? '[' + _('IP omitted') + ']' : full;
	});
	text = text.replace(/[A-Fa-f0-9:.]{2,}/g, function(candidate) {
		var suffix = '';
		while (candidate.length && candidate.charAt(candidate.length - 1) === '.') {
			suffix += '.';
			candidate = candidate.substring(0, candidate.length - 1);
		}
		return (isIpv4(candidate) || isIpv6(candidate) ? '[' + _('IP omitted') + ']' : candidate) + suffix;
	});
	return text.replace(/\b((?:[0-9]{1,3}\.){3}[0-9]{1,3})(?::[0-9]{1,5})?\b/g, function(full, address) {
		return isIpv4(address) ? '[' + _('IP omitted') + ']' : full;
	});
}

function sensitiveValues(result) {
	var values = [];
	var add = function(value) {
		if (value != null && value !== '' && values.indexOf(String(value)) < 0)
			values.push(String(value));
	};
	var request = result && result.request || {};
	var route = result && result.route || {};
	var network = result && result.network || {};
	var egress = result && result.egress || {};

	[ request.proxy, request.proxy_profile, request.interface, request.name, route.proxy, route.proxy_profile, route.interface,
		network.ipv4, network.ipv6, egress.ip, egress.ipv4, egress.ipv6 ].forEach(add);
	(result && result.providers || []).forEach(function(row) {
		add(row.remote_ip);
		add(row.request_id);
	});
	(result && result.probes || []).forEach(function(row) {
		add(row.endpoint);
		(row.answers || []).forEach(function(answer) { add(answer.value); });
	});
	return values;
}

function clean(value, sensitive) {
	var text = value == null ? '' : String(value);

	text = redactSensitive(text, sensitive);
	text = text.replace(/[\u0000-\u001f\u007f]+/g, ' ');
	text = text.replace(/\b(?:localhost|(?:[A-Za-z0-9_-]+\.)+[A-Za-z0-9_-]+):[0-9]{1,5}\b/g, '[' + _('endpoint omitted') + ']');
	text = redactAddresses(text);
	text = text.replace(/\\/g, '\\\\').replace(/\b([A-Za-z][A-Za-z0-9+.-]*):(?=\/\/)/g, '$1\\:').replace(/([!`*_[\]()])/g, '\\$1').replace(/\|/g, '\\|').replace(/</g, '&lt;').replace(/>/g, '&gt;').trim();
	return text.length > 500 ? text.substring(0, 497) + '...' : text;
}

function present(value, sensitive) {
	return value == null || value === '' ? _('N/A') : clean(value, sensitive);
}

function table(headers, rows, sensitive) {
	var lines = [
		'| ' + headers.map(function(header) { return clean(header, sensitive); }).join(' | ') + ' |',
		'| ' + headers.map(function() { return '---'; }).join(' | ') + ' |'
	];

	rows.forEach(function(row) {
		lines.push('| ' + row.map(function(value) { return present(value, sensitive); }).join(' | ') + ' |');
	});

	return lines.join('\n');
}

function metadata(result, fields, sensitive) {
	var lines = [];

	if (result.generated_at)
		lines.push('- ' + _('Generated') + ': ' + clean(result.generated_at, sensitive));
	if (result.duration_ms != null)
		lines.push('- ' + _('Duration') + ': ' + clean(result.duration_ms, sensitive) + ' ms');

	fields.forEach(function(field) {
		var value = result.request && result.request[field.key];
		if (value != null && value !== '')
			lines.push('- ' + field.label + ': ' + clean(value, sensitive));
	});

	return lines.join('\n');
}

function errorSection(errors, sensitive) {
	errors = errors || [];
	if (!errors.length)
		return '';

	return '## ' + _('Errors') + '\n\n' + errors.map(function(error) {
		return '- ' + clean(error.code || 'error', sensitive) + ': ' + clean(error.message || _('Unknown error'), sensitive);
	}).join('\n');
}

function probeText(probe) {
	if (!probe)
		return _('N/A');

	var parts = [ probe.label || probe.status || _('N/A') ];
	if (probe.value != null && probe.value !== '')
		parts.push(probe.value);
	if (probe.http_code)
		parts.push('HTTP ' + probe.http_code);
	if (probe.latency_ms != null)
		parts.push(probe.latency_ms + ' ms');
	if (probe.error)
		parts.push(probe.error);
	return parts.join('; ');
}

function regular(result) {
	result = result || {};
	var sensitive = sensitiveValues(result);
	var sections = [
		'# ' + _('IPRegion result'),
		metadata(result, [
			{ key: 'group', label: _('Group') },
			{ key: 'ip_mode', label: _('IP mode') },
			{ key: 'geoip_mode', label: _('GeoIP mode') }
		], sensitive),
		'> ' + _('Raw IP addresses, proxy endpoints and route identifiers are omitted.')
	];
	var groups = result.results || {};

	[ [ _('GeoIP services'), 'primary' ], [ _('Popular services'), 'custom' ], [ _('CDN services'), 'cdn' ] ].forEach(function(group) {
		var rows = groups[group[1]] || [];
		if (!rows.length)
			return;

		sections.push('## ' + group[0]);
		sections.push(table([ _('Service'), _('IPv4'), _('IPv6') ], rows.map(function(row) {
			return [ row.service || row.id, probeText(row.ipv4), probeText(row.ipv6) ];
		}), sensitive));
	});

	var errors = errorSection(result.errors, sensitive);
	if (errors)
		sections.push(errors);
	return sections.filter(Boolean).join('\n\n') + '\n';
}

function ai(result) {
	result = result || {};
	var sensitive = sensitiveValues(result);
	var rows = result.providers || [];
	var sections = [
		'# ' + _('IPRegion AI result'),
		metadata(result, [
			{ key: 'category', label: _('Category') },
			{ key: 'ip_mode', label: _('IP mode') }
		], sensitive),
		'> ' + _('Raw IP addresses, proxy endpoints and route identifiers are omitted.'),
		table([ _('Provider'), _('Role'), _('Transport'), _('HTTP'), _('Status'), _('Time'), _('Diagnosis') ], rows.map(function(row) {
			return [
				row.name || row.id,
				row.endpoint_role || row.kind,
				row.transport_label || row.transport,
				row.http_code || 0,
				row.label || row.status,
				row.latency_ms != null ? row.latency_ms + ' ms' : _('N/A'),
				row.diagnosis
			];
		}), sensitive)
	];
	var errors = errorSection(result.errors, sensitive);
	if (errors)
		sections.push(errors);
	return sections.filter(Boolean).join('\n\n') + '\n';
}

function dns(result) {
	result = result || {};
	var sensitive = sensitiveValues(result);
	var summary = result.summary || {};
	var findings = summary.finding_details || [];
	var sections = [
		'# ' + _('IPRegion DNS result'),
		metadata(result, [
			{ key: 'transport', label: _('Transport') },
			{ key: 'type', label: _('Record type') },
			{ key: 'ip_mode', label: _('IP mode') }
		], sensitive),
		'- ' + _('Passed') + ': ' + clean(summary.passed || 0, sensitive) + '\n- ' + _('Failed') + ': ' + clean(summary.failed || 0, sensitive) + '\n- ' + _('Interception') + ': ' + clean(summary.interception && summary.interception.status || 'not_run', sensitive),
		'> ' + _('Query names, answer values, endpoint addresses and route identifiers are omitted.'),
		table([ _('Provider'), _('Transport'), _('Network'), _('TLS'), _('Status'), _('Rcode'), _('Answers'), _('Time'), _('Diagnosis') ], (result.probes || []).map(function(row) {
			return [
				row.name || row.id,
				row.transport_label || row.transport,
				row.ip_label || (row.ip_version ? 'IPv' + row.ip_version : ''),
				row.tls_verified == null ? _('N/A') : row.tls_verified ? _('Verified') : _('Not verified'),
				row.label || row.status,
				row.rcode,
				(row.answers || []).length,
				row.latency_ms != null ? row.latency_ms + ' ms' : _('N/A'),
				row.diagnosis || row.status
			];
		}), sensitive)
	];

	if (findings.length)
		sections.push('## ' + _('Findings') + '\n\n' + findings.map(function(finding) {
			return '- ' + clean(finding.code || finding.message || 'finding', sensitive);
		}).join('\n'));

	var errors = errorSection(result.errors, sensitive);
	if (errors)
		sections.push(errors);
	return sections.filter(Boolean).join('\n\n') + '\n';
}

var api = { regular: regular, ai: ai, dns: dns, clean: clean };

if (typeof module !== 'undefined' && module.exports)
	module.exports = api;
else
	return baseclass.extend(api);
