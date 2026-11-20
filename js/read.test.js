/**
 * Reading together on the web (WEB-DESIGN §4.17, PLAYS-DESIGN §12), against a stubbed Worker.
 *
 *   node js/read.test.js
 *
 * Runs the SHIPPED js/api.js, js/read-core.js and js/read-session.js. ReadCore's port of the
 * protocol is golden-checked against worker/test/read-golden.json (the file every client port
 * reads), with a negative control: the same goldens over a copy of read-core.js with one rule
 * changed must fail. The stub Worker answers like worker/src/read-rooms.js and is built from
 * worker/src/read-protocol.js's own functions, so it holds no rule of its own; its fake socket
 * refuses or accepts as a school network might. The casting board's arithmetic (Fill evenly,
 * totals, scene ranges) is checked on a small cast.
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { pathToFileURL } = require('node:url');

const ROOT = path.resolve(__dirname, '..');
const API_SRC = fs.readFileSync(path.join(__dirname, 'api.js'), 'utf8');
const CORE_SRC = fs.readFileSync(path.join(__dirname, 'read-core.js'), 'utf8');
const SESSION_SRC = fs.readFileSync(path.join(__dirname, 'read-session.js'), 'utf8');
const golden = JSON.parse(fs.readFileSync(path.join(ROOT, 'worker', 'test', 'read-golden.json'), 'utf8'));

const tests = [];
function test(name, fn) { tests.push({ name, fn }); }
function eq(a, b, msg) {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg || ''} expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`);
}
function ok(v, msg) { if (!v) throw new Error(msg || 'expected true'); }

function coreFrom(src) {
  const ctx = vm.createContext({});
  vm.runInContext(src, ctx, { filename: 'read-core.js' });
  return vm.runInContext('ReadCore', ctx);
}
const C = coreFrom(CORE_SRC);

/* ---- The goldens: every case of a function the client ports ---- */
const PORTED = ['normalizeCode', 'codeFromBytes', 'clockOffset', 'canLead', 'partsOf', 'whoReads', 'nextMine', 'leaderGone'];
const norm = (v) => JSON.parse(JSON.stringify(v === undefined ? null : v));
function goldenFailures(core) {
  const bad = [];
  for (const c of golden.cases) {
    if (PORTED.includes(c.fn)) {
      const got = norm(core[c.fn](...c.args));
      if (JSON.stringify(got) !== JSON.stringify(norm(c.expect))) bad.push(`${c.fn} (${c.note}): got ${JSON.stringify(got)}`);
    } else if (c.fn === 'joinSnapshot') {
      // A snapshot is all a client holds: from it alone the client must land on the server's next line.
      const snap = c.expect;
      const cast = c.args[1];
      const got = norm(core.nextMine(core.roomOf(snap), cast, snap.you, snap.cursor));
      if (JSON.stringify(got) !== JSON.stringify(norm(snap.next_mine))) bad.push(`snapshot next line (${c.note}): got ${JSON.stringify(got)}`);
      const lit = core.mineIndexes(core.roomOf(snap), cast, snap.you);
      if (snap.next_mine && !lit.includes(cast.findIndex((l) => l[0] === snap.next_mine.line))) bad.push(`snapshot lit lines (${c.note})`);
    }
  }
  return bad;
}

test('golden: every ported case in worker/test/read-golden.json (every client port runs these)', () => {
  const n = golden.cases.filter((c) => PORTED.includes(c.fn) || c.fn === 'joinSnapshot').length;
  ok(n >= 30, `the golden file has its cases (${n})`);
  const bad = goldenFailures(C);
  ok(!bad.length, bad.slice(0, 3).join('\n    '));
});

test('golden: the constants are the protocol\'s', () => {
  for (const k of ['PROTOCOL_VERSION', 'CODE_ALPHABET', 'CODE_LENGTH', 'MAX_MEMBERS', 'MEMBER_GONE_MS', 'LEADER_GONE_MS', 'POLL_MS', 'MODES']) {
    eq(C[k], golden.constants[k], k);
  }
});

test('negative control: a class room that hands the lead on (the adult rule) fails the goldens', () => {
  const mutant = CORE_SRC.replace("if (room.kind === 'class') return { leader: room.leader, waiting: true };", '');
  ok(mutant !== CORE_SRC, 'the mutation applied');
  ok(goldenFailures(coreFrom(mutant)).length > 0, 'a class room passing its lead passed every golden');
});

test('negative control: a seat\'s range ignored (the whole part lit) fails the goldens', () => {
  const mutant = CORE_SRC.replace('if (i >= lo && i <= hi) return a;', 'return a;');
  ok(mutant !== CORE_SRC, 'the mutation applied');
  ok(goldenFailures(coreFrom(mutant)).length > 0, 'a seat lit outside its range passed every golden');
});

test('a slow poll never rewinds the cursor: an older generation is dropped', () => {
  const a = { type: 'snapshot', code: 'ABC123', generation: 5, server_time: 10 };
  ok(C.newer(null, a));
  ok(!C.newer(a, { ...a, generation: 4, server_time: 20 }), 'older generation');
  ok(C.newer(a, { ...a, generation: 6, server_time: 5 }), 'newer generation');
  ok(C.newer(a, { ...a, code: 'ZZZ999', generation: 1 }), 'another room');
});

test('the leader\'s Next and Back, and Rehearse\'s Again to the scene start', () => {
  const cast = [['a', 'directions'], ['b', 'role:X'], ['c', 'role:Y'], ['d', 'directions'], ['e', 'role:X']];
  eq(C.step(cast, 'b', 1), 'c');
  eq(C.step(cast, 'b', -1), 'a');
  eq(C.step(cast, 'e', 1), null, 'the end');
  eq(C.step(cast, 'a', -1), null, 'the start');
  eq(C.sceneStart(cast, 'e', [0, 3]), 'd');
  eq(C.sceneStart(cast, 'c', [0, 3]), 'a');
  eq(C.nextLine({ line: 'b', in: 3 }), 'Next: you, in 3 lines');
  eq(C.nextLine({ line: 'b', in: 1 }), 'Next: you, in 1 line');
  eq(C.nextLine({ line: 'b', in: 0 }), 'Your line');
  eq(C.nextLine(null), null);
});

/* ---- The casting board ---- */
const CAST = [['l1', 'directions'], ['l2', 'role:A'], ['l3', 'role:B'], ['l4', 'role:A'], ['l5', 'directions'], ['l6', 'role:C'], ['l7', 'role:A'], ['l8', 'role:B']];
const WORDS = [5, 40, 10, 30, 6, 12, 20, 8];
const STARTS = [0, 4];
const SEATS = [{ id: 's1', label: 'Lucy' }, { id: 's2', label: 'Tom' }, { id: 's3', label: 'Ana' }];

test('facts per part: lines, words, scenes, the longest speech', () => {
  const f = Object.fromEntries(C.partFacts(CAST, WORDS, STARTS).map((x) => [x.part, x]));
  eq([f['role:A'].lines, f['role:A'].words, f['role:A'].scenes, f['role:A'].longest], [3, 90, 2, 40]);
  eq([f['role:C'].lines, f['role:C'].words, f['role:C'].scenes], [1, 12, 1]);
});

test('Fill evenly is deterministic, largest part first to the lightest seat, and keeps the casting made', () => {
  const parts = C.partFacts(CAST, WORDS, STARTS).filter((p) => p.part.startsWith('role:'));
  const a = C.fillEvenly(parts, SEATS, [], CAST, WORDS);
  eq(a.map((x) => [x.part, x.seat]), [['role:A', 's1'], ['role:B', 's2'], ['role:C', 's3']]);
  eq(C.fillEvenly(parts, SEATS, [], CAST, WORDS), a, 'the same answer twice');
  const kept = C.fillEvenly(parts, SEATS, [{ part: 'role:A', seat: 's3', from: null, to: null }], CAST, WORDS);
  eq(kept[0], { part: 'role:A', seat: 's3', from: null, to: null }, 'the teacher\'s choice stands');
  eq(kept.slice(1).map((x) => x.seat), ['s1', 's2']);
  const totals = C.seatTotals(CAST, WORDS, a, SEATS);
  eq(totals.map((t) => t.words), [90, 18, 12]);
});

test('Split by scene: a part\'s ranges at scene boundaries, and a range counts only its lines', () => {
  const r = C.sceneRanges(CAST, 'role:A', STARTS);
  eq(r.map((x) => [x.from, x.to, x.lines]), [['l2', 'l4', 2], ['l7', 'l7', 1]]);
  const split = [{ part: 'role:A', seat: 's1', from: 'l2', to: 'l4' }, { part: 'role:A', seat: 's2', from: 'l7', to: 'l7' }];
  eq(C.seatTotals(CAST, WORDS, split, SEATS).map((t) => t.lines), [2, 1, 0]);
  eq(C.toWire(split)[0], { part: 'role:A', seat: 's1', from: 'l2', to: 'l4' });
  eq(C.toWire([{ part: 'role:B', seat: 's3', from: null, to: null }])[0], { part: 'role:B', seat: 's3' }, 'a whole part carries no range');
});

/* ---- The session against a stub Worker built from read-protocol.js ---- */
function world() {
  const w = { t: 1763500000000, timers: [], seq: 0 };
  w.now = () => w.t;
  w.timers_ = {
    setTimeout: (fn, ms) => { const id = ++w.seq; w.timers.push({ id, at: w.t + Math.max(0, ms || 0), fn }); return id; },
    clearTimeout: (id) => { w.timers = w.timers.filter((x) => x.id !== id); },
  };
  const flush = async () => { for (let i = 0; i < 20; i++) await new Promise((r) => setImmediate(r)); };
  w.flush = flush;
  w.advance = async (ms) => {
    const end = w.t + ms;
    for (;;) {
      await flush();
      w.timers.sort((a, b) => a.at - b.at || a.id - b.id);
      const next = w.timers[0];
      if (!next || next.at > end) break;
      w.t = next.at;
      w.timers.shift();
      next.fn();
    }
    w.t = end;
    await flush();
  };
  return w;
}

function stubWorker(P, w) {
  const s = { rooms: new Map(), calls: [], sockets: [], blockSockets: false, urls: [], n: 0 };
  const json = (status, body) => ({ ok: status >= 200 && status < 300, status, json: async () => body, headers: { get: () => null } });
  const problem = (status, error, detail) => json(status, { error, detail });
  const cast = [['l1', 'directions'], ['l2', 'role:LUCY'], ['l3', 'role:TOM'], ['l4', 'role:LUCY'], ['l5', 'role:TOM']];
  const member = (role) => { s.n++; return { id: `m${s.n}`, key: `key-${s.n}`, role, seat: null, joined_at: w.now(), seen_at: w.now() }; };
  const snap = (room, id) => P.joinSnapshot(room.room, cast, room.members, id, w.now());
  function broadcast(room) {
    for (const ws of s.sockets) if (ws.room === room && ws.member && ws.readyState === 1) ws.deliver(snap(room, ws.member));
  }
  function apply(room, id, msg) {
    const r = P.applyMessage({ room: room.room, cast, members: room.members }, id, msg, w.now());
    if (r.error) return r;
    room.room = r.room; room.members = r.members;
    if (r.changed) broadcast(room);
    return r;
  }
  s.cast = cast;
  s.fetch = async (url, init = {}) => {
    const u = new URL(url);
    s.urls.push(u.pathname + u.search);
    const method = init.method || 'GET';
    const body = init.body ? JSON.parse(init.body) : null;
    const key = (init.headers || {})['x-read-key'];
    s.calls.push({ method, path: u.pathname, key });
    if (u.pathname === '/v1/read') {
      const code = 'ABC123';
      const m = member('reader');
      const made = P.newRoom({ code, kind: 'adult', script_id: body.script_id, script_revision: body.script_revision }, cast, m.id, w.now());
      const room = { room: made.room, members: [m], keys: new Map([[m.key, m.id]]), pollOnly: !!s.pollOnly };
      s.rooms.set(code, room);
      return json(200, { ...snap(room, m.id), member_key: m.key, transport: room.pollOnly ? 'poll' : 'socket' });
    }
    const m = /^\/v1\/read\/([^/]+)(?:\/(join|send))?$/.exec(u.pathname);
    const room = m && s.rooms.get(P.normalizeCode(m[1]));
    if (!room) return problem(404, 'no_such_room');
    if (m[2] === 'join') {
      const refusal = P.joinRefusal(room.room, room.members, body, w.now());
      if (refusal) return problem(409, refusal);
      const me = member(body.role || 'reader');
      room.members.push(me); room.keys.set(me.key, me.id);
      broadcast(room);
      return json(200, { ...snap(room, me.id), member_key: me.key, transport: room.pollOnly ? 'poll' : 'socket' });
    }
    const id = room.keys.get(key);
    if (!id) return problem(403, 'not_a_member');
    room.members = room.members.map((x) => (x.id === id ? { ...x, seen_at: w.now() } : x));
    if (m[2] === 'send') {
      const r = apply(room, id, body);
      if (r.error) return problem(r.error === 'stale' ? 409 : 403, r.error, r.detail);
      return json(200, r.reply ? { ...snap(room, id), reply: r.reply } : snap(room, id));
    }
    return json(200, snap(room, id));
  };
  s.WebSocket = class {
    constructor(url) {
      this.url = url; this.readyState = 0; this.sent = []; this.member = null;
      s.urls.push(url);
      const code = /\/v1\/read\/([^/]+)\/socket$/.exec(new URL(url).pathname)[1];
      this.room = s.rooms.get(code);
      s.sockets.push(this);
      w.timers_.setTimeout(() => {
        if (s.blockSockets || !this.room || this.room.pollOnly) { this.readyState = 3; if (this.onclose) this.onclose({}); return; }
        this.readyState = 1; if (this.onopen) this.onopen({});
      }, 50);
    }
    deliver(msg) { w.timers_.setTimeout(() => { if (this.readyState === 1 && this.onmessage) this.onmessage({ data: JSON.stringify(msg) }); }, 5); }
    send(data) {
      const msg = JSON.parse(data);
      this.sent.push(msg);
      if (!this.member) {
        if (msg.type !== 'hello') { this.deliver({ type: 'error', error: 'hello_first' }); return; }
        const id = this.room.keys.get(msg.key);
        if (!id) { this.deliver({ type: 'error', error: 'not_a_member' }); return; }
        this.member = id;
        this.deliver(snap(this.room, id));
        return;
      }
      const r = apply(this.room, this.member, msg);
      if (r.error) this.deliver({ type: 'error', error: r.error, detail: r.detail });
      else if (r.reply) this.deliver(r.reply);
    }
    close() { this.readyState = 3; }
    drop() { this.readyState = 3; if (this.onclose) this.onclose({}); }
  };
  return s;
}

function memStorage() {
  const m = new Map();
  return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)), removeItem: (k) => m.delete(k) };
}

function client(w, server, storage = memStorage()) {
  const ctx = vm.createContext({
    console, URL, URLSearchParams, JSON, Promise, Map, Set, Error, encodeURIComponent, decodeURIComponent, setImmediate,
    CONFIG: { worker: 'https://api.test' },
    AbortSignal: { timeout: () => undefined },
    fetch: (url, init) => server.fetch(url, init),
    WebSocket: server.WebSocket,
    location: { search: '', hostname: 'localhost' },
    navigator: { onLine: true },
  });
  vm.runInContext(API_SRC, ctx, { filename: 'api.js' });
  vm.runInContext(CORE_SRC, ctx, { filename: 'read-core.js' });
  vm.runInContext(SESSION_SRC, ctx, { filename: 'read-session.js' });
  const api = vm.runInContext('API', ctx);
  api.read._test.clock(w.now);
  const session = vm.runInContext('ReadSession', ctx).make({ api, core: vm.runInContext('ReadCore', ctx), timers: w.timers_, now: w.now, storage });
  return { api, session, storage };
}

async function main() {
  const P = await import(pathToFileURL(path.join(ROOT, 'worker', 'src', 'read-protocol.js')).href);
  const body = { script_id: 'gut-1', script_revision: 'r1', cast: [] };

  test('the socket: the key goes in a first hello message, never in a URL, and the leader\'s Next reaches a reader', async () => {
    const w = world();
    const server = stubWorker(P, w);
    const lead = client(w, server);
    await lead.session.open(body);
    const reader = client(w, server);
    await reader.session.join('abc-123');
    await w.advance(200);
    eq(lead.session.state().transport, 'socket');
    eq(reader.session.state().transport, 'socket');
    const ws = server.sockets.find((x) => x.member);
    eq(ws.sent[0].type, 'hello');
    ok(ws.sent[0].key.startsWith('key-'), 'the hello carries the key');
    ok(!server.urls.some((u) => /key-/.test(u)), 'no URL holds a key');
    await lead.session.send({ type: 'cursor', line: 'l2', base: 0 });
    await w.advance(50);
    eq(reader.session.state().snap.cursor, 'l2', 'the reader follows');
    eq(reader.session.state().snap.cursor_gen, 1);
  });

  test('a network that blocks sockets falls back to polling the same room with the same messages', async () => {
    const w = world();
    const server = stubWorker(P, w);
    server.blockSockets = true;
    const lead = client(w, server);
    await lead.session.open(body);
    const reader = client(w, server);
    await reader.session.join('ABC123');
    await w.advance(300);
    eq(reader.session.state().transport, 'poll');
    eq(lead.session.state().transport, 'poll');
    await lead.session.send({ type: 'cursor', line: 'l3', base: 0 });
    eq(lead.session.state().snap.cursor, 'l3', 'the HTTP answer is the snapshot');
    await w.advance(1100);
    eq(reader.session.state().snap.cursor, 'l3', 'the reader\'s poll brings the move');
    ok(server.calls.some((c) => c.method === 'GET' && c.key), 'polled with the key in its header');
  });

  test('a dropped socket keeps following by polling, then the socket comes back', async () => {
    const w = world();
    const server = stubWorker(P, w);
    const lead = client(w, server);
    await lead.session.open(body);
    await w.advance(200);
    eq(lead.session.state().transport, 'socket');
    server.sockets[0].drop();
    await w.advance(10);
    eq(lead.session.state().transport, 'poll');
    await w.advance(2500);
    eq(lead.session.state().transport, 'socket', 'the socket again after the retry');
  });

  test('a stale move is refused and the device resyncs from the snapshot', async () => {
    const w = world();
    const server = stubWorker(P, w);
    server.blockSockets = true;
    const lead = client(w, server);
    await lead.session.open(body);
    await lead.session.send({ type: 'cursor', line: 'l2', base: 0 });
    let code = null;
    try { await lead.session.send({ type: 'cursor', line: 'l4', base: 0 }); } catch (e) { code = e.code; }
    eq(code, 'stale');
    await w.flush();
    eq(lead.session.state().snap.cursor, 'l2', 'the room did not jump');
  });

  test('a reload resumes with this tab\'s key and lands at the cursor', async () => {
    const w = world();
    const server = stubWorker(P, w);
    server.blockSockets = true;
    const lead = client(w, server);
    await lead.session.open(body);
    await lead.session.send({ type: 'cursor', line: 'l4', base: 0 });
    const again = client(w, server, lead.storage);
    eq(await again.session.resume('ABC123'), true);
    eq(again.session.state().snap.cursor, 'l4');
    eq(await client(w, server).session.resume('ABC123'), false, 'another tab holds no key');
  });

  test('every answer is a clock sample, and a ping\'s pong adds one (T4\'s delay measurement)', async () => {
    const w = world();
    const server = stubWorker(P, w);
    const lead = client(w, server);
    await lead.session.open(body);
    const n = lead.api.read.samples().length;
    ok(n >= 1, 'create was a sample');
    await w.advance(10500);
    ok(lead.api.read.samples().length > n, 'a ping added a sample');
    eq(typeof lead.session.offset(), 'number');
  });

  test('an ended room ends here and forgets the key', async () => {
    const w = world();
    const server = stubWorker(P, w);
    server.blockSockets = true;
    const lead = client(w, server);
    await lead.session.open(body);
    await lead.session.send({ type: 'end' });
    await w.flush();
    eq(lead.session.state().ended, 'room_ended');
    eq(lead.storage.getItem('ed.read'), null);
  });

  let pass = 0; let fail = 0;
  for (const t of tests) {
    try { await t.fn(); console.log(`  ok    ${t.name}`); pass++; } catch (e) { console.log(`  FAIL  ${t.name}\n    ${e.message}`); fail++; }
  }
  console.log(`${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
}
main().catch((e) => { console.error(e); console.log('FAIL harness'); process.exit(1); });
