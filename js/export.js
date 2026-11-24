/**
 * Export (Human-Shaped principle 11): a person's own listening history, follows, queue, takes list,
 * and script marks (PLAYS-DESIGN §2.10) as a JSON file, and the history as CSV. Built here from what the device holds; nothing is
 * sent anywhere. The same keys on every platform (docs/EXPORT.md).
 */
const DataExport = (() => {
  'use strict';

  const iso = (ms) => (ms ? new Date(ms).toISOString() : null);

  /**
   * `store` is Store; `productions` is the plays store's productions (records only, never audio);
   * `marks` is MarksCore.exportRows(localStorage), every play's marks on this device; `scripts` is
   * OwnScripts.exportRows(), the scripts the person added (PLAYS-DESIGN §13).
   */
  function build(store, productions = [], now = Date.now(), marks = [], scripts = []) {
    const positions = (id) => store.position(id) || {};
    return {
      app: 'Ear Drama',
      format: 1,
      exportedAt: iso(now),
      history: store.history().map(h => ({
        episode: h.id, title: h.title, series: h.series, seriesName: h.seriesName, airDate: h.date || null,
        listenedAt: iso(h.at), positionSeconds: positions(h.id).t ?? null, durationSeconds: positions(h.id).d ?? null,
      })),
      following: store.follows().map(f => ({ series: f.key, name: f.name })),
      queue: store.queue().map((q, i) => ({
        position: i + 1, episode: q.id, title: q.title, series: q.series, seriesName: q.seriesName, airDate: q.date || null,
      })),
      takes: productions.map(p => ({
        production: p.id, title: p.title, created: iso(p.created),
        takes: (p.takes || []).map(t => ({ ...t, chosen: (p.chosen || {})[t.lineID] === t.id })),
      })),
      marks: marks.map(m => ({ ...m })),
      scripts: scripts.map(s => ({ ...s })),
    };
  }

  const cell = (v) => {
    const s = v === null || v === undefined ? '' : String(v);
    return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };

  const HISTORY_COLUMNS = ['episode', 'title', 'seriesName', 'airDate', 'listenedAt', 'positionSeconds', 'durationSeconds'];

  function historyCsv(data) {
    const rows = [HISTORY_COLUMNS, ...data.history.map(h => HISTORY_COLUMNS.map(c => h[c]))];
    return rows.map(r => r.map(cell).join(',')).join('\r\n') + '\r\n';
  }

  /** The browser's own save: a file the person keeps. */
  function save(name, type, text) {
    const url = URL.createObjectURL(new Blob([text], { type }));
    const a = document.createElement('a');
    a.href = url; a.download = name;
    document.body.append(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  return { build, historyCsv, save };
})();
if (typeof module !== 'undefined') module.exports = DataExport;
