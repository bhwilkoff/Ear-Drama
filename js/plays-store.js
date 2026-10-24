/**
 * Productions on this browser (PLAYS-DESIGN §6, WEB-DESIGN §4.10): the one
 * module that writes a play's audio. Nothing is uploaded and no account is
 * needed (§8 rule 4).
 *
 * IndexedDB `ed-plays`, one `files` store keyed by path, laid out like
 * Apple's Plays/<production>/ folder:
 *   {id}/script.json        the script as cast, so a later catalog revision never changes a play
 *   {id}/production.json    the record (Apple's production.json, field for field)
 *   {id}/takes/{line}-{8}.wav   one 24-bit mono WAV per take, written with add(): never overwritten
 *   {id}/roomtone/roomtone-{8}.wav
 *   {id}/mix.wav            the rendered mix of a finished play, rebuilt when its takes change
 * Audio is stored as ArrayBuffers, which every browser's IndexedDB keeps.
 * Writers take only microphone captures ({ samples, sampleRate }) or the
 * rendered mix; the device voice has no samples to give (js/plays-voice.js).
 */
const PlayStore = (() => {
  'use strict';
  const C = PlaysCore;

  /** The backend the tests use, and the fallback where IndexedDB is missing. */
  function memoryBackend() {
    const files = new Map();
    return {
      files,
      async add(path, value) {
        if (files.has(path)) throw new Error(`exists: ${path}`);
        files.set(path, value);
      },
      async put(path, value) { files.set(path, value); },
      async get(path) { return files.has(path) ? files.get(path) : null; },
      async remove(path) { files.delete(path); },
      async removePrefix(prefix) { for (const k of [...files.keys()]) if (k.startsWith(prefix)) files.delete(k); },
      async keys(prefix = '') { return [...files.keys()].filter(k => k.startsWith(prefix)).sort(); },
    };
  }

  function indexedDBBackend(name = 'ed-plays') {
    let dbP = null;
    function db() {
      if (!dbP) {
        dbP = new Promise((resolve, reject) => {
          const req = indexedDB.open(name, 1);
          req.onupgradeneeded = () => req.result.createObjectStore('files');
          req.onsuccess = () => resolve(req.result);
          req.onerror = () => reject(req.error);
        });
        dbP.catch(() => { dbP = null; });
      }
      return dbP;
    }
    async function tx(mode, fn) {
      const d = await db();
      return new Promise((resolve, reject) => {
        const t = d.transaction('files', mode);
        let out;
        let failure = null;
        const req = fn(t.objectStore('files'));
        if (req) {
          req.onsuccess = () => { out = req.result; };
          req.onerror = () => { failure = req.error; };
        }
        t.oncomplete = () => resolve(out);
        // A refused add() aborts the transaction; the request's error says why.
        t.onerror = () => reject(failure || t.error || new Error('IndexedDB error'));
        t.onabort = () => reject(failure || t.error || new Error('IndexedDB transaction aborted'));
      });
    }
    const range = (prefix) => IDBKeyRange.bound(prefix, `${prefix}￿`);
    return {
      add: (path, value) => tx('readwrite', s => s.add(value, path)),
      put: (path, value) => tx('readwrite', s => s.put(value, path)),
      get: async (path) => { const v = await tx('readonly', s => s.get(path)); return v === undefined ? null : v; },
      remove: (path) => tx('readwrite', s => s.delete(path)),
      removePrefix: (prefix) => tx('readwrite', s => s.delete(range(prefix))),
      keys: async (prefix = '') => (await tx('readonly', s => s.getAllKeys(range(prefix)))) || [],
    };
  }

  const bufferOf = (bytes) => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  const short = () => C.uuid().replace(/-/g, '').slice(0, 8);

  function open(backend = (typeof indexedDB !== 'undefined' ? indexedDBBackend() : memoryBackend())) {
    let productions = [];
    let loaded = null;
    const scripts = new Map();
    const writes = new Map();

    const folder = (id) => `${id}/`;
    const recordPath = (id) => `${id}/production.json`;
    const scriptPath = (id) => `${id}/script.json`;
    const takePath = (id, file) => `${id}/takes/${file}`;
    const roomTonePath = (id, file) => `${id}/roomtone/${file}`;
    const mixPath = (id) => `${id}/mix.wav`;

    const store = {
      backend,
      lastError: null,
      get productions() { return productions; },
      production(id) { return productions.find(p => p.id === id) || null; },

      load() {
        if (!loaded) {
          loaded = (async () => {
            const keys = await backend.keys();
            const records = await Promise.all(keys.filter(k => /^[^/]+\/production\.json$/.test(k)).map(async k => {
              try { return JSON.parse(await backend.get(k)); } catch { return null; }
            }));
            productions = records.filter(Boolean).sort((a, b) => b.created - a.created);
            return productions;
          })();
          loaded.catch(() => { loaded = null; });
        }
        return loaded;
      },

      async create(script) {
        const p = C.newProduction(script);
        await backend.put(scriptPath(p.id), JSON.stringify(script));
        scripts.set(p.id, script);
        await store.save(p);
        return p;
      },

      /** The script as cast, read back from the production's own record. */
      async script(p) {
        if (!scripts.has(p.id)) {
          const raw = await backend.get(scriptPath(p.id));
          if (raw === null) return null;
          scripts.set(p.id, JSON.parse(raw));
        }
        return scripts.get(p.id);
      },

      /** The in-memory record changes now; its write follows in order, one per production. */
      save(p) {
        const i = productions.findIndex(x => x.id === p.id);
        if (i >= 0) productions[i] = p; else productions.unshift(p);
        const text = C.stableStringify(p);
        const prev = writes.get(p.id) || Promise.resolve();
        const w = prev.catch(() => {}).then(() => backend.put(recordPath(p.id), text));
        writes.set(p.id, w);
        return w;
      },

      /** Saves, keeping the error for the screen rather than throwing into a view. */
      update(p) {
        const w = store.save(p);
        w.then(() => { store.lastError = null; }, (e) => { store.lastError = e.message || String(e); });
        return w;
      },

      async delete(id) {
        await (writes.get(id) || Promise.resolve()).catch(() => {});
        await backend.removePrefix(folder(id));
        productions = productions.filter(p => p.id !== id);
        scripts.delete(id);
        writes.delete(id);
      },

      async discardUnusedTakes(id) {
        const p = store.production(id);
        if (!p) return;
        const { production, gone } = C.discardUnused(p);
        for (const t of gone) await backend.remove(takePath(id, t.file)).catch(() => {});
        await store.save(production);
      },

      /** Writes a take file that never existed before (takes are never overwritten). */
      async writeTake(capture, p, lineID) {
        const file = `${lineID}-${short()}.wav`;
        await backend.add(takePath(p.id, file), bufferOf(C.encodeWav(capture.samples, capture.sampleRate, 24)));
        return file;
      },

      async writeRoomTone(capture, p) {
        const file = `roomtone-${short()}.wav`;
        await backend.add(roomTonePath(p.id, file), bufferOf(C.encodeWav(capture.samples, capture.sampleRate, 24)));
        return file;
      },

      /** A take's WAV bytes. */
      async readTake(id, file) {
        const raw = await backend.get(takePath(id, file));
        if (raw === null) throw new Error(`missing take ${file}`);
        return raw;
      },

      /**
       * Renders mix.wav from the chosen takes when every speaking line has one
       * (§2.7) and records which takes it was made from. A partial play throws
       * MixFailure('incomplete') and writes nothing.
       */
      async renderMix(id, makeContext) {
        const p = store.production(id);
        const script = p && await store.script(p);
        if (!p || !script) throw new Error('production not found');
        const from = C.fingerprint(p);
        if (p.mixedFrom === from) {
          const existing = await backend.get(mixPath(id));
          if (existing !== null) return new Blob([existing], { type: 'audio/wav' });
        }
        const timeline = C.buildTimeline(script, p);
        const blob = await C.renderMix(timeline,
          async (placement) => C.decodeWav(await store.readTake(id, placement.file)).samples, makeContext);
        await backend.put(mixPath(id), await blob.arrayBuffer());
        const latest = store.production(id);
        if (latest) await store.save({ ...latest, mixedFrom: from });
        return blob;
      },

      /** Someone listened from the top to the end: the play is finished (§2.7). */
      async markListenedThrough(id, from) {
        const p = store.production(id);
        if (!p || C.fingerprint(p) !== from) return;
        await store.save({ ...p, listenedThrough: true });
      },

      /**
       * Export is the person's own act (§2.7): a download of the mix whenever every
       * speaking line is human (owner 2026-10-23), rendered first if missing or stale.
       * Refused otherwise (§5 rule 4).
       */
      async exportMix(id, makeContext) {
        const p = store.production(id);
        const script = p && await store.script(p);
        if (!p || !script || !C.isComplete(p, script)) throw new C.MixFailure('unfinished');
        const blob = await store.renderMix(id, makeContext);
        const a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = `${p.title.replace(/[\\/:*?"<>|]+/g, '').trim() || 'Play'}.wav`;
        document.body.append(a);
        a.click();
        a.remove();
        setTimeout(() => URL.revokeObjectURL(a.href), 60000);
      },
    };
    return store;
  }

  return { open, memoryBackend, indexedDBBackend };
})();
