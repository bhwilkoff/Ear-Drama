/**
 * Shared plays, phase 2 (LOOP-PLAN M8, PLAYS-DESIGN §11.7, WEB-DESIGN §4.10a):
 * a production in this browser, linked to its record on the Worker. No DOM;
 * js/plays-ui.js draws it; js/plays-share.test.js runs it against a stub Worker.
 *
 * The Worker is the arbiter (C7): who holds which part, which take is chosen.
 * Any open part may be claimed while none records; `next` is only the
 * suggestion. Nothing here decides a claim; it asks and shows the answer.
 * Takes are recorded in this browser exactly as phase 1 records them, then
 * uploaded: only the chosen take of each line of a part this person holds,
 * never one the bleed check flagged (it holds the device voice, §5). A take
 * reaches only the members, so uploading asks no consent (Decision 072); the
 * CC0 consent comes before Publish, and Publish waits for the Worker to reach archive.org.
 */
const PlaysShare = (() => {
  'use strict';
  const C = PlaysCore;
  const INVITE_KEY = 'ed.invite';
  const clone = (o) => JSON.parse(JSON.stringify(o));

  /** The cast sheet the Worker checks against its manifest: every line in script order. */
  const castSheet = (script) => script.lines.map(l => ({ id: l.id, part: C.linePart(l) }));

  const isMine = (rec, part, me) => {
    const s = rec.parts[part];
    return !!s && s.status === 'recording' && !!me && s.user_id === me;
  };
  const recordingPart = (rec) => Object.keys(rec.parts).find(k => rec.parts[k].status === 'recording') || null;
  const myParts = (rec, me) => Object.keys(rec.parts).filter(k => isMine(rec, k, me));
  const published = (rec) => !!rec && !!rec.archive && rec.archive.status === 'published';
  /**
   * The parts whose takes this person may send: the part they record now, and, once the
   * item is on archive.org, the parts they finished, whose lines they may replace (P12).
   */
  const ownParts = (rec, me) => Object.keys(rec.parts).filter(k => isMine(rec, k, me)
    || (published(rec) && !!me && rec.parts[k].status === 'done' && rec.parts[k].user_id === me));
  /** The owner's switch (Decision 066, P1): false until the take store exists. */
  const uploadsOpen = (rec) => !!rec && rec.uploads !== false;
  /** Any open part may be taken while no part records (C7). */
  const canClaim = (rec, part) => !recordingPart(rec) && (!rec.parts[part] || rec.parts[part].status === 'open');
  /** Speaking lines with no chosen take this person can see. */
  const unvoiced = (rec, script) => C.speechLineIDs(script).filter(id => !rec.chosen[id]);
  /** The one line shown while the Worker cannot upload to archive.org (P6). */
  const PUBLISH_WAITS = 'Publishing opens when the Ear Drama archive account is connected.';
  const complete = (rec, script) => !recordingPart(rec)
    && Object.values(rec.parts).every(s => s.status === 'done' || s.status === 'silent')
    && unvoiced(rec, script).length === 0;

  /**
   * The local record follows the Worker's parts: only this person's live claim
   * records here (so the phase 1 recorder opens for it); done and silent come
   * across with the performer's name; anyone else's claim is open here.
   */
  function mirror(local, rec, me) {
    const n = clone(local);
    n.parts = {};
    for (const [id, s] of Object.entries(rec.parts)) {
      const st = s.status === 'recording' ? (s.user_id === me ? 'recording' : 'open') : s.status;
      n.parts[id] = s.performer && st !== 'open' ? { status: st, performer: s.performer } : { status: st };
    }
    return n;
  }
  async function follow(store, localId, rec, me) {
    const local = store.production(localId);
    const n = mirror(local, rec, me);
    if (C.stableStringify(n) !== C.stableStringify(local)) await store.save(n);
    return n;
  }

  /** The chosen take of each line of a part this person holds that the Worker does not have yet. */
  function pending(local, script, rec, me) {
    const onServer = new Set(rec.takes.map(t => t.id));
    const out = [];
    for (const part of ownParts(rec, me)) {
      for (const l of C.linesFor(script, part)) {
        const t = C.chosenTake(local, l.id);
        if (t && !onServer.has(t.id)) out.push(t);
      }
    }
    return out;
  }

  /** The take's fields as the Worker reads them from `x-take` (docs/WORKER.md). */
  function metaOf(t) {
    const m = { lineID: t.lineID, part: t.part, file: t.file, created: t.created, frames: t.frames,
                sampleRate: t.sampleRate, capture: t.capture || 'direct', heard: t.heard || {}, peak: t.peak || 0,
                bleed: !!t.bleed };
    if (typeof t.loudness === 'number' && isFinite(t.loudness)) m.loudness = t.loudness;
    return m;
  }

  /**
   * Uploads this person's pending takes to the members (Decision 072: no
   * consent is asked; `GET /consent` is read only for the owner's switch).
   * Returns { sent, flagged, stopped?: 'uploads_off', error? }.
   */
  async function upload({ api, store, local, script, rec, me }) {
    const link = store.share(local.id);
    const todo = pending(local, script, rec, me);
    const flagged = todo.filter(t => t.bleed).length;
    const send = todo.filter(t => !t.bleed);
    let sent = 0;
    if (!send.length) return { sent, flagged };
    if (!uploadsOpen(rec)) return { sent, flagged, stopped: 'uploads_off' };
    try {
      const consent = await api.consent();
      if (consent.uploads === false) return { sent, flagged, stopped: 'uploads_off' };
      for (const t of send) {
        const bytes = await store.readTake(local.id, t.file);
        try {
          await api.upload(link.pid, t.id, bytes, metaOf(t));
          sent++;
        } catch (e) {
          if (e.code === 'take_exists') continue;
          throw e;
        }
      }
      // The person's own choice of take wins on the Worker too.
      const fresh = await api.get(link.pid);
      for (const part of ownParts(fresh, me)) {
        for (const l of C.linesFor(script, part)) {
          const mine = local.chosen[l.id];
          if (mine && fresh.chosen[l.id] !== mine && fresh.takes.some(t => t.id === mine)) await api.choose(link.pid, mine);
        }
      }
    } catch (error) {
      return { sent, flagged, error };
    }
    return { sent, flagged };
  }

  /**
   * The chosen take of each line as this browser should play it: the Worker's
   * for every line, except a line of a part this person holds, where their own
   * choice stands until it is uploaded. A line the Worker no longer shows
   * (blocked, reported) has none.
   */
  function mergedChosen(local, script, rec, me) {
    const out = { ...rec.chosen };
    for (const part of ownParts(rec, me)) {
      for (const l of C.linesFor(script, part)) if (local.chosen[l.id]) out[l.id] = local.chosen[l.id];
    }
    return out;
  }

  /** The other members' chosen takes this browser lacks. */
  function missingHere(local, rec) {
    const have = new Set(local.takes.map(t => t.id));
    return Object.values(rec.chosen).filter(id => !have.has(id) && rec.takes.some(t => t.id === id));
  }

  /** True when this browser already holds and plays exactly what the Worker shows. */
  const inStep = (local, script, rec, me) => !missingHere(local, rec).length
    && C.stableStringify(mergedChosen(local, script, rec, me)) === C.stableStringify(local.chosen);

  /**
   * Brings the chosen takes of the other members into this browser, so the
   * phase 1 listen-through can play the whole play. Takes pass through to the
   * director's device and are never fetched later (Decision 082: no route serves
   * take audio), so only takes that `delivered` holds (take id to bytes, from the
   * pickup) arrive; any other line stays open and the device voice reads it.
   * Only takes the Worker shows this person count (blocked and reported ones never do).
   */
  async function bringHome({ store, localId, rec, script, me, delivered = new Map() }) {
    const add = [];
    for (const takeId of missingHere(store.production(localId), rec)) {
      const bytes = delivered.get(takeId);
      if (!bytes) continue;
      const t = rec.takes.find(x => x.id === takeId);
      const file = `m-${takeId}.wav`;
      await store.importTake(localId, file, bytes);
      const take = { id: t.id, lineID: t.lineID, part: t.part, file, created: t.created, frames: t.frames,
                     sampleRate: t.sampleRate, capture: t.capture, heard: t.heard || {}, peak: t.peak || 0, bleed: false };
      if (typeof t.loudness === 'number') take.loudness = t.loudness;
      add.push(take);
    }
    const n = clone(store.production(localId));
    n.takes.push(...add);
    const chosen = mergedChosen(n, script, rec, me);
    if (C.stableStringify(chosen) !== C.stableStringify(n.chosen)) n.listenedThrough = false;
    n.chosen = chosen;
    await store.save(n);
    return add.length;
  }

  /** Members who hold a chosen take: each consents for their own recording (Decision 059). */
  const performers = (rec) => [
    ...(rec.members || []).filter(m => m.performer),
    // A maker with no account is credited by the name they gave; they have not agreed and cannot here (PLAYS-DESIGN §12.11).
    ...(rec.credits || []).map(c => ({ user_id: null, display_name: c.name, performer: true, consented: false, credited: true })),
  ];
  /** True when this person, not the director, performs in a complete play and has not agreed yet. */
  const needsMyConsent = (rec, script, me) => !!me && !rec.archive && publishable(rec) && rec.director !== me && complete(rec, script)
    && performers(rec).some(m => m.user_id === me && !m.consented);
  /** The performers other than the director who have not agreed: Publish waits on them. */
  const waitingOn = (rec) => performers(rec).filter(m => m.user_id !== rec.director && !m.consented);
  /** A performer's own agreement, at the version the Worker served. */
  async function agreeToPublish({ api, store, local, pid, consent }) {
    if (!consent || consent.publishes !== true) throw { code: 'publish_waits' };
    await api.agree(pid, consent.version);
    if (store && local) await store.setShare(local.id, { pid, consented: consent.version });
  }


  /**
   * What the record says about the archive.org job, in essential words (rule 9): a quiet line
   * while it waits, the item's link once published, the Worker's reason after a failure.
   */
  function archiveStatus(rec) {
    const a = rec && rec.archive;
    if (!a) return null;
    if (a.status === 'published') return { kind: 'published', text: 'On archive.org', url: a.url || null };
    if (a.status === 'failed') return { kind: 'failed', text: LINES[a.reason] || a.reason || 'Publishing failed.' };
    return { kind: 'waiting', text: a.status === 'uploading' ? 'Uploading to archive.org' : 'Queued for archive.org' };
  }
  /** Publish again, after a failure: the director's agreement stands, so the Worker is asked again. */
  const canPublishAgain = (rec, me) => !!me && rec.director === me && !!rec.archive && rec.archive.status === 'failed';

  /**
   * The lines of a published play this person may change (P12): a performer's own (Replace, Remove);
   * for the director every line with a take (Remove, with a reason unless it is their own).
   */
  function changeableLines(rec, script, me) {
    if (!published(rec) || !me) return [];
    const own = new Set(ownParts(rec, me));
    const out = [];
    for (const l of script.lines) {
      if (l.kind !== 'speech' || !rec.chosen[l.id]) continue;
      if (own.has(C.linePart(l))) out.push({ line: l, replace: true, reason: false });
      else if (rec.director === me) out.push({ line: l, replace: false, reason: true });
    }
    return out;
  }

  /** Whether the record's script may be published at all (Decision 088): false for an own script, always. */
  const publishable = (rec) => rec.publishable !== false;
  /** Why Publish is absent, in the place it would be (PLAYS-DESIGN §13 item 16); null when it may be offered. */
  const neverPublishes = (rec) => (publishable(rec) ? null : isOwnId(rec.scriptID) ? 'This script can’t be published.' : LINES.script_not_publishable);
  /** Publish for the director of a complete play (rule 9). Whether the Worker can upload is `consent.publishes`. */
  const canPublish = (rec, script, me) => !!me && rec.director === me && !rec.archive && publishable(rec) && complete(rec, script);

  /**
   * Publish after the consent screen (rule 6, Decisions 059 and 072): the agreement at the
   * version the Worker served is recorded, then the job is queued. `consent` is what
   * `GET /consent` returned for the screen just shown.
   */
  async function publishPlay({ api, store, local, pid, consent }) {
    if (!consent || consent.publishes !== true) throw { code: 'publish_waits' };
    await api.agree(pid, consent.version);
    if (store && local) await store.setShare(local.id, { pid, consented: consent.version });
    return api.publish(pid);
  }

  /**
   * What makes a production on the Worker (`POST /productions`, `POST /classes/:id/productions`): an own script's carries
   * its title and source. A scene's (`local.range`, PLAYS-DESIGN §2.12) sends the whole script's cast sheet, which the
   * Worker hashes, with the range and the scene's heading; the Worker keeps the range's cast sheet.
   */
  function makeBody(script, local = null) {
    const whole = C.wholeOf(script);
    const range = (local && local.range) || script.range || null;
    const heading = range && local && local.title.startsWith(`${whole.title}, `) ? local.title.slice(whole.title.length + 2) : null;
    return {
      script_id: whole.id, script_revision: whole.revision, cast: castSheet(whole),
      ...(range ? { range: { from: range.from, to: range.to }, ...(heading ? { heading } : {}) } : {}),
      ...(isOwnId(whole.id) ? { own: true, title: whole.title, ...(whole.episode ? { episode_id: whole.episode } : {}) } : {}),
    };
  }

  /**
   * "Share this production": the Worker makes the record; the caller directs it. An own script's lines
   * follow (§13 item 11): a sending that may pass later leaves the production shared and `unsent` (the
   * error); one that never can undoes the share and throws.
   */
  async function share({ api, store, local, script, displayName, scripts = ownScripts() }) {
    const name = (displayName || '').trim();
    const rec = await api.create({ ...makeBody(script, local), ...(name ? { display_name: name } : {}) });
    await store.setShare(local.id, { pid: rec.id });
    if (!isOwnId(script.id)) return rec;
    const unsent = await sendOrUndo({ api, pid: rec.id, script, scripts });
    if (!unsent) return rec;
    if (passes(unsent)) return { ...rec, unsent };
    await store.unshare(local.id);
    throw unsent;
  }

  /* ---- Own scripts (PLAYS-DESIGN §13 items 11 to 16; docs/WORKER.md "Own scripts") ---- */

  const isOwnId = (id) => typeof id === 'string' && id.startsWith('own-');
  const ownScripts = () => (typeof OwnScripts === 'undefined' ? null : OwnScripts.shared());
  const coded = (code, why) => Object.assign(new Error(why ? `${code}: ${why}` : code), { code });
  /** A refusal that may pass by itself: no answer, the server's own trouble, too many asks, signed out. */
  const passes = (err) => !(err && err.status >= 400 && err.status < 500) || err.status === 401 || err.status === 429;

  /** Sends a production's own script, once: the lines as they were hashed. A text already there is the same text. */
  async function sendScript({ api, pid, script }) {
    try { await api.putScript(pid, OwnCore.canonicalLines(script.lines)); } catch (e) { if (!e || e.code !== 'already_there') throw e; }
  }
  /** sendScript for a production just made: null, or the error. From here the script is frozen (item 12); one that can never be sent takes its production with it. */
  async function sendOrUndo({ api, pid, script, scripts = ownScripts() }) {
    const freeze = async () => { if (scripts) await scripts.freeze(script.id).catch((x) => console.error(x)); };
    try { await sendScript({ api, pid, script }); } catch (e) {
      if (!passes(e)) { await api.deleteProduction(pid).catch((x) => console.error(x)); return e; }
      await freeze();
      return e;
    }
    await freeze();
    return null;
  }

  const reconciled = new Set();
  /**
   * An own-script share whose creation answer was lost (§13 item 11a): the Worker holds a production of this person's
   * with the text `owed` and this device holds no link to it. Run once a page over the list the screen already read, so
   * nothing polls. One unshared production of that script at that revision here adopts it and sends the text; any other is
   * left: an owed text may be another device's, offline or full and still trying, and deleting it would end that share.
   */
  async function reconcileOwed({ api, store, remote, me, scripts = ownScripts(), checked = reconciled }) {
    let changed = false;
    for (const r of remote || []) {
      if (!isOwnId(r.script_id) || !me || r.director !== me || checked.has(r.id) || store.findShared(r.id)) continue;
      checked.add(r.id);
      let rec;
      try { rec = await api.get(r.id); } catch (e) { checked.delete(r.id); console.error(e); continue; }
      if (!rec || !rec.own_script || rec.own_script.state !== 'owed' || rec.own_script.by !== me) continue;
      const here = store.productions.filter(p => p.scriptID === r.script_id && p.scriptRevision === rec.scriptRevision && !store.share(p.id));
      const script = here.length === 1 && scripts ? await scripts.script(r.script_id).catch(() => null) : null;
      try {
        if (script && script.revision === rec.scriptRevision) {
          await store.setShare(here[0].id, { pid: r.id });
          const err = await sendOrUndo({ api, pid: r.id, script, scripts });
          if (err && !passes(err)) await store.unshare(here[0].id);
          changed = true;
        }
      } catch (e) { console.error(e); checked.delete(r.id); }
    }
    return changed;
  }

  /** The record's own script: null for a catalog play, else its state, with `held` (the owner removed it) and `mine` (this person brought it). */
  function ownState(rec, me = null) {
    const s = rec && rec.own_script;
    if (!s) return null;
    return { state: s.state, held: s.state === 'removed' && s.by !== null, mine: !!me && s.by === me, by: s.by || null };
  }

  const fetched = new Map();
  const sameParts = (script, want) => {
    // The Worker's cast lists Sound only where the script prints a sound line and counts those lines; the cast sheet lists
    // Sound on every script and counts its cue rows (B32 §3.1 item 1), so Sound is held only by its presence.
    const workerSound = want.some((w) => w.id === 'sound');
    const have = C.castParts(script).filter((p) => p.id !== 'sound' || workerSound);
    return have.length === want.length && want.every((w) => have.some((p) => p.id === w.id && (w.lineCount === undefined || p.id === 'sound' || p.lineCount === w.lineCount)));
  };
  const holdsLines = (script, ids) => { const at = new Set(script.lines.map((l) => l.id)); return ids.every((id) => !id || at.has(id)); };
  const holdsParts = (script, ids) => { const at = new Set(C.castParts(script).map((p) => p.id)); return ids.every((id) => at.has(id)); };
  /** What each door knows of the cast sheet, for a script to be held against. */
  const fits = {
    invite: (inv) => (script) => sameParts(script, inv.parts || []),
    record: (rec) => (script) => sameParts(script, Object.keys(rec.parts || {}).map((id) => ({ id })))
      && holdsLines(script, (rec.takes || []).map((t) => t.lineID)),
    room: (snap) => (script) => holdsLines(script, [snap.cursor]) && holdsParts(script, Object.keys(snap.claims || {})),
    seat: (prod) => (script) => holdsParts(script, (prod.assignments || []).map((a) => a.part))
      && holdsLines(script, (prod.assignments || []).flatMap((a) => [a.from, a.to])),
  };

  /** The Worker's bytes as a castable script, or `script_damaged`: their SHA-256 is the revision, they are canonical, the core keeps them, and they match the cast sheet. */
  async function arrived({ bytes, meta }, want, fit, link) {
    const O = OwnCore;
    const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
    if ([...digest.subarray(0, 6)].map((b) => b.toString(16).padStart(2, '0')).join('') !== want.revision) throw coded('script_damaged', 'digest');
    let lines = null;
    try {
      const text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);
      lines = JSON.parse(text);
      if (!Array.isArray(lines) || O.canonicalLines(lines) !== text) lines = null;
    } catch { lines = null; }
    if (!lines) throw coded('script_damaged', 'text');
    if (!meta || meta.id !== want.id || meta.revision !== want.revision || typeof meta.title !== 'string') throw coded('script_damaged', 'names');
    const episode = typeof meta.episode_id === 'string' && meta.episode_id ? meta.episode_id : null;
    const script = {
      id: want.id, revision: want.revision, kind: 'own', title: meta.title, authors: [],
      source: episode ? { name: 'Automatic transcript', url: link(episode) } : { name: 'Shared script', url: '' },
      ...(episode ? { episode } : {}), rights: { bucket: 'own', evidence: [] }, roles: O.rolesOf(lines), lines,
    };
    const why = O.refusalOf(script);
    if (why) throw coded('script_damaged', why);
    if (!fit(script)) throw coded('script_damaged', 'cast sheet');
    return script;
  }

  /** Who asks, and so which route answers: a member, a holder of an invite, a class's seat, a member of a room. */
  const readAs = (api, who) => (who.token ? api.plays.inviteScript(who.token)
    : who.seat ? api.plays.seatScript(who.seat, who.pid)
      : who.room ? api.read.script(who.room, who.key)
        : api.plays.script(who.pid));

  /**
   * The script of a production, an invite, a seat's part or a room (item 11): the one way every screen
   * gets it. A catalog play is the library's at `revision` (or the bundle's; any revision with
   * `anyRevision`). An own script is this device's copy in the production, this device's script at that
   * revision, then the Worker's, drawn only once it is shown to be whole (`fit`). Throws with the
   * Worker's code, `revision_mismatch` or `script_damaged`; what it answers is never null.
   */
  async function scriptOf({ api, id, revision, who = {}, fit = () => true, store = null, scripts = ownScripts(), anyRevision = false }) {
    if (!isOwnId(id)) {
      // The production's own copy at its recorded revision comes first: the library publishes only its current text, so a
      // play whose revision has moved on is otherwise unreadable for the production made from the old one.
      const local = store && who.pid ? store.findShared(who.pid) : null;
      const kept = local ? await store.script(local).catch(() => null) : null;
      if (kept && kept.id === id && kept.revision === revision && Array.isArray(kept.lines)) return kept;
      const found = await api.playScript(id);
      if (found && (found.revision === revision || anyRevision)) return found;
      const held = scriptFor(await api.castableScripts(), id, revision);
      if (held) return held;
      throw coded('revision_mismatch');
    }
    const local = store && who.pid ? store.findShared(who.pid) : null;
    const kept = local ? await store.script(local) : null;
    if (kept && kept.id === id && kept.revision === revision) return kept;
    const mine = scripts ? await scripts.script(id).catch(() => null) : null;
    if (mine && mine.revision === revision) return mine;
    const key = `${id}@${revision}`;
    if (fetched.has(key) && fit(fetched.get(key))) return fetched.get(key);
    const script = await arrived(await readAs(api, who), { id, revision }, fit, (e) => `https://eardrama.org${api.shareLink('episode', e)}`);
    fetched.set(key, script);
    return script;
  }
  const forgetFetched = () => fetched.clear();

  /** The production in this browser for a shared one, made from the bundle's script on first open. */
  async function localFor(store, pid, script, rec = null) {
    let local = store.findShared(pid);
    if (!local) {
      if (!script) throw Object.assign(new Error('revision_mismatch'), { code: 'revision_mismatch' });
      // A scene's production (PLAYS-DESIGN §2.12) is made here as the Worker keeps it: its range and its title.
      const range = rec && rec.range ? { from: rec.range.from, to: rec.range.to } : null;
      local = await store.create(C.wholeOf(script), range ? { range } : {});
      if (range && rec.title && local.title !== rec.title) { local = { ...local, title: rec.title }; await store.save(local); }
      await store.setShare(local.id, { pid });
    }
    return local;
  }

  /** The bundle's script for a shared production, only at the revision it was cast from. */
  const scriptFor = (scripts, scriptID, revision) =>
    (scripts || []).find(x => x.id === scriptID && x.revision === revision) || null;

  /** Joins by an invite and claims `part`; makes the production in this browser on the first join. */
  async function join({ api, store, token, part, displayName, script }) {
    const name = (displayName || '').trim();
    const rec = await api.joinByInvite(token, part, name || undefined);
    return { rec, local: await localFor(store, rec.id, script, rec) };
  }

  /**
   * Library's Ear dramas (Decision 068): this browser's productions, then the
   * shared ones this person is in that this browser has not opened yet, newest first.
   */
  function libraryRows(store, remote) {
    const rows = store.productions.map(p => ({ local: p, pid: (store.share(p.id) || {}).pid || null }))
      .filter(r => r.pid || !C.isEmptyProduction(r.local));
    const here = new Set(rows.map(r => r.pid).filter(Boolean));
    for (const r of remote || []) if (!here.has(r.id)) rows.push({ local: null, pid: r.id, remote: r });
    const when = (r) => (r.local ? r.local.created + 978307200 : (r.remote.updated_at || 0) / 1000);
    return rows.sort((a, b) => when(b) - when(a));
  }

  /* ---- Invite links (DEEP_LINKS.md): the token rides the fragment, so it never reaches a server log ---- */

  /** `https://eardrama.org/invite#{token}`, the twin of `eardrama://invite#{token}` (DEEP_LINKS.md). */
  function inviteLink(token, origin = 'https://eardrama.org') {
    return `${String(origin).replace(/\/+$/, '')}/invite#${token}`;
  }
  const TOKEN = /^[A-Za-z0-9_-]{43}$/;
  /** The token from /invite#{token}, or from the #invite={token} the 404 forwarder leaves. */
  function inviteToken(loc) {
    const hash = String(loc.hash || '').replace(/^#/, '');
    const named = new URLSearchParams(hash).get('invite');
    if (named && TOKEN.test(named)) return named;
    if (/\/invite\/?$/.test(String(loc.pathname || '')) && TOKEN.test(hash)) return hash;
    return null;
  }
  function pendingInvite() {
    try { return sessionStorage.getItem(INVITE_KEY); } catch { return null; }
  }
  function holdInvite(token) {
    try { if (token) sessionStorage.setItem(INVITE_KEY, token); else sessionStorage.removeItem(INVITE_KEY); } catch { /* this page only */ }
  }

  /* ---- A finished drama's playable copy on archive.org ---- */

  const MP3_ORDER = ['VBR MP3', '128Kbps MP3', '64Kbps MP3', 'MP3'];
  const LINE_FILE = /^\d{3,}-/;
  const LINE_RANK = ['mp3', 'flac', 'wav'];
  const extOf = (n) => (String(n).split('.').pop() || '').toLowerCase();
  function pickAudio(files, id) {
    const ok = files.filter(f => !f.private && !/(^|\/)history\//.test(f.name || '') && !/~\d+~$/.test(f.name || ''));
    const href = (f) => `https://archive.org/download/${encodeURIComponent(id)}/${f.name.split('/').map(encodeURIComponent).join('/')}`;
    const whole = ok.filter(f => !LINE_FILE.test(f.name));
    for (const fmt of MP3_ORDER) {
      const f = whole.find(x => x.format === fmt);
      if (f) return { whole: href(f) };
    }
    const byLine = new Map();
    for (const f of ok.filter(x => LINE_FILE.test(x.name) && LINE_RANK.includes(extOf(x.name)))) {
      const key = f.name.replace(/\.[^.]+$/, '');
      const had = byLine.get(key);
      if (!had || LINE_RANK.indexOf(extOf(f.name)) < LINE_RANK.indexOf(extOf(had.name))) byLine.set(key, f);
    }
    const keys = [...byLine.keys()].sort();
    const lines = keys.map(k => href(byLine.get(k)));
    // The file number is the line's 1-based place in the script (worker/src/plays-archive.js fileName).
    return lines.length ? { lines, seqs: keys.map(k => parseInt(k, 10)) } : null;
  }

  /* ---- One plain line for each refusal (AGENTS.md: a refusal, a warning, or a fact) ---- */

  const LINES = {
    storage_not_configured: 'Uploads are off.',
    uploads_off: 'Uploads are off.',
    not_open: 'This part is taken.',
    no_such_part: 'This part is not in the play.',
    line_is_another_part: 'This part is not yours to record.',
    unsupported_audio: 'A take could not be read.',
    audio_mismatch: 'A take could not be read.',
    bleed_flagged: 'A take holds the device voice. Re-take it with headphones.',
    publish_waits: PUBLISH_WAITS,
    publishing_unavailable: PUBLISH_WAITS,
    not_your_take: 'This line is not yours to change.',
    removed_by_director: 'The director removed this line.',
    not_published: 'This play is not on archive.org yet.',
    consent_version_mismatch: 'The consent changed. Read it again.',
    not_your_claim: 'This part is not yours to record.',
    not_your_part: 'Only its performer or the director can open this part.',
    lines_missing: null,
    speaking_part_needs_a_voice: 'A speaking part needs a voice.',
    not_finished: 'This part is not finished.',
    invite_not_found: 'This invite does not work.',
    not_found: 'This production is not shared with you.',
    no_such_take: 'This take is not available.',
    incomplete: 'Every part must be done or left silent first.',
    reported_take: 'A chosen take has been reported.',
    consent_missing: 'Not every performer has agreed to the consent.',
    school_consent_required: 'This class needs its school\'s consent before anyone can join.',
    class_not_found: 'No class has that code.',
    you_teach_this_class: 'You teach this class.',
    revision_mismatch: 'This play has changed since it was cast.',
    not_castable: 'This play cannot be shared.',
    cast_mismatch: 'This play cannot be shared.',
    script_not_publishable: 'This play cannot be published.',
    script_too_long: 'This script is too long to share.',
    scripts_full: 'Sharing scripts is full.',
    script_removed: 'This script was removed.',
    script_reported: 'This script has been reported.',
    script_damaged: 'This script did not arrive whole.',
    no_script: 'This script has not been sent yet.',
    bad_script_id: 'This script cannot be shared.',
    not_on_device: 'This script is not in this browser.',
    needs_account: 'Sharing needs an account.',
    production_full: 'This production is full.',
    too_many_productions: 'You have too many shared productions.',
    too_many_takes: 'This line has too many takes.',
    take_too_long: 'A take is too long.',
    too_large: 'A take is too long.',
    director_only: 'Only the director can do that.',
    name_too_long: 'That name is too long.',
    name_has_link: 'A name cannot hold a link.',
    name_not_allowed: 'That name is not allowed.',
    name_reserved: 'That name is not allowed.',
    bad_name: 'That name is not allowed.',
    rate_limited: 'Too many tries. Try again in a minute.',
  };
  /** The refusals an own script's sharing can meet, for screens whose other words are ReadCore's; '' for any other. */
  const SCRIPT_CODES = new Set(['script_too_long', 'too_many_scripts', 'scripts_full', 'script_removed', 'script_reported', 'script_damaged', 'no_script',
    'bad_script_id', 'revision_mismatch', 'script_not_publishable', 'not_on_device', 'needs_account']);
  const scriptLine = (err) => {
    const code = (err && err.code) || '';
    return SCRIPT_CODES.has(code) || (code === 'bad_name' && err.detail) ? line(err) : '';
  };
  function line(err) {
    if (!err) return '';
    if (err.name === 'QuotaExceededError') return 'This browser is out of space.';
    const code = err.code || '';
    if (code === 'bad_name' && err.detail) return err.detail === 'title' ? 'The title is not allowed.' : `The part name ${C.partTitle(err.detail)} is not allowed.`;
    if (code === 'too_many_scripts') return `You have shared ${err.detail || 20} scripts. Delete a production of one first.`;
    if (code === 'another_part_is_recording') return `${C.partTitle(err.detail)} is still recording.`;
    if (code === 'lines_missing') {
      const n = Array.isArray(err.detail) ? err.detail.length : 0;
      return n === 1 ? '1 line still needs a take.' : `${n} lines still need a take.`;
    }
    if (LINES[code]) return LINES[code];
    if (err.kind === 'rate_limited') return LINES.rate_limited;
    if (err.kind === 'offline') return 'You are offline.';
    if (err.kind === 'not_configured') return 'Not available yet.';
    if (err.kind === 'unauthorized') return 'Sign in again.';
    return 'Ear Drama could not be reached.';
  }

  /**
   * The Worker's consent words as structure, none changed: with "- " lines, the first
   * plain line leads and each "- " line is an item; without them every line is a paragraph.
   */
  function consentBlocks(text) {
    const lines = String(text || '').split('\n').map(l => l.trim()).filter(Boolean);
    const listed = lines.some(l => l.startsWith('- '));
    return lines.map((l, i) => {
      if (listed && l.startsWith('- ')) return { kind: 'item', text: l.slice(2).trim() };
      return { kind: listed && i === 0 ? 'lead' : 'para', text: l };
    });
  }

  return {
    consentBlocks, PUBLISH_WAITS, archiveStatus, canPublishAgain, changeableLines, published, ownParts, canPublish, publishPlay, performers, needsMyConsent, waitingOn, agreeToPublish, castSheet, isMine, recordingPart, myParts, uploadsOpen, canClaim, unvoiced, complete, mirror, follow, pending, metaOf,
    upload, mergedChosen, missingHere, inStep, bringHome, share, makeBody, sendScript, sendOrUndo, passes, isOwnId, ownState, publishable, neverPublishes, fits, scriptOf, forgetFetched, reconcileOwed, scriptLine, join, localFor, scriptFor, libraryRows, inviteLink, inviteToken, pendingInvite, holdInvite, pickAudio, line,
  };
})();
