/**
 * Better voices at first launch (PLAYS-DESIGN §2.8 rule 13, Decision 090, WEB-DESIGN §4.11b).
 *
 * One skippable sheet, offered once when the page first starts and, if skipped, once more the first
 * time a script is opened to read, cast or record; never after that, and never once a download has
 * begun. It draws Library > Voices' own Kokoro control (VoiceSettings.paintKokoro), so the size,
 * progress, Cancel and failure are one code path. Offered only where that download is offered now
 * (Voices.offered(): a WebGPU adapter, not refused, not here); nothing to offer, no sheet.
 *
 * The record is one number in this browser (`ed.voicesStep`): 0 never offered, 1 offered at launch,
 * 2 done. ?onboard=0 keeps the sheet away; ?voices_step=1 shows it at launch and reads and writes
 * nothing.
 */
const VoicesStep = (() => {
  'use strict';
  const KEY = 'ed.voicesStep';
  const BEGUN = ['downloading', 'checking', 'ready', 'refused'];

  function store() { try { return typeof localStorage !== 'undefined' ? localStorage : null; } catch { return null; } }
  function stageOf(storage) {
    try { const n = Number(storage && storage.getItem(KEY)); return n === 1 || n === 2 ? n : 0; } catch { return 0; }
  }

  /**
   * What a moment ('launch' or 'use') does: { show, next }. A forced session (the door) shows at launch
   * only and never moves the record; a skip door shows nothing.
   */
  function decide({ moment, stage, eligible, skip = false, forced = false }) {
    if (skip) return { show: false, next: stage };
    if (forced) return { show: moment === 'launch', next: stage };
    if (!eligible) return { show: false, next: stage };
    if (moment === 'launch') return stage === 0 ? { show: true, next: 1 } : { show: false, next: stage };
    return stage < 2 ? { show: true, next: 2 } : { show: false, next: stage };
  }

  function create({ storage = store(), search = (typeof location !== 'undefined' ? location.search : ''),
                    voices, present = sheet, tv = false } = {}) {
    const q = new URLSearchParams(search || '');
    const skip = tv || q.get('onboard') === '0';
    const forced = !skip && q.get('voices_step') === '1';
    let chain = Promise.resolve();
    let shown = false;
    const write = (n) => { if (forced) return; try { if (storage) storage.setItem(KEY, String(n)); } catch { /* unkept: offered again */ } };
    // A download begun anywhere (this sheet or Library) ends the offers.
    if (voices && voices.onChange) voices.onChange(() => { if (BEGUN.includes(voices.status())) write(2); });

    async function eligible() {
      try {
        await voices.whenStarted();
        await voices.probe();
        return voices.offered() && voices.status() !== 'probing';
      } catch { return false; }
    }
    function offer(moment) {
      chain = chain.then(async () => {
        if (shown || skip) return false;
        const stage = forced ? 0 : stageOf(storage);
        const d = decide({ moment, stage, eligible: forced || await eligible(), skip, forced });
        if (d.next !== stage) write(d.next);
        if (!d.show) return false;
        shown = true;
        present(voices);
        return true;
      }).catch((e) => { console.error('voices step', e); return false; });
      return chain;
    }
    return {
      /** Page start, once the first route is drawn. */
      launch: () => offer('launch'),
      /** The reader, a production (its cast and recorder) or a cast by ear opened. */
      firstUse: () => offer('use'),
      stage: () => stageOf(storage),
    };
  }

  /** The sheet: heading, the one fact, the Kokoro control, Not now (Done once the voices are here). */
  function sheet(h) {
    const { el } = CastUI;
    const ctl = el('div', { class: 'vs-hifi', 'aria-live': 'polite' });
    const close = el('button', { type: 'button', class: 'btn btn-ghost vstep-close', autofocus: '' }, 'Not now');
    const d = el('dialog', { id: 'voices-step', class: 'rd-sheet vstep', 'aria-labelledby': 'vstep-h' },
      el('h2', { id: 'vstep-h', class: 'section-header' }, 'Better voices'),
      el('p', { class: 'body vstep-fact' }, 'Downloaded voices read the parts nobody has cast.'),
      ctl,
      el('div', { class: 'actions vstep-actions' }, close));
    close.addEventListener('click', () => d.close());
    const paint = () => {
      VoiceSettings.paintKokoro(ctl, h, paint);
      const ready = h.status() === 'ready';
      close.textContent = ready ? 'Done' : 'Not now';
      close.classList.toggle('btn-primary', ready);
      close.classList.toggle('btn-ghost', !ready);
    };
    const off = h.onChange(paint);
    d.addEventListener('click', (e) => { if (e.target === d) d.close(); });
    d.addEventListener('close', () => { off(); d.remove(); });
    document.body.append(d);
    paint();
    d.showModal();
    return d;
  }

  let page = null;
  const shared = (opts) => { if (!page) page = create(opts); return page; };

  return { KEY, decide, create, shared, stageOf };
})();
