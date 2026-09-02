'use strict';
'require view';
'require form';
'require rpc';
'require ui';
'require uci';

var callDetectedCountry = rpc.declare({ object: 'luci.ipregion', method: 'detected_country', expect: { '': {} } });

function referenceCountryInput(section_id) {
	return document.getElementById('widget.cbid.ipregion.' + section_id + '.reference_country') ||
		document.querySelector('[name="cbid.ipregion.' + section_id + '.reference_country"]');
}

function setReferenceCountry(section_id, value) {
	var node = referenceCountryInput(section_id);
	if (!node)
		return false;

	node.value = String(value || '').toUpperCase();
	node.dispatchEvent(new Event('change', { bubbles: true }));
	return true;
}

return view.extend({
	load: function() {
		return uci.load('ipregion');
	},

	render: function() {
		var m, s, p, o;
		var profiles = uci.sections('ipregion', 'proxy') || [];
		var legacyProxy = uci.get('ipregion', 'main', 'proxy') || '';
		var selectedProxy = uci.get('ipregion', 'main', 'proxy_profile') || (legacyProxy ? 'legacy' : 'none');
		var groupHelp = [
			_('All groups run every enabled GeoIP, popular service and CDN check.'),
			_('GeoIP services query public geolocation APIs and registries to see what country they assign to the router IP.'),
			_('Popular services contact major platforms to see which region, access state or country their web/API endpoints report for this route.'),
			_('CDN services check which CDN edge or region the router reaches, for example Cloudflare, YouTube or Netflix.')
		].join(' ');

		m = new form.Map('ipregion', _('IP Region'), _('Configure default diagnostics options.'));
		s = m.section(form.NamedSection, 'main', 'ipregion', _('Settings'));
		s.addremove = false;
		s.anonymous = true;

		o = s.option(form.ListValue, 'group', _('Default group'));
		o.value('all', _('All'));
		o.value('primary', _('GeoIP services'));
		o.value('custom', _('Popular services'));
		o.value('cdn', _('CDN services'));
		o.description = groupHelp;
		o.default = 'all';

		o = s.option(form.ListValue, 'ip_mode', _('IP mode'));
		o.value('auto', _('Auto'));
		o.value('ipv4', _('IPv4 only'));
		o.value('ipv6', _('IPv6 only'));
		o.value('both', _('IPv4 and IPv6'));
		o.default = 'auto';

		o = s.option(form.ListValue, 'geoip_mode', _('GeoIP mode'));
		o.value('lookup', _('Check discovered IP'));
		o.value('route', _('Check service-visible route'));
		o.description = _('GeoIP lookup checks the discovered router IP. Service-visible route asks supported GeoIP APIs what country they see for this exact request path.');
		o.default = 'lookup';

		o = s.option(form.Value, 'reference_country', _('Reference country'));
		o.placeholder = 'RU';
		o.datatype = 'maxlength(2)';
		o.description = _('ISO 3166-1 alpha-2 country code used to highlight country values. Matching countries are orange; different countries are blue.');
		o.rmempty = true;
		o.validate = function(section_id, value) {
			return !value || /^[A-Za-z]{2}$/.test(value) ? true : _('Reference country must be a two-letter country code, for example RU.');
		};

		o = s.option(form.Button, '_detect_reference_country', _('Auto-detect reference country'));
		o.inputstyle = 'apply';
		o.description = _('Uses the latest successful GeoIP results. Run a check on the Status page first if no country is available.');
		o.onclick = function(section_id) {
			return callDetectedCountry().then(function(res) {
				if (res && res.available && res.country) {
					if (setReferenceCountry(section_id, res.country))
						ui.addNotification(null, E('p', {}, [ _('Reference country detected') + ': ' + res.country ]));
					else
						ui.addNotification(null, E('p', {}, [ _('Could not update reference country field.') ]), 'error');

					return;
				}

				ui.addNotification(null, E('p', {}, [ _('Run a GeoIP check before auto-detecting the reference country.') ]), 'warning');
			});
		};

		o = s.option(form.Value, 'timeout', _('Timeout'));
		o.datatype = 'range(1,60)';
		o.default = '5';

		o = s.option(form.Value, 'retries', _('Retries'));
		o.datatype = 'range(0,5)';
		o.default = '1';

		o = s.option(form.ListValue, 'proxy_profile', _('Default SOCKS5 proxy profile'));
		o.value('none', _('No proxy'));
		var selectedProxyFound = selectedProxy === 'none';
		if (legacyProxy)
			o.value('legacy', _('Legacy SOCKS5 proxy'));
		if (legacyProxy && selectedProxy === 'legacy')
			selectedProxyFound = true;
		profiles.forEach(function(profile) {
			o.value(profile['.name'], profile.label || profile['.name']);
			if (profile['.name'] === selectedProxy)
				selectedProxyFound = true;
		});
		if (!selectedProxyFound)
			o.value(selectedProxy, _('Selected SOCKS5 proxy profile does not exist or is invalid') + ' (' + selectedProxy + ')');
		o.description = _('Used by default for GeoIP, service and AI checks. New profiles appear here after the settings are saved and reloaded.');
		o.default = legacyProxy ? 'legacy' : 'none';

		o = s.option(form.Value, 'interface', _('Interface'));
		o.placeholder = _('Default route');
		o.datatype = 'maxlength(32)';

		o = s.option(form.Flag, 'mask_ip', _('Mask IP addresses in UI'));
		o.default = '1';

		o = s.option(form.DynamicList, 'disabled_service', _('Disabled services'));
		o.placeholder = 'GOOGLE_SEARCH_CAPTCHA';
		o.validate = function(section_id, value) {
			return !value || /^[A-Z0-9_]+$/.test(value) ? true : _('Service id must contain only uppercase letters, numbers and underscores');
		};

		o = s.option(form.Flag, 'debug', _('Debug logging'));
		o.default = '0';

		p = m.section(form.GridSection, 'proxy', _('SOCKS5 proxy profiles'));
		p.description = _('Define multiple SOCKS5 endpoints, for example Podkop mixed proxies, and select any profile on the Status page.');
		p.addremove = true;
		p.anonymous = false;
		p.sortable = true;
		p.nodescriptions = true;
		p.renderSectionAdd = function() {
			var node = form.GridSection.prototype.renderSectionAdd.apply(this, arguments);
			var input = node.querySelector('.cbi-section-create-name');

			ui.addValidator(input, 'uciname', false, function(value) {
				if (!value)
					return _('Profile ID is required');
				if (value === 'none' || value === 'legacy')
					return _('Profile IDs none and legacy are reserved');
				if (uci.sections('ipregion').some(function(section) { return section['.name'] === value; }))
					return _('A configuration section with this ID already exists');

				return true;
			}, 'blur', 'keyup');
			return node;
		};

		o = p.option(form.Value, 'label', _('Profile name'));
		o.placeholder = _('VPN Europe');
		o.datatype = 'maxlength(64)';
		o.rmempty = false;
		o.validate = function(section_id, value) {
			return value && value.trim() ? true : _('Profile name is required');
		};

		o = p.option(form.Value, 'address', _('SOCKS5 proxy'));
		o.placeholder = '192.168.1.1:1080';
		o.datatype = 'maxlength(255)';
		o.rmempty = false;
		o.validate = function(section_id, value) {
			var match = String(value || '').match(/^[A-Za-z0-9_.-]+:([0-9]+)$/);
			var port = match ? Number(match[1]) : 0;
			return match && port >= 1 && port <= 65535 ? true : _('SOCKS5 proxy must be host:port with a port from 1 to 65535');
		};

		o = p.option(form.ListValue, 'proxy_dns', _('SOCKS5 DNS mode'));
		o.value('remote', _('Remote DNS'));
		o.value('local', _('Local DNS'));
		o.description = _('Remote DNS uses socks5h:// and resolves names through the proxy. Local DNS uses socks5:// and resolves names on the router.');
		o.default = 'remote';

		return m.render().then(function(node) {
			return E('div', {}, [
				node,
				E('div', { 'class': 'cbi-section' }, [
					E('h3', {}, [ _('Where to see results') ]),
					E('p', {}, [ _('Run checks and inspect results on the Status page.') ]),
					E('a', { 'class': 'btn cbi-button cbi-button-apply', 'href': L.url('admin/status/ipregion') }, [ _('Open status page') ])
				])
			]);
		});
	}
});
