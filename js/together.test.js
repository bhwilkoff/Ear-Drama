/**
 * Listen Together on the web (WEB-DESIGN §4.12), against a stubbed Worker.
 *
 *   node js/together.test.js
 *
 * Runs the SHIPPED js/api.js, js/together-core.js, and js/together.js, two
 * clients in two contexts (a host and a guest) on one fake clock. The stub
 * Worker answers like worker/src/rooms.js and is built from
 * worker/src/room-protocol.js's own functions (the arbiter, handoff, presence,
 * the room message), so it cannot hold a rule of its own. The core's drift,
 * clock, cadence, and code rules are golden-checked against that same file on
 * shared cases. Each guarantee was broken once by hand to see its test fail
 * (the commit that added this file says how).
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const tests = [];
function test(name, fn) { tests.push({ name, fn }); }
function eq(a, b, msg) {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg || ''} expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`);
}
function ok(v, msg) { if (!v) throw new Error(msg || 'expected true'); }
const near = (a, b, eps = 1e-6) => Math.abs(a - b) <= eps;

/* ---- One fake clock and its timers, shared by both clients and the Worker ---- */
function world() {
  const w = { t: 1761200000000, timers: [], seq: 0, audios: [] };
  w.now = () => w.t;
  w.timersFor = () => ({
    setTimeout: (fn, ms) => { const id = ++w.seq; w.timers.push({ id, at: w.t + Math.max(0, ms || 0), fn }); return id; },
    clearTimeout: (id) => { w.timers = w.timers.filter((x) => x.id !== id); },
    setInterval: (fn, ms) => { const id = ++w.seq; w.timers.push({ id, at: w.t + ms, fn, every: ms }); return id; },
    clearInterval: (id) => { w.timers = w.timers.filter((x) => x.id !== id); },
  });
  const flush = async () => { for (let i = 0; i < 20; i++) await new Promise((r) => setImmediate(r)); };
  w.flush = flush;
  /** Moves the clock forward, playing every playing audio along, running each timer as it falls due. */
  w.advance = async (ms) => {
    const end = w.t + ms;
    for (;;) {
      w.timers.sort((a, b) => a.at - b.at || a.id - b.id);
      const next = w.timers[0];
      const to = next && next.at <= end ? next.at : end;
      w.audios.forEach((a) => { if (!a.paused && !a.stalled) a.currentTime += ((to - w.t) / 1000) * a.playbackRate; });
      w.t = to;
      if (!next || next.at > end) break;
      if (next.every) next.at += next.every; else w.timers.shift();
      next.fn();
      await flush();
    }
    await flush();
  };
  return w;
}

/* ---- The stub Worker: rooms.js's routes over room-protocol.js's rules ---- */
function stubWorker(P, w, skewMs) {
  const s = { rooms: new Map(), calls: [], n: 0, codes: [] };
  const clock = () => w.now() + skewMs;
  const json = (status, body) => ({ ok: status >= 200 && status < 300, status, json: async () => body });
  const problem = (status, error) => json(status, { error });
  function snapshot(room, memberId, now, extra = {}) {
    const live = P.liveMembers(room.members, now);
    return json(200, { ...P.roomSnapshot({ code: room.code, state: room.state, role: room.host === memberId ? 'host' : 'guest',
                                           members: live.length, now }), ...extra });
  }
  function newMember(now) { s.n++; return { id: `m${s.n}`, key: `key-${String(s.n).padStart(16, '0')}`, joined_at: now, seen_at: now }; }
  function settle(room, presentId, now) {
    room.members = P.liveMembers(room.members.map((m) => (m.id === presentId ? { ...m, seen_at: now } : m)), now);
    if (!room.members.some((m) => m.id === room.host)) room.host = P.nextHost(room.members, room.host, now);
    if (!room.host) { s.rooms.delete(room.code); return false; }
    return true;
  }
  s.fetch = async (url, init = {}) => {
    const u = new URL(url);
    const method = init.method || 'GET';
    const body = init.body ? JSON.parse(init.body) : null;
    const key = (init.headers && init.headers['x-room-key']) || null;
    s.calls.push({ method, path: u.pathname, body, key });
    await Promise.resolve();
    const now = clock();
    if (u.pathname === '/v1/rooms') {
      const r = P.applyHostState(null, body && body.state, now);
      if (r.error) return problem(400, 'bad_request');
      const code = s.codes.shift() || P.codeFromBytes(Array.from({ length: 6 }, () => Math.floor(Math.random() * 256)));
      const m = newMember(now);
      const room = { code, state: r.state, host: m.id, members: [m], touched_at: now };
      s.rooms.set(code, room);
      return snapshot(room, m.id, now, { member_key: m.key });
    }
    const match = /^\/v1\/rooms\/([^/]+)(?:\/(join|state|leave))?$/.exec(u.pathname);
    if (!match) return problem(404, 'not_found');
    const code = P.normalizeCode(decodeURIComponent(match[1]));
    if (!code) return problem(400, 'bad_code');
    const room = s.rooms.get(code);
    if (!room) return problem(404, 'no_such_room');
    if (P.roomExpired(room, now)) { s.rooms.delete(code); return problem(410, 'room_ended'); }
    const action = `${method} ${match[2] || ''}`;
    if (action === 'POST join') {
      if (!settle(room, null, now)) return problem(410, 'room_ended');
      if (room.members.length >= P.MAX_MEMBERS) return problem(409, 'room_full');
      const m = newMember(now);
      room.members.push(m);
      room.touched_at = now;
      return snapshot(room, m.id, now, { member_key: m.key });
    }
    const me = room.members.find((m) => m.key === key);
    if (!me) return problem(403, 'not_a_member');
    if (!settle(room, me.id, now)) return problem(410, 'room_ended');
    const isHost = room.host === me.id;
    if (action === 'POST leave') {
      room.members = room.members.filter((m) => m.id !== me.id);
      if (isHost) room.host = P.nextHost(room.members, me.id, now);
      if (!room.host) { s.rooms.delete(code); return json(200, { left: true, room_ended: true }); }
      return json(200, { left: true, room_ended: false });
    }
    if (action === 'DELETE ') {
      if (!isHost) return problem(403, 'host_only');
      s.rooms.delete(code);
      return json(200, { ended: true });
    }
    if (action === 'PUT state') {
      if (!isHost) return problem(403, 'host_only');
      const r = P.applyHostState(room.state, body, now);
      if (r.error) return problem(400, 'bad_request');
      room.state = r.state;
      room.touched_at = now;
      return snapshot(room, me.id, now);
    }
    if (action === 'GET ') return snapshot(room, me.id, now);
    return problem(405, 'method_not_allowed');
  };
  return s;
}

/* ---- A fake player with the shipped Player's surface ---- */
function fakePlayer(w) {
  const handlers = {};
  const audio = {
    paused: true, currentTime: 0, duration: 1800, playbackRate: 1, readyState: 4, seeking: false, stalled: false, blockPlay: false,
    addEventListener(t, fn) { (handlers[t] ||= []).push(fn); },
    fire(t) { (handlers[t] || []).slice().forEach((fn) => fn()); },
  };
  w.audios.push(audio);
  const listeners = new Set();
  const emit = (k) => listeners.forEach((fn) => fn(k));
  const p = {
    audio, current: null, following: false, stored: 1, loads: [],
    onChange(fn) { listeners.add(fn); },
    load(card, { autoplay = true, at = null } = {}) {
      p.current = card; p.loads.push({ card, at });
      audio.paused = true; audio.currentTime = at || 0; audio.playbackRate = p.stored;
      emit('load');
      if (autoplay) p.follow.play();
    },
    setFollowing(on) { p.following = !!on; if (!on) audio.playbackRate = p.stored; },
    follow: {
      play() {
        if (audio.blockPlay) { emit('blocked'); return Promise.reject(Object.assign(new Error('no'), { name: 'NotAllowedError' })); }
        if (audio.paused) { audio.paused = false; audio.fire('play'); }
        return Promise.resolve();
      },
      pause() { if (!audio.paused) { audio.paused = true; audio.fire('pause'); } },
      seek(t) { audio.currentTime = t; audio.fire('seeked'); },
      rate(r) { if (audio.playbackRate !== r) { audio.playbackRate = r; audio.fire('ratechange'); } },
    },
    // The person's verbs, as the shipped Player guards them.
    play() { if (!p.following) p.follow.play(); },
    pause() { if (!p.following) p.follow.pause(); },
    seek(t) { if (!p.following) p.follow.seek(t); },
    setRate(r) { if (!p.following) { p.stored = r; p.follow.rate(r); } },
    emit,
  };
  return p;
}

const ROOT = path.join(__dirname, '..');
function client(w, server, config = { worker: 'https://worker.test' }) {
  const ctx = vm.createContext({
    console, Math, Number, Date, JSON, Object, Promise, Set, Map, URL, URLSearchParams, Error, Array, String,
    encodeURIComponent, decodeURIComponent, TextEncoder, AbortSignal, setImmediate,
    setTimeout, clearTimeout, setInterval, clearInterval,
    navigator: { onLine: true }, CONFIG: config,
    fetch: (url, init) => server.fetch(url, init),
  });
  for (const f of ['api.js', 'together-core.js', 'together.js']) {
    vm.runInContext(fs.readFileSync(path.join(__dirname, f), 'utf-8'), ctx, { filename: f });
  }
  vm.runInContext('globalThis.API = API; globalThis.TogetherCore = TogetherCore; globalThis.Together = Together;', ctx);
  ctx.API.rooms._test.clock(w.now);
  const player = fakePlayer(w);
  const mem = new Map();
  const storage = { getItem: (k) => (mem.has(k) ? mem.get(k) : null), setItem: (k, v) => mem.set(k, v), removeItem: (k) => mem.delete(k) };
  const session = ctx.Together.make({ api: ctx.API.rooms, core: ctx.TogetherCore, player, now: w.now, timers: w.timersFor(), storage });
  return { ctx, player, session, storage, core: ctx.TogetherCore, api: ctx.API.rooms };
}

const EP = { id: 'suspense|1948-03-11', title: 'The Lodger', series: 'suspense',
             url: 'https://archive.org/download/OTRR_Suspense_Singles/Suspense%2048-03-11%20The%20Lodger%20%28AFRS%29.mp3' };
const EP2 = { id: 'suspense|1948-03-18', title: 'Next', series: 'suspense',
              url: 'https://archive.org/download/OTRR_Suspense_Singles/Suspense%2048-03-18.mp3' };

/** A host playing EP at 600 s and a guest who joined by a spoken code, both in the room. */
async function pair(P, { skew = 4000 } = {}) {
  const w = world();
  const server = stubWorker(P, w, skew);
  server.codes.push('7KQ2MX');
  const host = client(w, server);
  const guest = client(w, server);
  host.player.load(EP, { at: 600 });
  await host.session.start();
  await guest.session.join('7kq 2mx');
  await w.advance(2500);
  return { w, server, host, guest };
}

async function main() {
  const P = await import(path.join(ROOT, 'worker/src/room-protocol.js'));

  /* ---- Golden: the client's port against the protocol, on shared cases ---- */

  test('the core carries the protocol\'s constants', () => {
    const { ctx } = client(world(), { fetch: async () => null });
    const C = ctx.TogetherCore;
    eq({ ...C.DRIFT }, P.DRIFT, 'DRIFT');
    eq(C.CODE_ALPHABET, P.CODE_ALPHABET, 'alphabet');
    eq(C.CODE_LENGTH, P.CODE_LENGTH, 'code length');
    eq(C.PROTOCOL_VERSION, P.PROTOCOL_VERSION, 'version');
    eq(C.SPEEDS, P.SPEEDS, 'speeds');
  });

  test('golden: drift correction and where the host is, at and around every threshold', () => {
    const C = client(world(), { fetch: async () => null }).core;
    const offs = [-3, -2.01, -2, -1.99, -1, -0.151, -0.15, -0.149, 0, 0.149, 0.15, 0.151, 1, 1.99, 2, 2.01, 3];
    let n = 0;
    for (const rate of P.SPEEDS) {
      for (const playing of [true, false]) {
        for (const elapsed of [0, 1500, 61000]) {
          const state = { position: 600, playing, rate, updated_at: 1000 };
          const serverNow = 1000 + elapsed;
          eq(C.expectedPosition(state, serverNow), P.expectedPosition(state, serverNow), 'expectedPosition');
          const target = P.expectedPosition(state, serverNow);
          for (const off of offs) {
            for (const pp of [true, false]) {
              const player = { position: target + off, playing: pp };
              eq(C.correction(state, serverNow, player), P.correction(state, serverNow, player), `correction ${JSON.stringify({ state, off, pp })}`);
              n++;
            }
          }
        }
      }
    }
    ok(n > 1000, `cases ${n}`);
  });

  test('golden: the clock estimate, the poll cadence, and the code rules', () => {
    const C = client(world(), { fetch: async () => null }).core;
    const sets = [[], [{ t0: 0, server_time: 5000, t1: 100 }],
      [{ t0: 0, server_time: 5000, t1: 400 }, { t0: 1000, server_time: 6020, t1: 1040 }, { t0: 2000, server_time: 7000, t1: 2200 }],
      [{ t0: 10, server_time: 5, t1: 5 }, { t0: 0, server_time: 1, t1: 0 }]];
    for (const s of sets) eq(C.clockOffset(s), P.clockOffset(s), `clockOffset ${JSON.stringify(s)}`);
    for (const d of [0, 1999, 59999, 60000, 60001, 120000]) eq(C.pollInterval(0, d), P.pollInterval(0, d), `pollInterval ${d}`);
    for (const c of ['7KQ2MX', ' 7kq 2mx ', '7KQ-2MX', 'o1l-iuo', 'oilOIL', 'UUUUUU', '7KQ2M', '7KQ2MXX', '', 'ABC_DEF', '7kq2m!', 42, null]) {
      eq(C.normalizeCode(c), P.normalizeCode(c), `normalizeCode ${JSON.stringify(c)}`);
    }
    for (const [id, f] of [['OTRR_x', 'a b.mp3'], ['x', '../a.mp3'], ['x', 'a//b.mp3'], ['x', '/a.mp3'], ['x y', 'a.mp3'],
      ['x', 'dir/a (1).mp3'], ['x', 'a\\b.mp3'], ['x', 'a\u0001.mp3'], ['x', '']]) {
      eq(C.cleanCopy(id, f), P.cleanCopy(id, f), `cleanCopy ${id} ${f}`);
    }
  });

  test('the copy: a played URL names its archive.org item and file, and the guest rebuilds the same URL', () => {
    const C = client(world(), { fetch: async () => null }).core;
    const urls = [EP.url,
      'https://archive.org/download/FranklinDRooseveltsPrayer/Franklin%20D.%20Roosevelt%2527s%20Prayer%2C%2006%3A06%3A1944.mp3',
      'https://archive.org/download/command-performance/Command%20Performance%20%28xx%29%20Victory%20Extra%20%28part%201%29.mp3',
      'https://archive.org/download/faust2_1008_librivox/faust2_21_goethe_64kb.mp3'];
    for (const u of urls) {
      const copy = C.copyOfUrl(u);
      ok(copy && P.cleanCopy(copy.archive_id, copy.file), `copy of ${u}`);
      eq(C.urlOfCopy(copy), u, 'rebuilt URL');
    }
    eq(C.copyOfUrl('https://archive.org/download/OTRR_Suspense_Singles/Suspense%2048-03-11.mp3').file, 'Suspense 48-03-11.mp3');
    eq(C.copyOfUrl('https://example.com/download/x/a.mp3'), null, 'another host');
    eq(C.copyOfUrl('https://archive.org/download/x/..%2Fy.mp3'), null, 'a climb out of the item');
    eq(C.urlOfCopy({ archive_id: 'x', file: '../y.mp3' }), null, 'a bad copy builds no URL');
  });

  /* ---- The session against the stub Worker ---- */

  test('a placeholder Worker URL: not available, and no call is made', async () => {
    const w = world();
    const server = stubWorker(P, w, 0);
    const c = client(w, server, { worker: 'REPLACE_WITH_WORKER_BASE_URL' });
    c.player.load(EP);
    eq(c.session.info().available, false, 'available');
    await c.session.start();
    await c.session.join('7KQ2MX');
    eq(server.calls.length, 0, 'calls');
    eq(c.session.info().inRoom, false, 'in a room');
  });

  test('create carries the host\'s exact copy; join by a spoken code; the count is the room\'s', async () => {
    const { server, host, guest } = await pair(P);
    const room = server.rooms.get('7KQ2MX');
    eq([room.state.episode_id, room.state.archive_id, room.state.file],
      [EP.id, 'OTRR_Suspense_Singles', 'Suspense 48-03-11 The Lodger (AFRS).mp3'], 'room copy');
    eq(host.session.info().role, 'host');
    eq(guest.session.info().role, 'guest');
    eq(host.session.info().members, 2, 'host sees 2');
    eq(guest.session.info().members, 2, 'guest sees 2');
    eq(guest.player.current.url, EP.url, 'guest plays the host\'s copy, built from archive_id and file');
    eq(guest.player.following, true, 'guest follows');
    ok(!guest.player.audio.paused, 'guest plays');
    ok(server.calls.every((c) => !c.body || !('key' in c.body)), 'no key in a body');
  });

  test('leave: the guest is out and the host\'s count drops', async () => {
    const { w, server, host, guest } = await pair(P);
    await guest.session.leave();
    eq(guest.session.info().inRoom, false);
    eq(guest.player.following, false, 'the guest\'s controls are back');
    eq(guest.storage.getItem('ed.room'), null, 'the key is forgotten');
    await w.advance(2500);
    eq(host.session.info().members, 1, 'host count');
    eq(server.rooms.get('7KQ2MX').members.length, 1);
  });

  test('a guest cannot drive: the guest never writes, and a guest key is refused with the room unchanged', async () => {
    const { w, server, guest } = await pair(P);
    const gen = server.rooms.get('7KQ2MX').state.generation;
    guest.player.pause();
    guest.player.seek(10);
    guest.player.setRate(2);
    guest.player.audio.fire('pause');
    await w.advance(5000);
    const guestKey = JSON.parse(guest.storage.getItem('ed.room')).key;
    ok(!server.calls.some((c) => c.method === 'PUT' && c.key === guestKey), 'the guest sent no state');
    let refused = null;
    try { await guest.api.setState('7KQ2MX', guestKey, { playing: false }); } catch (e) { refused = e.kind; }
    eq(refused, 'host_only', 'refusal');
    eq(server.rooms.get('7KQ2MX').state.generation, gen, 'room unchanged');
    ok(!guest.player.audio.paused, 'the guest still plays with the host');
  });

  test('the guest follows play, pause, seek, and speed', async () => {
    const { w, host, guest } = await pair(P);
    host.player.pause();
    await w.advance(2500);
    ok(guest.player.audio.paused, 'paused with the host');
    ok(near(guest.player.audio.currentTime, host.player.audio.currentTime, 0.15), 'at the host\'s place');
    host.player.seek(1200);
    host.player.play();
    await w.advance(2500);
    ok(!guest.player.audio.paused, 'playing again');
    ok(Math.abs(guest.player.audio.currentTime - host.player.audio.currentTime) < 0.15, `after the seek: ${guest.player.audio.currentTime} vs ${host.player.audio.currentTime}`);
    host.player.setRate(1.5);
    await w.advance(2500);
    ok([1.5, 1.5 * 0.97, 1.5 * 1.03].some((r) => near(guest.player.audio.playbackRate, r)), `the host's speed, nudged at most: ${guest.player.audio.playbackRate}`);
    for (let i = 0; i < 60 && guest.player.audio.playbackRate !== 1.5; i++) await w.advance(500);
    eq(guest.player.audio.playbackRate, 1.5, 'speed');
    eq(guest.player.stored, 1, 'the room\'s speed is never kept as the guest\'s own');
  });

  test('drift: nothing under 150 ms, the speed by 3% from 150 ms to 2 s, a seek over 2 s', async () => {
    const { w, host, guest } = await pair(P, { skew: -7000 });
    const g = guest.player.audio;
    const target = () => guest.core.expectedPosition(guest.session.info().state, w.now() - 7000);
    const cases = [
      [0.149, 1, false], [-0.149, 1, false], [0.151, 0.97, false], [-0.151, 1.03, false],
      [1.99, 0.97, false], [-1.99, 1.03, false], [2.01, null, true], [-2.01, null, true],
    ];
    for (const [off, rate, seeks] of cases) {
      g.currentTime = target() + off;
      g.playbackRate = 1;
      guest.session._test.tick();
      if (seeks) ok(near(g.currentTime, target(), 1e-6), `${off}: seeks to the host`);
      else {
        ok(near(g.playbackRate, rate), `${off}: rate ${g.playbackRate}, want ${rate}`);
        ok(near(g.currentTime, target() + off), `${off}: no seek`);
      }
    }
    // A nudge closes the gap and then lets go.
    g.currentTime = target() + 1;
    g.playbackRate = 1;
    for (let i = 0; i < 80 && Math.abs(g.currentTime - target()) >= 0.15; i++) await w.advance(500);
    ok(Math.abs(g.currentTime - target()) < 0.15, 'closed by speed');
    await w.advance(500);
    eq(g.playbackRate, 1, 'back to the host\'s rate inside 150 ms');
    ok(host.player.audio.playbackRate === 1, 'the host is never nudged');
  });

  test('a stalled guest catches up; the room does not wait', async () => {
    const { w, server, guest } = await pair(P);
    const gen = server.rooms.get('7KQ2MX').state.generation;
    guest.player.audio.stalled = true;
    guest.player.audio.readyState = 2;
    await w.advance(5000);
    guest.player.audio.stalled = false;
    guest.player.audio.readyState = 4;
    await w.advance(600);
    const t = guest.core.expectedPosition(guest.session.info().state, w.now() + 4000);
    ok(Math.abs(guest.player.audio.currentTime - t) < 0.15, `caught up: ${guest.player.audio.currentTime} vs ${t}`);
    eq(server.rooms.get('7KQ2MX').state.generation, gen, 'the room never waited');
  });

  test('handoff: the host leaves, the guest becomes host and drives', async () => {
    const { w, server, host, guest } = await pair(P);
    await host.session.leave();
    await w.advance(2500);
    eq(guest.session.info().role, 'host', 'role');
    eq(guest.player.following, false, 'controls back');
    const gen = server.rooms.get('7KQ2MX').state.generation;
    guest.player.pause();
    await w.advance(500);
    const st = server.rooms.get('7KQ2MX').state;
    ok(st.generation > gen && st.playing === false, 'the new host\'s pause reached the room');
  });

  test('handoff when the host goes quiet for 2 minutes', async () => {
    const { w, host, guest } = await pair(P);
    host.ctx.API.rooms._test.configure({ worker: 'REPLACE_WITH_WORKER_BASE_URL' });
    await w.advance(P.MEMBER_GONE_MS + 15000);
    eq(guest.session.info().role, 'host', 'role');
  });

  test('an ended room: a plain notice for the guest, and a wrong or malformed code', async () => {
    const { w, server, host, guest } = await pair(P);
    await host.session.end();
    eq(host.session.info().inRoom, false);
    await w.advance(2500);
    eq(guest.session.info().inRoom, false, 'guest out');
    eq(guest.session.info().notice, 'room_ended', 'notice');
    eq(guest.player.following, false, 'controls back');
    await guest.session.join('ZZZZZZ');
    eq(guest.session.info().notice, 'no_such_room', 'wrong code');
    const before = server.calls.length;
    await guest.session.join('UUUUUU');
    eq(guest.session.info().notice, 'bad_code', 'malformed');
    eq(server.calls.length, before, 'a malformed code makes no call');
  });

  test('a guest who picks another episode leaves the room', async () => {
    const { w, host, guest } = await pair(P);
    guest.player.load(EP2);
    await w.flush();
    eq(guest.session.info().inRoom, false, 'left');
    await w.advance(2500);
    eq(host.session.info().members, 1);
  });

  test('a new episode on the host carries its copy to the guest', async () => {
    const { w, server, host, guest } = await pair(P);
    host.player.load(EP2, { at: 0 });
    await w.advance(2500);
    eq(server.rooms.get('7KQ2MX').state.file, 'Suspense 48-03-18.mp3');
    eq(guest.player.current.url, EP2.url, 'guest on the new copy');
    eq(guest.player.current.id, EP2.id);
  });

  test('the cadence: every 2 s while the room changes, every 10 s after a still minute', async () => {
    const { w, server, guest } = await pair(P);
    const key = JSON.parse(guest.storage.getItem('ed.room')).key;
    const reads = () => server.calls.filter((c) => c.method === 'GET' && c.key === key).length;
    let a = reads();
    await w.advance(10000);
    ok(reads() - a >= 4, `fast: ${reads() - a}`);
    await w.advance(60000);
    a = reads();
    await w.advance(30000);
    ok(reads() - a <= 3 && reads() - a >= 2, `slow: ${reads() - a}`);
  });

  test('a browser that will not start audio waits for one tap', async () => {
    const w = world();
    const server = stubWorker(P, w, 0);
    server.codes.push('7KQ2MX');
    const host = client(w, server);
    const guest = client(w, server);
    guest.player.audio.blockPlay = true;
    host.player.load(EP, { at: 30 });
    await host.session.start();
    await guest.session.join('7KQ2MX');
    await w.advance(1000);
    eq(guest.session.info().blocked, true, 'blocked');
    ok(guest.player.audio.paused);
    guest.player.audio.blockPlay = false;
    guest.session.tap();
    await w.advance(600);
    ok(!guest.player.audio.paused, 'plays after the tap');
  });

  test('a reload keeps the room from this tab\'s storage', async () => {
    const { w, server, guest } = await pair(P);
    const saved = guest.storage.getItem('ed.room');
    const again = client(w, server);
    again.storage.setItem('ed.room', saved);
    await again.session.restore();
    eq(again.session.info().inRoom, true);
    eq(again.session.info().code, '7KQ2MX');
  });

  let pass = 0; let fail = 0;
  for (const t of tests) {
    try { await t.fn(); console.log(`✓ ${t.name}`); pass++; } catch (e) { console.log(`FAIL ${t.name}\n    ${e.message}`); fail++; }
  }
  console.log(`${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
}
main().catch((e) => { console.error(e); console.log('FAIL harness'); process.exit(1); });
