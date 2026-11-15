/**
 * The downloadable voice model's files (Decision 076 S6 spike; docs/research/design/R2-kokoro-feasibility.md).
 * PROTOTYPE, behind a flag: nothing here runs unless the page was opened with ?kokoro=1 (kept in
 * this browser until ?kokoro=0). Not in the service worker's shell, not shown to anyone else.
 *
 * The model is data, like the play library: fetched only when the person asks (the size shown
 * first), each file checked against the SHA-256 its manifest records, kept in Cache Storage,
 * and deletable. A manifest without a permissive license recorded for every file is refused.
 *
 * This file holds model bytes only and no audio path: js/plays.test.js scans it for one.
 */
const KokoroModel = (() => {
  'use strict';

  const FLAG = 'ed.kokoro';
  const CACHE = 'ed-kokoro-v1';
  const LICENSES = ['Apache-2.0', 'MIT', 'BSD-2-Clause', 'BSD-3-Clause'];
  const DEFAULT_MANIFEST = 'data/voices/kokoro/manifest.json';

  /** Whether the prototype is on in this browser: ?kokoro=1 turns it on, ?kokoro=0 off. */
  function enabled(search = (typeof location !== 'undefined' ? location.search : ''), storage = store()) {
    const q = new URLSearchParams(search || '').get('kokoro');
    try {
      if (q === '1' && storage) storage.setItem(FLAG, '1');
      if (q === '0' && storage) storage.removeItem(FLAG);
      return !!(storage && storage.getItem(FLAG) === '1');
    } catch { return q === '1'; }
  }
  function store() { try { return typeof localStorage !== 'undefined' ? localStorage : null; } catch { return null; } }

  /**
   * A manifest is accepted only when every file names a size, a SHA-256 and a license on the
   * permissive list. Returns { ok, reason }.
   */
  function accept(m) {
    if (!m || m.format !== 1 || !Array.isArray(m.files) || !m.files.length) return { ok: false, reason: 'no files' };
    for (const f of m.files) {
      if (!f || typeof f.path !== 'string' || !/^[\w./-]+$/.test(f.path) || f.path.includes('..')) return { ok: false, reason: 'bad path' };
      if (!Number.isInteger(f.bytes) || f.bytes <= 0) return { ok: false, reason: `${f.path}: no size` };
      if (!/^[0-9a-f]{64}$/.test(f.sha256 || '')) return { ok: false, reason: `${f.path}: no SHA-256` };
      if (!LICENSES.includes(f.license)) return { ok: false, reason: `${f.path}: license ${f.license || 'missing'} is not permissive` };
    }
    return { ok: true, reason: null };
  }
  const totalBytes = (m) => m.files.reduce((n, f) => n + f.bytes, 0);
  const sizeText = (bytes) => `${Math.round(bytes / 1e6)} MB`;

  async function sha256(buf) {
    const d = await crypto.subtle.digest('SHA-256', buf);
    return [...new Uint8Array(d)].map(b => b.toString(16).padStart(2, '0')).join('');
  }

  function create({ manifestURL = DEFAULT_MANIFEST, fetchImpl = (typeof fetch !== 'undefined' ? fetch.bind(globalThis) : null),
                    cachesImpl = (typeof caches !== 'undefined' ? caches : null) } = {}) {
    let manifest = null;
    let ready = false;
    const base = new URL(manifestURL, typeof location !== 'undefined' ? location.href : 'https://eardrama.org/');
    const urlOf = (f) => new URL(f.path, base).href;

    async function loadManifest() {
      if (manifest) return manifest;
      const r = await fetchImpl(base.href, { cache: 'no-cache' });
      if (!r.ok) throw new Error(`manifest ${r.status}`);
      const m = await r.json();
      const a = accept(m);
      if (!a.ok) throw new Error(`manifest refused: ${a.reason}`);
      manifest = m;
      return m;
    }

    return {
      loadManifest,
      /** Whether every file is downloaded and checked. */
      async check() {
        if (!cachesImpl) return false;
        const m = await loadManifest().catch(() => null);
        if (!m) return false;
        const c = await cachesImpl.open(CACHE);
        for (const f of m.files) if (!(await c.match(urlOf(f)))) { ready = false; return false; }
        ready = true;
        return true;
      },
      isReady: () => ready,
      /** The person's explicit download: each file fetched, checked against its SHA-256, kept. */
      async download(onProgress = () => {}) {
        const m = await loadManifest();
        const c = await cachesImpl.open(CACHE);
        const total = totalBytes(m);
        let done = 0;
        for (const f of m.files) {
          if (await c.match(urlOf(f))) { done += f.bytes; onProgress(done, total); continue; }
          const r = await fetchImpl(urlOf(f));
          if (!r.ok || !r.body) throw new Error(`${f.path}: ${r.status}`);
          const reader = r.body.getReader();
          const parts = [];
          for (;;) {
            const { value, done: end } = await reader.read();
            if (end) break;
            parts.push(value);
            done += value.byteLength;
            onProgress(done, total);
          }
          const buf = new Uint8Array(parts.reduce((n, p) => n + p.byteLength, 0));
          let at = 0;
          for (const p of parts) { buf.set(p, at); at += p.byteLength; }
          if (buf.byteLength !== f.bytes || (await sha256(buf)) !== f.sha256) throw new Error(`${f.path}: checksum mismatch`);
          await c.put(urlOf(f), new Response(buf, { headers: { 'content-type': 'application/octet-stream' } }));
        }
        ready = true;
      },
      /** A downloaded file's bytes (the model, a voice table), for the worker. */
      async bytes(role) {
        const m = await loadManifest();
        const f = m.files.find(x => x.role === role);
        const c = await cachesImpl.open(CACHE);
        const r = f && await c.match(urlOf(f));
        return r ? r.arrayBuffer() : null;
      },
      manifest: () => manifest,
      async remove() { ready = false; if (cachesImpl) await cachesImpl.delete(CACHE); },
    };
  }

  return { FLAG, CACHE, LICENSES, enabled, accept, totalBytes, sizeText, create };
})();
