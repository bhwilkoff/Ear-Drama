/**
 * The downloadable voice model's files (Decision 076 S6 spike; docs/research/design/R2-kokoro-feasibility.md).
 * Loaded on demand by js/voices.js (Decision 086): only when the person downloads the voices in
 * Settings > Voices, or when they are already downloaded; never in the service worker's shell.
 *
 * The model is data, like the play library: fetched only when the person asks (the size shown
 * first), each file checked against the SHA-256 its manifest records, kept in Cache Storage,
 * and deletable. A manifest without a permissive license recorded for every file is refused.
 * A file too large for the site (the 326 MB fp32 model; Pages refuses files over 100 MB) is served
 * in `parts` under 50 MB (tools/fetch_kokoro_model.py): each part is checked and kept on its own,
 * so a broken download resumes at the part it lost, and the whole is checked once assembled.
 *
 * This file holds model bytes only and no audio path: js/plays.test.js scans it for one.
 */
const KokoroModel = (() => {
  'use strict';

  const CACHE = 'ed-kokoro-v1';
  const LICENSES = ['Apache-2.0', 'MIT', 'BSD-2-Clause', 'BSD-3-Clause'];
  const DEFAULT_MANIFEST = 'data/kokoro/manifest.json';

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
      if (f.parts !== undefined) {
        if (!Array.isArray(f.parts) || !f.parts.length) return { ok: false, reason: `${f.path}: no parts` };
        for (const p of f.parts) {
          if (!p || typeof p.path !== 'string' || !/^[\w./-]+$/.test(p.path) || p.path.includes('..')) return { ok: false, reason: `${f.path}: bad part path` };
          if (!Number.isInteger(p.bytes) || p.bytes <= 0 || !/^[0-9a-f]{64}$/.test(p.sha256 || '')) return { ok: false, reason: `${p.path}: no size or SHA-256` };
        }
        if (f.parts.reduce((n, p) => n + p.bytes, 0) !== f.bytes) return { ok: false, reason: `${f.path}: parts do not add up` };
      }
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
    const piecesOf = (f) => f.parts || [f];
    const join = (bufs) => {
      const out = new Uint8Array(bufs.reduce((n, b) => n + b.byteLength, 0));
      let at = 0;
      for (const b of bufs) { out.set(new Uint8Array(b), at); at += b.byteLength; }
      return out;
    };
    async function cachedBytes(c, f) {
      const bufs = [];
      for (const p of piecesOf(f)) {
        const r = await c.match(urlOf(p));
        if (!r) return null;
        bufs.push(await r.arrayBuffer());
      }
      return bufs.length === 1 ? new Uint8Array(bufs[0]) : join(bufs);
    }

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
        for (const f of m.files) for (const p of piecesOf(f)) if (!(await c.match(urlOf(p)))) { ready = false; return false; }
        ready = true;
        return true;
      },
      isReady: () => ready,
      /** The person's explicit download: each file fetched, checked against its SHA-256, kept. */
      async download(onProgress = () => {}, signal = null) {
        const m = await loadManifest();
        const c = await cachesImpl.open(CACHE);
        const total = totalBytes(m);
        let done = 0;
        for (const f of m.files) {
          for (const p of piecesOf(f)) {
            if (await c.match(urlOf(p))) { done += p.bytes; onProgress(done, total); continue; }
            // Cancel stops at once; every part already checked stays, so Download again resumes there.
            const r = await fetchImpl(urlOf(p), signal ? { signal } : undefined);
            if (!r.ok || !r.body) throw new Error(`${p.path}: ${r.status}`);
            const reader = r.body.getReader();
            const chunks = [];
            for (;;) {
              if (signal && signal.aborted) { try { await reader.cancel(); } catch { /* already closed */ } throw new DOMException('cancelled', 'AbortError'); }
              const { value, done: end } = await reader.read();
              if (end) break;
              chunks.push(value);
              done += value.byteLength;
              onProgress(done, total);
            }
            const buf = join(chunks);
            if (buf.byteLength !== p.bytes || (await sha256(buf)) !== p.sha256) throw new Error(`${p.path}: checksum mismatch`);
            await c.put(urlOf(p), new Response(buf, { headers: { 'content-type': 'application/octet-stream' } }));
          }
          if (f.parts) {
            const whole = await cachedBytes(c, f);
            if (!whole || whole.byteLength !== f.bytes || (await sha256(whole)) !== f.sha256) {
              for (const p of f.parts) await c.delete(urlOf(p));
              throw new Error(`${f.path}: the assembled parts do not match`);
            }
          }
        }
        ready = true;
      },
      /** A downloaded file's bytes (the model, a voice table), for the worker. */
      async bytes(role) {
        const m = await loadManifest();
        const f = m.files.find(x => x.role === role);
        const c = await cachesImpl.open(CACHE);
        const b = f && await cachedBytes(c, f);
        return b ? b.buffer : null;
      },
      manifest: () => manifest,
      async remove() { ready = false; if (cachesImpl) await cachesImpl.delete(CACHE); },
    };
  }

  return { CACHE, LICENSES, accept, totalBytes, sizeText, create };
})();
