/**
 * Vanilla test harness — no framework, no build step.
 *
 * Run in a browser:
 *   1. python3 -m http.server 8080
 *   2. open http://localhost:8080/js/api.test.html
 *      (or load this file from a <script> tag in an HTML page)
 * Run in node 22+:
 *   node js/api.test.js
 *
 * Pattern: every `test(...)` runs synchronously or as a Promise; results
 * print to console + (in the browser) the page. Add more tests as the
 * api.js surface grows. Mirrors the iOS Swift Testing + Android JUnit
 * + Turbine pattern — same shape, native tools.
 */

// Node fallback: api.js is a browser IIFE that attaches `API` to its
// closure. When run under node, we eval the script into the current
// context so the IIFE exports `API` and `shareTarget` as globals.
if (typeof window === 'undefined' && typeof API === 'undefined') {
  const fs = require('node:fs');
  const vm = require('node:vm');
  const src = fs.readFileSync(__dirname + '/api.js', 'utf-8');
  vm.runInThisContext(src);
}

const tests = [];
function test(name, fn) { tests.push({ name, fn }); }
function assert(cond, msg) { if (!cond) throw new Error(msg || 'assertion failed'); }
function assertEq(a, b, msg) {
  if (a !== b) throw new Error(msg || `expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`);
}

// --- TESTS -----------------------------------------------------------

test('playbackVolume reaches -21 LUFS by cutting, clamped at -1 dBTP (DECISIONS 061)', () => {
  const near = (a, b) => Math.abs(a - b) < 1e-9;
  assert(near(API.playbackVolume(-15, -6), Math.pow(10, -6 / 20)), 'a loud episode is cut 6 dB');
  assert(near(API.playbackVolume(-18, -1.3), Math.pow(10, -3 / 20)), '-18 LUFS is cut 3 dB');
  assertEq(API.playbackVolume(-25, -10), 1, 'a quiet episode is never boosted');
  assert(near(API.playbackVolume(-20, 1.0), Math.pow(10, -2 / 20)),
    'control: a hot peak pulls the gain below the loudness target (clamp)');
  assertEq(API.playbackVolume(null, null), 1, 'unmeasured plays at unity');
  assertEq(API.playbackVolume(undefined, -3), 1, 'no loudness, no change');
});

test('onAir reads the one clock from the published instants (R10, R14)', () => {
  const slots = [
    { utc_start: '2026-10-22T23:00:00Z', utc_end: '2026-10-22T23:30:00Z' },
    { utc_start: '2026-10-22T23:30:00Z', utc_end: '2026-10-23T00:00:00Z' },
    { utc_start: '2026-10-23T00:00:00Z', utc_end: '2026-10-23T00:30:00Z' },
  ];
  const at = (iso) => API.onAir(slots, Date.parse(iso));
  assertEq(at('2026-10-22T22:59:59Z').phase, 'before', 'before the first slot');
  assertEq(at('2026-10-22T23:00:00Z').index, 0, 'the first slot starts on its instant');
  assertEq(at('2026-10-22T23:45:00Z').index, 1, 'the slot whose instants hold now');
  assertEq(at('2026-10-23T00:29:59Z').index, 2, 'the last slot until its end');
  assertEq(at('2026-10-23T00:30:00Z').phase, 'after', 'the evening ends when its last slot does (R14)');
  assertEq(API.onAir([], Date.now()).phase, 'after', 'no slots: nothing on the air');
});

test('localDate is the person\'s own calendar date, not UTC', () => {
  assertEq(API.localDate(new Date(2026, 9, 22, 23, 30)), '2026-10-22', '11:30 PM local stays on its own date');
  assertEq(API.localDate(new Date(2026, 0, 5, 0, 5)), '2026-01-05', 'control: padding');
});

test('API exposes the data verbs', () => {
  assert(typeof API === 'object', 'API should be an object');
  for (const f of ['getJSON', 'manifest', 'seriesIndex', 'listen', 'thisDay', 'seriesPage', 'episodeDetail',
                   'searchSeries', 'searchEpisodeNumbers', 'searchDocs', 'rightsLine', 'tonight', 'onAir']) {
    assert(typeof API[f] === 'function', `API.${f} should be a function`);
  }
});

test('shareTarget is exposed as an async function', () => {
  assert(typeof shareTarget === 'function', 'shareTarget should be a function');
  assert(shareTarget.constructor.name === 'AsyncFunction', 'shareTarget should be async');
});

// Golden vectors printed by catalog/tools/build_web_projection.py: the browser
// must find the same shard and the same words as the builder that wrote them.
test('fnv1a and shardOf match the builder', () => {
  assertEq(API.fnv1a(''), 2166136261);
  assertEq(API.fnv1a('suspense|1948-11-18'), 2877880940);
  assertEq(API.shardOf('suspense|1948-11-18'), 'a6c');
  assertEq(API.shardOf('familytheater|1948-09-30'), '000');
  assertEq(API.shardOf('Caf\u00e9 No\u00ebl|x'), '3da');
});

test('control: a different id lands in a different shard', () => {
  assert(API.shardOf('suspense|1948-11-19') !== 'a6c', 'one day later should not collide here');
});

test('tokens fold like unicode61 and match the builder', () => {
  assertEq(JSON.stringify(API.tokens('Sorry, Wrong Number (Agnes Moorehead) \u2014 Caf\u00e9 \u00d1and\u00fa 1948')),
    JSON.stringify(['sorry', 'wrong', 'number', 'agnes', 'moorehead', 'cafe', 'nandu', '1948']));
  assertEq(API.termFile('\u00f1andu'), 'xf161');
  assertEq(API.termFile('1948'), '19');
});

// Plain JS has no compiler: every API.x a script calls must be exported.
test('every API.x called in js/*.js is exported', () => {
  if (typeof require === 'undefined') return;
  const fs = require('node:fs');
  const called = new Set();
  for (const f of fs.readdirSync(__dirname).filter(f => f.endsWith('.js') && !f.endsWith('.test.js'))) {
    for (const m of fs.readFileSync(__dirname + '/' + f, 'utf-8').matchAll(/\bAPI\.([A-Za-z]+)/g)) called.add(m[1]);
  }
  const missing = [...called].filter(n => !(n in API));
  assertEq(missing.join(','), '');
  assert(!('notAVerb' in API), 'control: the check can fail');
});

// --- RUNNER ----------------------------------------------------------

async function run() {
  let passed = 0, failed = 0;
  for (const { name, fn } of tests) {
    try {
      await fn();
      console.log(`✓ ${name}`);
      passed++;
    } catch (e) {
      console.error(`✗ ${name}: ${e.message}`);
      failed++;
    }
  }
  const summary = `${passed} passed, ${failed} failed`;
  console.log(summary);
  if (typeof document !== 'undefined') {
    const el = document.createElement('pre');
    el.textContent = summary;
    document.body.appendChild(el);
  }
  if (typeof process !== 'undefined' && failed > 0) process.exit(1);
}

// Auto-run in browser; explicit invocation in node.
if (typeof window !== 'undefined') {
  window.addEventListener('load', run);
} else {
  run();
}
