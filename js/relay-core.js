/**
 * Relay across time (PLAYS-DESIGN §12.11): the sender's rules and the receiver's pickup loop, no
 * DOM and no network of its own.
 * A performer's takes are written on their device first; this decides when each one passes
 * through the Worker to the receiving (teacher's or leader's) device, which is only when that
 * device is there, and says each take's state in essential words. Nothing is kept anywhere but
 * the performer's device. `source` and `timers` are passed in, so js/relay.test.js runs the
 * shipped queue against a stub Worker with no clock and no microphone.
 *
 * source: {
 *   pending():  Promise<take[]>   // the takes not yet passed through, script order; { id, ... }
 *   probe():    Promise<{ receiving, name }>   // GET .../receiver
 *   send(take): Promise            // throws { code } or { kind }; resolves once delivered
 *   sent(take): Promise|void       // the take arrived: the caller remembers it
 *   refused(take, code): void      // a final refusal: out of the queue, stays on the device
 * }
 */
const RelayCore = (() => {
  'use strict';
  /** Seconds between asks while the receiver is away: 5, 10, 20, 40, then every 60 (PLAYS-DESIGN §12.11 item 3). */
  const GAPS = [5000, 10000, 20000, 40000, 60000];
  const delay = (failures) => GAPS[Math.min(Math.max(failures, 0), GAPS.length - 1)];

  /** Refusals that mean "later": the take stays and the sender backs off. */
  const LATER = new Set(['nobody_receiving', 'one_take_at_a_time', 'offline', 'error', 'rate_limited', 'timeout',
    'not_configured', 'not_delivered', 'unauthorized']);
  const isLater = (err) => {
    const c = (err && (err.code || err.kind)) || 'error';
    return LATER.has(c) || (err && typeof err.status === 'number' && (err.status >= 500 || err.status === 429));
  };
  const codeOf = (err) => (err && (err.code || err.kind)) || 'error';

  /** The state a take is in on the sender: 'sent', 'sending', or 'waiting'. */
  function stateOf(id, { sent = [], sending = null } = {}) {
    if (new Set(sent).has(id)) return 'sent';
    return sending === id ? 'sending' : 'waiting';
  }

  /** The words (a fact, never an explanation): "On this device · sends when Ms. Ortiz is in Ear Drama". */
  function wording(state, name, fallback = 'the director') {
    if (state === 'sent') return 'Sent';
    if (state === 'sending') return 'Sending';
    return `On this device · sends when ${(name && String(name).trim()) || fallback} is in Ear Drama`;
  }

  /**
   * The lines a seat may record: a part, or a scene range of it, from the assignments (the Worker's
   * `covered`, ported: worker/src/plays-seats.js). `cast` is [[lineID, part]] in script order.
   */
  function assignedLines(cast, assignments) {
    const at = (id) => cast.findIndex(([l]) => l === id);
    const out = new Set();
    for (const a of assignments || []) {
      const lo = a.from ? at(a.from) : 0;
      const hi = a.to ? at(a.to) : cast.length - 1;
      for (let i = Math.max(lo, 0); i <= hi && i < cast.length; i++) if (cast[i][1] === a.part) out.add(cast[i][0]);
    }
    return cast.filter(([l]) => out.has(l)).map(([l]) => l);
  }

  function make({ source, timers = globalThis, online = () => (typeof navigator === 'undefined' || navigator.onLine !== false), onChange = () => {} }) {
    const st = { receiving: null, name: null, waiting: [], sending: null, sentNow: 0, error: null, failures: 0, idle: true };
    let timer = null;
    let running = false;
    let again = false;
    let stopped = false;
    const changed = () => { try { onChange(st); } catch (e) { console.error(e); } };
    const later = () => {
      if (timer) timers.clearTimeout(timer);
      timer = stopped ? null : timers.setTimeout(() => { timer = null; return run(); }, delay(st.failures - 1));
    };

    async function run() {
      if (running) { again = true; return; }
      if (stopped) return;
      running = true;
      try {
        do {
          again = false;
          let todo = [];
          try { todo = await source.pending(); } catch (e) { console.error(e); todo = []; }
          st.waiting = todo.map((t) => t.id);
          st.idle = !todo.length;
          if (!todo.length) { st.failures = 0; st.error = null; st.sending = null; changed(); break; }
          changed();
          if (!online()) { st.failures += 1; st.error = 'offline'; changed(); later(); break; }
          let p;
          try { p = await source.probe(); } catch (e) {
            st.failures += 1; st.error = codeOf(e); changed(); later(); break;
          }
          st.receiving = !!(p && p.receiving);
          if (p && p.name) st.name = p.name;
          if (!st.receiving) { st.failures += 1; st.error = null; changed(); later(); break; }
          let stuck = false;
          for (const take of todo) {
            if (stopped) break;
            st.sending = take.id;
            changed();
            try {
              await source.send(take);
              await source.sent(take);
              st.waiting = st.waiting.filter((x) => x !== take.id);
              st.sentNow += 1;
              st.failures = 0;
              st.error = null;
            } catch (e) {
              if (isLater(e)) { st.failures += 1; st.error = codeOf(e); stuck = true; break; }
              st.error = codeOf(e);
              st.waiting = st.waiting.filter((x) => x !== take.id);
              if (source.refused) source.refused(take, codeOf(e));
            }
          }
          st.sending = null;
          changed();
          if (stuck) { later(); break; }
        } while (again && !stopped);
      } finally {
        running = false;
      }
    }

    return {
      state: () => st,
      /** A take was saved, the network came back, or the app came to the front: ask now. */
      kick() { st.failures = 0; if (timer) { timers.clearTimeout(timer); timer = null; } return run(); },
      stop() { stopped = true; if (timer) timers.clearTimeout(timer); timer = null; },
    };
  }

  /** A receiver stops holding its pickup after this long with no take (PLAYS-DESIGN §12.11 item 4). */
  const RECEIVE_IDLE_MS = 30 * 60 * 1000;

  /**
   * The receiver's pickup (a class page, a director's cast sheet): long polls `inbox()` one after
   * another, but only while the page is visible, and stops after RECEIVE_IDLE_MS with no take,
   * calling `onIdle` so the page can offer Keep receiving takes. A held pickup keeps a Durable Object
   * awake, and every app shares one free Worker account (2026-11-23), so a hidden or forgotten tab
   * holds nothing. `onTake(got)` returning true ends the loop; `stopOn(err)` true ends it on a refusal.
   */
  function receive({ inbox, onTake, stopOn = () => false, onIdle = () => {}, doc = typeof document !== 'undefined' ? document : null,
                     timers = globalThis, now = () => Date.now(), idleMs = RECEIVE_IDLE_MS }) {
    let stopped = false;
    let wake = null;
    const visible = () => !doc || doc.visibilityState === 'visible';
    const rouse = () => { if (wake) { const w = wake; wake = null; w(); } };
    const onVisibility = () => { if (visible()) rouse(); };
    const stop = () => {
      if (stopped) return;
      stopped = true;
      if (doc) doc.removeEventListener('visibilitychange', onVisibility);
      rouse();
    };
    if (doc) doc.addEventListener('visibilitychange', onVisibility);
    (async () => {
      let active = now();
      let wait = 0;
      while (!stopped) {
        if (!visible()) {
          await new Promise((r) => { wake = r; });
          active = now();
          continue;
        }
        if (now() - active >= idleMs) { stop(); onIdle(); return; }
        try {
          const got = await inbox();
          wait = 0;
          if (stopped) break;
          if (got) {
            active = now();
            if (await onTake(got)) break;
          }
        } catch (err) {
          if (stopped || stopOn(err)) break;
          wait = Math.min(30000, wait ? wait * 2 : 2000);
          await new Promise((r) => timers.setTimeout(r, wait));
        }
      }
      stop();
    })();
    return { stop, stopped: () => stopped };
  }

  return { make, receive, delay, wording, stateOf, assignedLines, isLater, GAPS, RECEIVE_IDLE_MS };
})();
if (typeof module !== 'undefined') module.exports = RelayCore;
