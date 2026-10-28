/**
 * Another speaker (WEB-DESIGN §5.10): the AirPlay / Cast button's gating, run
 * against the SHIPPED js/remote-playback.js over fake <audio> elements.
 *   node js/remote-playback.test.js
 */
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const ctx = vm.createContext({ Promise, console });
vm.runInContext(`${fs.readFileSync(path.join(__dirname, 'remote-playback.js'), 'utf8')}\nthis.RemoteOutput = RemoteOutput;`, ctx);
const R = ctx.RemoteOutput;

let failures = 0;
function check(name, ok) {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}`);
  if (!ok) failures++;
}
const tick = () => new Promise((r) => setTimeout(r, 0));

/** Chrome's RemotePlayback: watchAvailability hands its callback the answer. */
function fakeRemote({ reject } = {}) {
  const r = {
    callback: null, prompts: 0,
    watchAvailability(cb) {
      if (reject) return Promise.reject(Object.assign(new Error(reject), { name: reject }));
      r.callback = cb; return Promise.resolve(1);
    },
    prompt() { r.prompts++; return Promise.reject(Object.assign(new Error('dismissed'), { name: 'NotAllowedError' })); },
  };
  return r;
}

function fakeSafariAudio() {
  const handlers = {};
  return {
    pickers: 0,
    webkitShowPlaybackTargetPicker() { this.pickers++; },
    addEventListener(t, fn) { (handlers[t] ||= []).push(fn); },
    fire(t, e) { (handlers[t] || []).forEach((fn) => fn(e)); },
  };
}

(async () => {
  const safariWin = { WebKitPlaybackTargetAvailabilityEvent: function () {} };

  check('no picker in this browser: no button', R.kindOf({}, {}) === null);
  check('no audio element: no button', R.kindOf(null, {}) === null);
  check('Safari: AirPlay', R.kindOf(fakeSafariAudio(), safariWin) === 'airplay');
  check('a picker method without the availability event is not AirPlay', R.kindOf(fakeSafariAudio(), {}) === null);
  check('Chrome: Cast', R.kindOf({ remote: fakeRemote() }, {}) === 'cast');
  check('the labels are the platforms\' own words', R.LABELS.airplay === 'AirPlay' && R.LABELS.cast === 'Cast');

  // Chrome: hidden until a receiver is there, hidden again when it goes.
  {
    const remote = fakeRemote();
    const seen = [];
    R.watch({ remote }, {}, (k) => seen.push(k));
    await tick();
    check('Cast starts hidden', seen[0] === null && seen.length === 1);
    remote.callback(true);
    check('Cast shows when a receiver appears', seen.at(-1) === 'cast');
    remote.callback(false);
    check('Cast hides when it goes', seen.at(-1) === null);
  }

  // A browser that cannot watch continuously still has a picker.
  {
    const seen = [];
    R.watch({ remote: fakeRemote({ reject: 'NotSupportedError' }) }, {}, (k) => seen.push(k));
    await tick();
    check('NotSupportedError: the button shows and the picker says what it finds', seen.at(-1) === 'cast');
  }
  {
    const seen = [];
    R.watch({ remote: fakeRemote({ reject: 'InvalidStateError' }) }, {}, (k) => seen.push(k));
    await tick();
    check('remote playback disabled: no button', seen.at(-1) === null);
  }

  // Safari: the availability event drives it.
  {
    const audio = fakeSafariAudio();
    const seen = [];
    R.watch(audio, safariWin, (k) => seen.push(k));
    check('AirPlay starts hidden', seen.at(-1) === null);
    audio.fire('webkitplaybacktargetavailabilitychanged', { availability: 'available' });
    check('AirPlay shows when a target is there', seen.at(-1) === 'airplay');
    audio.fire('webkitplaybacktargetavailabilitychanged', { availability: 'not-available' });
    check('AirPlay hides when it goes', seen.at(-1) === null);
    await R.prompt(audio, safariWin);
    check('AirPlay opens Safari\'s own picker', audio.pickers === 1);
  }

  // The picker is the browser's; a dismissed prompt is not an error.
  {
    const remote = fakeRemote();
    let threw = false;
    try { await R.prompt({ remote }, {}); } catch { threw = true; }
    check('Cast opens Chrome\'s own picker, and a dismissal is quiet', remote.prompts === 1 && !threw);
  }
  {
    const seen = [];
    R.watch({}, {}, (k) => seen.push(k));
    check('no picker: told null once, nothing watched', seen.length === 1 && seen[0] === null);
  }

  console.log(failures ? `${failures} FAILED` : 'all remote-playback checks passed');
  process.exit(failures ? 1 : 0);
})();
