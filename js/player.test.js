/**
 * The player's numbers (DECISIONS 062) and the behavior they drive, run
 * against the SHIPPED js/store.js and js/player.js over a fake <audio>.
 *   node js/player.test.js
 */
const fs = require('node:fs');
const vm = require('node:vm');

function fakeAudio() {
  const handlers = {};
  return {
    paused: true, ended: false, currentTime: 0, duration: NaN, volume: 1, muted: false,
    playbackRate: 1, defaultPlaybackRate: 1, src: '', error: null,
    addEventListener(type, fn) { (handlers[type] ||= []).push(fn); },
    fire(type) { (handlers[type] || []).slice().forEach(fn => fn()); },
    play() { this.paused = false; this.fire('play'); return Promise.resolve(); },
    pause() { if (this.paused) return; this.paused = true; this.fire('pause'); },
  };
}

/** A Web Audio stand-in that records the graph the player builds. */
function fakeAudioContext(log, state = 'running') {
  const param = (v) => ({ value: v });
  const node = (kind, extra = {}) => ({
    kind, outs: [], ...extra,
    connect(n) { this.outs.push(n); log.edges.push([kind, n.kind]); return n; },
    disconnect() { this.outs = []; log.edges.push([kind, 'cut']); },
  });
  return class {
    constructor() { this.state = state; this.destination = node('destination'); log.contexts++; }
    resume() { this.state = 'running'; return Promise.resolve(); }
    createMediaElementSource(el) { log.sources.push(el.crossOrigin); return node('source'); }
    createDynamicsCompressor() {
      const c = node('compressor', { threshold: param(-24), knee: param(30), ratio: param(12),
                                     attack: param(0.003), release: param(0.25) });
      log.comp = c;
      return c;
    }
    createGain() { const g = node('gain', { gain: param(1) }); log.gain = g; return g; }
  };
}

function boot(env = {}) {
  const audio = fakeAudio();
  const storage = {};
  const docListeners = {};
  const ctx = vm.createContext({
    console, Math, Number, Date, JSON, Object, Promise, Set, Map, URL, URLSearchParams,
    setInterval, clearInterval, setTimeout, clearTimeout, location: { href: 'http://localhost/' },
    document: { getElementById: () => audio, documentElement: { classList: { contains: () => false } },
                addEventListener: (t, fn) => { (docListeners[t] ||= []).push(fn); } },
    window: { addEventListener() {} },
    navigator: env.navigator || {},
    ...(env.AudioContext ? { AudioContext: env.AudioContext } : {}),
    localStorage: {
      getItem: k => (k in storage ? storage[k] : null),
      setItem: (k, v) => { storage[k] = String(v); },
    },
  });
  for (const f of ['api.js', 'store.js', 'player.js']) {
    vm.runInContext(fs.readFileSync(__dirname + '/' + f, 'utf-8'), ctx, { filename: f });
  }
  vm.runInContext('globalThis.Player = Player; globalThis.Store = Store;', ctx);
  ctx.Player.setArcSource(env.arcSource || (() => null));
  const tap = () => (docListeners.pointerdown || []).forEach(fn => fn());
  return { audio, storage, tap, Player: ctx.Player, Store: ctx.Store };
}

const ep = { id: 'x|1943-02-24', title: 'An Episode', series: 'x', seriesName: 'X', date: '1943-02-24',
             url: 'https://archive.org/download/x/a.mp3' };

const tests = [];
function test(name, fn) { tests.push({ name, fn }); }
function assertEq(a, b, msg) {
  if (JSON.stringify(a) !== JSON.stringify(b)) {
    throw new Error(`${msg || ''} expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`);
  }
}

test('the numbers are DECISIONS 062', () => {
  const { Player } = boot();
  assertEq(Player.FADE_S, 10, 'sleep fade');
  assertEq(Player.SPEEDS, [0.75, 1, 1.25, 1.5, 2], 'speeds');
  assertEq(Player.SAVE_EVERY_MS, 5000, 'save interval');
  assertEq(Player.REWIND_S, 3, 'rewind');
});

test('every speed on the page is one of SPEEDS, and every SPEED is on the page', () => {
  const { Player } = boot();
  const html = fs.readFileSync(__dirname + '/../index.html', 'utf-8');
  const select = html.match(/<select id="np-speed">([\s\S]*?)<\/select>/)[1];
  const offered = [...select.matchAll(/value="([\d.]+)"/g)].map(m => Number(m[1]));
  assertEq(offered, Player.SPEEDS);
});

test('a speed kept from an older build lands on the nearest choice', () => {
  const { Player, Store } = boot();
  Player.setRate(0.8);
  assertEq(Store.rate(), 0.75);
  Player.setRate(1.2);
  assertEq(Store.rate(), 1.25);
  Player.setRate('nonsense');
  assertEq(Store.rate(), 1);
});

test('the position saves every 5 s while playing, and on pause', () => {
  const { audio, Player, Store } = boot();
  Player.load(ep);
  audio.duration = 1800;
  let now = 1_000_000;
  const realNow = Date.now;
  Date.now = () => now;
  try {
    audio.currentTime = 100; audio.fire('timeupdate');
    assertEq(Store.position(ep.id).t, 100, 'first tick saves');
    now += 4000; audio.currentTime = 104; audio.fire('timeupdate');
    assertEq(Store.position(ep.id).t, 100, 'not before 5 s');
    now += 1500; audio.currentTime = 105; audio.fire('timeupdate');
    assertEq(Store.position(ep.id).t, 105, 'after 5 s');
    now += 1000; audio.currentTime = 106; Player.pause();
    assertEq(Store.position(ep.id).t, 106, 'on pause');
  } finally {
    Date.now = realNow;
  }
});

test('resuming after an interruption rewinds 3 s; the person\'s own pause does not', () => {
  const { audio, Player } = boot();
  Player.load(ep);
  audio.duration = 1800;
  audio.currentTime = 600;
  Player.pause();
  Player.play();
  assertEq(audio.currentTime, 600, 'a pause the person pressed resumes in place');
  audio.pause(); // the browser paused it: a call, another tab's sound
  Player.play();
  assertEq(audio.currentTime, 597, 'an interruption resumes 3 s back');
  Player.pause();
  Player.play();
  assertEq(audio.currentTime, 597, 'the rewind happens once');
});

test('the sleep fade starts 10 s before the end, not before', () => {
  const { audio, Player } = boot();
  Player.load(ep);
  audio.duration = 1800;
  Player.setSleep('end');
  audio.currentTime = 1785; // 15 s left
  assertEq(Player.sleepRemaining() > Player.FADE_S, true, '15 s left is outside the fade');
  audio.currentTime = 1795;
  assertEq(Player.sleepRemaining() <= Player.FADE_S, true, '5 s left is inside it');
  Player.setSleep('off');
});

test('a Listen Together guest cannot drive: the person\'s verbs do nothing; the room\'s nudge is never kept', () => {
  const { audio, Player, Store } = boot();
  Player.load(ep);
  audio.duration = 1800;
  audio.currentTime = 100;
  Player.setFollowing(true);
  Player.toggle();
  assertEq(audio.paused, false, 'toggle refused (still playing) when the room asks for no hold');
  Player.seek(500); Player.back(); Player.forward();
  assertEq(audio.currentTime, 100, 'seek and skip refused');
  Player.setRate(2);
  assertEq(Store.rate(), 1, 'speed refused');
  Player.follow.rate(1.03);
  assertEq(audio.playbackRate, 1.03, 'the room nudges');
  assertEq(Store.rate(), 1, 'a nudge is never the person\'s speed');
  Player.follow.seek(612.5);
  assertEq(audio.currentTime, 612.5, 'the room seeks');
  Player.setFollowing(false);
  assertEq(audio.playbackRate, 1, 'leaving restores the person\'s own speed');
  Player.seek(50);
  assertEq(audio.currentTime, 50, 'controls back');
});

test('067: an episode ends, the queue plays next whatever its series, then playback stops', () => {
  const { audio, Player, Store } = boot();
  const other = { id: 'y|1950-01-01', title: 'Another', series: 'y', seriesName: 'Y', url: 'https://archive.org/download/y/b.mp3' };
  Store.enqueue(other);
  Player.load(ep);
  audio.duration = 1800;
  assertEq(Player.nextInQueue() && Player.nextInQueue().id, 'y|1950-01-01', 'another series is next');
  audio.ended = true; audio.fire('ended');
  assertEq(Player.current.id, 'y|1950-01-01', 'the queued episode plays');
  audio.ended = true; audio.fire('ended');
  assertEq(Player.current.id, 'y|1950-01-01', 'with the queue empty nothing else starts');
});

/** A three-part story and the series' next one, as API.arcOf hands them over. */
const part = (n) => ({ id: `jd|1955-10-0${n + 2}`, title: `The Macormack Matter - Ep ${n}`, series: 'jd',
                       url: `https://archive.org/download/jd/${n}.mp3` });
const nextOne = { id: 'jd|1955-10-10', title: 'The Molly K Matter - Ep 1', series: 'jd', url: 'https://archive.org/download/jd/m.mp3' };
const story = (id) => {
  const n = Number(id.slice(-1)) - 2;
  if (id.startsWith('jd|1955-10-0') && n >= 1 && n <= 3) {
    return { part: n, parts: 3, next: n < 3 ? part(n + 1) : null, nextStory: n === 3 ? nextOne : null };
  }
  return null;
};

test('067: a part of an arc is followed by the next part, before anything queued', () => {
  const { audio, Player, Store } = boot({ arcSource: story });
  const other = { id: 'y|1950-01-01', title: 'Another', series: 'y', url: 'https://archive.org/download/y/b.mp3' };
  Store.enqueue(other);
  Player.load(part(1));
  assertEq(Player.upNext().kind, 'part', 'the next part is up next');
  assertEq(Player.nextStory(), null, 'no story is offered before the last part');
  audio.ended = true; audio.fire('ended');
  assertEq(Player.current.id, part(2).id, 'part 2 plays');
  audio.ended = true; audio.fire('ended');
  assertEq(Player.current.id, part(3).id, 'part 3 plays');
  assertEq(Player.nextStory() && Player.nextStory().id, nextOne.id, 'the last part offers the next story');
  assertEq(Player.upNext().card.id, other.id, 'after the arc only the queue is up next');
  audio.ended = true; audio.fire('ended');
  assertEq(Player.current.id, other.id, 'what the person queued plays after the arc');
});

test('067: at an arc\'s end playback stops; the next story is offered, never started', () => {
  const { audio, Player } = boot({ arcSource: story });
  const kinds = [];
  Player.onChange(k => kinds.push(k));
  Player.load(part(3));
  audio.ended = true; audio.fire('ended');
  assertEq(Player.current.id, part(3).id, 'nothing else starts');
  assertEq(kinds.includes('ended'), true, 'playback stopped');
  assertEq(Player.nextStory().id, nextOne.id, 'the offer stays after the end');
  Player.load(Player.nextStory());
  assertEq(Player.current.id, nextOne.id, 'the person starts it');
});

test('067: a live slot follows its clock, never an arc', () => {
  const { audio, Player } = boot({ arcSource: story });
  Player.load(part(1), { at: 60, arc: false });
  assertEq(Player.upNext(), null, 'no part is up next on the air');
  audio.ended = true; audio.fire('ended');
  assertEq(Player.current.id, part(1).id, 'the slot ends; the station starts what is next');
});

test('067: an arc read still in flight is waited for at the end, and dropped if the person moved on', async () => {
  let release;
  const { audio, Player } = boot({ arcSource: (id) => new Promise(r => { release = () => r(story(id)); }) });
  Player.load(part(1));
  audio.ended = true; audio.fire('ended');
  assertEq(Player.current.id, part(1).id, 'nothing starts before the arc is known');
  release();
  await new Promise(r => setTimeout(r, 0));
  assertEq(Player.current.id, part(2).id, 'then the next part plays');
  Player.load(part(1));
  const first = release;
  Player.load(nextOne);
  first();
  await new Promise(r => setTimeout(r, 0));
  assertEq(Player.upNext(), null, 'a stale read never lands on the episode now playing');
});

test('067: a failed arc read falls back to one episode, then the queue', async () => {
  const { audio, Player, Store } = boot({ arcSource: () => Promise.reject(new Error('offline')) });
  const other = { id: 'y|1950-01-01', title: 'Another', series: 'y', url: 'https://archive.org/download/y/b.mp3' };
  Store.enqueue(other);
  Player.load(part(1));
  await new Promise(r => setTimeout(r, 0));
  audio.ended = true; audio.fire('ended');
  assertEq(Player.current.id, other.id, 'the queue plays');
});

test('067: a Listen Together guest\'s play and pause are their own hold, handed to the room session', () => {
  const { audio, Player } = boot();
  const asked = [];
  Player.load(ep);
  Player.setFollowing(true);
  Player.setGuestHold((on) => asked.push(on));
  Player.toggle();
  Player.pause();
  audio.paused = true;
  Player.toggle();
  Player.play();
  assertEq(asked, [true, true, false, false], 'toggle and pause hold; toggle and play resume');
  Player.seek(500);
  assertEq(asked.length, 4, 'seek is still the host\'s');
  Player.setFollowing(false);
  Player.pause();
  assertEq(asked.length, 4, 'control: out of a room, pause is the player\'s own again');
});

test('067: volume is leveled by a compressor on the device, built only once a tap started audio', async () => {
  const log = { contexts: 0, sources: [], edges: [] };
  const { audio, tap, Player } = boot({ AudioContext: fakeAudioContext(log, 'suspended') });
  Player.load(ep);
  assertEq(audio.crossOrigin, 'anonymous', 'the copy is fetched with CORS so the graph can hear it');
  assertEq(log.sources.length, 0, 'a play the browser started on its own is never routed into a suspended context');
  tap();
  await Promise.resolve(); await Promise.resolve();
  Player.play();
  assertEq(log.sources, ['anonymous'], 'routed once, through a CORS copy');
  const c = log.comp;
  assertEq([c.threshold.value, c.ratio.value, c.knee.value, c.attack.value, c.release.value],
           [-24, 4, 12, 0.003, 0.25], 'the LEVEL numbers');
  assertEq(Math.round(Player.LEVEL.makeupDb * 10) / 10, 10.8, 'makeup is the Web Audio rule, 0.6 x 18 dB');
  assertEq(log.edges.slice(0, 3), [['source', 'compressor'], ['compressor', 'gain'], ['gain', 'destination']]);
  assertEq(Player.leveled, true);
  Player.setLeveling(false);
  assertEq(log.edges.slice(-2), [['source', 'cut'], ['source', 'gain']], 'off bypasses the compressor');
  Player.setLeveling(true);
  assertEq(log.edges.slice(-1), [['source', 'compressor']], 'on routes through it again');
  audio.duration = 1800;
  Player.setSleep('end');
  audio.currentTime = 1795;
  await new Promise(r => setTimeout(r, 300));
  assert(log.gain.gain.value < 1 && audio.volume === 1, 'the sleep fade rides the graph, not the element');
  Player.setSleep('off');
});

test('control: no leveling on iPhone or iPad, where a page\'s audio graph stops at the lock screen', () => {
  const log = { contexts: 0, sources: [], edges: [] };
  const { audio, tap, Player } = boot({ AudioContext: fakeAudioContext(log),
                                        navigator: { userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)' } });
  tap();
  Player.load(ep);
  assertEq([Player.canLevel, log.contexts, log.sources.length, audio.crossOrigin], [false, 0, 0, undefined]);
});

test('control: a copy refused with CORS plays again without it, unleveled', async () => {
  const log = { contexts: 0, sources: [], edges: [] };
  const { audio, Player } = boot({ AudioContext: fakeAudioContext(log, 'suspended') });
  audio.removeAttribute = function (a) { if (a === 'crossorigin') delete this.crossOrigin; };
  Player.load(ep);
  audio.fire('error');
  assertEq([audio.crossOrigin, Player.error], [undefined, null], 'retried plain, not an error');
  audio.error = { code: 4 };
  audio.fire('error');
  assertEq(Player.error !== null, true, 'a second failure is the recording\'s');
});

function assert(cond, msg) { if (!cond) throw new Error(msg || 'assertion failed'); }

(async () => {
  let passed = 0, failed = 0;
  for (const { name, fn } of tests) {
    try { await fn(); console.log(`✓ ${name}`); passed++; } catch (e) { console.error(`✗ ${name}: ${e.message}`); console.log(`FAIL ${name}`); failed++; }
  }
  console.log(`${passed} passed, ${failed} failed`);
  if (failed) process.exit(1);
})();
