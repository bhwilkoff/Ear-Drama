/**
 * Plays phase 2 on the web (PLAYS-DESIGN §11.7, WEB-DESIGN §4.10a), run
 * against the SHIPPED js/plays-share.js with a stub Worker whose record
 * carries the fields worker/src/plays.js sends: the cast sheet the Worker
 * checks, the mirror of the Worker's claims, any open part claimable (C7),
 * the owner's uploads switch, the consent step before a first upload and
 * again on a new version, never uploading a flagged take, bringing other
 * members' takes home without losing this person's unsent choice or keeping
 * a hidden one, invite links in both shapes, and Library's merged rows.
 * Nothing here plays or records sound.
 *   node js/plays-share.test.js
 *
 * Broken controls, 2026-10-24, each against a mutated copy of js/plays-share.js:
 *   upload() without the uploadsOpen check: "uploads off" fails (the upload endpoint is called).
 *   upload() asking consent only when none is stored (`!link.consented`): "a new consent version" fails.
 *   pending() keeping flagged takes in `send`: "a flagged take is never uploaded" fails.
 *   mirror() keeping another person's claim as recording: "the mirror" fails.
 *   canClaim() allowing a claim while a part records: "any open part" fails.
 *   mergedChosen() starting from local.chosen: "a hidden take" fails (it would still play).
 *   inviteToken() without the 43-character check: "invite tokens" fails.
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

for (const f of ['plays-core.js', 'plays-store.js', 'plays-share.js']) {
  vm.runInThisContext(fs.readFileSync(path.join(__dirname, f), 'utf8'), { filename: f });
}
const C = vm.runInThisContext('PlaysCore');
const PlayStore = vm.runInThisContext('PlayStore');
const S = vm.runInThisContext('PlaysShare');

let passes = 0, failures = 0;
const results = [];
function ok(cond, name) { if (cond) passes++; else { failures++; console.log(`FAIL ${name}`); } }
function eq(a, b, name) {
  const pass = JSON.stringify(a) === JSON.stringify(b);
  ok(pass, pass ? name : `${name}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`);
}
const test = (name, fn) => results.push([name, fn]);

/* ---- Fixtures ---- */

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
  ];
  const roles = ['MOLLY', 'FIBBER', 'DOC'].map(name => ({ name, lines: lines.filter(l => l.role === name).length, words: 2 }));
  return { id: 'gut-0', revision: 'r1', kind: 'radio', title: 'Good Grammar', authors: [],
           source: { name: 'Fixture', url: 'https://example.org' },
           rights: { bucket: 'script_source_cleared', evidence: [] }, roles, lines };
}
const ME = 'user-me';
const THEM = 'user-them';
const MOLLY = 'role:MOLLY';
const FIBBER = 'role:FIBBER';

/** A record shaped like worker/src/plays.js recordFor(). */
function record(over = {}) {
  return {
    id: 'pid-1', scriptID: 'gut-0', scriptRevision: 'r1', title: 'Good Grammar', created: 0,
    parts: { [MOLLY]: { status: 'recording', performer: 'Me', user_id: ME }, [FIBBER]: { status: 'open' },
             'role:DOC': { status: 'open' }, sound: { status: 'open' }, directions: { status: 'open' } },
    takes: [], chosen: {}, roomTone: [], listenedThrough: false, director: ME,
    members: [{ user_id: ME, display_name: 'Me', director: true }], next: FIBBER, hidden_takes: 0,
    archive: null, uploads: true, server_time: 1, ...over,
  };
}

/** The stub Worker: records every call, answers like the real one. */
function stubApi({ consentVersion = 'v1', uploads = true, rec = record() } = {}) {
  const calls = [];
  const api = {
    calls, rec,
    consent: async () => { calls.push(['consent']); return { version: consentVersion, text: 'OWNER: words', uploads }; },
    agree: async (pid, version) => { calls.push(['agree', version]); return null; },
    upload: async (pid, takeId, bytes, meta) => {
      calls.push(['upload', takeId, meta]);
      api.rec = { ...api.rec, takes: [...api.rec.takes, { id: takeId, ...meta, user_id: ME }],
                  chosen: { ...api.rec.chosen, [meta.lineID]: takeId } };
      return {};
    },
    get: async () => { calls.push(['get']); return api.rec; },
    choose: async (pid, id) => { calls.push(['choose', id]); return api.rec; },
    audio: async (pid, takeId) => { calls.push(['audio', takeId]); return new Uint8Array([1, 2, 3, 4]).buffer; },
    create: async (body) => { calls.push(['create', body]); return { ...record(), id: 'pid-new' }; },
    joinByInvite: async (token, part, name) => { calls.push(['join', token, part, name]); return record({ id: 'pid-join' }); },
  };
  return api;
}

async function freshStore() {
  const store = PlayStore.open(PlayStore.memoryBackend());
  await store.load();
  return store;
}

/** A production on this browser, shared as pid-1, with takes for MOLLY's lines (one flagged on demand). */
async function sharedLocal({ flagL0006 = false } = {}) {
  const script = fixtureScript();
  const store = await freshStore();
  let p = await store.create(script);
  await store.setShare(p.id, { pid: 'pid-1' });
  for (const id of ['L0003', 'L0006']) {
    const file = await store.writeTake({ samples: new Float32Array(480), sampleRate: 48000 }, p, id);
    p = C.addTake(store.production(p.id), { id: `T-${id}`, lineID: id, part: MOLLY, file, created: 1, frames: 480,
                                            sampleRate: 48000, capture: 'direct', heard: {}, peak: 0.1,
                                            bleed: flagL0006 && id === 'L0006' });
    await store.save(p);
  }
  return { script, store, local: store.production(p.id) };
}

/* ---- Tests ---- */

test('the cast sheet is every line in script order, with linePart', () => {
  const script = fixtureScript();
  eq(S.castSheet(script).map(x => x.part), script.lines.map(l => C.linePart(l)), 'parts in script order');
  eq(S.castSheet(script).map(x => x.id), script.lines.map(l => l.id), 'ids in script order');
});

test('the mirror: only my live claim records here; another person\'s claim is open here', () => {
  const script = fixtureScript();
  const local = C.newProduction(script);
  const rec = record({ parts: { ...record().parts, [MOLLY]: { status: 'recording', user_id: THEM, performer: 'Pat' },
                                [FIBBER]: { status: 'done', user_id: THEM, performer: 'Pat' } } });
  const n = S.mirror(local, rec, ME);
  eq(n.parts[MOLLY], { status: 'open' }, 'their claim is open here');
  eq(n.parts[FIBBER], { status: 'done', performer: 'Pat' }, 'done carries the name');
  eq(S.mirror(local, record(), ME).parts[MOLLY], { status: 'recording', performer: 'Me' }, 'my claim records here');
});

test('any open part may be taken while none records (C7)', () => {
  const idle = record({ parts: { ...record().parts, [MOLLY]: { status: 'open' } } });
  ok(S.canClaim(idle, 'role:DOC'), 'a part that is not next is claimable');
  ok(S.canClaim(idle, FIBBER), 'next is claimable');
  ok(!S.canClaim(record(), 'role:DOC'), 'nothing is claimable while a part records');
  const done = record({ parts: { ...idle.parts, [FIBBER]: { status: 'done', user_id: THEM } } });
  ok(!S.canClaim(done, FIBBER), 'a finished part is not claimable');
});

test('uploads off: nothing is sent, and no consent is asked', async () => {
  const { script, store, local } = await sharedLocal();
  for (const [where, api, rec] of [
    ['record', stubApi(), record({ uploads: false })],
    ['consent', stubApi({ uploads: false }), record()],
  ]) {
    let asked = 0;
    const r = await S.upload({ api, store, local, script, rec, me: ME, agree: async () => { asked++; return true; } });
    eq(r.stopped, 'uploads_off', `stopped by the switch in the ${where}`);
    eq(api.calls.filter(c => c[0] === 'upload').length, 0, `no upload call (${where})`);
    eq(asked, 0, `no consent asked (${where})`);
  }
  ok(!S.uploadsOpen(record({ uploads: false })), 'uploadsOpen reads the switch');
  ok(S.uploadsOpen(record()), 'open when the store exists');
  eq(S.line({ code: 'storage_not_configured' }), 'Uploads are off.', 'the Worker\'s 503 reads the same');
});

test('consent before the first upload, at the Worker\'s version', async () => {
  const { script, store, local } = await sharedLocal();
  const api = stubApi();
  let shown = null;
  const r = await S.upload({ api, store, local, script, rec: record(), me: ME, agree: async (c) => { shown = c; return true; } });
  eq(shown && shown.text, 'OWNER: words', 'the Worker\'s words are shown as they arrive');
  eq(r.sent, 2, 'both takes sent');
  const order = api.calls.map(c => c[0]);
  ok(order.indexOf('agree') < order.indexOf('upload'), 'agreed before the first upload');
  eq(store.share(local.id).consented, 'v1', 'the version is kept beside the record');
});

test('declining the consent sends nothing', async () => {
  const { script, store, local } = await sharedLocal();
  const api = stubApi();
  const r = await S.upload({ api, store, local, script, rec: record(), me: ME, agree: async () => false });
  eq(r.stopped, 'consent', 'stopped at consent');
  eq(api.calls.filter(c => c[0] === 'upload' || c[0] === 'agree').length, 0, 'no agree, no upload');
});

test('a new consent version asks again', async () => {
  const { script, store, local } = await sharedLocal();
  await store.setShare(local.id, { pid: 'pid-1', consented: 'v1' });
  let asked = 0;
  await S.upload({ api: stubApi({ consentVersion: 'v1' }), store, local, script, rec: record(), me: ME,
                   agree: async () => { asked++; return true; } });
  eq(asked, 0, 'the same version does not ask');
  await store.setShare(local.id, { pid: 'pid-1', consented: 'v1' });
  await S.upload({ api: stubApi({ consentVersion: 'v2' }), store, local, script, rec: record(), me: ME,
                   agree: async () => { asked++; return true; } });
  eq(asked, 1, 'a new version asks');
});

test('a flagged take is never uploaded (§5), and an uploaded one is not sent twice', async () => {
  const { script, store, local } = await sharedLocal({ flagL0006: true });
  const api = stubApi();
  const r = await S.upload({ api, store, local, script, rec: record(), me: ME, agree: async () => true });
  eq(r.flagged, 1, 'one flagged');
  eq(api.calls.filter(c => c[0] === 'upload').map(c => c[2].lineID), ['L0003'], 'only the clean take');
  ok(api.calls.filter(c => c[0] === 'upload').every(c => c[2].bleed === false), 'no sent take claims bleed');
  const rec2 = record({ takes: [{ id: 'T-L0003' }], chosen: { L0003: 'T-L0003' } });
  eq(S.pending(local, script, rec2, ME).map(t => t.id), ['T-L0006'], 'the uploaded take is not pending');
  eq(S.pending(local, script, record({ parts: { ...record().parts, [MOLLY]: { status: 'done', user_id: ME } } }), ME), [],
     'nothing pending for a part I no longer hold');
});

test('bringing takes home: theirs arrive, my unsent choice stands, a hidden take never plays', async () => {
  const { script, store, local } = await sharedLocal();
  const theirs = { id: 'T-THEM', lineID: 'L0002', part: FIBBER, file: 'x.wav', created: 2, frames: 480, sampleRate: 48000,
                   capture: 'direct', heard: {}, loudness: -20, peak: 0.2, bleed: false, user_id: THEM };
  const rec = record({ takes: [theirs], chosen: { L0002: 'T-THEM' } });
  ok(!S.inStep(local, script, rec, ME), 'out of step before');
  const api = stubApi({ rec });
  const n = await S.bringHome({ api, store, localId: local.id, rec, script, me: ME });
  eq(n, 1, 'one take arrived');
  const after = store.production(local.id);
  eq(after.chosen.L0002, 'T-THEM', 'their take is chosen here');
  eq(after.chosen.L0003, 'T-L0003', 'my unsent choice stands');
  ok(S.inStep(after, script, rec, ME), 'in step after');
  eq(await store.readTake(local.id, 'm-T-THEM.wav') !== null, true, 'the audio is a file here');
  // They are blocked or reported: the Worker stops showing the take.
  const hidden = record({ takes: [], chosen: {}, hidden_takes: 1 });
  await S.bringHome({ api: stubApi({ rec: hidden }), store, localId: local.id, rec: hidden, script, me: ME });
  eq(store.production(local.id).chosen.L0002, undefined, 'a hidden take is no longer chosen here');
});

test('invite tokens: both link shapes, and nothing else', () => {
  const tok = 'A'.repeat(20) + '_-' + 'b'.repeat(21);
  eq(tok.length, 43, 'fixture length');
  eq(S.inviteLink(tok, 'https://eardrama.org/'), `https://eardrama.org/invite#${tok}`, 'the link shape');
  eq(S.inviteToken({ pathname: '/invite', hash: `#${tok}` }), tok, '/invite#token');
  eq(S.inviteToken({ pathname: '/', hash: `#invite=${tok}` }), tok, 'the forwarded #invite=token');
  eq(S.inviteToken({ pathname: '/', hash: `#${tok}` }), null, 'a bare hash elsewhere is not an invite');
  eq(S.inviteToken({ pathname: '/invite', hash: '#short' }), null, 'a short token is refused');
  eq(S.inviteToken({ pathname: '/invite', hash: `#${tok}<script>` }), null, 'junk is refused');
  eq(S.inviteToken({ pathname: '/', hash: '#invite=short' }), null, 'a short forwarded token is refused');
});

test('joining makes the production here once, from the bundle\'s script at its revision', async () => {
  const store = await freshStore();
  const script = fixtureScript();
  const api = stubApi();
  const a = await S.join({ api, store, token: 't', part: FIBBER, displayName: '  Pat ', script });
  eq(api.calls[0], ['join', 't', FIBBER, 'Pat'], 'the claim carries the trimmed name');
  const b = await S.localFor(store, 'pid-join', script);
  eq(a.local.id, b.id, 'the same production on a second open');
  eq(S.scriptFor([script], 'gut-0', 'r1'), script, 'the matching revision');
  eq(S.scriptFor([script], 'gut-0', 'r0'), null, 'another revision is not offered');
  let code = null;
  try { await S.localFor(store, 'pid-other', null); } catch (e) { code = e.code; }
  eq(code, 'revision_mismatch', 'no script, no production');
  eq(S.line({ code }), 'This play has changed since it was cast.', 'and says so');
});

test('Library\'s Ear dramas: this browser\'s, then the shared ones not opened here', async () => {
  const { store, local } = await sharedLocal();
  const solo = await store.create(fixtureScript());
  const rows = S.libraryRows(store, [{ id: 'pid-1', title: 'Good Grammar', updated_at: 0 },
                                      { id: 'pid-far', title: 'Far Away', updated_at: 5 }]);
  eq(rows.length, 3, 'two here and one remote');
  eq(rows.filter(r => r.pid === 'pid-1').map(r => r.local && r.local.id), [local.id], 'a shared one here is listed once');
  eq(rows.filter(r => !r.local).map(r => r.pid), ['pid-far'], 'the remote one');
  ok(rows.some(r => r.local && r.local.id === solo.id && r.pid === null), 'an unshared one stays');
});

test('refusals read as one line each', () => {
  eq(S.line({ code: 'not_open' }), 'This part is taken.', 'not_open');
  eq(S.line({ code: 'invite_not_found' }), 'This invite does not work.', 'invite_not_found');
  eq(S.line({ code: 'lines_missing', detail: ['a', 'b'] }), '2 lines still need a take.', 'lines_missing');
  eq(S.line({ code: 'another_part_is_recording', detail: MOLLY }), `${C.partTitle(MOLLY)} is still recording.`, 'recording');
  eq(S.line({ kind: 'offline' }), 'You are offline.', 'offline');
  ok(!/not_next/.test(fs.readFileSync(path.join(__dirname, 'plays-share.js'), 'utf8')), 'no strict relay order is left');
});

(async () => {
  for (const [name, fn] of results) {
    try { await fn(); } catch (e) { failures++; console.log(`FAIL ${name}: ${e.stack || e}`); }
  }
  console.log(`${passes} passed, ${failures} failed`);
  process.exit(failures ? 1 : 0);
})();
