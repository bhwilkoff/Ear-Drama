/**
 * Own scripts (Decision 088.3 and 088.4; docs/research/design/R4-record-anything.md
 * §3.3, §7.7). Owner, 2026-11-24: "Yes, a shared script can be kept on our server."
 *
 * A production made with `own: true` holds its own text: the lines as canonical
 * JSON (js/own-core.js), sent once by its director and compared by SHA-256 with
 * the revision the production was made at. THE TEXT IS NEVER PARSED HERE: the
 * clients check that the lines match the cast sheet.
 *
 * WHO READS IT. The production's members, a class's seats, the holder of a live
 * invite, and the members of a read room that carries the production. Nobody
 * else: no route lists, searches, or finds a script by its id, and every answer
 * is `private, no-store`, so no cache gives it to another person.
 *
 * WHEN IT GOES. With its production or class, on every path 084 lists; with the
 * account that brought it, though the production passes on (its row is gone,
 * which reads as removed); by the owner, for one production or for an episode a
 * take-down names. The owner's removal HOLDS the production: no new person, no
 * claim, no take, no room. The people in it keep the record and their copies.
 *
 * A REPORT of a script hides its production from its reporter while the text is
 * here, and lets no new person in until the owner answers. It never publishes:
 * no manifest row exists for an `own-` id (plays-castable.js).
 */

import { problem } from "./http.js";
import { REVISION } from "./plays-manifest.js";
import { wordsRefusal } from "./plays-names.js";
import { castParts, isSpeaking } from "./plays-relay.js";
import { cleanEpisodeId } from "./room-protocol.js";

/** js/own-core.js's OWN_ID, LINE_ID, MAX_BYTES, MAX_LINES, MAX_TITLE and MAX_PART_NAME; test/own-scripts.test.js holds them equal. */
export const OWN_ID = /^own-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export const LINE_ID = /^L[0-9]{4}[a-z]*$/;
export const MAX_SCRIPT_BYTES = 400000;
export const MAX_OWN_LINES = 6000;
export const MAX_TITLE = 300;
export const MAX_PART_NAME = 40;
export const MAX_OWN_PARTS = 200;
/** Productions of own scripts one account has brought. */
export const MAX_OWN_SCRIPTS = 20;
/** All the text kept: half of D1's free 500 MB. */
export const SCRIPTS_CAP_BYTES = 250 * 1000 * 1000;
export const SCRIPT_HEADER = "x-script";

export const isOwn = (p) => p.script_id.startsWith("own-");

const removed = () => problem(410, "script_removed");
const missing = () => problem(404, "no_script");

/* ---- Making ---- */

/** A new own script's production: { title, revision, statement(pid) }, or { refusal }. */
export async function newOwnScript(env, body, cast, userId, now) {
  const refuse = (status, error, detail) => ({ refusal: problem(status, error, detail) });
  if (typeof body.script_id !== "string" || !OWN_ID.test(body.script_id)) return refuse(422, "bad_script_id");
  if (typeof body.script_revision !== "string" || !REVISION.test(body.script_revision)) return refuse(422, "bad_script_id", "script_revision");
  if (cast.length > MAX_OWN_LINES) return refuse(413, "script_too_long");
  if (!cast.every(([id]) => LINE_ID.test(id))) return refuse(400, "bad_request", "line ids");
  // A title and part names are read by someone who has only opened an invite, so they pass the filter; the text does not (it would refuse Othello).
  const title = typeof body.title === "string" ? body.title.trim() : "";
  if (!title || wordsRefusal(title, MAX_TITLE)) return refuse(422, "bad_name", "title");
  const parts = castParts(cast).map((p) => p.id).filter(isSpeaking);
  if (!parts.length || parts.length > MAX_OWN_PARTS) return refuse(422, "bad_request", `1 to ${MAX_OWN_PARTS} parts`);
  const bad = parts.find((part) => !part.slice(5).trim() || wordsRefusal(part.slice(5), MAX_PART_NAME));
  if (bad) return refuse(422, "bad_name", bad);
  const named = body.episode_id !== undefined && body.episode_id !== null;
  const episode = named ? cleanEpisodeId(body.episode_id) : null;
  if (named && !episode) return refuse(400, "bad_request", "episode_id");
  const { n, gone } = await env.DB.prepare(
    "SELECT (SELECT COUNT(*) FROM play_scripts WHERE user_id = ?1) AS n, EXISTS (SELECT 1 FROM play_removed_scripts WHERE key IN (?2, ?3)) AS gone",
  )
    .bind(userId, `revision:${body.script_revision}`, `episode:${episode ?? ""}`)
    .first();
  if (gone) return { refusal: removed() };
  if (n >= MAX_OWN_SCRIPTS) return refuse(409, "too_many_scripts", MAX_OWN_SCRIPTS);
  return {
    title,
    revision: body.script_revision,
    statement: (pid) =>
      env.DB.prepare("INSERT INTO play_scripts (production_id, user_id, episode_id, created_at) VALUES (?1, ?2, ?3, ?4)").bind(pid, userId, episode, now),
  };
}

/* ---- The state of one ---- */

const REPORTED = "EXISTS (SELECT 1 FROM play_reports r WHERE r.production_id = s.production_id AND r.script = 1 AND r.status = 'open') AS reported";
const rowOf = (env, pid) =>
  env.DB.prepare(`SELECT user_id, bytes, episode_id, held_at, ${REPORTED} FROM play_scripts s WHERE s.production_id = ?1`).bind(pid).first();

/** `owed` until its director sends it, `kept`, or `removed` (a row gone with the account that brought it, or held by the owner). */
const stateOf = (s) => (!s || s.held_at ? "removed" : s.bytes ? "kept" : "owed");

/** The record's `own_script`, or null for a catalog play. `by` is who brought it. */
export async function ownScriptOut(env, p) {
  if (!isOwn(p)) return null;
  const s = await rowOf(env, p.id);
  return { state: stateOf(s), by: s ? s.user_id : null, episode_id: s ? s.episode_id : null };
}

/** null when someone new may be let in: an invite made or opened, a room. */
export async function newPersonRefusal(env, p) {
  if (!isOwn(p)) return null;
  const s = await rowOf(env, p.id);
  const state = stateOf(s);
  if (state === "removed") return removed();
  if (s.reported) return problem(409, "script_reported");
  return state === "owed" ? problem(409, "no_script") : null;
}

/** null unless the owner removed this production's script: then no part is claimed and no take moves. */
export async function heldRefusal(env, p) {
  if (!isOwn(p)) return null;
  const s = await env.DB.prepare("SELECT held_at FROM play_scripts WHERE production_id = ?1").bind(p.id).first();
  return s && s.held_at ? removed() : null;
}

/** Whether `userId` reported this production's script: they no longer see it, while its text is here. */
export async function hiddenFromReporter(env, p, userId) {
  if (!isOwn(p)) return false;
  return !!(await env.DB.prepare(
    "SELECT 1 FROM play_reports r JOIN play_scripts s ON s.production_id = r.production_id WHERE r.production_id = ?1 AND r.user_id = ?2 AND r.script = 1 AND s.bytes > 0",
  )
    .bind(p.id, userId)
    .first());
}

/** Who a report of this production's script is about, or null when there is none to report. */
export async function reportedScriptOwner(env, pid) {
  const s = await rowOf(env, pid);
  return stateOf(s) === "kept" ? s.user_id : null;
}

/* ---- The text ---- */

/** Exactly `length` bytes of the body, or null when it is shorter or longer. */
async function readExactly(request, length) {
  if (!request.body) return null;
  const out = new Uint8Array(length);
  let at = 0;
  const reader = request.body.getReader();
  for (;;) {
    const { done, value } = await reader.read();
    if (done) return at === length ? out : null;
    if (at + value.byteLength > length) {
      await reader.cancel().catch(() => {});
      return null;
    }
    out.set(value, at);
    at += value.byteLength;
  }
}

/**
 * PUT /v1/plays/productions/:id/script, the director, once. Its length is
 * judged before a byte is read and its digest before a byte is kept. Stored
 * as text: a D1 blob crosses to the database as a JSON array of numbers,
 * several times the size and the CPU.
 */
export async function putScript(auth, request, env, p, now) {
  if (!isOwn(p)) return missing();
  if (p.user_id !== auth.userId) return problem(403, "director_only");
  const before = await env.DB.prepare(
    "SELECT s.bytes, s.held_at, (SELECT bytes FROM play_script_total WHERE id = 1) AS total, EXISTS (SELECT 1 FROM play_removed_scripts WHERE key = ?2) AS gone " +
      "FROM play_scripts s WHERE s.production_id = ?1",
  )
    .bind(p.id, `revision:${p.script_revision}`)
    .first();
  if (stateOf(before) === "removed" || before.gone) return removed();
  if (before.bytes) return problem(409, "already_there");
  const declared = request.headers.get("content-length");
  if (declared === null || !/^\d{1,12}$/.test(declared)) return problem(411, "length_required");
  const length = Number(declared);
  if (length > MAX_SCRIPT_BYTES) return problem(413, "script_too_long");
  if (before.total + length > SCRIPTS_CAP_BYTES) return problem(503, "scripts_full");
  const bytes = await readExactly(request, length);
  if (!bytes) return problem(400, "bad_request", "the body is not its Content-Length");
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  const revision = [...digest.subarray(0, 6)].map((b) => b.toString(16).padStart(2, "0")).join("");
  if (revision !== p.script_revision) return problem(422, "revision_mismatch", p.script_revision);
  let text;
  try {
    // Fatal and keeping a BOM, so the text kept is byte for byte what was hashed.
    text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes);
  } catch {
    return problem(400, "bad_request", "the body is not UTF-8");
  }
  // Canonical JSON escapes every control; a raw NUL would also cut the text short in SQLite.
  if (/[\u0000-\u001f]/.test(text)) return problem(400, "bad_request", "the body is not canonical JSON");
  const kept = await env.DB.prepare(
    "UPDATE play_scripts SET body = ?2, bytes = ?3, created_at = ?4 WHERE production_id = ?1 AND bytes = 0 AND held_at IS NULL " +
      "AND (SELECT bytes FROM play_script_total WHERE id = 1) + ?3 <= ?5",
  )
    .bind(p.id, text, length, now, SCRIPTS_CAP_BYTES)
    .run();
  if (kept.meta.changes) return new Response(null, { status: 204 });
  const after = await env.DB.prepare("SELECT bytes, held_at FROM play_scripts WHERE production_id = ?1").bind(p.id).first();
  if (stateOf(after) === "removed") return removed();
  return after.bytes ? problem(409, "already_there") : problem(503, "scripts_full");
}

/** JSON safe in a header: every character past ASCII escaped. */
const headerJson = (v) => JSON.stringify(v).replace(/[^ -~]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, "0")}`);

/**
 * The text, to someone the caller has shown may read it: the lines as they came,
 * with what a device needs beside them (id, revision, title, episode) in
 * `x-script`. `newPerson` is a reader who is not yet in the production.
 */
export async function sendScript(request, env, p, { newPerson = false } = {}) {
  if (!isOwn(p)) return missing();
  const etag = `"${p.script_revision}"`;
  const has = (request.headers.get("if-none-match") || "").split(",").some((t) => t.trim().replace(/^W\//, "") === etag);
  const s = await env.DB.prepare(
    `SELECT bytes, episode_id, held_at, CASE WHEN ?2 THEN NULL ELSE body END AS body, ${REPORTED} FROM play_scripts s WHERE s.production_id = ?1`,
  )
    .bind(p.id, has ? 1 : 0)
    .first();
  const state = stateOf(s);
  if (state === "removed") return removed();
  if (newPerson && s.reported) return problem(409, "script_reported");
  if (state === "owed") return missing();
  const headers = {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "private, no-store",
    "x-content-type-options": "nosniff",
    etag,
    [SCRIPT_HEADER]: headerJson({ id: p.script_id, revision: p.script_revision, title: p.title, episode_id: s.episode_id }),
  };
  return has ? new Response(null, { status: 304, headers }) : new Response(s.body, { headers });
}

/* ---- The owner's removal (operator.yml; tools/reports.py runs the same three statements for one report) ---- */

/** Drops the text of the rows `where` picks, holds their productions, remembers what was removed, and answers its reports. */
async function removeWhere(env, where, bind, now, extra = []) {
  const [, held] = await env.DB.batch([
    env.DB.prepare(
      "INSERT OR IGNORE INTO play_removed_scripts (key, removed_at) SELECT 'revision:' || p.script_revision, ?2 FROM play_scripts s " +
        `JOIN play_productions p ON p.id = s.production_id WHERE s.${where} AND s.bytes > 0`,
    ).bind(bind, now),
    env.DB.prepare(`UPDATE play_scripts SET body = NULL, bytes = 0, held_at = ?2 WHERE ${where} AND held_at IS NULL RETURNING production_id`).bind(bind, now),
    env.DB.prepare(
      `UPDATE play_reports SET status = 'acted' WHERE script = 1 AND status = 'open' AND production_id IN (SELECT production_id FROM play_scripts WHERE ${where})`,
    ).bind(bind),
    ...extra,
  ]);
  return held.results.length;
}

/** One production's script. False when it has none. */
export async function removeScript(env, pid, now) {
  if (!(await env.DB.prepare("SELECT 1 FROM play_scripts WHERE production_id = ?1").bind(pid).first())) return false;
  await removeWhere(env, "production_id = ?1", pid, now);
  return true;
}

/** Every transcript of an episode a take-down names, and any shared after. */
export const removeEpisodeScripts = (env, episodeId, now) =>
  removeWhere(env, "episode_id = ?1", episodeId, now, [
    env.DB.prepare("INSERT OR IGNORE INTO play_removed_scripts (key, removed_at) VALUES (?1, ?2)").bind(`episode:${episodeId}`, now),
  ]);
