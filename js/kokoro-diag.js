/**
 * The Kokoro voices' stage log (?diag=kokoro): an overlay of every stage the engine passes (manifest,
 * each cached part, the model handed to the worker, the execution provider, the session, the self-test,
 * each render's time, the AudioContext's state around each line, errors), kept in localStorage as it
 * happens, so a tab the system kills mid-load shows its last stage on the reload. Off unless the page is
 * opened with ?diag=kokoro (kept until ?diag=0); every call is a no-op then. Diagnostics, not a feature:
 * it never shows in an ordinary session.
 *
 * Holds stage names and numbers only: no audio, no words of a play.
 */
const KokoroDiag = (() => {
  'use strict';

  const KEY = 'ed.kokoro.diag';
  const ON = 'ed.kokoro.diag.on';
  const MAX = 80;
  const t0 = Date.now();
  const store = () => { try { return typeof localStorage !== 'undefined' ? localStorage : null; } catch { return null; } };

  function enabled() {
    if (typeof location === 'undefined') return false;
    const q = new URLSearchParams(location.search).get('diag');
    const s = store();
    try {
      if (q === 'kokoro' && s) s.setItem(ON, '1');
      if (q === '0' && s) s.removeItem(ON);
      return q === 'kokoro' || !!(s && s.getItem(ON) === '1');
    } catch { return q === 'kokoro'; }
  }
  const on = enabled();

  let previous = [];
  let trail = [];
  let box = null;
  let list = null;
  const actions = [];

  /** What the browser will say about memory (Chrome only; Safari says nothing). */
  function memory() {
    const out = {};
    try { if (performance.memory) out.heapMB = Math.round(performance.memory.usedJSHeapSize / 1e6); } catch { /* none */ }
    try { if (navigator.deviceMemory) out.deviceGB = navigator.deviceMemory; } catch { /* none */ }
    return out;
  }

  function mark(stage, data) {
    if (!on) return;
    const row = { s: Math.round((Date.now() - t0) / 100) / 10, stage, ...(data || {}), ...memory() };
    trail.push(row);
    if (trail.length > MAX) trail.shift();
    try { const s = store(); if (s) s.setItem(KEY, JSON.stringify({ at: t0, ua: navigator.userAgent, trail })); } catch { /* full */ }
    try { console.log('[kokoro-diag]', JSON.stringify(row)); } catch { /* none */ }
    paint();
  }

  const line = (r) => {
    const { s, stage, ...rest } = r;
    const kv = Object.entries(rest).map(([k, v]) => `${k}=${typeof v === 'number' ? Math.round(v * 100) / 100 : v}`).join(' ');
    return `${String(s).padStart(5)}s ${stage}${kv ? ` ${kv}` : ''}`;
  };

  function paint() {
    if (!on || !list || typeof document === 'undefined') return;
    const rows = [];
    if (previous.length) {
      rows.push('-- last session --');
      rows.push(...previous.slice(-8).map(line));
      rows.push('-- this session --');
    }
    rows.push(...trail.slice(-24).map(line));
    list.textContent = rows.join('\n');
    list.scrollTop = list.scrollHeight;
  }

  /** A button on the overlay; `fn` runs inside the tap (a user gesture). */
  function action(label, fn) {
    if (!on) return;
    actions.push([label, fn]);
    if (box) addButton(label, fn);
  }
  function addButton(label, fn) {
    const b = document.createElement('button');
    b.type = 'button';
    b.textContent = label;
    b.style.cssText = 'font:600 15px system-ui;padding:10px 14px;margin:0 8px 8px 0;border-radius:8px;border:0;background:#fff;color:#000';
    b.addEventListener('click', () => { mark('tap', { action: label }); try { fn(); } catch (e) { mark('error', { where: label, msg: String(e && e.message || e) }); } });
    box.querySelector('[data-actions]').append(b);
  }

  function mount() {
    if (!on || typeof document === 'undefined' || box) return;
    box = document.createElement('div');
    box.setAttribute('data-kokoro-diag', '');
    box.style.cssText = 'position:fixed;left:8px;right:8px;bottom:calc(env(safe-area-inset-bottom) + 72px);z-index:2147483647;'
      + 'background:rgba(0,0,0,.86);color:#9f9;border-radius:10px;padding:8px;max-height:52vh;display:flex;flex-direction:column';
    const acts = document.createElement('div');
    acts.setAttribute('data-actions', '');
    list = document.createElement('pre');
    list.style.cssText = 'margin:0;font:11px/1.35 ui-monospace,Menlo,monospace;white-space:pre-wrap;overflow:auto;flex:1';
    box.append(acts, list);
    document.body.append(box);
    for (const [l, f] of actions) addButton(l, f);
    paint();
  }

  if (on) {
    try {
      const kept = JSON.parse((store() && store().getItem(KEY)) || 'null');
      if (kept && Array.isArray(kept.trail)) previous = kept.trail;
    } catch { previous = []; }
    if (typeof window !== 'undefined') {
      window.addEventListener('error', (e) => mark('error', { msg: String(e.message || e.error || 'error').slice(0, 160) }));
      window.addEventListener('unhandledrejection', (e) => mark('rejection', { msg: String((e.reason && e.reason.message) || e.reason).slice(0, 160) }));
      window.addEventListener('pagehide', () => mark('pagehide'));
    }
    if (typeof document !== 'undefined') {
      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount); else mount();
    }
    mark('page', { prevLast: previous.length ? previous[previous.length - 1].stage : 'none', gpu: !!(typeof navigator !== 'undefined' && navigator.gpu),
                   secure: typeof isSecureContext === 'undefined' ? 'n/a' : isSecureContext });
    /* global Voices, KokoroVoice */
    const PLAY = 'gut-59770-105';
    const gate = () => (typeof Voices !== 'undefined' ? Voices.shared() : null);
    /** Runs the engine with nothing played: the download if it is not here, else the self-test again. */
    const runEngine = () => {
      const g = gate();
      if (!g) return mark('error', { msg: 'no Voices' });
      const st = g.status();
      mark('engine', { status: st });
      if (['absent', 'failed'].includes(st)) g.download(); else g.recheck();
    };
    action('Engine', runEngine);
    action('Read 3 lines', async () => {
      const e = typeof KokoroVoice !== 'undefined' ? KokoroVoice.engine() : null;
      if (!e) return mark('error', { msg: 'no engine (model not downloaded?)' });
      await KokoroVoice.prepare({ id: PLAY, kind: 'stage' });
      let rows = [];
      try { rows = ((await (await fetch(`data/plays/library/phonemes/${PLAY}.json`)).json()).lines || []).slice(0, 3); } catch (err) { mark('error', { msg: String(err) }); }
      for (const [i, r] of rows.entries()) {
        const read = await e.speak(r.t, 'af_heart');
        mark('line', { i, read });
      }
      mark('read-done');
    });
    action('Clear log', () => { trail = []; previous = []; try { const s = store(); if (s) s.removeItem(KEY); } catch { /* none */ } paint(); });
    if (typeof window !== 'undefined') {
      window.addEventListener('load', () => {
        const g = gate();
        let last = '';
        if (g) g.onChange(() => {
          const now = `${g.status()} ${Math.floor(g.progress().done / 50e6) * 50}`;
          if (now !== last) { last = now; mark('status', { status: g.status(), MB: Math.round(g.progress().done / 1e6) }); }
        });
        if (new URLSearchParams(location.search).get('auto') === '1') setTimeout(() => (g ? g.whenStarted() : Promise.resolve()).then(runEngine), 1500);
      });
    }
  }

  return { on, mark, action, previous: () => previous.slice(), trail: () => trail.slice() };
})();
