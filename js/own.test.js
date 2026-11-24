/**
 * Own scripts on this device (PLAYS-DESIGN §13, WEB-DESIGN §4.21), run against the SHIPPED
 * js/own-store.js, plays-store.js, export.js and api.js: what is kept, the locks a take puts on a
 * line, a change reaching its productions, the version 1 to 2 migration, a full disk, export, Save as
 * text, and the one seam every reader of a script goes through. Nothing here touches a network.
 *   node js/own.test.js
 *
 * Broken controls (tools/own_mutants.mjs runs each against a mutated copy and wants a failure).
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const dir = process.env.OWN_JS_DIR || __dirname;
const ROOT = path.resolve(__dirname, '..');
const load = (f) => vm.runInThisContext(fs.readFileSync(path.join(dir, f), 'utf8'), { filename: f });
for (const f of ['plays-core.js', 'plays-store.js', 'own-core.js', 'own-store.js', 'api.js']) load(f);
vm.runInThisContext(fs.readFileSync(path.join(dir, 'export.js'), 'utf8').replace(/if \(typeof module[\s\S]*$/, ''), { filename: 'export.js' });
const C = vm.runInThisContext('PlaysCore');
const O = vm.runInThisContext('OwnCore');
const PlayStore = vm.runInThisContext('PlayStore');
const OwnScripts = vm.runInThisContext('OwnScripts');
const DataExport = vm.runInThisContext('DataExport');
const API = vm.runInThisContext('API');

let passes = 0, failures = 0;
const results = [];
function ok(cond, name) { if (cond) passes++; else { failures++; console.log(`FAIL ${name}`); } }
function eq(a, b, name) {
  const pass = JSON.stringify(a) === JSON.stringify(b);
  ok(pass, pass ? name : `${name}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`);
}
async function rejects(p, name, test = () => true) {
  try { await p; ok(false, `${name}: resolved`); } catch (e) { ok(test(e), `${name}: ${e && e.name} ${e && e.message}`); }
}
const test = (name, fn) => results.push([name, fn]);

const TEXT = `A LITTLE PLAY

ANNA: Who is there?
BEN: Only me.

Somebody knocks twice.

ANNA: Come in, then. (She opens the door.) Mind the step.
BEN: Thank you.
SOUND: DOOR CLOSES
ANNA: Sit down.
`;

async function fresh() {
  const plays = PlayStore.open(PlayStore.memoryBackend());
  await plays.load();
  const backend = PlayStore.memoryBackend();
  let clock = 1000;
  const own = OwnScripts.open({ backend, plays: async () => plays, now: () => (clock += 1) });
  return { plays, backend, own };
}
/** Adds TEXT and presses Done, as the parts page does. */
async function made(env, title = 'A Little Play') {
  const rec = await env.own.create({ title, text: TEXT });
  rec.doc = O.done(rec.doc);
  rec.done = true;
  await env.own.keep(rec);
  return rec;
}
const step = (rec, op, takes = []) => { const r = O.apply(rec.doc, op, { takes }); rec.doc = r.doc; return r.refusal; };
const speech = (rec, role, n = 0) => rec.doc.lines.filter(l => l.kind === 'speech' && l.role === role)[n];
async function record(env, script, lineID, created = C.now()) {
  const p = await env.plays.create(script);
  const line = script.lines.find(l => l.id === lineID);
  await env.plays.save(C.addTake(p, { id: C.uuid(), lineID, part: C.linePart(line), file: `${lineID}-x.wav`, created, frames: 10, sampleRate: 48000 }));
  return p.id;
}

test('a script is added with its parts proposed and no id given, and is not castable until Done', async () => {
  const env = await fresh();
  const rec = await env.own.create({ title: '  A Little Play  ', text: TEXT });
  ok(O.OWN_ID.test(rec.id), `an own id (${rec.id})`);
  eq(rec.title, 'A Little Play', 'the title as typed, trimmed');
  eq(rec.doc.lines.every(l => l.id === null), true, 'no line id before Done');
  eq(await env.own.script(rec.id), null, 'no castable script before Done');
  const [row] = await env.own.list();
  eq([row.title, row.parts, row.open, row.done], ['A Little Play', 2, 2, false], 'its row: two lines have no part');
  const back = await env.own.get(rec.id);
  eq(back.doc.lines, rec.doc.lines, 'the working copy reads back whole');
  eq(back.original, O.normalize(TEXT), 'and the text as pasted');
});

test('Done gives each line its id once and keeps the castable shape, sealed', async () => {
  const env = await fresh();
  const rec = await made(env);
  const s = await env.own.script(rec.id);
  eq(O.refusalOf(s), null, 'the core accepts it');
  eq([s.kind, s.rights.bucket, s.source.name, s.source.url], ['own', 'own', 'Added by you', ''], 'own, with no link and no evidence');
  eq(s.revision, await O.revisionOf(s.lines), 'the revision is its lines\'');
  eq(s.lines.map(l => l.id).slice(0, 3), ['L0001', 'L0002', 'L0003'], 'ids in order');
  eq(s.lines.filter(l => l.kind === 'direction').map(l => l.source), ['A LITTLE PLAY', 'Somebody knocks twice.'], 'a line with no part is a direction');
  eq(C.castParts(s).map(p => p.title), ['ANNA', 'BEN', 'Sound effects', 'Stage directions'], 'the recorder casts it');
  eq((await env.own.list())[0].done, true, 'its row says Done');
});

test('words given to a script whose lines cannot be one leave the last that could', async () => {
  const env = await fresh();
  const rec = await made(env);
  const before = await env.own.script(rec.id);
  eq(step(rec, { op: 'notPart', part: 'ANNA' }), null, 'ANNA is not a part');
  eq(step(rec, { op: 'notPart', part: 'BEN' }), null, 'nor BEN');
  eq(await env.own.keep(rec), 'no_parts', 'the refusal is the answer');
  eq(await env.own.script(rec.id), before, 'the castable script is the last one that could be cast');
  eq((await env.own.get(rec.id)).doc.lines.filter(l => l.kind === 'speech').length, 0, 'and the working copy has the change');
});

test('a full disk keeps nothing of a change and says why; the page still holds the work', async () => {
  const env = await fresh();
  const rec = await made(env);
  const files = new Map(env.backend.files);
  const put = env.backend.putAll;
  env.backend.putAll = async () => { const e = new Error('full'); e.name = 'QuotaExceededError'; throw e; };
  step(rec, { op: 'words', line: speech(rec, 'ANNA').k, text: 'Who goes there?' });
  await rejects(env.own.keep(rec), 'a full disk refuses', e => e.name === 'QuotaExceededError');
  eq([...env.backend.files], [...files], 'not one of the three files changed');
  env.backend.putAll = put;
  eq(await env.own.keep(rec), null, 'Try again keeps it');
  eq(O.textOf((await env.own.script(rec.id)).lines.find(l => l.role === 'ANNA').parts), 'Who goes there?', 'with the words typed');
  env.backend.putAll = async () => { throw new Error('x'); };
  await rejects(env.own.create({ title: 'T', text: TEXT }), 'Add a script refuses too');
});

test('two changes kept close together end as the second', async () => {
  const env = await fresh();
  const rec = await made(env);
  const slow = env.backend.putAll;
  let first = true;
  env.backend.putAll = async (e) => { if (first) { first = false; await new Promise(r => setTimeout(r, 30)); } return slow(e); };
  step(rec, { op: 'words', line: speech(rec, 'ANNA').k, text: 'One?' });
  const a = env.own.keep(rec);
  step(rec, { op: 'words', line: speech(rec, 'ANNA').k, text: 'Two?' });
  await Promise.all([a, env.own.keep(rec)]);
  eq((await env.own.get(rec.id)).doc.lines.find(l => l.role === 'ANNA').text, 'Two?', 'the later change stands');
});

test('a take fixes its line\'s part and boundaries in every production, chosen or not', async () => {
  const env = await fresh();
  const rec = await made(env);
  const s = await env.own.script(rec.id);
  const anna = s.lines.find(l => l.role === 'ANNA');
  await record(env, s, anna.id);
  await record(env, s, s.lines.filter(l => l.role === 'BEN')[1].id);
  const other = await made(env, 'Another');
  eq((await env.own.takes(rec.id)).sort(), [anna.id, s.lines.filter(l => l.role === 'BEN')[1].id].sort(), 'both productions\' takes lock');
  eq(await env.own.takes(other.id), [], 'another script\'s are free');
  const takes = await env.own.takes(rec.id);
  const k = speech(rec, 'ANNA').k;
  for (const op of [{ op: 'assign', line: k, to: { role: 'BEN' } }, { op: 'split', line: k, at: 4 }, { op: 'leaveOut', line: k }]) eq(step(rec, op, takes), 'line_has_take', `${op.op} is refused`);
  eq(step(rec, { op: 'rename', part: 'ANNA', to: 'ANN' }, takes), 'part_has_take', 'so is its part\'s name');
  eq(step(rec, { op: 'words', line: k, text: 'Who is it?' }, takes), null, 'its words may change');
  // A take another tab recorded: the plays store in this one has not seen it.
  const p = env.plays.productions[0];
  const rawPath = `${p.id}/production.json`;
  const raw = JSON.parse(await env.plays.backend.get(rawPath));
  raw.takes.push({ id: 'other-tab', lineID: s.lines.find(l => l.role === 'BEN').id, created: C.now() });
  await env.plays.backend.put(rawPath, JSON.stringify(raw));
  ok((await env.own.takes(rec.id)).includes(s.lines.find(l => l.role === 'BEN').id), 'a take from another tab locks its line');
});

test('a change reaches its productions: lines, revision, parts and title; takes stay; Words changed reads true only for an older take', async () => {
  const env = await fresh();
  const rec = await made(env);
  const s = await env.own.script(rec.id);
  const annaIDs = s.lines.filter(l => l.role === 'ANNA').map(l => l.id);
  const pid = await record(env, s, annaIDs[0], C.now() - 60);
  await env.plays.save({ ...env.plays.production(pid), listenedThrough: true, mixedFrom: 'x' });
  const old = env.plays.production(pid).takes[0];
  step(rec, { op: 'words', line: speech(rec, 'ANNA').k, text: 'Who goes there?' }, annaIDs.slice(0, 1));
  rec.title = 'Renamed';
  await env.own.keep(rec);
  let p = env.plays.production(pid);
  let ps = await env.plays.script(p);
  const now = await env.own.script(rec.id);
  eq([p.title, p.scriptRevision, ps.revision], ['Renamed', now.revision, now.revision], 'title and revision follow');
  ok(now.revision !== s.revision, 'and the revision is new');
  eq(O.textOf(ps.lines.find(l => l.id === annaIDs[0]).parts), 'Who goes there?', 'the production reads the new words');
  eq(p.takes.map(t => [t.id, t.lineID, t.file, t.created]), [[old.id, old.lineID, old.file, old.created]], 'the take stays');
  eq([p.listenedThrough, p.mixedFrom], [true, 'x'], 'words alone leave a finished play finished');
  ok(OwnScripts.wordsChanged(ps, old), 'the old take reads Words changed');
  ok(!OwnScripts.wordsChanged(ps, { ...old, created: C.now() + 60 }), 'a take of the new words does not');
  ok(!OwnScripts.wordsChanged(ps, { ...old, lineID: annaIDs[1] }), 'nor one on another line');
  // Punctuation alone is no change of words; changing back is none either.
  step(rec, { op: 'words', line: speech(rec, 'ANNA').k, text: 'Who is there.' }, annaIDs.slice(0, 1));
  await env.own.keep(rec);
  ok(!OwnScripts.wordsChanged(await env.own.script(rec.id), old), 'a changed comma is not changed words');
  // A part renamed and a line split: parts follow, and the play is no longer finished.
  eq(step(rec, { op: 'rename', part: 'BEN', to: 'BENJAMIN' }, annaIDs.slice(0, 1)), null, 'BEN has no take');
  const second = speech(rec, 'ANNA', 1);
  eq(step(rec, { op: 'split', line: second.k, at: 13 }, annaIDs.slice(0, 1)), null, 'a free line splits');
  await env.own.keep(rec);
  p = env.plays.production(pid);
  ps = await env.plays.script(p);
  eq(Object.keys(p.parts).filter(C.isSpeaking).sort(), ['role:ANNA', 'role:BENJAMIN'], 'the parts follow');
  ok(ps.lines.some(l => l.id === `${second.id}a`), 'the split line takes a letter');
  eq([p.listenedThrough, p.mixedFrom], [false, undefined], 'new lines make it unfinished');
  eq(p.takes.length, 1, 'and the take is still there');
  eq(JSON.parse(await env.plays.backend.get(`${pid}/production.json`)).scriptRevision, ps.revision, 'and it is kept, not only in memory');
});

test('a shared production keeps its own text', async () => {
  const env = await fresh();
  const rec = await made(env);
  const s = await env.own.script(rec.id);
  const pid = await record(env, s, s.lines.find(l => l.role === 'ANNA').id);
  await env.plays.setShare(pid, { pid: 'w1' });
  step(rec, { op: 'words', line: speech(rec, 'BEN').k, text: 'Nobody.' });
  await env.own.keep(rec);
  eq(env.plays.production(pid).scriptRevision, s.revision, 'frozen');
  eq((await env.plays.script(env.plays.production(pid))).revision, s.revision, 'its script too');
});

test('deleting a script leaves its productions their copy', async () => {
  const env = await fresh();
  const rec = await made(env);
  const s = await env.own.script(rec.id);
  const pid = await record(env, s, s.lines.find(l => l.role === 'ANNA').id);
  const keep = await made(env, 'Kept');
  eq((await env.own.productions(rec.id)).map(p => p.id), [pid], 'its production is known');
  await env.own.remove(rec.id);
  eq([await env.own.get(rec.id), await env.own.script(rec.id)], [null, null], 'the script is gone');
  eq((await env.own.list()).map(r => r.id), [keep.id], 'and only it');
  eq((await env.plays.script(env.plays.production(pid))).id, s.id, 'the production reads its own copy');
});

test('the text being added is kept, and goes when it is empty', async () => {
  const env = await fresh();
  eq(await env.own.draft(), null, 'none at first');
  await env.own.setDraft({ title: 'T', text: 'ANNA: Hello' });
  eq(await env.own.draft(), { title: 'T', text: 'ANNA: Hello' }, 'kept');
  eq(await env.own.list(), [], 'and it is no script');
  await env.own.setDraft({ title: '', text: '' });
  eq(await env.own.draft(), null, 'an empty one goes');
});

test('Export my data carries every own script, Done or not', async () => {
  const env = await fresh();
  const rec = await made(env);
  await env.own.create({ title: 'Not yet', text: TEXT });
  const rows = await env.own.exportRows();
  const empty = { history: () => [], follows: () => [], queue: () => [], position: () => null };
  const data = DataExport.build(empty, [], 0, [], rows);
  eq(data.scripts.map(s => [s.title, s.source, s.done]), [['Not yet', 'Added by you', false], ['A Little Play', 'Added by you', true]], 'both, the newest first');
  const s = data.scripts[1];
  eq([s.id, s.lines.length, s.lines[2].id], [rec.id, rec.doc.lines.length, 'L0003'], 'lines in the castable shape');
  ok(/^\d{4}-\d\d-\d\dT/.test(s.created), 'created, ISO');
  eq(data.scripts[0].lines.filter(l => l.kind === 'open').map(l => l.source), ['A LITTLE PLAY', 'Somebody knocks twice.'], 'a line with no part says so');
  eq(DataExport.build(empty, []).scripts, [], 'none is an empty list');
});

test('Save as text reads back as the same speeches', async () => {
  const env = await fresh();
  const rec = await made(env);
  const s = await env.own.script(rec.id);
  const text = OwnScripts.asText(s);
  ok(text.includes('\n\nANNA\nWho is there?\n\n'), 'a name in capitals over its words (Fountain)');
  const speeches = (lines) => lines.filter(l => l.kind === 'speech').map(l => [l.role, l.text !== undefined ? l.text : O.textOf(l.parts)]);
  eq(speeches(O.parse(text).lines), speeches(s.lines), 'and Add a script reads it back');
  eq(O.parse(text).lines.filter(l => l.kind === 'sound').map(l => l.text), ['SOUND: DOOR CLOSES'], 'a sound cue too');
  eq(OwnScripts.fileName('A/B: "C"?'), 'AB C.txt', 'a file name any system takes');
  eq(OwnScripts.fileName('///'), 'Script.txt', 'and one for a title of none');
});

test('a file is text or refused, counted before it is read', () => {
  const bytes = (...x) => new Uint8Array(x);
  const utf8 = (t) => new TextEncoder().encode(t);
  eq(OwnScripts.decode(utf8('ANNA: Café')), { text: 'ANNA: Café' }, 'UTF-8');
  eq(OwnScripts.decode(bytes(0xef, 0xbb, 0xbf, 0x41)).text, 'A', 'with its mark');
  eq(OwnScripts.decode(bytes(0xff, 0xfe, 0x41, 0, 0xe9, 0)).text, 'Aé', 'UTF-16, little end first');
  eq(OwnScripts.decode(bytes(0xfe, 0xff, 0, 0x41)).text, 'A', 'and big');
  eq(OwnScripts.decode(bytes(0x43, 0x61, 0x66, 0xe9, 0x92)).text, 'Café’', 'an old Windows file');
  for (const [b, what] of [[utf8('%PDF-1.4'), 'a PDF'], [utf8('{\\rtf1'), 'RTF'], [bytes(0x50, 0x4b, 3, 4, 0), '.docx'], [bytes(0x41, 0, 0x42), 'a binary'],
    [bytes(0xff, 0xd8, 0xff, 1, 2, 3, 4, 5), 'a picture']]) eq(OwnScripts.decode(b), { refusal: 'not_text' }, `${what} is refused`);
  eq(OwnScripts.decode(new Uint8Array(O.MAX_BYTES * 2 + 3)), { refusal: 'too_long' }, 'too many bytes, unread');
  eq(OwnScripts.decode(utf8('é'.repeat(O.MAX_BYTES / 2 + 1))), { refusal: 'too_long' }, 'too many once read');
  eq(OwnScripts.decode(utf8('a'.repeat(O.MAX_BYTES))).text.length, O.MAX_BYTES, 'the cap itself is allowed');
});

test('the nearest speakers of every line answer as the core does', () => {
  let seed = 7;
  const rnd = (n) => { seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) % n; };
  for (let round = 0; round < 200; round++) {
    const lines = Array.from({ length: 1 + rnd(30) }, (_, i) => {
      const r = rnd(10);
      return r < 4 ? { k: i + 1, kind: 'speech', role: 'ABCD'[rnd(1 + rnd(4))], text: 'x' } : r < 6 ? { k: i + 1, kind: 'direction', text: 'x' } : { k: i + 1, kind: 'open', role: null, text: 'x' };
    });
    const all = OwnScripts.nearestAll(lines);
    lines.forEach((l, i) => { if (l.kind === 'open') { const a = all.get(l.k), b = O.nearestParts(lines, i); if (JSON.stringify(a) !== JSON.stringify(b)) eq(a, b, `round ${round} line ${i}`); } });
  }
  ok(true, '200 scripts agree');
  const big = Array.from({ length: 6000 }, (_, i) => ({ k: i, kind: i === 0 ? 'speech' : 'open', role: i === 0 ? 'A' : null, text: 'x' }));
  const t = performance.now();
  OwnScripts.nearestAll(big);
  ok(performance.now() - t < 200, `6,000 lines in ${Math.round(performance.now() - t)} ms`);
});

/* ---- Version 1 to 2 ---- */

/** IndexedDB, as much of it as an upgrade needs: versions, versionchange, blocked, stores. */
function fakeIDB() {
  const dbs = new Map();
  const later = (fn) => setTimeout(fn, 0);
  const fake = {
    dbs,
    open(name, version) {
      const req = {};
      const go = () => {
        let d = dbs.get(name);
        if (!d) { d = { version: 0, stores: new Map(), open: new Set(), waiting: [] }; dbs.set(name, d); }
        if (version < d.version) { req.error = Object.assign(new Error('version'), { name: 'VersionError' }); req.onerror && req.onerror({}); return; }
        const finish = () => {
          const conn = {
            objectStoreNames: { contains: (s) => d.stores.has(s) },
            createObjectStore(s) { if (d.stores.has(s)) throw new Error('ConstraintError'); d.stores.set(s, new Map()); },
            close() { d.open.delete(conn); if (!d.open.size) d.waiting.splice(0).forEach(fn => later(fn)); },
            transaction(store, mode) {
              if (!d.open.has(conn)) throw Object.assign(new Error('closed'), { name: 'InvalidStateError' });
              if (!d.stores.has(store)) throw Object.assign(new Error('NotFoundError'), { name: 'NotFoundError' });
              const t = {};
              const map = d.stores.get(store);
              t.objectStore = () => ({
                put(v, k) { map.set(k, v); const r = {}; later(() => r.onsuccess && r.onsuccess()); return r; },
                get(k) { const r = {}; later(() => { r.result = map.get(k); r.onsuccess && r.onsuccess(); }); return r; },
              });
              later(() => later(() => t.oncomplete && t.oncomplete()));
              return t;
            },
          };
          d.open.add(conn);
          req.result = conn;
          if (version > d.version) { const from = d.version; d.version = version; req.onupgradeneeded && req.onupgradeneeded({ oldVersion: from }); }
          req.onsuccess && req.onsuccess({});
        };
        if (version > d.version && d.open.size) {
          for (const c of [...d.open]) if (c.onversionchange) c.onversionchange({});
          if (d.open.size) { req.onblocked && req.onblocked({}); d.waiting.push(finish); return; }
        }
        finish();
      };
      later(go);
      return req;
    },
  };
  return fake;
}
/** A page of the app as it was: version 1, one store, no versionchange handler. */
function oldPage(idb, name) {
  return new Promise((resolve) => {
    const r = idb.open(name, 1);
    r.onupgradeneeded = () => r.result.createObjectStore('files');
    r.onsuccess = () => resolve(r.result);
  });
}

test('version 1 becomes 2 with every production kept, and a new browser gets both stores', async () => {
  const idb = fakeIDB();
  const old = await oldPage(idb, 'm1');
  old.transaction('files', 'readwrite').objectStore('files').put('{"id":"p1"}', 'p1/production.json');
  old.close();
  const files = PlayStore.indexedDBBackend('m1', 'files', idb);
  const scripts = PlayStore.indexedDBBackend('m1', 'scripts', idb);
  eq(await files.get('p1/production.json'), '{"id":"p1"}', 'the production is where it was');
  await scripts.put('scripts/x/row.json', '1');
  eq(await scripts.get('scripts/x/row.json'), '1', 'the new store keeps');
  eq(await files.get('scripts/x/row.json'), null, 'apart from the plays');
  eq([idb.dbs.get('m1').version, idb.dbs.get('m1').open.size], [2, 1], 'version 2, over one connection');
  await PlayStore.indexedDBBackend('m2', 'files', idb).put('a', 1);
  eq([...idb.dbs.get('m2').stores.keys()], ['files', 'scripts'], 'a new browser gets both');
});

test('a tab on version 1 holds the new page out, with a reason, and lets it in when it closes', async () => {
  const idb = fakeIDB();
  const old = await oldPage(idb, 'm3');
  const scripts = PlayStore.indexedDBBackend('m3', 'scripts', idb);
  await rejects(scripts.get('x'), 'held out', e => e.kind === 'blocked');
  old.close();
  await new Promise(r => setTimeout(r, 10));
  eq(await scripts.get('x'), null, 'and in, at the next try');
  eq(idb.dbs.get('m3').open.size, 1, 'the refused connection was closed');
});

test('a page of this version gives way to a newer one', async () => {
  const idb = fakeIDB();
  const files = PlayStore.indexedDBBackend('m4', 'files', idb);
  await files.put('a', 1);
  let blocked = false;
  await new Promise((resolve) => {
    const r = idb.open('m4', 3);
    r.onblocked = () => { blocked = true; resolve(); };
    r.onsuccess = resolve;
  });
  eq(blocked, false, 'the newer page is never blocked by this one');
});

/* ---- The seam and the promise ---- */

test('API.playScript reads an own id from this device and never asks the network', async () => {
  const env = await fresh();
  const rec = await made(env);
  const was = OwnScripts.shared;
  vm.runInThisContext('OwnScripts').shared = () => env.own;
  let asked = 0;
  const get = async () => { asked += 1; return { plays: [], scripts: [] }; };
  eq((await API.playScript(rec.id, get)).title, 'A Little Play', 'the script');
  eq(await API.playScript('own-00000000-0000-0000-0000-000000000000', get), null, 'none by that id');
  eq(asked, 0, 'nothing fetched');
  await API.playScript('gut-1', get);
  ok(asked > 0, 'control: a catalog id is');
  vm.runInThisContext('OwnScripts').shared = was;
});

test('nothing leaves the device: no own-script file names the network, the Worker, or a sign-in', () => {
  const leaks = (src) => (src.replace(/\/\*[\s\S]*?\*\//g, '').match(/\bfetch\s*\(|XMLHttpRequest|sendBeacon|WebSocket|\bAPI\.(plays|account|read)\b|AccountUI|AgeGate/g) || []);
  for (const f of ['own-core.js', 'own-store.js', 'own-ui.js']) eq(leaks(fs.readFileSync(path.join(dir, f), 'utf8')), [], f);
  eq(leaks('API.plays.share(x); fetch (u)').length, 2, 'control: a call is caught');
  const ui = fs.readFileSync(path.join(dir, 'plays-ui.js'), 'utf8');
  ok(/isOwn\(script\) \? null : shareBox\(/.test(ui), 'no Share on a production of one');
  ok(/ReadUI !== 'undefined' && !isOwn\(script\)/.test(ui), 'no Read together on its page');
  ok(/script\.kind === 'own' \? 'Your script'/.test(ui), 'its kicker is its own');
  ok(/voices: \(\) => \{ const h = hifi\(\); return \[\.\.\.\(h && spoken/.test(fs.readFileSync(path.join(dir, 'cast-ui.js'), 'utf8')), 'no Kokoro voice offered');
  ok(/script\.kind !== 'own'\) return shared\.prepare/.test(fs.readFileSync(path.join(dir, 'kokoro-voice.js'), 'utf8')), 'no phonemes asked for');
});

test('a real play, pasted, is corrected, kept and read by the recorder\'s own core', async () => {
  const lib = JSON.parse(fs.readFileSync(path.join(ROOT, 'catalog/plays/castable-scripts.json'), 'utf8')).scripts;
  const play = lib.slice().sort((a, b) => b.lines.length - a.lines.length)[0];
  const env = await fresh();
  const rec = await env.own.create({ title: play.title, text: OwnScripts.asText(play) });
  ok(rec.doc.lines.length > 200, `${rec.doc.lines.length} lines of a real text`);
  rec.doc = O.done(rec.doc);
  rec.done = true;
  eq(await env.own.keep(rec), null, 'kept');
  const s = await env.own.script(rec.id);
  const p = await env.plays.create(s);
  ok(C.next(p, s) !== null, 'a part to record');
  ok(C.listenPlan(p, s).length > 0, 'and a listen-through');
  eq(C.speechLineIDs(s).length, s.lines.filter(l => l.kind === 'speech').length, 'every speech is castable');
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
