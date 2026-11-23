/**
 * Relay across time (PLAYS-DESIGN §12.11) against a stubbed Worker:   node js/relay.test.js
 *
 * Runs the SHIPPED js/relay-core.js and js/relay-watch.js with the real plays-core, plays-store
 * (memory backend) and plays-share. The sender queue's clock is a hand-turned fake, so backoff is
 * measured, not waited for; the stub Worker answers like worker/src/plays-seats.js (a receiver
 * that is there or not, `nobody_receiving`, `not_assigned`), keeps no audio, and records every call.
 *
 * Each rule below was broken once in its source and the test seen to fail:
 *   RelayCore.delay() not growing: "backoff" fails.
 *   run() sending without a probe: "nothing is sent while the receiver is away" fails.
 *   isLater() treating nobody_receiving as final: "a take the receiver was not there for stays" fails.
 *   assignedLines() ignoring the range: "a scene range" fails.
 *   unsent() dropping the assigned-lines filter: "only assigned lines" fails.
 *   unsent() ignoring t.bleed: "a flagged take never leaves" fails.
 *   performers() without credits: "a credited maker blocks Publish and is listed" fails.
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const SRC = process.env.RELAY_SRC_DIR || __dirname;
for (const f of ['plays-core.js', 'plays-store.js']) vm.runInThisContext(fs.readFileSync(path.join(__dirname, f), 'utf8'), { filename: f });
for (const f of ['plays-share.js', 'relay-core.js', 'relay-watch.js']) vm.runInThisContext(fs.readFileSync(path.join(SRC, f), 'utf8'), { filename: f });
const C = vm.runInThisContext('PlaysCore');
const PlayStore = vm.runInThisContext('PlayStore');
const S = vm.runInThisContext('PlaysShare');
const R = vm.runInThisContext('RelayCore');
const W = vm.runInThisContext('RelayWatch');

let passes = 0, failures = 0;
const results = [];
function ok(cond, name) { if (cond) passes++; else { failures++; console.log(`FAIL ${name}`); } }
function eq(a, b, name) {
  const pass = JSON.stringify(a) === JSON.stringify(b);
  ok(pass, pass ? name : `${name}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`);
}
const test = (name, fn) => results.push([name, fn]);

/** A clock that only moves when told to. */
function fakeTimers() {
  let now = 0, id = 0;
  const jobs = new Map();
  return {
    setTimeout(fn, ms) { jobs.set(++id, { at: now + ms, fn }); return id; },
    clearTimeout(i) { jobs.delete(i); },
    setInterval() { return 0; },
    clearInterval() {},
    pending: () => [...jobs.values()].map(j => j.at - now),
    async advance(ms) {
      now += ms;
      for (const [k, j] of [...jobs]) if (j.at <= now) { jobs.delete(k); await j.fn(); }
    },
  };
}

function line(id, role, kind = 'speech', text = 'words') {
  return kind === 'speech' ? { id, kind, role, parts: [{ say: text }] } : { id, kind, source: text };
}
function fixtureScript() {
  const lines = [
    line('L0001', null, 'direction', '(A kitchen.)'),
    line('L0002', 'FIBBER', 'speech', 'Well, Molly.'),
    line('L0003', 'MOLLY', 'speech', 'Yes, dearie?'),
    line('L0004', null, 'sound', 'SOUND: DOOR OPENS'),
    line('L0005', 'DOC', 'speech', 'Anybody home?'),
    line('L0006', 'MOLLY', 'speech', 'Come in.'),
    line('L0007', 'MOLLY', 'speech', 'Sit down.'),
  ];
  const roles = ['MOLLY', 'FIBBER', 'DOC'].map(name => ({ name, lines: lines.filter(l => l.role === name).length, words: 2 }));
  return { id: 'gut-0', revision: 'r1', kind: 'radio', title: 'Good Grammar', authors: [], source: { name: 'Fixture', url: 'https://example.org' },
           rights: { bucket: 'script_source_cleared', evidence: [] }, roles, lines };
}
const MOLLY = 'role:MOLLY';
const castOf = (script) => script.lines.map(l => [l.id, C.linePart(l)]);

/** A production on this device with a take for each of `lineIDs` (one flagged on demand). */
async function localWith(link, lineIDs, { flagged = [] } = {}) {
  const script = fixtureScript();
  const store = PlayStore.open(PlayStore.memoryBackend());
  await store.load();
  let p = await store.create(script);
  await store.setShare(p.id, link);
  for (const id of lineIDs) {
    const file = await store.writeTake({ samples: new Float32Array(480), sampleRate: 48000 }, p, id);
    p = C.addTake(store.production(p.id), { id: `T-${id}`, lineID: id, part: C.linePart(script.lines.find(l => l.id === id)), file, created: 1, frames: 480,
                                            sampleRate: 48000, capture: 'direct', heard: {}, peak: 0.1, bleed: flagged.includes(id) });
    await store.save(p);
  }
  return { script, store, id: p.id };
}

/** The stub Worker for one seat: receiver present or not, a take refused or passed through, no audio kept. */
function stubWorker({ receiving = false, name = 'Ms. Ortiz', assignments = [{ part: MOLLY, from: null, to: null, seat: 's1' }], failWith = null, onlyLine = null } = {}) {
  const w = { receiving, name, assignments, calls: [], taken: [], failWith, probes: 0 };
  w.plays = {
    seatHome: async () => ({ productions: [{ id: 'pid-1', assignments: w.assignments, takes: w.taken.map(id => ({ id })) }] }),
    seatReceiver: async () => { w.probes++; return { receiving: w.receiving, name: w.name }; },
    seatSend: async (key, pid, takeId, bytes, meta) => {
      w.calls.push(['send', takeId, meta.lineID, bytes.byteLength]);
      if (w.failWith) { const e = new Error(w.failWith); e.code = w.failWith; throw e; }
      if (!w.receiving) { const e = new Error('nobody_receiving'); e.code = 'nobody_receiving'; throw e; }
      w.taken.push(takeId);
      return { delivered: true };
    },
  };
  return w;
}

const seatLink = { pid: 'pid-1', seat: { key: 'k'.repeat(24), class_id: 'c1', label: 'Lucy' }, assignments: [] };

/* ---- The rules ---- */

test('a take says one thing: where it is, or that it is sent', () => {
  eq(R.wording('waiting', 'Ms. Ortiz'), 'On this device · sends when Ms. Ortiz is in Ear Drama', 'waiting names the receiver');
  eq(R.wording('waiting', null, 'your teacher'), 'On this device · sends when your teacher is in Ear Drama', 'a fallback when the Worker has no name');
  eq(R.wording('sent', 'x'), 'Sent', 'sent');
  eq(R.wording('sending', 'x'), 'Sending', 'sending');
  eq(R.stateOf('a', { sent: ['a'], sending: 'a' }), 'sent', 'sent beats sending');
  eq(R.stateOf('b', { sent: ['a'], sending: 'b' }), 'sending', 'sending');
  eq(R.stateOf('c', { sent: ['a'], sending: 'b' }), 'waiting', 'waiting');
});

test('backoff: 5, 10, 20, 40 seconds, then every 60', () => {
  eq([0, 1, 2, 3, 4, 5, 20].map(R.delay), [5000, 10000, 20000, 40000, 60000, 60000, 60000], 'the gaps');
});

test('a scene range: a seat records only the lines of its part inside the range', () => {
  const cast = castOf(fixtureScript());
  eq(R.assignedLines(cast, [{ part: MOLLY, from: 'L0003', to: 'L0006', seat: 's1' }]), ['L0003', 'L0006'], 'the range');
  eq(R.assignedLines(cast, [{ part: MOLLY, from: null, to: null, seat: 's1' }]), ['L0003', 'L0006', 'L0007'], 'the whole part');
  eq(R.assignedLines(cast, []), [], 'no assignment, nothing to record');
});

test('nothing is sent while the receiver is away; it asks again 5, 10, 20 s later and sends the moment the receiver is there', async () => {
  const w = stubWorker({ receiving: false });
  const { script, store, id } = await localWith(seatLink, ['L0003', 'L0006']);
  const t = fakeTimers();
  const watch = W.make({ api: w, store, timers: t, online: () => true });
  await watch.kick(id);
  eq(w.calls, [], 'nothing sent while nobody receives');
  eq(w.probes, 1, 'it asked once');
  eq(t.pending(), [5000], 'and will ask again in 5 s');
  await t.advance(5000);
  eq(t.pending(), [10000], 'then 10 s');
  await t.advance(10000);
  eq(t.pending(), [20000], 'then 20 s');
  eq(watch.takeState(id, 'T-L0003').state, 'waiting', 'the take is waiting on this device');
  eq(watch.takeState(id, 'T-L0003').name, 'Ms. Ortiz', 'and knows who it waits for');
  w.receiving = true;
  await t.advance(20000);
  eq(w.calls.map(c => c[2]), ['L0003', 'L0006'], 'sent in script order the moment the receiver is there');
  eq(w.calls.every(c => c[3] > 44), true, 'the audio went with it');
  eq(watch.takeState(id, 'T-L0003').state, 'sent', 'sent');
  eq(store.share(id).sent, ['T-L0003', 'T-L0006'], 'remembered on the device, so Sent reads the same offline');
  ok((await store.readTake(id, store.production(id).takes[0].file)).byteLength > 44, 'the take stays on the device');
  eq(t.pending(), [], 'nothing left to ask about');
  void script;
});

test('a take the receiver was not there for stays: nobody_receiving is a back-off, never a loss', async () => {
  const w = stubWorker({ receiving: true });
  const { store, id } = await localWith(seatLink, ['L0003']);
  w.plays.seatReceiver = async () => ({ receiving: true, name: 'Ms. Ortiz' });
  w.receiving = false;
  const t = fakeTimers();
  const watch = W.make({ api: w, store, timers: t, online: () => true });
  await watch.kick(id);
  eq(w.calls.length, 1, 'tried once');
  eq(watch.takeState(id, 'T-L0003').state, 'waiting', 'still waiting');
  eq(store.share(id).sent || [], [], 'not marked sent');
  eq(t.pending(), [5000], 'backs off');
});

test('a final refusal leaves the queue once, stays on the device, and is never sent again', async () => {
  const w = stubWorker({ receiving: true, failWith: 'not_assigned' });
  const { store, id } = await localWith(seatLink, ['L0003']);
  const t = fakeTimers();
  const watch = W.make({ api: w, store, timers: t, online: () => true });
  await watch.kick(id);
  eq(watch.takeState(id, 'T-L0003'), { state: 'refused', code: 'not_assigned' }, 'the Worker\'s code');
  await watch.kick(id);
  eq(w.calls.length, 1, 'not sent again');
  eq(store.production(id).takes.length, 1, 'the take is still here');
});

test('offline: it does not ask, and tries again when told the network is back', async () => {
  const w = stubWorker({ receiving: true });
  const { store, id } = await localWith(seatLink, ['L0003']);
  const t = fakeTimers();
  let on = false;
  const watch = W.make({ api: w, store, timers: t, online: () => on });
  await watch.kick(id);
  eq(w.probes, 0, 'no probe offline');
  on = true;
  await watch.kick(id);
  eq(w.calls.length, 1, 'sent on kick');
});

test('only assigned lines: a take of a line the seat does not hold never leaves', async () => {
  const w = stubWorker({ receiving: true, assignments: [{ part: MOLLY, from: 'L0006', to: 'L0006', seat: 's1' }] });
  const { store, id } = await localWith(seatLink, ['L0003', 'L0006']);
  const watch = W.make({ api: w, store, timers: fakeTimers(), online: () => true });
  await watch.kick(id);
  eq(w.calls.map(c => c[2]), ['L0006'], 'only the assigned line');
});

test('a take the Worker already holds is not sent again, and a flagged take never leaves', async () => {
  const w = stubWorker({ receiving: true });
  w.taken.push('T-L0003');
  const { store, id } = await localWith(seatLink, ['L0003', 'L0006', 'L0007'], { flagged: ['L0007'] });
  const watch = W.make({ api: w, store, timers: fakeTimers(), online: () => true });
  await watch.kick(id);
  eq(w.calls.map(c => c[2]), ['L0006'], 'L0003 is already there, L0007 holds the device voice');
  eq(watch.takeState(id, 'T-L0003', ['T-L0003']).state, 'sent', 'what the Worker holds reads Sent');
});

test('two seats at once: each production has its own sender and its own state', async () => {
  const w = stubWorker({ receiving: true });
  const a = await localWith(seatLink, ['L0003']);
  const b = await localWith({ ...seatLink, seat: { ...seatLink.seat, label: 'Tom' } }, ['L0006']);
  const watchA = W.make({ api: w, store: a.store, timers: fakeTimers(), online: () => true });
  const watchB = W.make({ api: w, store: b.store, timers: fakeTimers(), online: () => true });
  await Promise.all([watchA.kick(a.id), watchB.kick(b.id)]);
  eq(w.calls.map(c => c[2]).sort(), ['L0003', 'L0006'], 'both passed through');
});

test('a member of an adult production: the same queue over the member routes, and an uploads-off Worker holds everything', async () => {
  const calls = [];
  const rec = { id: 'pid-1', takes: [], chosen: {}, uploads: true, parts: { [MOLLY]: { status: 'recording', user_id: 'me' } }, director: 'dee' };
  const api = { plays: {
    get: async () => rec,
    receiver: async () => ({ receiving: true, name: 'Dee' }),
    upload: async (pid, takeId, bytes, meta) => { calls.push(meta.lineID); rec.takes.push({ id: takeId }); return {}; },
  } };
  const { store, id } = await localWith({ pid: 'pid-1' }, ['L0003', 'L0006']);
  const t = fakeTimers();
  const watch = W.make({ api, store, me: () => 'me', timers: t, online: () => true });
  rec.uploads = false;
  await watch.kick(id);
  eq(calls, [], 'uploads off: nothing is sent');
  rec.uploads = true;
  await watch.kick(id);
  eq(calls, ['L0003', 'L0006'], 'sent to the director');
  eq(watch.takeState(id, 'T-L0003').name, 'Dee', 'names the director');
});

test('a credited maker blocks Publish and is listed; the director\'s own agreement does not stand in for them', () => {
  const rec = { director: 'dee', archive: null,
    members: [{ user_id: 'dee', display_name: 'Dee', director: true, performer: false, consented: true }],
    credits: [{ name: 'Ann', lines: 2, consented: false }] };
  eq(S.performers(rec).map(m => [m.display_name, m.consented]), [['Ann', false]], 'Ann is listed, not agreed');
  eq(S.waitingOn(rec).map(m => m.display_name), ['Ann'], 'Publish waits on Ann by name');
  eq(S.waitingOn({ ...rec, credits: [] }).length, 0, 'with no credited maker nothing waits');
  eq(S.line({ code: 'consent_missing' }), 'Not every performer has agreed to the consent.', 'the Worker\'s refusal reads the same');
});

/* ---- The free plan (2026-11-23 audit): what an open tab costs the shared Worker account ---- */

/** A clock that runs every job due in order, including jobs a job schedules, as time moves. */
function steppedClock() {
  let t = 0, id = 0;
  const jobs = new Map();
  const flush = async () => { for (let i = 0; i < 10; i++) await new Promise((r) => setImmediate(r)); };
  const add = (fn, ms, every) => { jobs.set(++id, { at: t + Math.max(0, ms || 0), fn, every }); return id; };
  return {
    now: () => t,
    setTimeout: (fn, ms) => add(fn, ms, 0),
    clearTimeout: (i) => jobs.delete(i),
    setInterval: (fn, ms) => add(fn, ms, ms),
    clearInterval: (i) => jobs.delete(i),
    async advance(ms) {
      const end = t + ms;
      for (;;) {
        await flush();
        let next = null;
        for (const [k, j] of jobs) if (!next || j.at < next[1].at) next = [k, j];
        if (!next || next[1].at > end) break;
        const [k, j] = next;
        t = j.at;
        if (j.every) j.at += j.every; else jobs.delete(k);
        await j.fn();
      }
      t = end;
      await flush();
    },
  };
}

function fakeDoc(state) {
  const fns = new Set();
  const doc = {
    visibilityState: state,
    get hidden() { return doc.visibilityState !== 'visible'; },
    addEventListener: (type, fn) => { if (type === 'visibilitychange') fns.add(fn); },
    removeEventListener: (type, fn) => fns.delete(fn),
    set(v) { doc.visibilityState = v; fns.forEach((f) => f()); },
  };
  return doc;
}

test('a receiver holds no pickup while its page is hidden, and stops after 30 idle minutes until asked again', async () => {
  const t = steppedClock();
  const doc = fakeDoc('hidden');
  let calls = 0, idle = 0;
  const inbox = () => { calls++; return new Promise((r) => t.setTimeout(() => r(null), 25000)); };
  const h = R.receive({ inbox, onTake: () => false, onIdle: () => { idle++; }, doc, timers: t, now: t.now });
  await t.advance(10 * 60 * 1000);
  eq(calls, 0, 'no pickup in 10 hidden minutes');
  doc.set('visible');
  await t.advance(1000);
  eq(calls, 1, 'visible again: it asks at once');
  await t.advance(31 * 60 * 1000);
  eq(idle, 1, 'thirty minutes with no take: it stops and says so once');
  ok(h.stopped(), 'stopped');
  const at = calls;
  ok(at <= 74, `pickups in those 30 minutes: ${at}`);
  await t.advance(10 * 60 * 1000);
  eq(calls, at, 'stopped means no more pickups');
});

test('a take resets the idle clock, and a page hidden mid-wait asks no more until it is back', async () => {
  const t = steppedClock();
  const doc = fakeDoc('visible');
  let calls = 0, idle = 0;
  const takes = [];
  const inbox = () => { calls++; return new Promise((r) => t.setTimeout(() => r(calls === 40 ? { take: { id: 'T1' } } : null), 25000)); };
  R.receive({ inbox, onTake: (got) => { takes.push(got.take.id); return false; }, onIdle: () => { idle++; }, doc, timers: t, now: t.now });
  await t.advance(31 * 60 * 1000);
  eq(takes, ['T1'], 'the take arrived');
  eq(idle, 0, 'a take at 16 minutes keeps it receiving past 30');
  doc.set('hidden');
  await t.advance(30000);
  const at = calls;
  await t.advance(20 * 60 * 1000);
  eq(calls, at, 'hidden: no pickup');
});

test('a watch with nothing to send asks the Worker at most twice in 10 minutes while hidden, and backs off while shown', async () => {
  for (const [state, most] of [['hidden', 2], ['visible', 3]]) {
    const w = stubWorker({ receiving: false });
    let pendings = 0;
    const seatHome = w.plays.seatHome;
    w.plays.seatHome = (...a) => { pendings++; return seatHome(...a); };
    const a = await localWith(seatLink, []);
    const t = steppedClock();
    const watch = W.make({ api: w, store: a.store, timers: t, online: () => true, doc: fakeDoc(state) });
    watch.start();
    await t.advance(10 * 60 * 1000);
    watch.stop();
    ok(pendings >= 1 && pendings <= most, `${state}: pending() asked ${pendings} times in 10 minutes (at most ${most})`);
  }
});

(async () => {
  for (const [name, fn] of results) {
    try { await fn(); } catch (e) { failures++; console.log(`FAIL ${name}: ${e.stack || e}`); }
  }
  console.log(`${passes} passed, ${failures} failed`);
  process.exit(failures ? 1 : 0);
})();
