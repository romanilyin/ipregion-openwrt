#!/usr/bin/ucode
// SPDX-License-Identifier: MIT
'use strict';

import * as fs from 'fs';
import { cursor } from 'uci';

const VERSION = '2026.5.26-2';
const CATALOG_PATH = getenv('IPREGION_CATALOG_PATH') || '/usr/share/ipregion/services.json';
const AI_CATALOG_PATH = getenv('IPREGION_AI_CATALOG_PATH') || '/usr/share/ipregion/services-ai.json';
const RUNTIME_DIR = getenv('IPREGION_RUNTIME_DIR') || '/tmp/run/ipregion';
const STATE_FILE = RUNTIME_DIR + '/state.json';
const AI_STATE_FILE = RUNTIME_DIR + '/ai-state.json';
const DEFAULT_CONFIG = '/etc/config/ipregion';
const USER_AGENT = 'Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0';

const STATUS_LABELS = {
	ok: 'OK',
	na: 'N/A',
	denied: 'Denied',
	rate_limit: 'Rate-limit',
	server_error: 'Server error',
	error: 'Error'
};

const AI_STATUS_LABELS = {
	ok: 'OK',
	reachable: 'Reachable',
	reachable_auth_required: 'Auth required',
	auth_failed: 'Auth failed',
	blocked_by_provider_region: 'Region blocked',
	forbidden: 'Forbidden',
	rate_limited: 'Rate-limit',
	endpoint_reached_wrong_method: 'Endpoint reached',
	dns_failed: 'DNS failed',
	tls_failed: 'TLS failed',
	timeout: 'Timeout',
	network_failed: 'Network failed',
	server_error: 'Server error',
	skipped: 'Skipped'
};

const VALID_GROUPS = [ 'all', 'primary', 'custom', 'cdn' ];
const VALID_IP_MODES = [ 'auto', 'ipv4', 'ipv6', 'both' ];
const VALID_PROXY_DNS = [ 'local', 'remote' ];
const VALID_AI_CATEGORIES = [ 'all', 'ai', 'ai_china' ];
const VALID_GEOIP_MODES = [ 'lookup', 'route' ];
const IDENTITY_ENDPOINTS = [
	'https://api64.ipify.org',
	'https://ifconfig.co/ip',
	'https://ifconfig.me',
	'https://ident.me'
];

const TWITCH_QUERY = '[{"operationName":"VerifyEmail_CurrentUser","variables":{},"extensions":{"persistedQuery":{"version":1,"sha256Hash":"f9e7dcdf7e99c314c82d8f7f725fab5f99d1df3d7359b53c9ae122deec590198"}}}]';
const REDDIT_LOID_QUERY = '{"scopes":["email"]}';
const REDDIT_LOCATION_QUERY = '{"operationName":"UserLocation","variables":{},"extensions":{"persistedQuery":{"version":1,"sha256Hash":"f07de258c54537e24d7856080f662c1b1268210251e5789c8c08f20d76cc8ab2"}}}';
const DISNEY_PLUS_JSON_BODY = '{"query":"\n     mutation registerDevice($registerDevice: RegisterDeviceInput!) {\n       registerDevice(registerDevice: $registerDevice) {\n         __typename\n       }\n     }\n     ","variables":{"registerDevice":{"applicationRuntime":"android","attributes":{"operatingSystem":"Android","operatingSystemVersion":"13"},"deviceFamily":"android","deviceLanguage":"en","deviceProfile":"phone","devicePlatformId":"android"}},"operationName":"registerDevice"}';

function usage() {
	return 'Usage: ipregion [OPTIONS]\n' +
		'       ipregion ai [OPTIONS]\n' +
		'\n' +
		'IPRegion checks how GeoIP, streaming, CDN and AI endpoints see this route.\n' +
		'\n' +
		'Options:\n' +
		'  -h, --help                 Show this help message\n' +
		'  -j, --json                 Output JSON\n' +
		'  -g, --group GROUP          all, primary, custom, or cdn\n' +
		'  -t, --timeout SEC          Request timeout, 1..60\n' +
		'      --retries N            Request retries, 0..5\n' +
		'      --ip-mode MODE         auto, ipv4, ipv6, or both\n' +
		'      --geoip-mode MODE      lookup => check discovered IP, route => check service-visible route\n' +
		'  -4, --ipv4                 Test IPv4 only\n' +
		'  -6, --ipv6                 Test IPv6 only\n' +
		'  -p, --proxy HOST:PORT      Use SOCKS5 proxy\n' +
		'      --proxy-dns MODE       remote => socks5h, local => socks5\n' +
		'  -i, --interface IFNAME     Use a validated network interface\n' +
		'      --config FILE          UCI config path, default /etc/config/ipregion\n' +
		'      --output FILE          Write JSON result to FILE\n' +
		'      --lock FILE            Reserved runtime lock path\n' +
		'      --list-services        List service catalog\n' +
		'      --list-ai-providers    List AI provider catalog\n' +
		'      --service SERVICE_ID   Run only selected service, repeatable\n' +
		'      --exclude SERVICE_ID   Exclude service, repeatable\n' +
		'      --provider PROVIDER    AI mode: run one provider, repeatable\n' +
		'      --category CATEGORY    AI mode: all, ai, or ai_china\n' +
		'      --safe                 AI mode: unauthenticated endpoint probe\n' +
		'      --auth-check           AI mode: use API keys from environment\n' +
		'      --compat-json          Output legacy-compatible result schema\n' +
		'      --self-test            Print local diagnostics\n' +
		'      --no-uci               Ignore UCI config for this run\n';
}

function die(message, code) {
	warn('ipregion: ' + message + '\n');
	exit(code || 1);
}

function contains(list, value) {
	if (type(list) != 'array')
		return false;

	for (let i = 0; i < length(list); i++)
		if (list[i] == value)
			return true;

	return false;
}

function trim_str(value) {
	return rtrim(ltrim('' + (value ?? '')));
}

function upper_ascii(value) {
	let s = '' + (value ?? '');
	let out = '';

	for (let i = 0; i < length(s); i++) {
		let c = ord(s, i);
		out += chr(c >= 97 && c <= 122 ? c - 32 : c);
	}

	return out;
}

function now_iso() {
	let t = gmtime(time());
	return sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ', t.year, t.mon, t.mday, t.hour, t.min, t.sec);
}

function require_value(argv, index, name) {
	if (index + 1 >= length(argv))
		die(name + ' requires a value', 2);

	return argv[index + 1];
}

function parse_int_range(value, name, min, max) {
	let n = int(value);

	if (n != n || sprintf('%d', n) != '' + value || n < min || n > max)
		die('invalid ' + name + ': ' + value, 2);

	return n;
}

function validate_token(value, name) {
	if (!match(value, /^[A-Za-z0-9_.:-]+$/))
		die('invalid ' + name + ': ' + value, 2);

	return value;
}

function validate_path(value, name) {
	if (!match(value, /^\/[A-Za-z0-9_./:-]+$/))
		die('invalid ' + name + ': ' + value, 2);

	return value;
}

function read_catalog() {
	let data = fs.readfile(CATALOG_PATH);

	if (data == null)
		die('cannot read service catalog: ' + CATALOG_PATH, 1);

	try {
		let catalog = json(data);

		if (type(catalog) != 'object' || type(catalog.services) != 'object' || type(catalog.groups) != 'object')
			die('invalid service catalog: ' + CATALOG_PATH, 1);

		return catalog;
	}
	catch (e) {
		die('invalid service catalog JSON: ' + CATALOG_PATH, 1);
	}
}

function read_ai_catalog() {
	let data = fs.readfile(AI_CATALOG_PATH);

	if (data == null)
		die('cannot read AI provider catalog: ' + AI_CATALOG_PATH, 1);

	try {
		let catalog = json(data);

		if (type(catalog) != 'array')
			die('invalid AI provider catalog: ' + AI_CATALOG_PATH, 1);

		return catalog;
	}
	catch (e) {
		die('invalid AI provider catalog JSON: ' + AI_CATALOG_PATH, 1);
	}
}

function default_options() {
	return {
		json: false,
		group: 'all',
		ip_mode: 'auto',
		geoip_mode: 'lookup',
		timeout: 5,
		retries: 1,
		proxy: null,
		proxy_dns: 'remote',
		interface: null,
		mask_ip: true,
		cache_ttl: 300,
		max_parallel: 3,
		config: DEFAULT_CONFIG,
		output: null,
		lock: null,
		list_services: false,
		list_ai_providers: false,
		self_test: false,
		no_uci: false,
		compat_json: false,
		verbose: false,
		debug: false,
		mode: 'region',
		ai_category: 'all',
		auth_check: false,
		ai_providers: [],
		services: [],
		exclude: []
	};
}

function mark(seen, name) {
	seen[name] = true;
}

function parse_args(argv) {
	let opts = default_options();
	let seen = {};

	for (let i = 0; i < length(argv); i++) {
		let arg = argv[i];

		switch (arg) {
		case '-h':
		case '--help':
			printf('%s', usage());
			exit(0);

		case 'ai':
			opts.mode = 'ai';
			break;

		case '-j':
		case '--json':
			opts.json = true;
			break;

		case '-g':
		case '--group':
			opts.group = require_value(argv, i, arg);
			mark(seen, 'group');
			i++;
			break;

		case '-t':
		case '--timeout':
			opts.timeout = parse_int_range(require_value(argv, i, arg), 'timeout', 1, 60);
			mark(seen, 'timeout');
			i++;
			break;

		case '--retries':
			opts.retries = parse_int_range(require_value(argv, i, arg), 'retries', 0, 5);
			mark(seen, 'retries');
			i++;
			break;

		case '--ip-mode':
			opts.ip_mode = require_value(argv, i, arg);
			mark(seen, 'ip_mode');
			i++;
			break;

		case '--geoip-mode':
			opts.geoip_mode = require_value(argv, i, arg);
			mark(seen, 'geoip_mode');
			i++;
			break;

		case '-4':
		case '--ipv4':
			opts.ip_mode = 'ipv4';
			mark(seen, 'ip_mode');
			break;

		case '-6':
		case '--ipv6':
			opts.ip_mode = 'ipv6';
			mark(seen, 'ip_mode');
			break;

		case '--both':
			opts.ip_mode = 'both';
			mark(seen, 'ip_mode');
			break;

		case '-p':
		case '--proxy':
			opts.proxy = require_value(argv, i, arg);
			mark(seen, 'proxy');
			i++;
			break;

		case '--proxy-dns':
			opts.proxy_dns = require_value(argv, i, arg);
			mark(seen, 'proxy_dns');
			i++;
			break;

		case '-i':
		case '--interface':
			opts.interface = validate_token(require_value(argv, i, arg), 'interface');
			mark(seen, 'interface');
			i++;
			break;

		case '--config':
			opts.config = validate_path(require_value(argv, i, arg), 'config path');
			i++;
			break;

		case '--output':
			opts.output = validate_path(require_value(argv, i, arg), 'output path');
			i++;
			break;

		case '--lock':
			opts.lock = validate_path(require_value(argv, i, arg), 'lock path');
			i++;
			break;

		case '--list-services':
			opts.list_services = true;
			break;

		case '--list-ai-providers':
			opts.list_ai_providers = true;
			break;

		case '--service':
			push(opts.services, validate_token(require_value(argv, i, arg), 'service id'));
			i++;
			break;

		case '--exclude':
			push(opts.exclude, validate_token(require_value(argv, i, arg), 'service id'));
			i++;
			break;

		case '--provider':
			push(opts.ai_providers, validate_token(require_value(argv, i, arg), 'provider id'));
			i++;
			break;

		case '--category':
			opts.ai_category = require_value(argv, i, arg);
			i++;
			break;

		case '--safe':
			opts.auth_check = false;
			break;

		case '--auth-check':
			opts.auth_check = true;
			break;

		case '--self-test':
			opts.self_test = true;
			break;

		case '--no-uci':
			opts.no_uci = true;
			break;

		case '--compat-json':
			opts.compat_json = true;
			break;

		case '-v':
		case '--verbose':
			opts.verbose = true;
			break;

		case '-d':
		case '--debug':
			opts.debug = true;
			mark(seen, 'debug');
			break;

		default:
			die('unknown option: ' + arg, 2);
		}
	}

	opts._seen = seen;
	return opts;
}

function apply_uci_config(opts) {
	if (opts.no_uci || opts.config != DEFAULT_CONFIG)
		return opts;

	let uci = cursor();
	if (uci == null || uci.load('ipregion') == null)
		return opts;

	let cfg = uci.get_all('ipregion', 'main');
	if (type(cfg) != 'object')
		return opts;

	let seen = opts._seen || {};

	if (!seen.group && cfg.group != null) opts.group = cfg.group;
	if (!seen.ip_mode && cfg.ip_mode != null) opts.ip_mode = cfg.ip_mode;
	if (!seen.geoip_mode && cfg.geoip_mode != null) opts.geoip_mode = cfg.geoip_mode;
	if (!seen.timeout && cfg.timeout != null) opts.timeout = parse_int_range(cfg.timeout, 'timeout', 1, 60);
	if (!seen.retries && cfg.retries != null) opts.retries = parse_int_range(cfg.retries, 'retries', 0, 5);
	if (!seen.proxy && cfg.proxy != null && cfg.proxy != '') opts.proxy = cfg.proxy;
	if (!seen.proxy_dns && cfg.proxy_dns != null) opts.proxy_dns = cfg.proxy_dns;
	if (!seen.interface && cfg.interface != null && cfg.interface != '') opts.interface = validate_token(cfg.interface, 'interface');
	if (!seen.debug && cfg.debug != null) opts.debug = cfg.debug == '1';
	if (cfg.mask_ip != null) opts.mask_ip = cfg.mask_ip != '0';
	if (cfg.cache_ttl != null) opts.cache_ttl = parse_int_range(cfg.cache_ttl, 'cache_ttl', 0, 86400);
	if (cfg.max_parallel != null) opts.max_parallel = parse_int_range(cfg.max_parallel, 'max_parallel', 1, 8);

	let disabled = cfg.disabled_service;
	if (type(disabled) == 'string')
		disabled = [ disabled ];

	if (type(disabled) == 'array') {
		for (let id in disabled) {
			let service_id = validate_token(id, 'disabled_service');
			if (!contains(opts.exclude, service_id))
				push(opts.exclude, service_id);
		}
	}

	return opts;
}

function validate_options(opts) {
	if (!contains(VALID_GROUPS, opts.group))
		die('invalid group: ' + opts.group, 2);

	if (!contains(VALID_IP_MODES, opts.ip_mode))
		die('invalid IP mode: ' + opts.ip_mode, 2);

	if (!contains(VALID_GEOIP_MODES, opts.geoip_mode))
		die('invalid GeoIP mode: ' + opts.geoip_mode, 2);

	if (!contains(VALID_PROXY_DNS, opts.proxy_dns))
		die('invalid proxy DNS mode: ' + opts.proxy_dns, 2);

	if (opts.proxy != null) {
		if (index(opts.proxy, 'socks5h://') == 0) {
			opts.proxy_dns = 'remote';
			opts.proxy = substr(opts.proxy, length('socks5h://'));
		}
		else if (index(opts.proxy, 'socks5://') == 0) {
			opts.proxy_dns = 'local';
			opts.proxy = substr(opts.proxy, length('socks5://'));
		}
		else if (index(opts.proxy, '://') >= 0) {
			die('invalid proxy scheme: ' + opts.proxy, 2);
		}
	}

	if (opts.proxy != null && !match(opts.proxy, /^[A-Za-z0-9_.-]+:[0-9]+$/))
		die('invalid proxy, expected host:port: ' + opts.proxy, 2);

	if (opts.proxy != null) {
		let parts = split(opts.proxy, ':');
		let port = int(parts[length(parts) - 1]);
		if (port != port || port < 1 || port > 65535)
			die('invalid proxy port: ' + opts.proxy, 2);
	}

	if (opts.interface != null && fs.stat('/sys/class/net/' + opts.interface) == null)
		die('unknown network interface: ' + opts.interface, 2);

	if (!contains(VALID_AI_CATEGORIES, opts.ai_category))
		die('invalid AI provider category: ' + opts.ai_category, 2);
}

function service_exists(catalog, id) {
	return catalog.services[id] != null;
}

function validate_service_ids(catalog, ids) {
	for (let i = 0; i < length(ids); i++)
		if (!service_exists(catalog, ids[i]))
			die('unknown service id: ' + ids[i], 2);
}

function ai_provider_exists(catalog, id) {
	for (let provider in catalog)
		if (provider.id == id)
			return true;

	return false;
}

function validate_ai_provider_ids(catalog, ids) {
	for (let i = 0; i < length(ids); i++)
		if (!ai_provider_exists(catalog, ids[i]))
			die('unknown AI provider id: ' + ids[i], 2);
}

function contains_number(list, value) {
	if (type(list) != 'array')
		return false;

	for (let i = 0; i < length(list); i++)
		if (int(list[i]) == value)
			return true;

	return false;
}

function url_encode(value) {
	let s = '' + (value ?? '');
	let out = '';

	for (let i = 0; i < length(s); i++) {
		let c = ord(s, i);
		if ((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 45 || c == 46 || c == 95 || c == 126)
			out += chr(c);
		else
			out += sprintf('%%%02X', c);
	}

	return out;
}

function append_query(url, name, value) {
	return url + (index(url, '?') >= 0 ? '&' : '?') + url_encode(name) + '=' + url_encode(value);
}

function shell_quote(value) {
	return "'" + replace('' + (value ?? ''), "'", "'\"'\"'") + "'";
}

function token_replace(value, ip, catalog) {
	let out = '' + (value ?? '');
	out = replace(out, '{ip}', ip ?? '');

	let tokens = catalog.public_tokens || {};
	for (let key in tokens)
		out = replace(out, '{' + key + '}', tokens[key]);

	return out;
}

function status_from_http_code(code) {
	if (code == 403)
		return 'denied';

	if (code == 429)
		return 'rate_limit';

	if (code >= 500 && code <= 599)
		return 'server_error';

	if (code >= 400 && code <= 499)
		return 'na';

	return null;
}

function has_header(headers, wanted) {
	wanted = lc(wanted);
	for (let name in headers)
		if (lc(name) == wanted)
			return true;

	return false;
}

function curl_request(method, url, opts, ip_version, extra) {
	extra = extra || {};
	let headers = extra.headers || {};
	let args = [
		'curl',
		'--silent',
		'--show-error',
		'--location',
		'--retry-connrefused',
		'--retry', '' + opts.retries,
		'--connect-timeout', '' + opts.timeout,
		'--max-time', '' + opts.timeout,
		'--write-out', '\n__IPREGION_HTTP_CODE:%{http_code}\n__IPREGION_TIME_TOTAL:%{time_total}'
	];

	if (ip_version == 4)
		push(args, '-4');
	else if (ip_version == 6)
		push(args, '-6');

	if (method == 'HEAD')
		push(args, '--head');
	else
		push(args, '--request', method || 'GET');

	let user_agent = extra.user_agent ?? USER_AGENT;
	if (user_agent != null && user_agent != '')
		push(args, '--user-agent', user_agent);

	if (opts.proxy != null) {
		let scheme = opts.proxy_dns == 'remote' ? 'socks5h://' : 'socks5://';
		push(args, '--proxy', scheme + opts.proxy);
	}

	if (opts.interface != null)
		push(args, '--interface', opts.interface);

	for (let name in headers)
		push(args, '--header', name + ': ' + headers[name]);

	if (extra.json_body != null) {
		push(args, '--header', 'Content-Type: application/json');
		push(args, '--data-binary', extra.json_body);
	}
	else if (extra.data != null) {
		if (!has_header(headers, 'content-type'))
			push(args, '--header', 'Content-Type: application/x-www-form-urlencoded');
		push(args, '--data-binary', extra.data);
	}

	push(args, url);

	let quoted = [];
	for (let i = 0; i < length(args); i++)
		push(quoted, shell_quote(args[i]));

	let started = clock(true);
	let proc = fs.popen(join(' ', quoted), 'r');
	let output = proc ? proc.read('all') : '';
	let exit_code = proc ? proc.close() : 127;
	let elapsed = clock(true);
	let fallback_ms = null;

	if (type(started) == 'array' && type(elapsed) == 'array')
		fallback_ms = ((elapsed[0] - started[0]) * 1000) + int((elapsed[1] - started[1]) / 1000000);

	let code_marker = '\n__IPREGION_HTTP_CODE:';
	let time_marker = '\n__IPREGION_TIME_TOTAL:';
	let code_pos = rindex(output, code_marker);
	let time_pos = rindex(output, time_marker);
	let body = output;
	let http_code = 0;
	let latency_ms = fallback_ms;

	if (code_pos >= 0) {
		body = substr(output, 0, code_pos);
		let code_end = time_pos >= 0 ? time_pos : length(output);
		http_code = int(trim_str(substr(output, code_pos + length(code_marker), code_end - code_pos - length(code_marker))));
		if (http_code != http_code)
			http_code = 0;
	}

	if (time_pos >= 0) {
		let time_value = trim_str(substr(output, time_pos + length(time_marker)));
		latency_ms = int((+time_value) * 1000);
		if (latency_ms != latency_ms)
			latency_ms = fallback_ms;
	}

	return {
		body: body,
		http_code: http_code,
		latency_ms: latency_ms,
		exit_code: exit_code,
		status: status_from_http_code(http_code)
	};
}

function marker_value(output, name) {
	let marker = '\n__IPREGION_' + name + ':';
	let pos = rindex(output, marker);
	if (pos < 0)
		return null;

	let start = pos + length(marker);
	let rest = substr(output, start);
	let end = index(rest, '\n');
	return trim_str(end >= 0 ? substr(rest, 0, end) : rest);
}

function seconds_marker_ms(output, name) {
	let value = marker_value(output, name);
	if (value == null || value == '')
		return null;

	let ms = int((+value) * 1000);
	return ms == ms ? ms : null;
}

function split_header_body(text) {
	let marker = '\r\n\r\n';
	let pos = index(text, marker);

	if (pos < 0) {
		marker = '\n\n';
		pos = index(text, marker);
	}

	if (pos < 0)
		return { headers_text: '', body: text || '' };

	return {
		headers_text: substr(text, 0, pos),
		body: substr(text, pos + length(marker))
	};
}

function parse_headers(text) {
	let headers = {};
	text = replace(text || '', '\r', '');

	for (let line in split(text, '\n')) {
		let pos = index(line, ':');
		if (pos <= 0)
			continue;

		let name = lc(trim_str(substr(line, 0, pos)));
		let value = trim_str(substr(line, pos + 1));
		if (name != '')
			headers[name] = value;
	}

	return headers;
}

function header_value(headers, names) {
	for (let name in names) {
		let value = headers[lc(name)];
		if (value != null && value != '')
			return value;
	}

	return null;
}

function get_path(value, path) {
	let current = value;

	for (let i = 0; i < length(path); i++) {
		if (current == null)
			return null;

		current = current[path[i]];
	}

	return current;
}

function parse_json_safe(text) {
	try {
		return json(text);
	}
	catch (e) {
		return null;
	}
}

function read_json_file(path, fallback) {
	let data = fs.readfile(path);
	if (data == null)
		return fallback;

	let parsed = parse_json_safe(data);
	return type(parsed) == 'object' ? parsed : fallback;
}

function merge_object(base, updates) {
	base = type(base) == 'object' ? base : {};
	updates = type(updates) == 'object' ? updates : {};

	for (let key in updates)
		base[key] = updates[key];

	return base;
}

function write_partial_output(opts, value) {
	if (opts.output == null)
		return;

	fs.mkdir(RUNTIME_DIR);
	fs.writefile(opts.output, sprintf('%J\n', value));
}

function result_status(status, value, latency_ms, http_code, error) {
	return {
		status: status,
		label: STATUS_LABELS[status] || status,
		value: value,
		latency_ms: latency_ms,
		http_code: http_code,
		error: error ?? null
	};
}

function result_ok(value, response) {
	let normalized = value == null ? null : trim_str(value);

	if (normalized == '' || normalized == 'null')
		return result_status('na', null, response.latency_ms, response.http_code, null);

	return result_status('ok', normalized, response.latency_ms, response.http_code, null);
}

function result_from_response_error(response) {
	if (response.exit_code != 0 && response.http_code == 0)
		return result_status('error', null, response.latency_ms, response.http_code, 'curl exit ' + response.exit_code);

	if (response.status != null)
		return result_status(response.status, STATUS_LABELS[response.status], response.latency_ms, response.http_code, null);

	return null;
}

function extract_value(service, response) {
	let err = result_from_response_error(response);
	if (err != null)
		return err;

	let body = response.body ?? '';
	let extract = service.extract || { type: 'plain_trim' };

	if (body == '')
		return result_status('na', null, response.latency_ms, response.http_code, null);

	if (extract.type == 'json' && match(body, /<html/i))
		return result_status('na', null, response.latency_ms, response.http_code, null);

	if (extract.type == 'plain_trim')
		return result_ok(body, response);

	if (extract.type == 'json') {
		let parsed = parse_json_safe(body);
		if (parsed == null)
			return result_status('error', null, response.latency_ms, response.http_code, 'invalid JSON');

		return result_ok(get_path(parsed, extract.path || []), response);
	}

	if (extract.type == 'regex') {
		try {
			let m = match(body, regexp(extract.pattern, 's'));
			return result_ok(m ? m[1] : null, response);
		}
		catch (e) {
			return result_status('error', null, response.latency_ms, response.http_code, 'invalid regex');
		}
	}

	if (extract.type == 'status')
		return result_status(response.status == null ? 'ok' : response.status, response.status == null ? 'Yes' : STATUS_LABELS[response.status], response.latency_ms, response.http_code, null);

	return result_status('na', null, response.latency_ms, response.http_code, 'unsupported extractor');
}

function is_ipv4(ip) {
	return type(ip) == 'string' && index(ip, ':') < 0 && iptoarr(ip) != null;
}

function is_ipv6(ip) {
	return type(ip) == 'string' && index(ip, ':') >= 0 && iptoarr(ip) != null;
}

function mask_ipv4(ip) {
	if (!is_ipv4(ip))
		return null;

	let p = split(ip, '.');
	return p[0] + '.' + p[1] + '.*.*';
}

function mask_ipv6(ip) {
	if (!is_ipv6(ip))
		return null;

	let p = split(ip, ':');
	let parts = [];
	for (let i = 0; i < length(p) && length(parts) < 3; i++)
		if (p[i] != '')
			push(parts, p[i]);

	return join(':', parts) + '::';
}

function discover_ip(version, opts) {
	for (let url in IDENTITY_ENDPOINTS) {
		let response = curl_request('GET', url, opts, version, { headers: {}, user_agent: null });
		if (response.status != null || response.exit_code != 0)
			continue;

		let value = trim_str(response.body);
		if (version == 4 && is_ipv4(value))
			return value;

		if (version == 6 && is_ipv6(value))
			return value;
	}

	return null;
}

function active_versions(opts) {
	if (opts.ip_mode == 'ipv4')
		return [ 4 ];

	if (opts.ip_mode == 'ipv6')
		return [ 6 ];

	return [ 4, 6 ];
}

function selected_groups(group) {
	if (group == 'all')
		return [ 'primary', 'custom', 'cdn' ];

	return [ group ];
}

function is_service_enabled(service, opts, id) {
	if (service.default_enabled == false)
		return false;

	if (contains(opts.exclude, id))
		return false;

	if (length(opts.services) > 0 && !contains(opts.services, id))
		return false;

	return true;
}

function empty_probe_result() {
	return result_status('na', null, null, null, null);
}

function request_service(service, catalog, opts, ip, logical_version) {
	let route_geoip = service.group == 'primary' && opts.geoip_mode == 'route';
	let method = route_geoip && service.self_method != null ? service.self_method : service.method || 'GET';
	let transport_version = logical_version;

	if (logical_version == 6 && service.ipv6_transport == 'ipv4_with_ipv6_param')
		transport_version = 4;

	let raw_url = service.url;
	let raw_body = service.body;
	let extract_service = service;

	if (route_geoip) {
		if (service.self_url != null)
			raw_url = service.self_url;
		else if (index(raw_url || '', '{ip}') >= 0)
			return result_status('na', null, null, null, 'route GeoIP mode is not supported by this service');

		if (service.self_body == null && index(raw_body || '', '{ip}') >= 0)
			return result_status('na', null, null, null, 'route GeoIP mode is not supported by this service');

		raw_body = service.self_body ?? null;
		ip = null;

		if (service.self_extract != null) {
			extract_service = {};
			for (let key in service)
				extract_service[key] = service[key];
			extract_service.extract = service.self_extract;
		}
	}

	let url = token_replace(raw_url, ip, catalog);
	let body = raw_body == null ? null : token_replace(raw_body, ip, catalog);
	let response = curl_request(method, url, opts, transport_version, {
		headers: route_geoip && service.self_headers != null ? service.self_headers : service.headers || {},
		data: body
	});

	return extract_value(extract_service, response);
}

function json_request(method, url, opts, ip_version, headers, body, user_agent) {
	return curl_request(method, url, opts, ip_version, {
		headers: headers || {},
		json_body: body,
		user_agent: user_agent ?? USER_AGENT
	});
}

function ai_category_label(category) {
	if (category == 'ai_china')
		return 'AI China/Asia';

	return 'AI';
}

function copy_headers(headers) {
	let out = {};
	headers = headers || {};

	for (let name in headers)
		out[name] = headers[name];

	return out;
}

function curl_ai_probe(provider, opts, ip_version, url, headers) {
	let method = provider.method || 'GET';
	let args = [
		'curl',
		'--silent',
		'--show-error',
		'--retry-connrefused',
		'--retry', '' + opts.retries,
		'--connect-timeout', '' + opts.timeout,
		'--max-time', '' + opts.timeout,
		'--dump-header', '-',
		'--output', '-',
		'--write-out', '\n__IPREGION_HTTP_CODE:%{http_code}\n__IPREGION_REMOTE_IP:%{remote_ip}\n__IPREGION_TIME_CONNECT:%{time_connect}\n__IPREGION_TIME_APPCONNECT:%{time_appconnect}\n__IPREGION_TIME_TOTAL:%{time_total}'
	];

	if (ip_version == 4)
		push(args, '-4');
	else if (ip_version == 6)
		push(args, '-6');

	if (method == 'HEAD')
		push(args, '--head');
	else
		push(args, '--request', method);

	push(args, '--user-agent', USER_AGENT);

	if (opts.proxy != null) {
		let scheme = opts.proxy_dns == 'remote' ? 'socks5h://' : 'socks5://';
		push(args, '--proxy', scheme + opts.proxy);
	}

	if (opts.interface != null)
		push(args, '--interface', opts.interface);

	for (let name in headers)
		push(args, '--header', name + ': ' + headers[name]);

	if (provider.body != null)
		push(args, '--data-binary', provider.body);

	push(args, url);

	let quoted = [];
	for (let i = 0; i < length(args); i++)
		push(quoted, shell_quote(args[i]));

	let started = clock(true);
	let proc = fs.popen(join(' ', quoted), 'r');
	let output = proc ? proc.read('all') : '';
	let exit_code = proc ? proc.close() : 127;
	let elapsed = clock(true);
	let fallback_ms = null;

	if (type(started) == 'array' && type(elapsed) == 'array')
		fallback_ms = ((elapsed[0] - started[0]) * 1000) + int((elapsed[1] - started[1]) / 1000000);

	let code_marker = '\n__IPREGION_HTTP_CODE:';
	let code_pos = rindex(output, code_marker);
	let payload = code_pos >= 0 ? substr(output, 0, code_pos) : output;
	let split_payload = split_header_body(payload);
	let response_headers = parse_headers(split_payload.headers_text);
	let http_code = int(marker_value(output, 'HTTP_CODE') || '0');
	if (http_code != http_code)
		http_code = 0;

	let total_ms = seconds_marker_ms(output, 'TIME_TOTAL');
	if (total_ms == null)
		total_ms = fallback_ms;

	return {
		body: split_payload.body,
		headers: response_headers,
		http_code: http_code,
		remote_ip: marker_value(output, 'REMOTE_IP'),
		latency_ms: total_ms,
		exit_code: exit_code,
		timing: {
			connect_ms: seconds_marker_ms(output, 'TIME_CONNECT'),
			tls_ms: seconds_marker_ms(output, 'TIME_APPCONNECT'),
			total_ms: total_ms
		}
	};
}

function ai_pattern_match(body, patterns) {
	body = lc(body || '');
	patterns = patterns || [];

	for (let pattern in patterns)
		if (pattern != null && pattern != '' && index(body, lc(pattern)) >= 0)
			return true;

	return false;
}

function ai_network_status(exit_code) {
	if (exit_code == 6)
		return 'dns_failed';

	if (exit_code == 28)
		return 'timeout';

	if (exit_code == 35 || exit_code == 51 || exit_code == 58 || exit_code == 60)
		return 'tls_failed';

	return 'network_failed';
}

function ai_diagnosis(status, auth_check) {
	switch (status) {
	case 'ok':
		return auth_check ? 'Authenticated provider check succeeded.' : 'Endpoint reached successfully.';
	case 'reachable':
		return 'Endpoint reached through this route.';
	case 'reachable_auth_required':
		return 'Endpoint reached; API key is missing or invalid.';
	case 'auth_failed':
		return 'Provider rejected the configured API key.';
	case 'blocked_by_provider_region':
		return 'Provider rejected this route because of country, region or territory policy.';
	case 'forbidden':
		return 'Provider returned HTTP 403. Check region, account policy or IP allowlist.';
	case 'rate_limited':
		return 'Endpoint reached, but provider returned rate limit.';
	case 'endpoint_reached_wrong_method':
		return 'Endpoint host was reachable, but this path or method is not accepted.';
	case 'dns_failed':
		return 'DNS resolution failed through this route.';
	case 'tls_failed':
		return 'TLS handshake or certificate validation failed through this route.';
	case 'timeout':
		return 'DNS, TCP, TLS or HTTP request did not complete before timeout.';
	case 'server_error':
		return 'Endpoint reached, but provider returned a server error.';
	case 'skipped':
		return 'Provider was skipped.';
	default:
		return 'Request failed through this route.';
	}
}

function classify_ai_provider(provider, response, auth_check) {
	let code = response.http_code;

	if (response.exit_code != 0 && code == 0)
		return ai_network_status(response.exit_code);

	if (contains_number(provider.success_status || [ 200 ], code))
		return 'ok';

	if (code == 401)
		return auth_check ? 'auth_failed' : 'reachable_auth_required';

	if (code == 403)
		return ai_pattern_match(response.body, provider.region_error_patterns) ? 'blocked_by_provider_region' : 'forbidden';

	if (code == 429)
		return 'rate_limited';

	if ((code == 404 || code == 405) && contains_number(provider.reachable_status || [], code))
		return 'endpoint_reached_wrong_method';

	if (code >= 500 && code <= 599)
		return 'server_error';

	if (contains_number(provider.reachable_status || [], code))
		return 'reachable';

	return code > 0 ? 'reachable' : 'network_failed';
}

function skipped_ai_provider(provider, reason) {
	return {
		id: provider.id,
		name: provider.name || provider.id,
		category: provider.category || 'ai',
		category_label: ai_category_label(provider.category || 'ai'),
		kind: provider.kind || 'api',
		url: provider.url,
		status: 'skipped',
		label: AI_STATUS_LABELS.skipped,
		http_code: 0,
		remote_ip: null,
		request_id: null,
		latency_ms: null,
		timing: { connect_ms: null, tls_ms: null, total_ms: null },
		diagnosis: reason || ai_diagnosis('skipped', false)
	};
}

function probe_ai_provider(provider, opts, ip_version) {
	let headers = copy_headers(provider.headers || {});
	let url = provider.url;

	if (opts.auth_check) {
		let auth = provider.auth || {};
		let key = auth.env ? getenv(auth.env) : null;

		if (auth.optional == true && (key == null || key == ''))
			return skipped_ai_provider(provider, 'Environment variable ' + (auth.env || 'API_KEY') + ' is not set.');

		if (auth.type == 'bearer')
			headers.Authorization = 'Bearer ' + key;
		else if (auth.type == 'x-api-key')
			headers['x-api-key'] = key;
		else if (auth.type == 'query')
			url = append_query(url, auth.name || 'key', key);
	}

	let response = curl_ai_probe(provider, opts, ip_version, url, headers);
	let status = classify_ai_provider(provider, response, opts.auth_check);
	let request_id = header_value(response.headers, provider.request_id_headers || [ 'x-request-id', 'request-id' ]);

	return {
		id: provider.id,
		name: provider.name || provider.id,
		category: provider.category || 'ai',
		category_label: ai_category_label(provider.category || 'ai'),
		kind: provider.kind || 'api',
		url: provider.url,
		status: status,
		label: AI_STATUS_LABELS[status] || status,
		http_code: response.http_code,
		remote_ip: response.remote_ip || null,
		request_id: request_id,
		latency_ms: response.latency_ms,
		timing: response.timing,
		diagnosis: ai_diagnosis(status, opts.auth_check)
	};
}

function selected_ai_providers(catalog, opts) {
	let result = [];

	for (let provider in catalog) {
		if (provider.default_enabled == false)
			continue;

		if (opts.ai_category != 'all' && provider.category != opts.ai_category)
			continue;

		if (length(opts.ai_providers) > 0 && !contains(opts.ai_providers, provider.id))
			continue;

		push(result, provider);
	}

	return result;
}

function choose_ai_transport(opts, egress) {
	if (opts.ip_mode == 'ipv6')
		return 6;

	if (opts.ip_mode == 'ipv4')
		return 4;

	if (egress.ipv4 != null)
		return 4;

	if (egress.ipv6 != null)
		return 6;

	return 4;
}

function discover_ai_egress(opts) {
	let egress = {
		ipv4: null,
		ipv6: null,
		ipv4_masked: null,
		ipv6_masked: null,
		ip: null,
		ip_masked: null,
		country: null,
		asn: null,
		asn_name: null,
		source: 'maxmind.com',
		transport_ip_version: null
	};

	let versions = active_versions(opts);
	for (let version in versions) {
		let ip = discover_ip(version, opts);
		if (version == 4) {
			egress.ipv4 = ip;
			egress.ipv4_masked = opts.mask_ip ? mask_ipv4(ip) : ip;
		}
		else {
			egress.ipv6 = ip;
			egress.ipv6_masked = opts.mask_ip ? mask_ipv6(ip) : ip;
		}
	}

	egress.transport_ip_version = choose_ai_transport(opts, egress);
	egress.ip = egress.transport_ip_version == 6 ? egress.ipv6 : egress.ipv4;
	egress.ip_masked = egress.transport_ip_version == 6 ? egress.ipv6_masked : egress.ipv4_masked;

	let response = curl_request('GET', 'https://geoip.maxmind.com/geoip/v2.1/city/me', opts, egress.transport_ip_version, { headers: { 'Referer': 'https://www.maxmind.com' }, user_agent: USER_AGENT });
	let parsed = parse_json_safe(response.body || '');
	if (parsed != null) {
		let country = get_path(parsed, [ 'country', 'iso_code' ]);
		let asn = get_path(parsed, [ 'traits', 'autonomous_system_number' ]);
		let name = get_path(parsed, [ 'traits', 'autonomous_system_organization' ]);
		if (country != null) egress.country = country;
		if (asn != null) egress.asn = 'AS' + asn;
		if (name != null) egress.asn_name = name;
	}

	return egress;
}

function google_country(opts, ip_version) {
	let response = curl_request('GET', 'https://www.google.com', opts, ip_version, { headers: {}, user_agent: USER_AGENT });
	return extract_value({ extract: { type: 'regex', pattern: '"MgUcDb":"([^"]+)' } }, response);
}

function youtube_country(opts, ip_version) {
	let response = curl_request('GET', 'https://www.youtube.com/sw.js_data', opts, ip_version, { headers: {}, user_agent: USER_AGENT });
	let err = result_from_response_error(response);
	if (err != null)
		return err;

	let lines = split(response.body || '', '\n');
	let payload = length(lines) > 2 ? join('\n', slice(lines, 2)) : response.body;
	let parsed = parse_json_safe(payload);
	if (parsed == null)
		return result_status('error', null, response.latency_ms, response.http_code, 'invalid YouTube JSON payload');

	return result_ok(get_path(parsed, [0, 2, 0, 0, 1]), response);
}

function twitch_country(catalog, opts, ip_version) {
	let response = json_request('POST', 'https://gql.twitch.tv/gql', opts, ip_version, { 'Client-Id': catalog.public_tokens.twitch_client_id }, TWITCH_QUERY);
	return extract_value({ extract: { type: 'json', path: [0, 'data', 'requestInfo', 'countryCode'] } }, response);
}

function chatgpt_country(catalog, opts, ip_version) {
	let response = curl_request('POST', 'https://ab.chatgpt.com/v1/initialize', opts, ip_version, { headers: { 'Statsig-Api-Key': catalog.public_tokens.chatgpt_statsig_api_key } });
	return extract_value({ extract: { type: 'json', path: ['derived_fields', 'country'] } }, response);
}

function netflix_country(catalog, opts, ip_version) {
	let url = token_replace('https://api.fast.com/netflix/speedtest/v2?https=true&token={netflix_api_key}&urlCount=1', null, catalog);
	let response = curl_request('GET', url, opts, ip_version, { headers: {}, user_agent: USER_AGENT });
	let parsed = parse_json_safe(response.body || '');
	if (parsed == null)
		return result_from_response_error(response) || result_ok(response.body, response);

	return result_ok(get_path(parsed, ['client', 'location', 'country']), response);
}

function spotify_country(catalog, opts, ip_version) {
	let url = token_replace('https://spclient.wg.spotify.com/signup/public/v1/account/?validate=1&key={spotify_api_key}', null, catalog);
	let response = curl_request('GET', url, opts, ip_version, { headers: { 'X-Client-Id': catalog.public_tokens.spotify_client_id }, user_agent: USER_AGENT });
	return extract_value({ extract: { type: 'json', path: ['country'] } }, response);
}

function reddit_country(catalog, opts, ip_version) {
	let user_agent = 'Reddit/Version 2025.29.0/Build 2529021/Android 13';
	let auth_response = json_request('POST', 'https://www.reddit.com/auth/v2/oauth/access-token/loid', opts, ip_version, { 'Authorization': 'Basic ' + catalog.public_tokens.reddit_basic_access_token }, REDDIT_LOID_QUERY, user_agent);
	let err = result_from_response_error(auth_response);
	if (err != null)
		return err;

	let auth = parse_json_safe(auth_response.body || '');
	let token = auth ? auth.access_token : null;
	if (token == null || token == '')
		return result_status('error', null, auth_response.latency_ms, auth_response.http_code, 'missing Reddit access token');

	let response = json_request('POST', 'https://gql-fed.reddit.com', opts, ip_version, { 'Authorization': 'Bearer ' + token }, REDDIT_LOCATION_QUERY, user_agent);
	return extract_value({ extract: { type: 'json', path: ['data', 'userLocation', 'countryCode'] } }, response);
}

function disney_plus_country(catalog, opts, ip_version) {
	let response = json_request('POST', 'https://disney.api.edge.bamgrid.com/graph/v1/device/graphql', opts, ip_version, { 'Authorization': 'Bearer ' + catalog.public_tokens.disney_plus_api_key }, DISNEY_PLUS_JSON_BODY);
	return extract_value({ extract: { type: 'json', path: ['extensions', 'sdk', 'session', 'location', 'countryCode'] } }, response);
}

function gemini_supported(opts, ip_version) {
	let country = google_country(opts, ip_version);
	if (country.status != 'ok')
		return country;

	let name_response = curl_request('GET', 'https://restcountries.com/v3.1/alpha/' + country.value + '?fields=name', opts, 4, { headers: {}, user_agent: USER_AGENT });
	let parsed = parse_json_safe(name_response.body || '');
	let country_name = parsed ? get_path(parsed, ['name', 'common']) : null;
	if (country_name == null || country_name == '')
		return result_status('na', null, name_response.latency_ms, name_response.http_code, null);

	let regions = curl_request('GET', 'https://ai.google.dev/gemini-api/docs/available-regions.md.txt', opts, ip_version, { headers: {}, user_agent: USER_AGENT });
	let err = result_from_response_error(regions);
	if (err != null)
		return err;

	let available = false;
	for (let line in split(regions.body || '', '\n')) {
		if (trim_str(line) == '- ' + country_name) {
			available = true;
			break;
		}
	}
	return result_status('ok', available ? 'Yes' : 'No', regions.latency_ms, regions.http_code, null);
}

function reddit_guest_access(opts, ip_version) {
	let response = curl_request('GET', 'https://www.reddit.com', opts, ip_version, { headers: {}, user_agent: USER_AGENT });
	if (response.status == 'denied')
		return result_status('ok', 'No', response.latency_ms, response.http_code, null);
	return result_status('ok', response.exit_code == 0 ? 'Yes' : 'No', response.latency_ms, response.http_code, response.exit_code == 0 ? null : 'curl exit ' + response.exit_code);
}

function youtube_premium(catalog, opts, ip_version) {
	let response = curl_request('GET', 'https://www.youtube.com/premium', opts, ip_version, {
		headers: {
			'Cookie': 'SOCS=' + catalog.public_tokens.youtube_socs_cookie,
			'Accept-Language': 'en-US,en;q=0.9'
		},
		user_agent: USER_AGENT
	});
	let err = result_from_response_error(response);
	if (err != null)
		return err;

	let unavailable = match(response.body || '', /youtube premium is not available in your country/i) != null;
	return result_status('ok', unavailable ? 'No' : 'Yes', response.latency_ms, response.http_code, null);
}

function google_search_captcha(opts, ip_version) {
	let response = curl_request('GET', 'https://www.google.com/search?q=cats', opts, ip_version, { headers: { 'Accept-Language': 'en-US,en;q=0.9' }, user_agent: USER_AGENT });
	let err = result_from_response_error(response);
	if (err != null)
		return err;

	let captcha = match(response.body || '', /unusual traffic from|is blocked|unaddressed abuse/i) != null;
	return result_status('ok', captcha ? 'Yes' : 'No', response.latency_ms, response.http_code, null);
}

function spotify_signup(catalog, opts, ip_version) {
	let base = spotify_country(catalog, opts, ip_version);
	if (base.status != 'ok')
		return base;

	let url = token_replace('https://spclient.wg.spotify.com/signup/public/v1/account/?validate=1&key={spotify_api_key}', null, catalog);
	let response = curl_request('GET', url, opts, ip_version, { headers: { 'X-Client-Id': catalog.public_tokens.spotify_client_id }, user_agent: USER_AGENT });
	let parsed = parse_json_safe(response.body || '');
	if (parsed == null)
		return result_status('error', null, response.latency_ms, response.http_code, 'invalid Spotify JSON');

	let blocked = parsed.status == 120 || parsed.status == 320 || parsed.is_country_launched == false;
	return result_status('ok', blocked ? 'No' : 'Yes', response.latency_ms, response.http_code, null);
}

function disney_plus_access(catalog, opts, ip_version) {
	let response = json_request('POST', 'https://disney.api.edge.bamgrid.com/graph/v1/device/graphql', opts, ip_version, { 'Authorization': 'Bearer ' + catalog.public_tokens.disney_plus_api_key }, DISNEY_PLUS_JSON_BODY);
	let parsed = parse_json_safe(response.body || '');
	if (parsed == null)
		return result_from_response_error(response) || result_status('error', null, response.latency_ms, response.http_code, 'invalid Disney+ JSON');

	let errors = parsed.errors == null ? 0 : length(parsed.errors);
	let supported = get_path(parsed, ['extensions', 'sdk', 'session', 'inSupportedLocation']) == true;
	return result_status('ok', errors == 0 && supported ? 'Yes' : 'No', response.latency_ms, response.http_code, null);
}

function get_iata_country(catalog, opts, iata) {
	iata = upper_ascii(trim_str(iata));
	if (!match(iata, /^[A-Z]{3}$/))
		return null;

	let response = curl_request('POST', 'https://www.air-port-codes.com/api/v1/single', opts, 4, {
		headers: {
			'APC-Auth': catalog.public_tokens.air_port_codes_auth,
			'Referer': 'https://www.air-port-codes.com/'
		},
		data: 'iata=' + iata,
		user_agent: USER_AGENT
	});
	let parsed = parse_json_safe(response.body || '');
	return parsed ? get_path(parsed, ['airport', 'country', 'iso']) : null;
}

function cloudflare_cdn(catalog, opts, ip_version) {
	let response = curl_request('GET', 'https://speed.cloudflare.com/meta', opts, ip_version, { headers: { 'Referer': 'https://speed.cloudflare.com' }, user_agent: USER_AGENT });
	let parsed = parse_json_safe(response.body || '');
	if (parsed == null)
		return result_from_response_error(response) || result_status('error', null, response.latency_ms, response.http_code, 'invalid Cloudflare JSON');

	let iata = get_path(parsed, ['colo', 'iata']);
	let country = get_iata_country(catalog, opts, iata);
	return result_ok((country != null ? country + ' ' : '') + '(' + upper_ascii(iata || '') + ')', response);
}

function youtube_cdn(catalog, opts, ip_version) {
	let response = curl_request('GET', 'https://redirector.googlevideo.com/report_mapping?di=no', opts, ip_version, { headers: {}, user_agent: USER_AGENT });
	let err = result_from_response_error(response);
	if (err != null)
		return err;

	let m = match(response.body || '', /-([A-Za-z]{3})[0-9A-Za-z_-]*/);
	let iata = m ? upper_ascii(m[1]) : null;
	if (iata == null)
		return result_status('na', null, response.latency_ms, response.http_code, null);

	let country = get_iata_country(catalog, opts, iata);
	return result_ok((country != null ? country + ' ' : '') + '(' + iata + ')', response);
}

function netflix_cdn(catalog, opts, ip_version) {
	let url = token_replace('https://api.fast.com/netflix/speedtest/v2?https=true&token={netflix_api_key}&urlCount=1', null, catalog);
	let response = curl_request('GET', url, opts, ip_version, { headers: {}, user_agent: USER_AGENT });
	return extract_value({ extract: { type: 'json', path: ['targets', 0, 'location', 'country'] } }, response);
}

function handler_result(id, service, catalog, opts, ip_version) {
	switch (id) {
	case 'IPLOCATION_COM':
		return request_service(service, catalog, opts, ip_version == 4 ? opts._network.ipv4 : opts._network.ipv6, ip_version);
	case 'GOOGLE':
		return google_country(opts, ip_version);
	case 'YOUTUBE':
		return youtube_country(opts, ip_version);
	case 'TWITCH':
		return twitch_country(catalog, opts, ip_version);
	case 'CHATGPT':
		return chatgpt_country(catalog, opts, ip_version);
	case 'NETFLIX':
		return netflix_country(catalog, opts, ip_version);
	case 'SPOTIFY':
		return spotify_country(catalog, opts, ip_version);
	case 'REDDIT':
		return reddit_country(catalog, opts, ip_version);
	case 'DISNEY_PLUS':
		return disney_plus_country(catalog, opts, ip_version);
	case 'GEMINI_SUPPORTED':
		return gemini_supported(opts, ip_version);
	case 'REDDIT_GUEST_ACCESS':
		return reddit_guest_access(opts, ip_version);
	case 'YOUTUBE_PREMIUM':
		return youtube_premium(catalog, opts, ip_version);
	case 'GOOGLE_SEARCH_CAPTCHA':
		return google_search_captcha(opts, ip_version);
	case 'SPOTIFY_SIGNUP':
		return spotify_signup(catalog, opts, ip_version);
	case 'DISNEY_PLUS_ACCESS':
		return disney_plus_access(catalog, opts, ip_version);
	case 'CLOUDFLARE_CDN':
		return cloudflare_cdn(catalog, opts, ip_version);
	case 'YOUTUBE_CDN':
		return youtube_cdn(catalog, opts, ip_version);
	case 'NETFLIX_CDN':
		return netflix_cdn(catalog, opts, ip_version);
	default:
		return request_service(service, catalog, opts, ip_version == 4 ? opts._network.ipv4 : opts._network.ipv6, ip_version);
	}
}

function probe_one(id, service, catalog, opts, ip_version) {
	let ip = ip_version == 4 ? opts._network.ipv4 : opts._network.ipv6;

	if (ip == null)
		return empty_probe_result();

	if (service.handler != null)
		return handler_result(id, service, catalog, opts, ip_version);

	return request_service(service, catalog, opts, ip, ip_version);
}

function update_state(state) {
	fs.mkdir(RUNTIME_DIR);
	fs.writefile(STATE_FILE, sprintf('%J\n', merge_object(read_json_file(STATE_FILE, {}), state)));
}

function update_ai_state(state) {
	fs.mkdir(RUNTIME_DIR);
	fs.writefile(AI_STATE_FILE, sprintf('%J\n', merge_object(read_json_file(AI_STATE_FILE, {}), state)));
}

function build_ai_result(opts, catalog) {
	let start = clock(true);
	let result = {
		version: 1,
		mode: 'ai',
		generated_at: now_iso(),
		duration_ms: 0,
		request: {
			category: opts.ai_category,
			providers: opts.ai_providers,
			auth_check: opts.auth_check,
			ip_mode: opts.ip_mode,
			interface: opts.interface,
			proxy: opts.proxy,
			proxy_dns: opts.proxy_dns,
			config: opts.no_uci ? null : opts.config,
			timeout: opts.timeout,
			retries: opts.retries
		},
		route: {
			interface: opts.interface,
			proxy: opts.proxy,
			proxy_dns: opts.proxy_dns
		},
		egress: {},
		providers: [],
		errors: []
	};

	update_ai_state({ running: true, started_at: result.generated_at, mode: 'ai', category: opts.ai_category });
	write_partial_output(opts, result);

	result.egress = discover_ai_egress(opts);
	if (result.egress.ip == null)
		push(result.errors, { code: 'egress_unavailable', message: 'External IP address could not be discovered for AI transport route' });
	write_partial_output(opts, result);

	let providers = selected_ai_providers(catalog, opts);
	if (length(providers) == 0)
		push(result.errors, { code: 'no_ai_providers', message: 'No AI providers matched the requested filters' });

	for (let provider in providers) {
		update_ai_state({ running: true, current: provider.name || provider.id, current_id: provider.id, finished: length(result.providers), total: length(providers) });
		push(result.providers, probe_ai_provider(provider, opts, result.egress.transport_ip_version || 4));
		write_partial_output(opts, result);
	}

	let end = clock(true);
	if (type(start) == 'array' && type(end) == 'array')
		result.duration_ms = ((end[0] - start[0]) * 1000) + int((end[1] - start[1]) / 1000000);

	update_ai_state({ running: false, current: null, current_id: null, finished: length(result.providers), total: length(providers), exit_code: length(result.errors) ? 1 : 0, started_at: result.generated_at, finished_at: now_iso(), duration_ms: result.duration_ms, result_file: opts.output });

	return result;
}

function build_result(opts, catalog) {
	let start = clock(true);
	let result = {
		version: 2,
		generated_at: now_iso(),
		duration_ms: 0,
		request: {
			group: opts.group,
			ip_mode: opts.ip_mode,
			geoip_mode: opts.geoip_mode,
			interface: opts.interface,
			proxy: opts.proxy,
			proxy_dns: opts.proxy_dns,
			config: opts.no_uci ? null : opts.config,
			timeout: opts.timeout,
			retries: opts.retries
		},
		network: {
			ipv4: null,
			ipv6: null,
			ipv4_masked: null,
			ipv6_masked: null,
			ipv4_supported: false,
			ipv6_supported: false,
			asn: null,
			asn_name: null
		},
		results: {
			primary: [],
			custom: [],
			cdn: []
		},
		errors: []
	};

	update_state({ running: true, started_at: result.generated_at, group: opts.group, ip_mode: opts.ip_mode, current: 'Discovering external IP', current_id: 'network' });
	write_partial_output(opts, result);

	let versions = active_versions(opts);
	for (let version in versions) {
		let ip = discover_ip(version, opts);
		if (version == 4) {
			result.network.ipv4 = ip;
			result.network.ipv4_masked = opts.mask_ip ? mask_ipv4(ip) : ip;
			result.network.ipv4_supported = ip != null;
		}
		else {
			result.network.ipv6 = ip;
			result.network.ipv6_masked = opts.mask_ip ? mask_ipv6(ip) : ip;
			result.network.ipv6_supported = ip != null;
		}
	}

	if ((opts.ip_mode == 'ipv4' || opts.ip_mode == 'both') && result.network.ipv4 == null)
		push(result.errors, { code: 'ipv4_unavailable', message: 'External IPv4 address could not be discovered' });

	if ((opts.ip_mode == 'ipv6' || opts.ip_mode == 'both') && result.network.ipv6 == null)
		push(result.errors, { code: 'ipv6_unavailable', message: 'External IPv6 address could not be discovered' });

	if (result.network.ipv4 == null && result.network.ipv6 == null)
		push(result.errors, { code: 'network_unavailable', message: 'No external IP address could be discovered' });

	opts._network = result.network;
	write_partial_output(opts, result);

	update_state({ running: true, current: 'Discovering ASN', current_id: 'asn' });
	let asn_response = curl_request('GET', 'https://geoip.maxmind.com/geoip/v2.1/city/me', opts, 4, { headers: { 'Referer': 'https://www.maxmind.com' }, user_agent: USER_AGENT });
	let asn_json = parse_json_safe(asn_response.body || '');
	if (asn_json != null) {
		let asn = get_path(asn_json, ['traits', 'autonomous_system_number']);
		let name = get_path(asn_json, ['traits', 'autonomous_system_organization']);
		if (asn != null) result.network.asn = 'AS' + asn;
		if (name != null) result.network.asn_name = name;
	}

	let groups = selected_groups(opts.group);
	let total_checks = 0;
	for (let group in groups)
		for (let id in catalog.groups[group] || []) {
			let service = catalog.services[id];
			if (service != null && is_service_enabled(service, opts, id))
				total_checks++;
		}

	let finished_checks = 0;
	for (let group in groups) {
		let ids = catalog.groups[group] || [];

		for (let id in ids) {
			let service = catalog.services[id];
			if (service == null || !is_service_enabled(service, opts, id))
				continue;

			update_state({ running: true, group: group, current: service.name || id, current_id: id, finished: finished_checks, total: total_checks });

			let row = { id: id, service: service.name || id, ipv4: empty_probe_result(), ipv6: empty_probe_result() };

			if (contains(versions, 4))
				row.ipv4 = probe_one(id, service, catalog, opts, 4);

			if (contains(versions, 6))
				row.ipv6 = probe_one(id, service, catalog, opts, 6);

			push(result.results[group], row);
			finished_checks++;
			write_partial_output(opts, result);
		}
	}

	let end = clock(true);
	if (type(start) == 'array' && type(end) == 'array')
		result.duration_ms = ((end[0] - start[0]) * 1000) + int((end[1] - start[1]) / 1000000);

	update_state({ running: false, current: null, current_id: null, finished: finished_checks, total: total_checks, exit_code: length(result.errors) ? 1 : 0, started_at: result.generated_at, finished_at: now_iso(), duration_ms: result.duration_ms, result_file: opts.output });

	return result;
}

function compat_result(result) {
	let out = {
		version: 1,
		ipv4: result.network.ipv4,
		ipv6: result.network.ipv6,
		results: { primary: [], custom: [], cdn: [] }
	};

	for (let group in [ 'primary', 'custom', 'cdn' ]) {
		for (let row in result.results[group]) {
			push(out.results[group], {
				service: row.service,
				ipv4: row.ipv4.status == 'ok' ? row.ipv4.value : null,
				ipv6: row.ipv6.status == 'ok' ? row.ipv6.value : null
			});
		}
	}

	return out;
}

function print_json(value) {
	printf('%J\n', value);
}

function write_json_output(opts, value, emit_stdout) {
	let payload = sprintf('%J\n', value);

	if (opts.output != null) {
		fs.mkdir(RUNTIME_DIR);
		if (fs.writefile(opts.output, payload) == null)
			die('failed to write output: ' + opts.output, 1);
	}

	if (emit_stdout)
		printf('%s', payload);
}

function list_services(catalog, as_json) {
	if (as_json) {
		print_json(catalog);
		return;
	}

	for (let group in [ 'primary', 'custom', 'cdn' ]) {
		let ids = catalog.groups[group] || [];
		printf('%s\n', group);

		for (let id in ids) {
			let service = catalog.services[id] || {};
			let enabled = service.default_enabled == false ? 'disabled' : 'enabled';
			printf('  %s\t%s\t%s\n', id, service.name || id, enabled);
		}
	}
}

function list_ai_providers(catalog, as_json) {
	if (as_json) {
		print_json(catalog);
		return;
	}

	for (let provider in catalog)
		printf('%s\t%s\t%s\n', provider.id, provider.category || 'ai', provider.name || provider.id);
}

function self_test(catalog) {
	let checks = [];
	let catalog_ok = type(catalog.services) == 'object';
	let ai_catalog_ok = fs.stat(AI_CATALOG_PATH) != null;
	let runtime_ok = fs.access('/tmp/run', 'w') == true;
	let ca_ok = fs.stat('/etc/ssl/certs/ca-certificates.crt') != null || fs.stat('/etc/ssl/cert.pem') != null;
	let curl_ok = fs.access('/usr/bin/curl', 'x') == true || fs.access('/bin/curl', 'x') == true;
	let ucode_ok = fs.access('/usr/bin/ucode', 'x') == true || fs.access('/bin/ucode', 'x') == true;
	let openwrt_release = fs.readfile('/etc/openwrt_release') || '';
	let test_opts = default_options();
	test_opts.timeout = 2;
	test_opts.retries = 0;
	let external_ipv4 = curl_ok ? discover_ip(4, test_opts) : null;
	let external_ipv6 = curl_ok ? discover_ip(6, test_opts) : null;

	push(checks, { name: 'service_catalog', ok: catalog_ok, path: CATALOG_PATH });
	push(checks, { name: 'ai_provider_catalog', ok: ai_catalog_ok, path: AI_CATALOG_PATH, required: false });
	push(checks, { name: 'runtime_dir_parent', ok: runtime_ok, path: '/tmp/run' });
	push(checks, { name: 'ca_bundle', ok: ca_ok });
	push(checks, { name: 'curl', ok: curl_ok });
	push(checks, { name: 'ucode', ok: ucode_ok });
	push(checks, { name: 'openwrt_release_present', ok: openwrt_release != '' });
	push(checks, { name: 'external_ipv4_discovery', ok: external_ipv4 != null });
	push(checks, { name: 'external_ipv6_discovery', ok: external_ipv6 != null, required: false });

	return { version: VERSION, ok: catalog_ok && runtime_ok && ca_ok && curl_ok && ucode_ok && external_ipv4 != null, checks: checks };
}

function print_plain_result(result) {
	printf('IPRegion %s\n', VERSION);
	printf('Generated: %s\n', result.generated_at);
	if (result.network.ipv4_masked != null) printf('IPv4: %s\n', result.network.ipv4_masked);
	if (result.network.ipv6_masked != null) printf('IPv6: %s\n', result.network.ipv6_masked);
	if (result.network.asn != null) printf('ASN: %s %s\n', result.network.asn, result.network.asn_name || '');

	for (let group in [ 'primary', 'custom', 'cdn' ]) {
		if (length(result.results[group]) == 0)
			continue;

		printf('\n%s\n', group);
		for (let row in result.results[group]) {
			let v4 = row.ipv4.status == 'ok' ? row.ipv4.value : row.ipv4.label;
			let v6 = row.ipv6.status == 'ok' ? row.ipv6.value : row.ipv6.label;
			printf('  %s\tIPv4=%s\tIPv6=%s\n', row.service, v4, v6);
		}
	}

	if (length(result.errors) > 0) {
		printf('\nErrors:\n');
		for (let err in result.errors)
			printf('  %s: %s\n', err.code, err.message);
	}
}

function print_plain_ai_result(result) {
	printf('IPRegion AI %s\n', VERSION);
	printf('Generated: %s\n', result.generated_at);
	if (result.egress.ip_masked != null) printf('Egress IP: %s\n', result.egress.ip_masked);
	if (result.egress.country != null) printf('Egress country: %s\n', result.egress.country);
	if (result.egress.asn != null) printf('ASN: %s %s\n', result.egress.asn, result.egress.asn_name || '');

	printf('\nAI providers\n');
	for (let provider in result.providers)
		printf('  %s\tHTTP=%s\t%s\t%s\n', provider.name, provider.http_code || 0, provider.label, provider.diagnosis || '');

	if (length(result.errors) > 0) {
		printf('\nErrors:\n');
		for (let err in result.errors)
			printf('  %s: %s\n', err.code, err.message);
	}
}

let opts = parse_args(ARGV || []);
let catalog = read_catalog();
opts = apply_uci_config(opts);
validate_options(opts);

validate_service_ids(catalog, opts.services);
validate_service_ids(catalog, opts.exclude);

if (opts.list_services) {
	list_services(catalog, opts.json);
	exit(0);
}

if (opts.list_ai_providers) {
	let ai_catalog = read_ai_catalog();
	list_ai_providers(ai_catalog, opts.json);
	exit(0);
}

if (opts.self_test) {
	let result = self_test(catalog);
	print_json(result);
	exit(result.ok ? 0 : 1);
}

if (opts.mode == 'ai') {
	let ai_catalog = read_ai_catalog();
	validate_ai_provider_ids(ai_catalog, opts.ai_providers);
	let ai_result = build_ai_result(opts, ai_catalog);

	if (opts.output != null)
		write_json_output(opts, ai_result, opts.json);
	else if (opts.json)
		write_json_output(opts, ai_result, true);
	else
		print_plain_ai_result(ai_result);

	exit(length(ai_result.errors) > 0 ? 1 : 0);
}

let result = build_result(opts, catalog);
let output = opts.compat_json ? compat_result(result) : result;

if (opts.output != null)
	write_json_output(opts, output, opts.json || opts.compat_json);
else if (opts.json || opts.compat_json)
	write_json_output(opts, output, true);
else
	print_plain_result(result);

exit(length(result.errors) > 0 ? 1 : 0);
