#!/usr/bin/ucode
// SPDX-License-Identifier: MIT
'use strict';

import * as fs from 'fs';
import { cursor } from 'uci';

const CATALOG_PATH = '/usr/share/ipregion/services.json';
const AI_CATALOG_PATH = '/usr/share/ipregion/services-ai.json';
const RUN_DIR = '/tmp/run/ipregion';
const STATE_FILE = RUN_DIR + '/state.json';
const RESULT_FILE = RUN_DIR + '/result.json';
const LOG_FILE = RUN_DIR + '/log.txt';
const AI_STATE_FILE = RUN_DIR + '/ai-state.json';
const AI_RESULT_FILE = RUN_DIR + '/ai-result.json';
const AI_LOG_FILE = RUN_DIR + '/ai-log.txt';
const UPDATE_STATE_FILE = RUN_DIR + '/update-state.json';
const UPDATE_LOG_FILE = RUN_DIR + '/update.log';
const GITHUB_REPO = 'romanilyin/ipregion-openwrt';
const GITHUB_LATEST_URL = 'https://api.github.com/repos/' + GITHUB_REPO + '/releases/latest';
const INSTALLER_URL = 'https://raw.githubusercontent.com/' + GITHUB_REPO + '/main/install.sh';

function read_json_file(path, fallback) {
	let data = fs.readfile(path);

	if (data == null)
		return fallback;

	try {
		let parsed = json(data);
		return parsed == null ? fallback : parsed;
	}
	catch (e) {
		return fallback;
	}
}

function valid_enum(value, allowed, fallback) {
	value = value || fallback;

	for (let i = 0; i < length(allowed); i++)
		if (allowed[i] == value)
			return value;

	return fallback;
}

function valid_token(value) {
	return value != null && match(value, /^[A-Za-z0-9_.:-]+$/) != null;
}

function valid_proxy(value) {
	return value == null || value == '' || match(value, /^[A-Za-z0-9_.-]+:[0-9]+$/) != null;
}

function trim_str(value) {
	return rtrim(ltrim('' + (value ?? '')));
}

function upper_ascii(value) {
	let s = '' + (value ?? '');
	let out = '';
	for (let i = 0; i < length(s); i++) {
		let c = substr(s, i, 1);
		let o = ord(c);
		out += (o >= 97 && o <= 122) ? chr(o - 32) : c;
	}
	return out;
}

function shell_quote(value) {
	return "'" + replace('' + (value ?? ''), "'", "'\"'\"'") + "'";
}

function shell_cmd(args) {
	let quoted = [];
	for (let arg in args)
		push(quoted, shell_quote(arg));
	return join(' ', quoted);
}

function command_exists(name) {
	return system('command -v ' + shell_quote(name) + ' >/dev/null 2>&1') == 0;
}

function read_command(args) {
	let pipe = fs.popen(shell_cmd(args) + ' 2>/dev/null', 'r');
	let output = pipe ? pipe.read('all') : '';

	if (pipe)
		pipe.close();

	return output || '';
}

function downloader_args(url, timeout) {
	timeout = '' + (timeout || 8);

	if (command_exists('curl'))
		return [ 'curl', '-fsSL', '--connect-timeout', timeout, '--max-time', timeout, url ];

	if (command_exists('wget'))
		return [ 'wget', '-T', timeout, '-q', '-O', '-', url ];

	if (command_exists('uclient-fetch'))
		return [ 'uclient-fetch', '-T', timeout, '-q', '-O', '-', url ];

	return null;
}

function read_url(url) {
	let args = downloader_args(url, 8);
	if (args == null)
		return null;

	return read_command(args);
}

function ensure_run_dir() {
	fs.mkdir(RUN_DIR);
}

function atomic_write(path, payload) {
	let suffix = '' + time();
	let now = clock(true);

	if (type(now) == 'array')
		suffix = '' + now[0] + '.' + now[1];

	let tmp = path + '.tmp.' + suffix;
	if (fs.writefile(tmp, payload) == null)
		return null;

	return fs.rename(tmp, path);
}

function write_state(state) {
	ensure_run_dir();
	atomic_write(STATE_FILE, sprintf('%J\n', state));
}

function write_update_state(state) {
	ensure_run_dir();
	atomic_write(UPDATE_STATE_FILE, sprintf('%J\n', state));
}

function process_alive(pid) {
	pid = int(pid);
	if (pid != pid || pid <= 0)
		return false;

	return system('kill -0 ' + pid + ' 2>/dev/null') == 0;
}

function current_config() {
	let defaults = {
		enabled: '1',
		group: 'all',
		ip_mode: 'auto',
		geoip_mode: 'lookup',
		reference_country: '',
		timeout: '5',
		retries: '1',
		proxy: '',
		proxy_dns: 'remote',
		interface: '',
		mask_ip: '1',
		cache_ttl: '300',
		max_parallel: '3',
		debug: '0',
		keep_logs: '0',
		disabled_service: [ 'GOOGLE_SEARCH_CAPTCHA' ]
	};

	let uci = cursor();
	if (uci == null || uci.load('ipregion') == null)
		return defaults;

	let cfg = uci.get_all('ipregion', 'main');
	if (type(cfg) != 'object')
		return defaults;

	for (let key in defaults)
		if (cfg[key] == null)
			cfg[key] = defaults[key];

	return cfg;
}

function country_from_value(value) {
	value = upper_ascii(trim_str(value || ''));
	let m = match(value, /^([A-Z][A-Z])($|[^A-Z])/);
	return m ? m[1] : null;
}

function detected_country_from_result() {
	let result = read_json_file(RESULT_FILE, {});
	let rows = result.results && result.results.primary || [];
	let counts = {};
	let sources = {};
	let order = [];

	for (let row in rows) {
		let candidate = null;
		let source = row.service || row.id || '';

		for (let probe in [ row.ipv4, row.ipv6 ]) {
			if (probe == null || probe.status != 'ok')
				continue;

			candidate = country_from_value(probe.value);
			if (candidate != null)
				break;
		}

		if (candidate == null)
			continue;

		if (counts[candidate] == null) {
			counts[candidate] = 0;
			sources[candidate] = source;
			push(order, candidate);
		}

		counts[candidate]++;
	}

	let best = null;
	for (let country in order)
		if (best == null || counts[country] > counts[best])
			best = country;

	return {
		available: best != null,
		country: best,
		count: best != null ? counts[best] : 0,
		source: best != null ? sources[best] : null,
		generated_at: result.generated_at || null
	};
}

function package_version(pkg) {
	let output;
	let prefix;

	if (command_exists('apk')) {
		output = read_command([ 'apk', 'list', '--installed', pkg ]);
		prefix = pkg + '-';

		for (let line in split(output, '\n')) {
			line = trim_str(line);
			if (index(line, prefix) == 0) {
				let version = substr(line, length(prefix));
				let end = index(version, ' ');
				return end >= 0 ? substr(version, 0, end) : version;
			}
		}
	}

	if (!command_exists('opkg'))
		return null;

	output = read_command([ 'opkg', 'list-installed', pkg ]);
	prefix = pkg + ' - ';

	for (let line in split(output, '\n')) {
		line = trim_str(line);
		if (index(line, prefix) == 0) {
			let version = substr(line, length(prefix));
			let end = index(version, ' ');
			return end >= 0 ? substr(version, 0, end) : version;
		}
	}

	return null;
}

function normalize_version(value) {
	value = trim_str(value || '');
	if (value == '')
		return null;

	if (index(value, 'v') == 0 || index(value, 'V') == 0)
		value = substr(value, 1);

	let release_pos = index(value, '-r');
	if (release_pos >= 0)
		value = substr(value, 0, release_pos) + '-' + substr(value, release_pos + 2);

	return value;
}

function parse_version(value) {
	value = normalize_version(value);
	if (value == null)
		return null;

	let release = 0;
	let dash = index(value, '-');
	if (dash >= 0) {
		release = int(substr(value, dash + 1));
		value = substr(value, 0, dash);
	}

	let parts = split(value, '.');
	if (length(parts) != 3)
		return null;

	let out = [];
	for (let part in parts) {
		let number = int(part);
		if (number != number)
			return null;

		push(out, number);
	}

	if (release != release)
		return null;

	push(out, release);
	return out;
}

function compare_versions(left, right) {
	let a = parse_version(left);
	let b = parse_version(right);

	if (a == null || b == null)
		return null;

	for (let i = 0; i < 4; i++) {
		if (a[i] < b[i])
			return -1;

		if (a[i] > b[i])
			return 1;
	}

	return 0;
}

function update_state() {
	let state = read_json_file(UPDATE_STATE_FILE, { running: false, log_file: UPDATE_LOG_FILE });

	if (state.running && !process_alive(state.pid)) {
		state.running = false;
		state.finished_at = state.finished_at || time();
		write_update_state(state);
	}

	return state;
}

function latest_release() {
	let output = read_url(GITHUB_LATEST_URL);
	if (output == null || trim_str(output) == '')
		return null;

	try {
		let release = json(output);
		if (type(release) == 'object' && release.tag_name)
			return release;
	}
	catch (e) {
		return null;
	}

	return null;
}

function version_info() {
	let current = package_version('ipregion');
	let current_norm = normalize_version(current);
	let release = latest_release();
	let latest = release ? release.tag_name : null;
	let latest_norm = normalize_version(latest);
	let status = 'not_found';

	if (latest_norm == null)
		status = 'not_found';
	else if (current_norm == null)
		status = 'installed_not_found';
	else if (current_norm == latest_norm)
		status = 'latest';
	else {
		let cmp = compare_versions(current_norm, latest_norm);
		if (cmp == null)
			status = 'version_mismatch';
		else if (cmp < 0)
			status = 'update_available';
		else
			status = 'latest_is_older';
	}

	return {
		status: status,
		current: current,
		current_normalized: current_norm,
		latest: latest,
		latest_normalized: latest_norm,
		release_url: release ? release.html_url : null,
		github_repo: GITHUB_REPO,
		update: update_state()
	};
}

function normalized_options(input) {
	input = input || {};
	let cfg = current_config();
	let group = valid_enum(input.group || cfg.group, [ 'all', 'primary', 'custom', 'cdn' ], 'all');
	let ip_mode = valid_enum(input.ip_mode || cfg.ip_mode, [ 'auto', 'ipv4', 'ipv6', 'both' ], 'auto');
	let geoip_mode = valid_enum(input.geoip_mode || cfg.geoip_mode, [ 'lookup', 'route' ], 'lookup');
	let proxy_dns = valid_enum(input.proxy_dns || cfg.proxy_dns, [ 'local', 'remote' ], 'remote');
	let timeout = int(input.timeout ?? cfg.timeout ?? 5);
	let retries = int(input.retries ?? cfg.retries ?? 1);
	let proxy = input.proxy ?? cfg.proxy ?? '';
	let iface = input.interface ?? cfg.interface ?? '';
	let disabled = cfg.disabled_service || [];

	if (timeout != timeout || timeout < 1 || timeout > 60)
		timeout = 5;

	if (retries != retries || retries < 0 || retries > 5)
		retries = 1;

	if (!valid_proxy(proxy))
		proxy = '';

	if (iface != '' && (!valid_token(iface) || fs.stat('/sys/class/net/' + iface) == null))
		iface = '';

	if (type(disabled) == 'string')
		disabled = [ disabled ];

	if (type(disabled) != 'array')
		disabled = [];

	return { group: group, ip_mode: ip_mode, geoip_mode: geoip_mode, proxy_dns: proxy_dns, timeout: timeout, retries: retries, proxy: proxy, interface: iface, disabled_service: disabled };
}

function normalized_ai_options(input) {
	let options = normalized_options(input);
	let category = valid_enum(input && input.category, [ 'all', 'ai', 'ai_china' ], 'all');
	let providers = input && input.providers ? input.providers : [];

	if (type(providers) == 'string')
		providers = [ providers ];

	if (type(providers) != 'array')
		providers = [];

	return {
		category: category,
		providers: providers,
		auth_check: false,
		ip_mode: options.ip_mode,
		proxy_dns: options.proxy_dns,
		timeout: options.timeout,
		retries: options.retries,
		proxy: options.proxy,
		interface: options.interface
	};
}

const methods = {
	get_config: {
		call: function(req) {
			return current_config();
		}
	},

	list_services: {
		call: function(req) {
			return read_json_file(CATALOG_PATH, { version: 0, groups: {}, services: {} });
		}
	},

	list_ai_providers: {
		call: function(req) {
			return { providers: read_json_file(AI_CATALOG_PATH, []) };
		}
	},

	list_interfaces: {
		call: function(req) {
			let entries = fs.lsdir('/sys/class/net') || [];
			let result = [ { name: '', label: 'Default route' } ];

			for (let name in entries)
				push(result, { name: name, label: name });

			return { interfaces: result };
		}
	},

	detected_country: {
		call: function(req) {
			return detected_country_from_result();
		}
	},

	start: {
		args: { options: {} },
		call: function(req) {
			let existing = read_json_file(STATE_FILE, {});
			if (existing.running && process_alive(existing.pid))
				return existing;

			let input = req && req.args ? req.args.options : req && req.options ? req.options : {};
			let options = normalized_options(input);
			let args = [ '/usr/bin/ipregion', '--no-uci', '--group', options.group, '--ip-mode', options.ip_mode, '--geoip-mode', options.geoip_mode, '--timeout', '' + options.timeout, '--retries', '' + options.retries, '--output', RESULT_FILE ];

			if (options.proxy != '')
				push(args, '--proxy', options.proxy, '--proxy-dns', options.proxy_dns);

			if (options.interface != '')
				push(args, '--interface', options.interface);

			for (let id in options.disabled_service)
				if (valid_token(id))
					push(args, '--exclude', id);

			ensure_run_dir();
			fs.unlink(RESULT_FILE);
			fs.unlink(LOG_FILE);

			let cmd = shell_cmd(args) + ' > ' + shell_quote(LOG_FILE) + ' 2>&1 & echo $!';
			let pipe = fs.popen(cmd, 'r');
			let pid = pipe ? int(trim_str(pipe.read('all') || '')) : 0;

			if (pipe)
				pipe.close();

			let state = {
				running: true,
				pid: pid,
				started_at: time(),
				group: options.group,
				ip_mode: options.ip_mode,
				geoip_mode: options.geoip_mode,
				current: 'Starting',
				current_id: 'start',
				result_file: RESULT_FILE,
				log_file: LOG_FILE
			};

			write_state(state);
			return state;
		}
	},

	status: {
		call: function(req) {
			let state = read_json_file(STATE_FILE, { running: false, result_file: RESULT_FILE, log_file: LOG_FILE });

			if (state.running && !process_alive(state.pid)) {
				state.running = false;
				state.finished_at = state.finished_at || time();
				write_state(state);
			}

			return state;
		}
	},

	result: {
		call: function(req) {
			return read_json_file(RESULT_FILE, { version: 2, results: { primary: [], custom: [], cdn: [] }, errors: [] });
		}
	},

	ai_start: {
		args: { options: {} },
		call: function(req) {
			let existing = read_json_file(AI_STATE_FILE, {});
			if (existing.running && process_alive(existing.pid))
				return existing;

			let input = req && req.args ? req.args.options : req && req.options ? req.options : {};
			let options = normalized_ai_options(input || {});
			let args = [ '/usr/bin/ipregion', 'ai', '--no-uci', '--category', options.category, '--ip-mode', options.ip_mode, '--timeout', '' + options.timeout, '--retries', '' + options.retries, '--output', AI_RESULT_FILE ];

			if (options.proxy != '')
				push(args, '--proxy', options.proxy, '--proxy-dns', options.proxy_dns);

			if (options.interface != '')
				push(args, '--interface', options.interface);

			for (let id in options.providers)
				if (valid_token(id))
					push(args, '--provider', id);

			ensure_run_dir();
			fs.unlink(AI_RESULT_FILE);
			fs.unlink(AI_LOG_FILE);

			let cmd = shell_cmd(args) + ' > ' + shell_quote(AI_LOG_FILE) + ' 2>&1 & echo $!';
			let pipe = fs.popen(cmd, 'r');
			let pid = pipe ? int(trim_str(pipe.read('all') || '')) : 0;

			if (pipe)
				pipe.close();

			let state = {
				running: true,
				pid: pid,
				started_at: time(),
				mode: 'ai',
				category: options.category,
				current: 'Starting',
				current_id: 'start',
				finished: 0,
				total: 0,
				result_file: AI_RESULT_FILE,
				log_file: AI_LOG_FILE
			};

			ensure_run_dir();
			atomic_write(AI_STATE_FILE, sprintf('%J\n', state));
			return state;
		}
	},

	ai_status: {
		call: function(req) {
			let state = read_json_file(AI_STATE_FILE, { running: false, result_file: AI_RESULT_FILE, log_file: AI_LOG_FILE });

			if (state.running && !process_alive(state.pid)) {
				state.running = false;
				state.finished_at = state.finished_at || time();
				atomic_write(AI_STATE_FILE, sprintf('%J\n', state));
			}

			return state;
		}
	},

	ai_result: {
		call: function(req) {
			return read_json_file(AI_RESULT_FILE, { version: 1, mode: 'ai', egress: {}, providers: [], errors: [] });
		}
	},

	ai_log: {
		call: function(req) {
			return { log: fs.readfile(AI_LOG_FILE, 32768) || '' };
		}
	},

	ai_stop: {
		call: function(req) {
			let state = read_json_file(AI_STATE_FILE, {});

			if (state.pid && process_alive(state.pid))
				system('kill ' + int(state.pid) + ' 2>/dev/null');

			state.running = false;
			state.stopped_at = time();
			atomic_write(AI_STATE_FILE, sprintf('%J\n', state));

			return state;
		}
	},

	ai_clear: {
		call: function(req) {
			fs.unlink(AI_STATE_FILE);
			fs.unlink(AI_RESULT_FILE);
			fs.unlink(AI_LOG_FILE);

			return { cleared: true };
		}
	},

	log: {
		call: function(req) {
			return { log: fs.readfile(LOG_FILE, 32768) || '' };
		}
	},

	stop: {
		call: function(req) {
			let state = read_json_file(STATE_FILE, {});

			if (state.pid && process_alive(state.pid))
				system('kill ' + int(state.pid) + ' 2>/dev/null');

			state.running = false;
			state.stopped_at = time();
			write_state(state);

			return state;
		}
	},

	clear: {
		call: function(req) {
			fs.unlink(STATE_FILE);
			fs.unlink(RESULT_FILE);
			fs.unlink(LOG_FILE);

			return { cleared: true };
		}
	},

	selftest: {
		call: function(req) {
			let pipe = fs.popen('/usr/bin/ipregion --self-test --json', 'r');
			let output = pipe ? pipe.read('all') : '';

			if (pipe)
				pipe.close();

			try {
				return json(output || '{}') || { ok: false };
			}
			catch (e) {
				return { ok: false, error: 'self-test output was not valid JSON' };
			}
		}
	},

	version: {
		call: function(req) {
			return version_info();
		}
	},

	update: {
		call: function(req) {
			let existing = update_state();
			if (existing.running && process_alive(existing.pid))
				return existing;

			let info = version_info();
			if (info.status != 'update_available')
				return { running: false, ok: false, error: 'update_not_available', message: 'No newer GitHub release is available', status: info.status, current: info.current_normalized, latest: info.latest_normalized, release_url: info.release_url };

			let args = downloader_args(INSTALLER_URL, 20);
			if (args == null)
				return { running: false, ok: false, error: 'downloader_not_found', message: 'curl, wget or uclient-fetch is required' };

			ensure_run_dir();
			let cmd = '( ' + shell_cmd(args) + ' | IPREGION_RELEASE=latest sh ) > ' + shell_quote(UPDATE_LOG_FILE) + ' 2>&1 & echo $!';
			let pipe = fs.popen(cmd, 'r');
			let pid = pipe ? int(trim_str(pipe.read('all') || '')) : 0;

			if (pipe)
				pipe.close();

			let state = {
				running: true,
				pid: pid,
				started_at: time(),
				release: 'latest',
				log_file: UPDATE_LOG_FILE,
				installer_url: INSTALLER_URL
			};

			write_update_state(state);
			return state;
		}
	}
};

return { 'luci.ipregion': methods };
