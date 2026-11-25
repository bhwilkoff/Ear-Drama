/**
 * Productions on this browser (PLAYS-DESIGN §6, WEB-DESIGN §4.10): the one
 * module that writes a play's audio. Nothing is uploaded and no account is
 * needed (§8 rule 4); a shared production (phase 2, js/plays-share.js) keeps
 * its link to the Worker beside its record, and other members' takes are
 * written here only as their audio arrives for the listen-through.
 *
 * IndexedDB `ed-plays`, one `files` store keyed by path, laid out like
 * Apple's Plays/<production>/ folder:
 *   {id}/script.json        the script as cast, so a later catalog revision never changes a play
 *   {id}/production.json    the record (Apple's production.json, field for field)
 *   {id}/takes/{line}-{8}.wav   one 24-bit mono WAV per take, written with add(): never overwritten
 *   {id}/roomtone/roomtone-{8}.wav
 *   {id}/mix.wav            the rendered mix of a finished play, rebuilt when its takes change
 *   {id}/share.json         phase 2 only: the Worker's production id and the consent version agreed to
 * Version 2 (Decision 088.3) adds the object store `scripts`, the person's own scripts (js/own-store.js).
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
      async putAll(entries) { for (const [path, value] of entries) files.set(path, value); },
      async remove(path) { files.delete(path); },
      async removePrefix(prefix) { for (const k of [...files.keys()]) if (k.startsWith(prefix)) files.delete(k); },
      async keys(prefix = '') { return [...files.keys()].filter(k => k.startsWith(prefix)).sort(); },
    };
  }

  const VERSION = 2;
  /** Each version's change, in order; none touches a store an earlier one made. */
  function upgrade(db, from) {
    if (from < 1) db.createObjectStore('files');
    if (from < 2) db.createObjectStore('scripts');
  }
  /** One connection a database, shared by its object stores' backends. */
  const connections = new Map();
  function connect(name, idb) {
    if (connections.has(name)) return connections.get(name);
    const p = new Promise((resolve, reject) => {
      const req = idb.open(name, VERSION);
      let refused = false;
      req.onupgradeneeded = (e) => upgrade(req.result, e.oldVersion);
      // A tab still on an older version holds the upgrade back until it closes.
      req.onblocked = () => {
        refused = true;
        const err = new Error('another tab is open on an older version');
        err.kind = 'blocked';
        reject(err);
      };
      req.onsuccess = () => {
        const d = req.result;
        if (refused) { d.close(); return; }
        const gone = () => { if (connections.get(name) === p) connections.delete(name); };
        d.onversionchange = () => { gone(); d.close(); };
        d.onclose = gone;
        resolve(d);
      };
      req.onerror = () => reject(req.error);
    });
    connections.set(name, p);
    p.catch(() => { if (connections.get(name) === p) connections.delete(name); });
    return p;
  }

  function indexedDBBackend(name = 'ed-plays', storeName = 'files', idb = indexedDB) {
    const db = () => connect(name, idb);
    async function tx(mode, fn) {
      const d = await db();
      return new Promise((resolve, reject) => {
        const t = d.transaction(storeName, mode);
        let out;
        let failure = null;
        const req = fn(t.objectStore(storeName));
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
      /** Every entry or none: one transaction. */
      putAll: (entries) => tx('readwrite', s => { let req = null; for (const [path, value] of entries) req = s.put(value, path); return req; }),
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
    const pendingTakes = new Map();

    const folder = (id) => `${id}/`;
    const recordPath = (id) => `${id}/production.json`;
    const scriptPath = (id) => `${id}/script.json`;
    const takePath = (id, file) => `${id}/takes/${file}`;
    const roomTonePath = (id, file) => `${id}/roomtone/${file}`;
    const mixPath = (id) => `${id}/mix.wav`;
    const sharePath = (id) => `${id}/share.json`;
    const shares = new Map();

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
            await Promise.all(productions.map(async p => {
              const raw = await backend.get(sharePath(p.id)).catch(() => null);
              if (raw) { try { shares.set(p.id, JSON.parse(raw)); } catch { /* unreadable: not shared */ } }
            }));
            // An abandoned try never becomes a row (Decision 079, PLAYS-DESIGN §2.3 rule 3a).
            for (const p of productions.filter(x => C.isEmptyProduction(x) && !shares.has(x.id) && !pendingTakes.has(x.id))) {
              await store.delete(p.id).catch(() => {});
            }
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

      /** Phase 2: { pid, consented? } when this production is shared through the Worker. */
      share(id) { return shares.get(id) || null; },
      async setShare(id, link) {
        shares.set(id, link);
        await backend.put(sharePath(id), JSON.stringify(link));
      },
      async unshare(id) {
        shares.delete(id);
        await backend.remove(sharePath(id));
      },
      findShared(pid) { return productions.find(p => shares.get(p.id)?.pid === pid) || null; },

      /** Another member's take, as its audio arrived from the Worker; never overwrites a file. */
      async importTake(id, file, bytes) {
        const path = takePath(id, file);
        if ((await backend.get(path)) !== null) return;
        await backend.add(path, bytes instanceof ArrayBuffer ? bytes : bufferOf(new Uint8Array(bytes)));
      },

      /** A take being encoded and written for `id`: the production is not deleted until it settles (Decision 079). */
      trackTake(id, work) {
        const set = pendingTakes.get(id) || new Set();
        pendingTakes.set(id, set);
        const w = Promise.resolve(work).catch(() => {});
        set.add(w);
        w.then(() => { set.delete(w); if (!set.size) pendingTakes.delete(id); });
        return work;
      },
      pendingTakes(id) { const set = pendingTakes.get(id); return set ? set.size : 0; },
      async settled(id) {
        while (pendingTakes.has(id)) await Promise.all([...pendingTakes.get(id)]);
        await (writes.get(id) || Promise.resolve()).catch(() => {});
      },

      /** Deletes an abandoned try once its take writes have settled; never one held by a screen, shared, or with a take. */
      async discardIfAbandoned(id, held = () => false) {
        await store.settled(id);
        const left = store.production(id);
        if (!left || held() || !C.isEmptyProduction(left) || store.share(id) || store.pendingTakes(id)) return false;
        await store.delete(id);
        return true;
      },

      async delete(id) {
        await (writes.get(id) || Promise.resolve()).catch(() => {});
        await backend.removePrefix(folder(id));
        productions = productions.filter(p => p.id !== id);
        scripts.delete(id);
        shares.delete(id);
        writes.delete(id);
      },

      /** The lines of `scriptID` with a take in any production, read from what is kept (another tab may have recorded). */
      async takenLines(scriptID) {
        const out = new Set();
        for (const p of await store.productionsOf(scriptID)) for (const t of p.takes || []) out.add(t.lineID);
        return [...out];
      },
      async productionsOf(scriptID) {
        const keys = (await backend.keys()).filter(k => /^[^/]+\/production\.json$/.test(k));
        const all = await Promise.all(keys.map(async k => { try { return JSON.parse(await backend.get(k)); } catch { return null; } }));
        return all.filter(p => p && p.scriptID === scriptID);
      },

      /**
       * A changed own script reaches its productions here (PLAYS-DESIGN §13 item 5): each takes its lines
       * and revision, keeps its takes, and gains or loses parts with them. A shared one keeps its own text.
       */
      async adopt(script) {
        for (const found of await store.productionsOf(script.id)) {
          if (shares.has(found.id)) continue;
          await (writes.get(found.id) || Promise.resolve()).catch(() => {});
          const p = JSON.parse(await backend.get(recordPath(found.id)));
          const raw = await backend.get(scriptPath(p.id));
          const was = raw ? JSON.parse(raw) : { lines: [] };
          const parts = {};
          for (const part of C.castParts(script)) parts[part.id] = p.parts[part.id] || { status: 'open' };
          const next = { ...p, parts, title: script.title, scriptRevision: script.revision };
          const ids = (s) => s.lines.map(l => l.id).join(' ');
          if (ids(was) !== ids(script)) { next.listenedThrough = false; delete next.mixedFrom; }
          await backend.putAll([[scriptPath(p.id), JSON.stringify(script)], [recordPath(p.id), C.stableStringify(next)]]);
          scripts.delete(p.id);
          productions = productions.map(x => (x.id === p.id ? next : x));
        }
      },

      /** Every unchosen take (on `lineIDs` only, when given) and its file; returns how many went. */
      async discardUnusedTakes(id, lineIDs = null) {
        const p = store.production(id);
        if (!p) return 0;
        const { production, gone } = C.discardUnused(p, lineIDs);
        for (const t of gone) await backend.remove(takePath(id, t.file)).catch(() => {});
        await store.save(production);
        return gone.length;
      },

      /** One unchosen take and its file, the person's own act (PLAYS-DESIGN §2.9 rule 4); false when refused. */
      async deleteTake(id, takeID) {
        const p = store.production(id);
        if (!p) return false;
        const { production, gone } = C.deleteTake(p, takeID);
        if (!gone.length) return false;
        for (const t of gone) await backend.remove(takePath(id, t.file)).catch(() => {});
        await store.save(production);
        return true;
      },

      /** Discard the run (Run through's review): its takes and their files go, each line back to its prior take. */
      async discardRun(id, run) {
        const p = store.production(id);
        if (!p) return;
        const { production, gone } = C.discardRun(p, run);
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
