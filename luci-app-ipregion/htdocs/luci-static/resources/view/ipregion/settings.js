'use strict';
'require view';
'require form';

return view.extend({
	render: function() {
		var m, s, o;
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

		o = s.option(form.Flag, 'enabled', _('Enable'));
		o.default = '1';

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

		o = s.option(form.Value, 'timeout', _('Timeout'));
		o.datatype = 'range(1,60)';
		o.default = '5';

		o = s.option(form.Value, 'retries', _('Retries'));
		o.datatype = 'range(0,5)';
		o.default = '1';

		o = s.option(form.Value, 'proxy', _('SOCKS5 proxy'));
		o.placeholder = '127.0.0.1:1080';
		o.datatype = 'maxlength(255)';

		o = s.option(form.ListValue, 'proxy_dns', _('SOCKS5 DNS mode'));
		o.value('remote', _('Remote DNS'));
		o.value('local', _('Local DNS'));
		o.default = 'remote';

		o = s.option(form.Value, 'interface', _('Interface'));
		o.placeholder = _('Default route');
		o.datatype = 'maxlength(32)';

		o = s.option(form.Flag, 'mask_ip', _('Mask IP addresses in UI'));
		o.default = '1';

		o = s.option(form.Value, 'cache_ttl', _('Cache TTL'));
		o.datatype = 'uinteger';
		o.default = '300';

		o = s.option(form.Value, 'max_parallel', _('Max parallel checks'));
		o.datatype = 'range(1,8)';
		o.default = '3';

		o = s.option(form.DynamicList, 'disabled_service', _('Disabled services'));
		o.placeholder = 'GOOGLE_SEARCH_CAPTCHA';
		o.validate = function(section_id, value) {
			return !value || /^[A-Z0-9_]+$/.test(value) ? true : _('Service id must contain only uppercase letters, numbers and underscores');
		};

		o = s.option(form.Flag, 'debug', _('Debug logging'));
		o.default = '0';

		o = s.option(form.Flag, 'keep_logs', _('Keep logs'));
		o.default = '0';

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
