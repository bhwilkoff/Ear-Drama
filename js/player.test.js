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

function boot() {
  const audio = fakeAudio();
  const storage = {};
  const ctx = vm.createContext({
    console, Math, Number, Date, JSON, Object, Promise, Set, Map, URL, URLSearchParams,
    setInterval, clearInterval, setTimeout, clearTimeout, location: { href: 'http://localhost/' },
    document: { getElementById: () => audio },
    window: { addEventListener() {} },
    navigator: {},
    localStorage: {
      getItem: k => (k in storage ? storage[k] : null),
      setItem: (k, v) => { storage[k] = String(v); },
    },
  });
  for (const f of ['api.js', 'store.js', 'player.js']) {
    vm.runInContext(fs.readFileSync(__dirname + '/' + f, 'utf-8'), ctx, { filename: f });
  }
  vm.runInContext('globalThis.Player = Player; globalThis.Store = Store;', ctx);
  return { audio, storage, Player: ctx.Player, Store: ctx.Store };
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

(async () => {
  let passed = 0, failed = 0;
  for (const { name, fn } of tests) {
    try { await fn(); console.log(`✓ ${name}`); passed++; } catch (e) { console.error(`✗ ${name}: ${e.message}`); console.log(`FAIL ${name}`); failed++; }
  }
  console.log(`${passed} passed, ${failed} failed`);
  if (failed) process.exit(1);
})();
