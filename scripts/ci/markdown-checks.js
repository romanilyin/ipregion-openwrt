'use strict';

const assert = require('assert');
global._ = function(value) { return value; };
const markdown = require('../../luci-app-ipregion/htdocs/luci-static/resources/ipregion/markdown.js');

const secretValues = [
	'203.0.113.42',
	'2001:db8:1234::42',
	'secret.proxy.local:6000',
	'wg-secret',
	'private.example.test',
	'192.0.2.99',
	'request-secret'
];

const regular = markdown.regular({
	generated_at: '2026-09-02T12:00:00Z',
	duration_ms: 123,
	request: { group: 'all', ip_mode: 'both', geoip_mode: 'route', proxy: 'secret.proxy.local:6000', interface: 'wg-secret' },
	network: { ipv4: '203.0.113.42', ipv6: '2001:db8:1234::42' },
	results: {
		primary: [ { service: 'Geo|Service', ipv4: { status: 'ok', label: 'OK', value: 'DE|test\\value', http_code: 200, latency_ms: 10 }, ipv6: { status: 'error', label: 'Error', error: 'route 203.0.113.42 via wg-secret and secret.proxy.local:6000 failed' } } ],
		custom: [],
		cdn: []
	},
	errors: []
});

const ai = markdown.ai({
	generated_at: '2026-09-02T12:00:00Z',
	request: { category: 'ai', ip_mode: 'ipv4', proxy: 'secret.proxy.local:6000', interface: 'wg-secret' },
	providers: [ { name: 'Gemini <Web>', endpoint_role: 'web', transport: 'IPv4', http_code: 200, status: 'ok', label: 'OK', latency_ms: 20, diagnosis: '![tracker](https://tracker.example/pixel) Endpoint request-secret reached from 2001:db8::dead:beef via wg-secret.', remote_ip: '203.0.113.42', request_id: 'request-secret' } ],
	errors: []
});

const dns = markdown.dns({
	generated_at: '2026-09-02T12:00:00Z',
	request: { transport: 'all', type: 'A', ip_mode: 'ipv4', name: 'private.example.test', interface: 'wg-secret' },
	probes: [ { name: 'Resolver', transport: 'doh', ip_label: 'IPv4', endpoint: '192.0.2.99', tls_verified: true, status: 'ok', label: 'OK', rcode: 'NOERROR', answers: [ { value: '203.0.113.42' } ], latency_ms: 30, diagnosis: 'private.example.test via 192.0.2.99 returned 203.0.113.42' } ],
	summary: { passed: 1, failed: 0, interception: { status: 'no_mismatch_detected' }, finding_details: [] },
	errors: []
});

[ regular, ai, dns ].forEach(function(output) {
	secretValues.forEach(function(secret) {
		assert(!output.includes(secret), 'Markdown leaked sensitive value: ' + secret);
	});
	assert(output.includes('| --- |'), 'Markdown table separator is missing');
});

assert(regular.includes('Geo\\|Service'), 'Markdown table pipe was not escaped');
assert(regular.includes('DE\\|test\\\\value'), 'Regular probe value was not escaped exactly once');
assert(ai.includes('Gemini &lt;Web&gt;'), 'HTML characters were not escaped');
assert(!ai.includes('![tracker](') && !ai.includes('https://tracker.example'), 'Active Markdown content was not neutralized');
assert(dns.includes('| Resolver | DoH |') || dns.includes('| Resolver | doh |'), 'DNS row was not formatted');
assert(regular.includes('2026-09-02T12:00:00Z'), 'ISO timestamp was corrupted');
[ '2001:db8:1234::42', '2001:db8::dead:beef', '::1', 'fe80::1234:5678' ].forEach(function(address) {
	assert(!markdown.clean(address).includes(address), 'Compressed IPv6 was not redacted: ' + address);
});
assert.strictEqual(markdown.clean('12:00:00'), '12:00:00', 'Time was mistaken for IPv6');
assert.strictEqual(markdown.clean('[2001:db8::1]:443'), '\\[IP omitted\\]', 'Bracketed IPv6 endpoint was not redacted as one token');
assert.strictEqual(markdown.clean('::ffff:192.0.2.1'), '\\[IP omitted\\]', 'IPv4-mapped IPv6 was not redacted as one token');

const shortSecrets = markdown.dns({
	generated_at: '2026-09-02T12:00:00Z',
	request: { name: 'a', interface: 'lo' },
	probes: [ { name: 'Cloudflare', transport: 'doh', status: 'ok', diagnosis: 'Valid answer via LO for A' } ],
	summary: {}
});
assert(shortSecrets.includes('Cloudflare'), 'Short secret corrupted an unrelated provider name');
assert(shortSecrets.includes('Valid answer'), 'Short secret corrupted unrelated diagnosis text');
assert(!shortSecrets.includes('via LO for A'), 'Case-insensitive route details were not redacted');

console.log('markdown checks OK');
