/**
 * Own scripts shared (PLAYS-DESIGN §13 items 11 to 16; R4-5), run against the SHIPPED js/plays-share.js,
 * own-store.js, plays-store.js and api.js with a stub Worker that answers as worker/src/plays-own.js does:
 * the text sent once and as it was hashed, owed and tried again, a share undone when it can never pass,
 * the one resolver by every door and what it refuses to draw, the freeze and Edit a copy, the words.
 *   node js/own-share.test.js
 *
 * Broken controls: tools/own_mutants.mjs runs each rule's mutant against this suite and wants a failure.
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const dir = process.env.OWN_JS_DIR || __dirname;
const read = (f) => fs.readFileSync(path.join(dir, f), 'utf8');
for (const f of ['plays-core.js', 'plays-store.js', 'own-core.js', 'own-store.js', 'plays-share.js', 'api.js']) vm.runInThisContext(read(f), { filename: f });
const C = vm.runInThisContext('PlaysCore');
const O = vm.runInThisContext('OwnCore');
const S = vm.runInThisContext('PlaysShare');
const PlayStore = vm.runInThisContext('PlayStore');
const OwnScripts = vm.runInThisContext('OwnScripts');
const API = vm.runInThisContext('API');
console.error = () => {};

let passes = 0, failures = 0;
const results = [];
function ok(cond, name) { if (cond) passes++; else { failures++; console.log(`FAIL ${name}`); } }
const sorted = (v) => (Array.isArray(v) ? v.map(sorted) : v && typeof v === 'object' ? Object.fromEntries(Object.keys(v).sort().map(k => [k, sorted(v[k])])) : v);
function eq(a, b, name) {
  const pass = JSON.stringify(sorted(a)) === JSON.stringify(sorted(b));
  ok(pass, pass ? name : `${name}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`);
}
async function refused(p, code, name) {
  try { await p; ok(false, `${name}: resolved`); } catch (e) { eq(e && e.code, code, name); return e; }
  return null;
}
const test = (name, fn) => results.push([name, fn]);

const TEXT = 'ANNA: Who is there? Déjà vu.\nBEN: Only me.\n\nSomebody knocks.\n\nANNA: Come in.\nSOUND: DOOR CLOSES\nBEN: Thank you.\n';
const problem = (status, code, detail) => Object.assign(new Error(code), { status, code, detail, kind: status === 503 ? 'not_configured' : 'error' });
const offline = () => Object.assign(new Error('offline'), { kind: 'offline' });

/** The Worker's own-script half, over bytes, as worker/src/plays-own.js judges them. */
function worker() {
  const W = { rows: new Map(), calls: [], fail: {}, n: 0 };
  const row = (pid) => W.rows.get(pid);
  const failing = (name) => { const f = (W.fail[name] || []).shift(); if (f) throw f; };
  const make = (body) => {
    failing('create');
    W.calls.push(['create', body]);
    const pid = `P${++W.n}`;
    W.rows.set(pid, { body, bytes: null, title: body.title, held: false });
    return { id: pid, scriptID: body.script_id, scriptRevision: body.script_revision, director: 'me', takes: [], chosen: {}, publishable: false, own_script: { state: 'owed', by: 'me', episode_id: body.episode_id || null },
             parts: Object.fromEntries(body.cast.map(l => [l.part, { status: 'open' }])) };
  };
  const send = (pid) => {
    const r = row(pid);
    if (!r) throw problem(404, 'not_found');
    if (r.held) throw problem(410, 'script_removed');
    if (!r.bytes) throw problem(404, 'no_script');
    return { bytes: r.bytes.buffer.slice(0), meta: { id: r.body.script_id, revision: r.body.script_revision, title: r.title, episode_id: r.body.episode_id || null } };
  };
  W.api = {
    create: async (body) => { const rec = make(body); if (W.lose) { W.lose = false; throw offline(); } return rec; },
    list: async () => ({ productions: [...W.rows].map(([id, r]) => ({ id, title: r.title, script_id: r.body.script_id, director: r.director || 'me', updated_at: r.at || 0 })) }),
    get: async (pid) => {
      W.calls.push(['get', pid]);
      const r = row(pid);
      if (!r) throw problem(404, 'not_found');
      return { id: pid, scriptID: r.body.script_id, scriptRevision: r.body.script_revision, own_script: r.body.own ? { state: r.bytes ? 'kept' : 'owed', by: r.director || 'me' } : undefined };
    },
    classProduction: async (id, body) => make(body),
    putScript: async (pid, text) => {
      W.calls.push(['put', pid]);
      failing('put');
      const r = row(pid);
      if (r.bytes) throw problem(409, 'already_there');
      const bytes = new TextEncoder().encode(text);
      const d = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
      if ([...d.subarray(0, 6)].map(b => b.toString(16).padStart(2, '0')).join('') !== r.body.script_revision) throw problem(422, 'revision_mismatch');
      r.bytes = bytes;
    },
    deleteProduction: async (pid) => { W.calls.push(['delete', pid]); W.rows.delete(pid); },
    script: async (pid) => { W.calls.push(['member', pid]); return send(pid); },
    inviteScript: async (token) => { W.calls.push(['invite', token]); return send(token.split(':')[1]); },
    seatScript: async (key, pid) => { W.calls.push(['seat', key, pid]); return send(pid); },
  };
  W.app = { plays: W.api, read: { script: async (code, key) => { W.calls.push(['room', code, key]); return send(code); } }, shareLink: API.shareLink,
            playScript: async () => { W.calls.push(['library']); return null; }, castableScripts: async () => [] };
  W.count = (name) => W.calls.filter(c => c[0] === name).length;
  return W;
}
async function device() {
  const plays = PlayStore.open(PlayStore.memoryBackend());
  await plays.load();
  let clock = 1000;
  const own = OwnScripts.open({ backend: PlayStore.memoryBackend(), plays: async () => plays, now: () => (clock += 1) });
  return { plays, own };
}
async function made(d, title = 'A Little Play', text = TEXT) {
  const rec = await d.own.create({ title, text });
  rec.doc = O.done(rec.doc);
  rec.done = true;
  await d.own.keep(rec);
  return d.own.script(rec.id);
}
async function shared(W, d, script = null) {
  const s = script || await made(d);
  const local = await d.plays.create(s);
  const rec = await S.share({ api: W.api, store: d.plays, local, script: s, scripts: d.own });
  return { script: s, local, rec };
}
/** A second person's resolver call: no production here, no script here. */
const ask = (W, rec, who, extra = {}) => { S.forgetFetched(); return S.scriptOf({ api: W.app, id: rec.scriptID, revision: rec.scriptRevision, who, scripts: null, ...extra }); };

/* ---- Sharing ---- */

test('Share makes an own production with the cast sheet and title, then sends the lines as they were hashed, once', async () => {
  const W = worker(), d = await device();
  const { script, rec, local } = await shared(W, d);
  const body = W.calls[0][1];
  eq([body.own, body.title, body.script_id, body.script_revision], [true, 'A Little Play', script.id, script.revision], 'the body');
  eq(body.cast, S.castSheet(script), 'every line in order');
  eq('episode_id' in body, false, 'no episode for a script that was pasted');
  eq(new TextDecoder().decode(W.rows.get(rec.id).bytes), O.canonicalLines(script.lines), 'the canonical lines');
  eq(W.count('put'), 1, 'once');
  eq([rec.unsent, d.plays.share(local.id)], [undefined, { pid: rec.id }], 'shared, and linked here');
  eq(S.makeBody({ id: 'gut-1', revision: 'r', title: 'T', lines: [] }), { script_id: 'gut-1', script_revision: 'r', cast: [] }, 'a catalog play sends no text and no title');
  const ear = { ...script, episode: 'ep-1' };
  eq(S.makeBody(ear).episode_id, 'ep-1', 'a cast transcript names its episode, so a take-down finds it');
});

test('a text already there is the same text: success', async () => {
  const W = worker(), d = await device();
  W.fail.put = [problem(409, 'already_there')];
  const { rec } = await shared(W, d);
  eq(rec.unsent, undefined, '409 already_there');
});

test('a sending that may pass later leaves it owed, and Try again sends it', async () => {
  for (const e of [offline(), problem(503, 'scripts_full'), problem(429, 'rate_limited'), problem(401, 'unauthorized'), Object.assign(new Error('reset'), { kind: 'error' })]) {
    const W = worker(), d = await device();
    W.fail.put = [e];
    const { rec, local, script } = await shared(W, d);
    eq(rec.unsent, e, `owed after ${e.code || e.kind}`);
    eq([W.count('delete'), d.plays.share(local.id)], [0, { pid: rec.id }], 'the share stands');
    eq(await d.own.frozen(script.id), true, 'and what is owed is what will be sent');
    eq(await S.sendOrUndo({ api: W.api, pid: rec.id, script, scripts: d.own }), null, 'sent by Try again');
    ok(W.rows.get(rec.id).bytes, 'there');
  }
});

test('a sending that can never pass undoes the share, on the Worker and here', async () => {
  for (const [status, code] of [[413, 'script_too_long'], [422, 'revision_mismatch'], [410, 'script_removed'], [400, 'bad_request']]) {
    const W = worker(), d = await device();
    W.fail.put = [problem(status, code)];
    const s = await made(d);
    const local = await d.plays.create(s);
    await refused(S.share({ api: W.api, store: d.plays, local, script: s, scripts: d.own }), code, code);
    eq([W.count('delete'), W.rows.size, d.plays.share(local.id)], [1, 0, null], 'nothing is left shared');
    eq(await d.plays.backend.get(`${local.id}/share.json`), null, 'on disk too');
    eq(await d.own.frozen(s.id), false, 'and nothing is frozen');
  }
  const W = worker(), d = await device();
  W.fail.create = [problem(422, 'bad_name', 'title')];
  const s = await made(d), local = await d.plays.create(s);
  await refused(S.share({ api: W.api, store: d.plays, local, script: s, scripts: d.own }), 'bad_name', 'a title the filter refuses');
  eq([W.count('put'), d.plays.share(local.id)], [0, null], 'no text was sent');
});

test('a share whose creation answer was lost is adopted when it can be, else left; asked once a page, never polled', async () => {
  const lost = async (W, d, title) => {
    const s = await made(d, title), local = await d.plays.create(s);
    W.lose = true;
    await refused(S.share({ api: W.api, store: d.plays, local, script: s, scripts: d.own }), undefined, 'the answer is lost').catch(() => {});
    return { s, local };
  };
  const run = async (W, d, checked = new Set()) => {
    const remote = (await W.api.list()).productions;
    return S.reconcileOwed({ api: W.api, store: d.plays, remote, me: 'me', scripts: d.own, checked });
  };
  // Adopt: one unshared production of that script here.
  let W = worker(), d = await device();
  let { s, local } = await lost(W, d, 'Lost One');
  eq([W.rows.size, d.plays.share(local.id)], [1, null], 'the Worker holds it and this device has no link');
  const checked = new Set();
  eq(await run(W, d, checked), true, 'reconciled');
  eq([d.plays.share(local.id), W.count('put'), W.rows.get('P1').bytes !== null], [{ pid: 'P1' }, 1, true], 'linked, and the text sent');
  eq([await run(W, d, checked), W.count('get')], [false, 1], 'asked once a page: the second pass asks nothing');
  eq(await run(W, d), false, 'a linked production is not fetched again');
  // With nothing here it is left, however old: another device may still owe the text. A catalog row, another person's row: never fetched.
  W = worker(); d = await device();
  await lost(W, d, 'Old');
  for (const p of [...d.plays.productions]) await d.plays.delete(p.id);
  W.rows.get('P1').at = 0;
  W.rows.set('P3', { body: { script_id: 'gut-1', script_revision: 'r', cast: [] }, bytes: null, title: 'Catalog' });
  W.rows.set('P4', { body: { script_id: 'own-x', script_revision: 'r', cast: [], own: true }, bytes: null, title: 'Theirs', director: 'you' });
  const page = new Set();
  eq(await run(W, d, page), false, 'nothing changed');
  eq(await run(W, d, page), false, 'the same page asks about it once');
  eq([...W.rows.keys()], ['P1', 'P3', 'P4'], 'nothing is deleted');
  eq(W.calls.filter(c => c[0] === 'get').map(c => c[1]), ['P1'], 'only this person\'s own rows are fetched');
  // A refusal that can never pass undoes the adopted share, here and there.
  W = worker(); d = await device();
  ({ s, local } = await lost(W, d, 'Never'));
  W.fail.put = [problem(413, 'script_too_long')];
  await run(W, d);
  eq([W.rows.size, d.plays.share(local.id)], [0, null], 'nothing left shared');
});

test('a disk that will not keep the freeze does not lose the share', async () => {
  const W = worker(), d = await device();
  const s = await made(d), local = await d.plays.create(s);
  const full = { freeze: async () => { throw new Error('full'); }, script: async () => null };
  const rec = await S.share({ api: W.api, store: d.plays, local, script: s, scripts: full });
  eq([rec.unsent, d.plays.share(local.id)], [undefined, { pid: rec.id }], 'shared');
});

/* ---- The one resolver ---- */

test('each door asks its own route, and what arrives is the script', async () => {
  const W = worker(), d = await device();
  const { script, rec } = await shared(W, d);
  for (const [who, call] of [[{ pid: rec.id }, ['member', rec.id]], [{ token: `t:${rec.id}`, pid: rec.id }, ['invite', `t:${rec.id}`]],
    [{ seat: 'key', pid: rec.id }, ['seat', 'key', rec.id]], [{ room: rec.id, key: 'mk', pid: rec.id }, ['room', rec.id, 'mk']]]) {
    const got = await ask(W, rec, who);
    eq(W.calls[W.calls.length - 1], call, `${call[0]} route`);
    eq(got.lines, script.lines, 'the lines');
    eq([got.id, got.revision, got.kind, got.title, got.rights.bucket], [script.id, script.revision, 'own', 'A Little Play', 'own'], 'the castable shape');
    eq(O.refusalOf(got), null, 'the core keeps it');
    eq(C.castParts(got).map(p => p.id), C.castParts(script).map(p => p.id), 'and casts it');
    eq(got.roles, script.roles, 'the roles are counted here');
  }
  eq(W.count('library'), 0, 'no own id is asked of the library');
});

test('what is here comes first: the production\'s copy, then the device\'s script at that revision', async () => {
  const W = worker(), d = await device();
  const { script, rec } = await shared(W, d);
  const before = W.calls.length;
  S.forgetFetched();
  const copy = await S.scriptOf({ api: W.app, store: d.plays, scripts: null, id: rec.scriptID, revision: rec.scriptRevision, who: { pid: rec.id } });
  eq(copy.lines, script.lines, 'the production\'s');
  const mine = await S.scriptOf({ api: W.app, scripts: d.own, id: rec.scriptID, revision: rec.scriptRevision, who: { pid: rec.id } });
  eq(mine.source.name, 'Added by you', 'the device\'s');
  eq(W.calls.length, before, 'nothing was asked');
  await refused(S.scriptOf({ api: W.app, store: d.plays, scripts: d.own, id: rec.scriptID, revision: '000000000000', who: { pid: rec.id } }), 'script_damaged', 'another revision is not what is here');
});

test('a script is fetched once a page', async () => {
  const W = worker(), d = await device();
  const { rec } = await shared(W, d);
  await ask(W, rec, { pid: rec.id });
  await S.scriptOf({ api: W.app, id: rec.scriptID, revision: rec.scriptRevision, who: { pid: rec.id }, scripts: null });
  eq(W.count('member'), 1, 'once');
});

test('what did not arrive whole is never drawn', async () => {
  const W = worker(), d = await device();
  const { script, rec } = await shared(W, d);
  const bytes = W.rows.get(rec.id).bytes;
  const text = new TextDecoder().decode(bytes);
  const serve = async (t, over = {}, revision = null) => {
    const b = typeof t === 'string' ? new TextEncoder().encode(t) : t;
    const dig = new Uint8Array(await crypto.subtle.digest('SHA-256', b));
    const rev = revision || [...dig.subarray(0, 6)].map(x => x.toString(16).padStart(2, '0')).join('');
    const app = { ...W.app, plays: { ...W.api, script: async () => ({ bytes: b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength), meta: over === null ? null : { id: script.id, revision: rev, title: 'T', episode_id: null, ...over } }) } };
    S.forgetFetched();
    return S.scriptOf({ api: app, id: script.id, revision: rev, who: { pid: rec.id }, scripts: null });
  };
  ok(await serve(text), 'control: the text itself is');
  await refused(serve(text.slice(0, -1), {}, script.revision), 'script_damaged', 'cut short');
  await refused(serve(text.replace('Come in', 'Come on'), {}, script.revision), 'script_damaged', 'one word changed');
  await refused(serve(JSON.stringify(script.lines, null, 1)), 'script_damaged', 'not canonical');
  await refused(serve('{"lines":[]}'), 'script_damaged', 'not lines');
  await refused(serve('not json'), 'script_damaged', 'not JSON');
  await refused(serve(new Uint8Array([0x5b, 0xff, 0x5d])), 'script_damaged', 'not UTF-8');
  await refused(serve('﻿' + text), 'script_damaged', 'a byte order mark');
  await refused(serve(O.canonicalLines(script.lines.map(l => ({ ...l, kind: 'song' })))), 'script_damaged', 'a kind no core knows');
  await refused(serve(O.canonicalLines([...script.lines, script.lines[0]])), 'script_damaged', 'a line id twice');
  await refused(serve(text, null), 'script_damaged', 'no x-script');
  await refused(serve(text, { id: 'own-00000000-0000-4000-8000-000000000000' }), 'script_damaged', 'another script\'s name');
  await refused(serve(text, { revision: '000000000000' }), 'script_damaged', 'another revision\'s name');
  await refused(serve(text, { title: '' }), 'script_damaged', 'no title');
});

test('the lines match the cast sheet, as each door knows it', async () => {
  const W = worker(), d = await device();
  const { script, rec } = await shared(W, d);
  const parts = C.castParts(script).map(p => ({ id: p.id, lineCount: p.lineCount }));
  const inv = (ps) => S.fits.invite({ parts: ps });
  const at = (fit) => ask(W, rec, { pid: rec.id }, { fit });
  ok(await at(inv(parts)), 'control: the invite\'s own parts');
  await refused(at(inv(parts.slice(1))), 'script_damaged', 'a part the sheet does not have');
  await refused(at(inv([...parts, { id: 'role:ZED', lineCount: 1 }])), 'script_damaged', 'a part the lines do not have');
  await refused(at(inv(parts.map((p, i) => (i ? p : { ...p, lineCount: p.lineCount + 1 })))), 'script_damaged', 'a part with other lines');
  ok(await at(S.fits.record(rec)), 'control: the record\'s parts');
  await refused(at(S.fits.record({ ...rec, parts: { 'role:ANNA': {} } })), 'script_damaged', 'a record of other parts');
  await refused(at(S.fits.record({ ...rec, takes: [{ lineID: 'L9999' }] })), 'script_damaged', 'a take of a line it does not have');
  ok(await at(S.fits.room({ cursor: 'L0001', claims: { 'role:BEN': 'm1' } })), 'control: the room\'s cursor and claims');
  await refused(at(S.fits.room({ cursor: 'L9999', claims: {} })), 'script_damaged', 'a cursor on no line');
  await refused(at(S.fits.room({ cursor: 'L0001', claims: { 'role:ZED': 'm1' } })), 'script_damaged', 'a claim of no part');
  ok(await at(S.fits.seat({ assignments: [{ part: 'role:ANNA', from: 'L0001', to: null }] })), 'control: the seat\'s casting');
  await refused(at(S.fits.seat({ assignments: [{ part: 'role:ZED' }] })), 'script_damaged', 'cast to no part');
  await refused(at(S.fits.seat({ assignments: [{ part: 'role:ANNA', from: 'L9999' }] })), 'script_damaged', 'cast from no line');
});

test('the Worker\'s refusals pass through by their codes', async () => {
  const W = worker(), d = await device();
  const { rec } = await shared(W, d);
  W.rows.get(rec.id).held = true;
  await refused(ask(W, rec, { pid: rec.id }), 'script_removed', 'removed');
  W.rows.get(rec.id).held = false;
  W.rows.get(rec.id).bytes = null;
  await refused(ask(W, rec, { pid: rec.id }), 'no_script', 'owed');
});

test('a cast transcript keeps its source: the episode, linked', async () => {
  const W = worker(), d = await device();
  const s = await made(d);
  const { rec } = await shared(W, d, { ...s, episode: 'ep-9' });
  const got = await ask(W, rec, { pid: rec.id });
  eq([got.episode, got.source], ['ep-9', { name: 'Automatic transcript', url: 'https://eardrama.org/episode/ep-9' }], 'its source');
});

test('a catalog play is the library\'s at the recorded revision, else the bundle\'s, else a refusal', async () => {
  const lib = { id: 'gut-1', revision: 'b', lines: [] }, old = { id: 'gut-1', revision: 'a', lines: [] };
  const app = { playScript: async () => lib, castableScripts: async () => [old] };
  const at = (revision, more = {}) => S.scriptOf({ api: app, id: 'gut-1', revision, ...more });
  eq(await at('b'), lib, 'the library\'s');
  eq(await at('a'), old, 'the bundle\'s');
  await refused(at('c'), 'revision_mismatch', 'neither');
  eq(await at('c', { anyRevision: true }), lib, 'a class page draws what the library has now');
  // A production whose play's revision moved on (547 scripts changed 2026-11-24): its own copy is the text, at every door that knows the production.
  const d = await device();
  const was = { id: 'gut-1', revision: 'a0', kind: 'radio', title: 'Old', authors: [], roles: [], lines: [{ id: 'L0001', kind: 'speech', role: 'ANN', text: 'Hello.' }] };
  const mine = await d.plays.create(was);
  await d.plays.setShare(mine.id, { pid: 'PX' });
  eq(await at('a0', { store: d.plays, who: { pid: 'PX' } }), was, 'the production\'s copy at its recorded revision');
  eq(await at('a0', { store: d.plays, who: { pid: 'PX' }, anyRevision: true }), was, 'and on a class page, before the library\'s current text');
  await refused(at('a0', { store: d.plays, who: { pid: 'PY' } }), 'revision_mismatch', 'a person with no copy of it has only the library, which no longer holds it');
  await refused(at('a0', { store: d.plays }), 'revision_mismatch', 'and no production named, none');
  await refused(S.scriptOf({ api: { playScript: async () => null, castableScripts: async () => [] }, id: 'gut-1', revision: 'b', anyRevision: true }), 'revision_mismatch', 'and nothing is never drawn');
});

test('a person who joins keeps the script in their production, and reads it with no Worker', async () => {
  const W = worker(), d = await device(), other = await device();
  const { script, rec } = await shared(W, d);
  const got = await ask(W, rec, { token: `t:${rec.id}`, pid: rec.id });
  const local = await S.localFor(other.plays, rec.id, got);
  const kept = await other.plays.script(local);
  eq([kept.lines, local.scriptID, local.scriptRevision], [script.lines, script.id, script.revision], 'kept whole');
  W.rows.clear();
  S.forgetFetched();
  const again = await S.scriptOf({ api: W.app, store: other.plays, scripts: other.own, id: rec.scriptID, revision: rec.scriptRevision, who: { pid: rec.id } });
  eq(again.lines, script.lines, 'read from the production');
  eq((await other.own.list()).length, 0, 'and it is not one of their own scripts');
});

/* ---- Frozen, and Edit a copy ---- */

test('sharing freezes the script; a change made before reached its productions, none after can', async () => {
  const W = worker(), d = await device();
  const { script, local } = await shared(W, d);
  eq(await d.own.frozen(script.id), true, 'frozen');
  const at = (await d.own.get(script.id)).shared;
  await d.own.freeze(script.id);
  eq((await d.own.get(script.id)).shared, at, 'once');
  eq((await d.own.script(script.id)).revision, script.revision, 'the same text');
  await d.own.freeze('own-00000000-0000-4000-8000-000000000000');
  eq((await d.own.list()).length, 1, 'a script that is not here is not made');
  const row = (await d.own.exportRows())[0];
  ok(/^\d{4}-/.test(row.shared), 'Export my data says when it was shared');
  eq(d.plays.share(local.id).pid, 'P1', 'shared');
  const open = await d.own.get(script.id);
  delete open.shared;
  open.doc = O.apply(open.doc, { op: 'words', line: open.doc.lines[0].k, text: 'Changed elsewhere.' }).doc;
  let kept = null;
  try { await d.own.keep(open); } catch (e) { kept = e.kind; }
  eq([kept, (await d.own.script(script.id)).revision, await d.own.frozen(script.id)], ['shared', script.revision, true], 'a page that opened it before may not write over it');
  const unshared = await made(d, 'Another');
  eq('shared' in (await d.own.exportRows()).find(r => r.id === unshared.id), false, 'and nothing for one that was not');
});

test('Edit a copy: a new script of the same text, with its own id, no takes, not frozen, its lines\' ids kept', async () => {
  const W = worker(), d = await device();
  const { script } = await shared(W, d);
  const rec = await d.own.copy(script);
  const copy = await d.own.script(rec.id);
  ok(rec.id !== script.id && O.OWN_ID.test(rec.id), 'a new id');
  eq([copy.lines, copy.revision, copy.title, rec.shared, rec.done], [script.lines, script.revision, 'A Little Play (copy)', undefined, true], 'the same words');
  eq(await d.own.frozen(rec.id), false, 'it can be changed');
  eq((await d.own.get(script.id)).shared > 0, true, 'and the first is still frozen');
  const r = O.apply(rec.doc, { op: 'words', line: rec.doc.lines[0].k, text: 'Other words.' });
  rec.doc = r.doc;
  await d.own.keep(rec);
  ok((await d.own.script(rec.id)).revision !== script.revision, 'its own text now');
  eq((await d.own.script(script.id)).revision, script.revision, 'the first unchanged');
  eq((await d.own.copy({ ...script, title: 'x'.repeat(O.MAX_TITLE) })).title.length, O.MAX_TITLE, 'a long title stays inside the cap');
});

test('Edit a copy on a device without the script: from the production\'s text', async () => {
  const W = worker(), d = await device(), other = await device();
  const { script, rec } = await shared(W, d, { ...(await made(d)), episode: 'ep-9', source: { name: 'Automatic transcript', url: 'u' } });
  const got = await ask(W, rec, { pid: rec.id });
  const made2 = await other.own.copy(got);
  const copy = await other.own.script(made2.id);
  eq([copy.lines, copy.episode, copy.source.name], [script.lines, 'ep-9', 'Automatic transcript'], 'the text, and its source');
});

test('a casting copied goes on where it was, and the episode finds the copy', async () => {
  const d = await device();
  const cues = [{ text: 'One here.', at: [0, 1000] }, { text: 'Two here.', at: [1000, 2000] }, { text: 'Three here.', at: [2000, 3000] }];
  const rec = d.own.begin({ title: 'An Episode', doc: O.fromCues(cues), episode: { id: 'ep-1', url: 'u' }, ear: { sig: 's', copy: 'c', place: 5 } });
  rec.doc = O.done(O.tap(rec.doc, 1, { role: 'Ann' }).doc, { keepOpen: true });
  rec.done = true;
  await d.own.keep(rec);
  await d.own.freeze(rec.id);
  const copy = await d.own.copy(await d.own.script(rec.id));
  eq([copy.ear, copy.episode.id, O.castCount(copy.doc)], [rec.ear, 'ep-1', { cast: 1, lines: 3 }], 'the marks, the times, the place');
  ok(copy.doc.lines.every(l => l.at), 'each line its times');
  eq((await d.own.ofEpisode(['ep-1'])).id, copy.id, 'the copy is the episode\'s casting now');
});

/* ---- What the record says ---- */

test('the text\'s state: held when the owner removed it, gone with the account that brought it, whose it is', () => {
  const of = (own_script) => S.ownState({ own_script }, 'me');
  eq(S.ownState({}, 'me'), null, 'a catalog play has none');
  eq(of({ state: 'kept', by: 'me' }), { state: 'kept', held: false, mine: true, by: 'me' }, 'kept, mine');
  eq(of({ state: 'kept', by: 'ann' }).mine, false, 'kept, hers');
  eq(of({ state: 'removed', by: 'ann' }).held, true, 'the owner\'s removal holds it');
  eq(of({ state: 'removed', by: null }).held, false, 'with its bringer\'s account, members go on');
});

test('Publish is absent where the record says so, with the reason', () => {
  const script = { lines: [{ id: 'L0001', kind: 'speech', role: 'A', parts: [{ say: 'x' }] }] };
  const rec = (over) => ({ scriptID: 'own-1', director: 'me', archive: null, parts: { 'role:A': { status: 'done', user_id: 'me' } }, chosen: { L0001: 't' },
    members: [{ user_id: 'me', performer: true }, { user_id: 'ann', performer: true }], ...over });
  eq(S.canPublish(rec({ publishable: false }), script, 'me'), false, 'an own script');
  eq(S.canPublish(rec({ publishable: true }), script, 'me'), true, 'control: a castable one');
  eq(S.canPublish(rec({}), script, 'me'), true, 'a record that does not say');
  eq(S.needsMyConsent(rec({ publishable: false }), script, 'ann'), false, 'no consent is asked for what is never published');
  eq(S.needsMyConsent(rec({ publishable: true }), script, 'ann'), true, 'control');
  eq(S.neverPublishes(rec({ publishable: false })), 'This script can’t be published.', 'its reason');
  eq(S.neverPublishes({ scriptID: 'grw-1', publishable: false }), 'This play cannot be published.', 'any other\'s');
  eq(S.neverPublishes(rec({ publishable: true })), null, 'none');
});

test('every refusal has its words', () => {
  const said = (code, detail, status) => S.line(problem(status || 422, code, detail));
  eq(said('bad_name', 'title'), 'The title is not allowed.', 'the title');
  eq(said('bad_name', 'role:ANNA'), 'The part name ANNA is not allowed.', 'the part');
  eq(said('bad_name'), 'That name is not allowed.', 'a person\'s name, as before');
  eq(said('too_many_scripts', 20), 'You have shared 20 scripts. Delete a production of one first.', 'the cap');
  for (const [code, words] of [['script_too_long', 'This script is too long to share.'], ['scripts_full', 'Sharing scripts is full.'], ['script_removed', 'This script was removed.'],
    ['script_reported', 'This script has been reported.'], ['script_damaged', 'This script did not arrive whole.'], ['no_script', 'This script has not been sent yet.']]) {
    eq(said(code), words, code);
    eq(S.scriptLine({ code }), words, `${code} on a screen with other words`);
  }
  eq(S.line(problem(503, 'scripts_full')), 'Sharing scripts is full.', 'a 503 with a code says the code\'s');
  eq(S.scriptLine({ code: 'room_full' }), '', 'a room\'s own refusal is the room\'s');
  // Each code the Worker can answer an own script with has words.
  const src = fs.readFileSync(path.join(__dirname, '..', 'worker', 'src', 'plays-own.js'), 'utf8');
  const codes = [...new Set([...src.matchAll(/(?:problem|refuse)\((\d+), "([a-z_]+)"/g)].map(m => m[2]))];
  ok(codes.length > 8, `${codes.length} codes read`);
  for (const code of codes.filter(c => !['bad_request', 'length_required', 'already_there'].includes(c))) ok(S.line(problem(422, code)) !== S.line(problem(422, 'nothing')), `${code} has no words`);
});

/* ---- The calls ---- */

test('the calls: the text as bytes, each read by its own key, and no list of shared scripts anywhere', async () => {
  const seen = [];
  const was = globalThis.fetch;
  let answer = () => new Response('[]', { headers: { 'x-script': '{"id":"i"}' } });
  globalThis.fetch = async (url, init) => { seen.push([init.method, url, init.headers || {}, init.body]); return answer(); };
  API.account._test.configure({ worker: 'https://worker.stub.dev' });
  try {
    const base = API.account.base();
    if (!base) { ok(false, 'a base for the stub'); return; }
    await API.plays.inviteScript('tok');
    await API.plays.seatScript('sk', 'P 1');
    const got = await API.read.script('ABC234', 'mk');
    eq(seen.map(s => [s[0], s[1].replace(base, '')]), [['GET', '/v1/plays/open/invite/script'], ['GET', '/v1/plays/seat/productions/P%201/script'], ['GET', '/v1/read/ABC234/script']], 'the routes');
    eq([seen[0][2]['x-invite'], seen[1][2]['x-seat-key'], seen[2][2]['x-read-key']], ['tok', 'sk', 'mk'], 'each with its key, none in the address');
    eq([got.meta, got.bytes.byteLength], [{ id: 'i' }, 2], 'the bytes and what x-script says');
    answer = () => new Response('[]');
    eq((await API.read.script('ABC234', 'mk')).meta, null, 'no x-script is none');
    answer = () => new Response(new Uint8Array([1]), { headers: { 'x-take': '{"id":"T"}' } });
    eq((await API.read.inbox('ABC234', 'mk')).take, { id: 'T' }, 'a take with its fields');
    answer = () => new Response(new Uint8Array([1]));
    let threw = null;
    try { await API.read.inbox('ABC234', 'mk'); } catch (e) { threw = e; }
    ok(threw, 'a take whose fields cannot be read is never answered as no take');
    answer = () => new Response(null, { status: 204 });
    eq(await API.read.inbox('ABC234', 'mk'), null, 'no take is none');
  } finally { globalThis.fetch = was; }
  const all = ['api.js', 'plays-share.js', 'plays-ui.js', 'class-ui.js', 'read-ui.js', 'parts-ui.js', 'own-ui.js', 'own-store.js', 'ear-ui.js', 'app.js'];
  eq(all.filter(f => /putScript\(/.test(read(f))), ['plays-share.js'], 'the text is sent from one place');
  eq(all.filter(f => /own: true/.test(read(f))), ['plays-share.js'], 'and an own production made in one');
  eq(all.filter(f => /\/scripts?['`?]/.test(read(f))), ['api.js'], 'no other file names a script route');
  eq((read('api.js').match(/\/script`|\/script'/g) || []).length, 5, 'one send and four reads: no list, no search');
  for (const f of ['plays-ui.js', 'class-ui.js', 'read-ui.js', 'parts-ui.js']) {
    ok(/scriptOf\(/.test(read(f)), `${f} asks the resolver`);
    ok(!/playScript\((rec|snap|prod|inv|p\.rec)\b/.test(read(f)), `${f} reads no production's script any other way`);
  }
});

(async () => {
  for (const [name, fn] of results) {
    const before = failures;
    try { await fn(); } catch (e) { failures++; console.log(`FAIL ${name}: threw ${e && e.stack}`); }
    if (failures === before) console.log(`  ok  ${name}`);
  }
  console.log(`${failures ? 'FAIL' : 'ok'}: ${passes} passed, ${failures} failed`);
  process.exit(failures ? 1 : 0);
})();
