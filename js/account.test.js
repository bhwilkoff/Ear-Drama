/**
 * Sign-in and sync on the web (M5, Decision 063), against a stubbed Worker.
 *
 *   node js/account.test.js
 *
 * Runs the SHIPPED js/api.js, js/store.js, and js/sync.js. The stub answers
 * like worker/src (docs/WORKER.md): sessions with expiries, refresh tokens
 * spent on use (a replay ends the sign-in), last-write-wins sync with
 * server_time, the merge, and deletion. Each guarantee was broken once by
 * hand to see its test fail (the commit that added this file says how).
 */
'use strict';
const fs = require('node:fs');
const vm = require('node:vm');

const mem = new Map();
const shim = {
  getItem: (k) => (mem.has(k) ? mem.get(k) : null),
  setItem: (k, v) => { mem.set(k, String(v)); },
  removeItem: (k) => { mem.delete(k); },
  clear: () => mem.clear(),
};
Object.defineProperty(globalThis, 'localStorage', { value: shim, configurable: true, writable: true });
for (const f of ['api.js', 'store.js', 'sync.js']) vm.runInThisContext(fs.readFileSync(`${__dirname}/${f}`, 'utf-8'), { filename: f });

const HOUR = 3600 * 1000;
const MIN = 60 * 1000;
const BASE = 'https://worker.test';
const acct = API.account;

/* ---- A stub Worker ---- */
function stubWorker(clock) {
  const w = {
    calls: [], refreshTokens: new Map(), access: new Map(), rows: { history: new Map(), follows: new Map(), queue: null },
    serverTime: 1000, failSync401: 0, deleteFails: false, nextId: 1,
  };
  function session(user) {
    const n = w.nextId++;
    const at = `at-${n}`; const rt = `rt-${n}`;
    w.access.set(at, { user, exp: clock() + HOUR });
    w.refreshTokens.set(rt, { user, spent: false });
    return { access_token: at, access_expires_at: clock() + HOUR, refresh_token: rt,
             refresh_expires_at: clock() + 60 * 24 * HOUR, user_id: user, provider: 'google' };
  }
  const json = (status, body) => ({ ok: status >= 200 && status < 300, status, json: async () => body });
  function bearer(init) {
    const h = (init.headers && init.headers.authorization) || '';
    const a = w.access.get(h.replace(/^Bearer /, ''));
    return a && a.exp > clock() ? a : null;
  }
  w.fetch = async (url, init = {}) => {
    const u = new URL(url);
    const path = u.pathname;
    const method = init.method || 'GET';
    const body = init.body ? JSON.parse(init.body) : null;
    w.calls.push({ method, path, search: u.search, body, auth: !!(init.headers && init.headers.authorization) });
    await new Promise(r => setTimeout(r, 1));
    if (path === '/v1/auth/google' || path === '/v1/auth/apple') {
      if (!body.nonce) return json(401, { error: 'invalid_token' });
      return json(200, { ...session('u1'), created: true });
    }
    if (path === '/v1/auth/refresh') {
      const r = w.refreshTokens.get(body.refresh_token);
      if (!r) return json(401, { error: 'unauthorized' });
      if (r.spent) { for (const v of w.refreshTokens.values()) v.spent = true; return json(401, { error: 'unauthorized', detail: 'replayed' }); }
      r.spent = true;
      return json(200, session(r.user));
    }
    const who = bearer(init);
    if (!who) return json(401, { error: 'unauthorized' });
    w.serverTime += 10;
    if (path === '/v1/sync' && method === 'GET') {
      if (w.failSync401 > 0) { w.failSync401--; return json(401, { error: 'unauthorized' }); }
      const since = Number(u.searchParams.get('since'));
      return json(200, {
        server_time: w.serverTime,
        history: [...w.rows.history.values()].filter(r => r.changed_at >= since),
        follows: [...w.rows.follows.values()].filter(r => r.changed_at >= since),
        queue: w.rows.queue && w.rows.queue.changed_at >= since ? w.rows.queue : null,
      });
    }
    if ((path === '/v1/sync' && method === 'PUT') || path === '/v1/sync/merge') {
      for (const h of body.history || []) {
        const old = w.rows.history.get(h.episode_id);
        if (!old || h.updated_at > old.updated_at) w.rows.history.set(h.episode_id, { ...h, changed_at: w.serverTime });
      }
      for (const f of body.follows || []) {
        const old = w.rows.follows.get(f.series_id);
        if (!old || f.updated_at > old.updated_at) w.rows.follows.set(f.series_id, { ...f, changed_at: w.serverTime });
      }
      if (body.queue) w.rows.queue = { ...body.queue, changed_at: w.serverTime };
      return json(200, { server_time: w.serverTime, applied: {} });
    }
    if (path === '/v1/account' && method === 'DELETE') {
      if (w.deleteFails) return json(500, { error: 'internal' });
      w.access.clear(); w.refreshTokens.clear();
      return json(200, { deleted: true, apple_token_revoked: null });
    }
    if (path === '/v1/auth/signout') return { ok: true, status: 204, json: async () => null };
    return json(404, { error: 'not_found' });
  };
  w.count = (path, method) => w.calls.filter(c => c.path === path && (!method || c.method === method)).length;
  return w;
}

function memVault() {
  let t = null;
  return { async get() { return t; }, async set(v) { t = v; }, async clear() { t = null; }, peek: () => t };
}

/** A fresh browser: empty storage, a stub Worker, a clock we move by hand. */
function fresh(config = { worker: BASE, apple: { servicesId: 'org.eardrama.web', redirectURI: 'https://eardrama.org/' },
                          google: { clientId: 'x.apps.googleusercontent.com' } }) {
  mem.clear();
  let t = 1_800_000_000_000;
  const clock = () => t;
  const w = stubWorker(clock);
  const vault = memVault();
  globalThis.fetch = w.fetch;
  acct._test.configure(config);
  acct._test.clock(clock);
  acct._test.vault(vault);
  acct._test.reset();
  return { w, vault, advance: (ms) => { t += ms; } };
}

const tests = [];
function test(name, fn) { tests.push({ name, fn }); }
function assert(cond, msg) { if (!cond) throw new Error(msg || 'assertion failed'); }
function eq(a, b, msg) { if (a !== b) throw new Error(`${msg || ''}: expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`); }

/* ---- Tests ---- */

test('placeholders: sign-in is not available, and nothing is called', async () => {
  const { w } = fresh({ worker: 'REPLACE_WITH_WORKER_BASE_URL', apple: { servicesId: 'REPLACE_WITH_X', redirectURI: 'https://eardrama.org/' },
                        google: { clientId: 'REPLACE_WITH_Y' } });
  const a = acct.available();
  eq(a.apple, false, 'apple'); eq(a.google, false, 'google');
  eq(acct.signedIn(), false, 'signed out');
  eq(await Sync.run(), false, 'a run does nothing signed out');
  eq(w.calls.length, 0, 'no request reaches any Worker');
  fresh({ worker: BASE, apple: { servicesId: 'REPLACE_WITH_X', redirectURI: 'https://eardrama.org/' }, google: { clientId: 'real.id' } });
  eq(acct.available().google, true, 'control: a real Google id with a real Worker is available');
  eq(acct.available().apple, false, 'while Apple stays a placeholder');
});

test('sign-in sends the raw nonce and keeps the refresh token out of localStorage', async () => {
  const { w, vault } = fresh();
  const nonce = acct.newNonce();
  assert(/^[A-Za-z0-9_-]{43}$/.test(nonce), 'a 32-byte base64url nonce');
  await acct.signIn('google', 'id-token', nonce);
  const c = w.calls.find(x => x.path === '/v1/auth/google');
  eq(c.body.nonce, nonce, 'nonce sent raw');
  eq(c.body.device, 'web', 'device');
  eq(vault.peek(), 'rt-1', 'refresh token in the vault');
  assert(![...mem.values()].some(v => v.includes('rt-1') || v.includes('at-1')), 'no token in localStorage');
  eq(acct.state().merge_pending, true, 'the merge is owed');
});

test('refresh before a call when under 5 minutes remain, not before', async () => {
  const { w, advance } = fresh();
  await acct.signIn('google', 'id', acct.newNonce());
  advance(HOUR - 30 * MIN);
  await acct.syncRead(0);
  eq(w.count('/v1/auth/refresh'), 0, 'control: 30 minutes left, no refresh');
  advance(26 * MIN);                       // 4 minutes left
  await acct.syncRead(0);
  eq(w.count('/v1/auth/refresh'), 1, 'one refresh');
  const i = w.calls.findIndex(x => x.path === '/v1/auth/refresh');
  eq(w.calls[i + 1].path, '/v1/sync', 'the refresh came before the call');
});

test('one refresh at a time: concurrent calls share it, and no refresh token is replayed', async () => {
  const { w, vault, advance } = fresh();
  await acct.signIn('google', 'id', acct.newNonce());
  advance(HOUR + MIN);                    // expired
  await Promise.all([acct.syncRead(0), acct.syncRead(0), acct.info().catch(() => null), acct.syncRead(0)]);
  eq(w.count('/v1/auth/refresh'), 1, 'one refresh for four calls');
  eq(vault.peek(), 'rt-2', 'the rotated token is kept');
  eq(acct.signedIn(), true, 'still signed in (a replay would have ended it)');
});

test('a 401 refreshes once and retries; a second 401 is surfaced', async () => {
  const { w } = fresh();
  await acct.signIn('google', 'id', acct.newNonce());
  w.failSync401 = 1;
  const r = await acct.syncRead(0);
  assert(r && r.server_time, 'retried after one refresh');
  eq(w.count('/v1/auth/refresh'), 1, 'one refresh');
  w.calls.length = 0;
  w.failSync401 = 5;
  let err = null;
  try { await acct.syncRead(0); } catch (e) { err = e; }
  assert(err, 'surfaced');
  eq(err.kind, 'unauthorized', 'kind');
  eq(w.count('/v1/sync'), 2, 'the call and one retry, no loop');
  eq(w.count('/v1/auth/refresh'), 1, 'one refresh');
});

test('a refused refresh ends the sign-in here', async () => {
  const { w, vault, advance } = fresh();
  await acct.signIn('google', 'id', acct.newNonce());
  w.refreshTokens.clear();
  advance(HOUR);
  let err = null;
  try { await acct.syncRead(0); } catch (e) { err = e; }
  eq(err && err.kind, 'unauthorized', 'surfaced');
  eq(acct.signedIn(), false, 'signed out');
  eq(vault.peek(), null, 'no token kept');
  eq(acct.state().ended, 'session_ended', 'the row can say so');
});

test('the signed-out history is merged once, then only changes are sent', async () => {
  const { w } = fresh();
  Store.addHistory({ id: 'suspense|1948-03-11', title: 'The Visitor', series: 'suspense', url: 'https://a/x.mp3' });
  Store.savePosition('suspense|1948-03-11', 612, 1795);
  Store.toggleFollow({ key: 'suspense', name: 'Suspense' });
  Store.enqueue({ id: 'x-minus-one|1955-04-24', title: 'And the Moon Be Still as Bright', url: 'https://a/y.mp3' });
  await acct.signIn('google', 'id', acct.newNonce());
  await Sync.run();
  await Sync.run();
  eq(w.count('/v1/sync/merge'), 1, 'merge sent once');
  const m = w.calls.find(x => x.path === '/v1/sync/merge').body;
  eq(m.history.length, 1, 'history'); eq(m.history[0].position, 612, 'position');
  eq(m.follows[0].series_id, 'suspense', 'follows');
  eq(m.queue.items[0], 'x-minus-one|1955-04-24', 'queue');
  eq(w.count('/v1/sync', 'PUT'), 0, 'nothing changed since, nothing PUT');
  eq(acct.state().merge_pending, false, 'merge no longer owed');
  assert(acct.state().last_sync_at, 'last sync recorded');
  Store.savePosition('suspense|1948-03-11', 700, 1795);
  await Sync.run();
  const put = w.calls.filter(x => x.path === '/v1/sync' && x.method === 'PUT');
  eq(put.length, 1, 'one PUT after a change');
  eq(put[0].body.history.length, 1, 'only the changed row');
  eq(put[0].body.follows, undefined, 'no unchanged follows');
  const reads = w.calls.filter(x => x.path === '/v1/sync' && x.method === 'GET').map(x => x.search);
  eq(reads[0], '?since=0', 'first read since 0');
  assert(reads[reads.length - 1] !== '?since=0', 'later reads since the last server_time');
});

test('a failed merge stays owed, and the error is recorded', async () => {
  const { w } = fresh();
  Store.addHistory({ id: 'a|1950-01-01', url: 'u' });
  await acct.signIn('google', 'id', acct.newNonce());
  const real = globalThis.fetch;
  globalThis.fetch = async (u, i) => (String(u).includes('/merge') ? Promise.reject(new TypeError('Failed to fetch')) : real(u, i));
  const quiet = console.error; console.error = () => {};
  try { eq(await Sync.run(), false, 'run failed'); } finally { console.error = quiet; }
  eq(acct.state().merge_pending, true, 'still owed');
  eq(acct.state().last_error.kind, 'error', 'last error');
  globalThis.fetch = real;
  eq(await Sync.run(), true, 'next run');
  eq(acct.state().last_error, null, 'error cleared');
  eq(w.count('/v1/sync/merge'), 1, 'merged once it could');
});

test('last write wins per row, with removal markers', () => {
  fresh();
  Store.addHistory({ id: 'e1', title: 'One', url: 'u1' });
  Store.savePosition('e1', 100, 1000);
  Store.addHistory({ id: 'e2', title: 'Two', url: 'u2' });
  Store.savePosition('e2', 200, 1000);
  Store.addHistory({ id: 'e3', title: 'Three', url: 'u3' });
  Store.toggleFollow({ key: 's1', name: 'S1' });
  Store.toggleFollow({ key: 's2', name: 'S2' });
  Store.enqueue({ id: 'e1', title: 'One', url: 'u1' });
  const now = Date.now();
  const changed = Store.applyRemote({
    history: [
      { episode_id: 'e1', position: 500, duration: 1000, deleted: false, updated_at: now + 5000 },  // newer: wins
      { episode_id: 'e2', position: 900, duration: 1000, deleted: false, updated_at: now - 60000 }, // older: loses
      { episode_id: 'e3', position: 0, deleted: true, updated_at: now + 5000 },                     // marker: removes
      { episode_id: 'e9', position: 42, duration: 1800, deleted: false, updated_at: now + 5000 },   // new: a stub
    ],
    follows: [
      { series_id: 's1', following: false, updated_at: now + 5000 },   // marker: unfollows
      { series_id: 's2', following: false, updated_at: now - 60000 },  // older marker: ignored
      { series_id: 's3', following: true, updated_at: now + 5000 },
    ],
    queue: { items: ['e2'], updated_at: now - 60000 },                 // older queue: loses whole
  });
  eq(changed, 5, 'rows changed');
  eq(Store.position('e1').t, 500, 'newer remote position applied');
  eq(Store.position('e2').t, 200, 'older remote position ignored');
  eq(Store.position('e3'), null, 'removed position');
  assert(!Store.history().some(x => x.id === 'e3'), 'removed from history');
  eq(Store.history().find(x => x.id === 'e1').title, 'One', 'the card is kept');
  eq(Store.position('e9').t, 42, 'new row applied');
  eq(JSON.stringify(Store.stubs().episodes), '["e9"]', 'and waits for its card');
  eq(Store.isFollowing('s1'), false, 'unfollowed by marker');
  eq(Store.isFollowing('s2'), true, 'older marker ignored');
  eq(Store.isFollowing('s3'), true, 'followed');
  eq(Store.queue().map(x => x.id).join(), 'e1', 'older queue ignored');
  eq(Store.hasPending(), true, 'local rows still owed');
  const up = Store.syncUpload();
  assert(!up.history.some(r => r.episode_id === 'e1' || r.episode_id === 'e9'), 'applied rows are not sent back');
  Store.applyRemote({ queue: { items: ['e9', 'e1'], updated_at: Date.now() + 9000 } });
  eq(Store.queue().map(x => x.id).join(), 'e9,e1', 'a newer queue wins whole');
  eq(Store.queue()[1].url, 'u1', 'keeping the cards it knew');
  const tie = Store.applyRemote({ history: [{ episode_id: 'e1', position: 1, duration: 1000, updated_at: now + 5000 }] });
  eq(tie, 0, 'an equal stamp keeps this device');
});

test('clearing history sends a removal marker for every row', () => {
  fresh();
  Store.addHistory({ id: 'e1', url: 'u' });
  Store.savePosition('e2', 30, 100);
  Store.markSynced(Store.syncUpload({ all: true }));
  Store.clearHistory();
  const up = Store.syncUpload();
  eq(up.history.length, 2, 'both rows');
  assert(up.history.every(r => r.deleted === true), 'as markers');
});

test('deleting the account clears the tokens and the account state, only once the Worker agrees', async () => {
  const { w, vault } = fresh();
  Store.addHistory({ id: 'e1', url: 'u' });
  await acct.signIn('google', 'id', acct.newNonce());
  await Sync.run();
  w.deleteFails = true;
  let err = null;
  try { await Sync.deleteAccount({}); } catch (e) { err = e; }
  assert(err, 'a failed deletion is surfaced');
  eq(acct.signedIn(), true, 'control: still signed in after a failed deletion');
  eq(vault.peek() !== null, true, 'control: token kept to try again');
  w.deleteFails = false;
  const r = await Sync.deleteAccount({ appleAuthorizationCode: 'c', appleClientId: 'org.eardrama.web' });
  eq(r.deleted, true, 'deleted');
  const del = w.calls.filter(x => x.method === 'DELETE').pop();
  assert(del.auth, 'with the bearer');
  eq(del.body.apple_authorization_code, 'c', 'the Apple code for revocation');
  eq(vault.peek(), null, 'refresh token gone');
  eq(acct._test.access(), null, 'access token gone');
  eq(acct.state(), null, 'account state gone');
  eq(localStorage.getItem('ed.account'), null, 'and not on disk');
  eq(acct.signedIn(), false, 'signed out');
  eq(Store.hasPending(), true, 'the listening stays here, unsent');
});

// Contract §3.5. Registered last: Store keeps the forwarding it was given for the rest of the page.
test('forwarded ids: stored rows move once, by the newer stamp; synced rows forward as they land', () => {
  fresh();
  const f = API.forwardingOf({ 'jb|1921-03-11': 'jb|1943-11-21', 'jb|old-slug': 'jb|1944-01-02', 'q|old': 'q|new' },
                             ['jb|gone']);
  Store.addHistory({ id: 'jb|1921-03-11', title: 'No. 4', date: '1921-03-11', url: 'https://a/benny.mp3' });
  Store.savePosition('jb|1921-03-11', 600, 1800);
  Store.addHistory({ id: 'jb|1944-01-02', title: 'Kept', url: 'https://a/kept.mp3' });
  Store.savePosition('jb|1944-01-02', 300, 1800);
  const s = JSON.parse(localStorage.getItem('ed.stamps'));
  s.h['jb|old-slug'] = { at: s.h['jb|1944-01-02'].at - 5000, del: 0, dirty: 0 };   // an older row, never uploaded
  localStorage.setItem('ed.stamps', JSON.stringify(s));
  Store.addHistory({ id: 'jb|gone', title: 'Gone', url: 'https://a/gone.mp3' });
  Store.enqueue({ id: 'q|old', title: 'Old', url: 'https://a/q.mp3' });
  Store.enqueue({ id: 'jb|gone', title: 'Gone', url: 'https://a/gone.mp3' });
  Store.enqueue({ id: 'q|new', title: 'New', url: 'https://a/q.mp3' });
  const before = JSON.parse(localStorage.getItem('ed.stamps')).h['jb|1921-03-11'];

  assert(Store.forward(f) > 0, 'something moved');
  eq(Store.position('jb|1943-11-21').t, 600, 'the position moved to the new id');
  eq(Store.position('jb|1921-03-11'), null, 'and left the old one');
  const h = Store.history();
  assert(!h.some(x => x.id === 'jb|1921-03-11'), 'the old id left the history');
  eq(JSON.stringify(Store.stubs().episodes), '["jb|1943-11-21"]', 'the moved row is a stub the catalog draws again');
  const after = JSON.parse(localStorage.getItem('ed.stamps')).h;
  eq(after['jb|1943-11-21'].at, before.at, 'the row keeps its own stamp (a rewrite is not a listen)');
  eq(after['jb|old-slug'], undefined, 'an older moved row is dropped');
  eq(Store.position('jb|1944-01-02').t, 300, 'and the newer row it merged into wins');
  eq(Store.queue().map(x => x.id).join(), 'q|new', 'the queue maps, dedupes, and drops a tombstoned id');
  assert(h.some(x => x.id === 'jb|gone'), 'history keeps a tombstoned id: it is the person\'s record');
  eq(Store.forward(f), 0, 'it migrates once');

  Store.applyRemote({
    history: [{ episode_id: 'jb|1921-03-11', position: 900, duration: 1800, deleted: false, updated_at: Date.now() + 9000 }],
    queue: { items: ['jb|1921-03-11', 'jb|gone', 'jb|1943-11-21'], updated_at: Date.now() + 9000 },
  });
  eq(Store.position('jb|1943-11-21').t, 900, 'another device\'s row for the old id lands on the new one');
  eq(Store.position('jb|1921-03-11'), null, 'never under the old id');
  eq(Store.queue().map(x => x.id).join(), 'jb|1943-11-21', 'a synced queue forwards too');
});

test('API.forwarding reads aliases and tombstones once; a catalog without tombstones has none', async () => {
  const served = { 'index/aliases.json': { a: 'b' } };
  const get = async (p) => { if (p in served) return served[p]; throw new API.DataError('missing', p); };
  const f = API.forwardingOf(await get('index/aliases.json'), []);
  eq(f.resolve('a'), 'b', 'an alias resolves');
  eq(f.resolve('c'), 'c', 'an unknown id is kept (it may be from a newer catalog)');
  eq(f.gone('c'), false, 'and is not gone');
  eq(API.forwardingOf({}, ['t']).resolve('toString'), 'toString', 'an inherited name is not an alias');
  eq(API.forwardingOf({ a: 5 }, []).resolve('a'), 'a', 'only a string target resolves');
  eq(API.forwardingOf({}, ['t']).gone('t'), true, 'a tombstoned id is gone');
  eq(API.forwardingOf(null, null).resolve('a'), 'a', 'a malformed file forwards nothing');
});

(async () => {
  let passed = 0; let failed = 0;
  for (const { name, fn } of tests) {
    try { await fn(); console.log(`✓ ${name}`); passed++; } catch (e) { console.error(`✗ FAIL ${name}: ${e.message}`); failed++; }
  }
  console.log(`${passed} passed, ${failed} failed`);
  if (failed) process.exit(1);
})();
