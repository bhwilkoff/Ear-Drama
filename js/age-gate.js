/**
 * The neutral age question (Decision 084, PLAYS-DESIGN §12.12; owner 2026-11-21): before a first
 * share, invite, joining by invite, or publish outside a class, a birth year with no default. Only
 * "under 13 or not" is kept, on this device, never sent; an under-13 answer keeps sharing off here.
 *
 * A year alone cannot tell a 12-year-old from a 13-year-old born the same year, so that year counts
 * as under 13 (the safer reading of a year-only answer).
 */
const AgeGate = (() => {
  'use strict';
  const KEY = 'ed.over13';
  const OLDEST = 120;

  /** True when someone born in `birthYear` may be under 13 in `year`. */
  const isUnder13 = (birthYear, year) => year - birthYear <= 13;

  function stored() {
    try { const v = localStorage.getItem(KEY); return v === '1' ? true : v === '0' ? false : null; } catch { return null; }
  }
  function keep(over13) { try { localStorage.setItem(KEY, over13 ? '1' : '0'); } catch { /* asked again next time */ } }

  /** The years to pick from, newest first. */
  const years = (year) => Array.from({ length: OLDEST }, (_, i) => year - i);

  /** Resolves true when sharing may go on; asks once per device. `h` is the app's helpers (el). */
  function ask(h) {
    const known = stored();
    if (known === true) return Promise.resolve(true);
    if (known === false) { refuse(h); return Promise.resolve(false); }
    return new Promise((resolve) => {
      const year = new Date().getFullYear();
      const sel = h.el('select', { class: 'field-input', id: 'age-year', 'aria-label': 'Year you were born' },
        h.el('option', { value: '', selected: true, disabled: true }, 'Year'),
        ...years(year).map((y) => h.el('option', { value: String(y) }, String(y))));
      const go = h.el('button', { type: 'submit', class: 'btn btn-primary', disabled: true }, 'Continue');
      sel.addEventListener('change', () => { go.disabled = !sel.value; });
      let done = false;
      const d = h.el('dialog', { class: 'account-sheet age-sheet', 'aria-labelledby': 'age-h' });
      const finish = (v) => { if (done) return; done = true; resolve(v); };
      d.addEventListener('close', () => { d.remove(); finish(false); });
      d.append(h.el('form', { method: 'dialog', onsubmit: (e) => {
        e.preventDefault();
        if (!sel.value) return;
        const over = !isUnder13(Number(sel.value), year);
        keep(over);
        finish(over);
        d.close();
        if (!over) refuse(h);
      } },
      h.el('h2', { id: 'age-h', class: 'section-header' }, 'What year were you born?'),
      sel,
      h.el('div', { class: 'actions' }, go),
      h.el('div', { class: 'actions' }, h.el('button', { type: 'button', class: 'btn btn-ghost', onclick: () => d.close() }, 'Cancel'))));
      document.body.append(d);
      d.showModal();
    });
  }

  function refuse(h) {
    const d = h.el('dialog', { class: 'account-sheet age-sheet', role: 'alertdialog', 'aria-labelledby': 'age-no' });
    d.addEventListener('close', () => d.remove());
    d.append(h.el('p', { id: 'age-no', class: 'body-strong' }, 'Sharing is for 13 and over. Your teacher can add you to a class.'),
      h.el('div', { class: 'actions' }, h.el('button', { type: 'button', class: 'btn', onclick: () => d.close() }, 'OK')));
    document.body.append(d);
    d.showModal();
  }

  return { isUnder13, ask, stored, KEY };
})();
if (typeof module !== 'undefined') module.exports = AgeGate;
