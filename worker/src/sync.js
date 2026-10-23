/**
 * Personal sync: listening history, the queue, and followed series.
 *
 * LAST WRITE WINS, per row, by the client's `updated_at` (milliseconds). A
 * clock running ahead cannot win forever: an `updated_at` past the server's
 * clock is clamped to it. Equal stamps break by device name, so every server
 * arrives at the same row whichever upload lands first.
 *
 * The queue is one ordered list and wins or loses whole.
 *
 * GET reads by `changed_at` (the server's clock at write time), not
 * `updated_at`, so an upload carrying an old stamp that arrives late is still
 * delivered to the other devices.
 *
 * THE ANONYMOUS MERGE (POST /v1/sync/merge) is the same upload, sent once
 * after sign-in with whatever the device kept while signed out. History and
 * follows merge row by row exactly as a PUT does; the queue is the one
 * difference: the device's items are appended to the account's (not
 * replacing them), so signing in never empties a queue someone built.
 */

import { json, problem, readJson } from "./http.js";
import { cleanDevice } from "./auth.js";

const MAX_ROWS = 500;
const MAX_QUEUE = 500;
const MAX_POSITION_S = 7 * 86400;

/** The catalog's ids (`{seriesKey}|{YYYY-MM-DD}` and the like): printable, bounded. */
export function cleanId(v) {
  if (typeof v !== "string" || v.length < 1 || v.length > 200) return null;
  if (/[\u0000-\u001f\u007f]/.test(v)) return null;
  return v;
}

function seconds(v) {
  const n = Number(v);
  return Number.isFinite(n) && n >= 0 && n <= MAX_POSITION_S ? n : null;
}

function stamp(v, now) {
  const n = Number(v);
  if (!Number.isInteger(n) || n <= 0) return null;
  return Math.min(n, now);
}

/** Validates an upload into rows ready to bind, or returns an error string. */
export function parseUpload(body, now) {
  const device = cleanDevice(body.device);
  const history = [];
  const follows = [];
  let queue = null;

  if (body.history !== undefined) {
    if (!Array.isArray(body.history) || body.history.length > MAX_ROWS) return { error: "history must be an array of at most 500" };
    for (const h of body.history) {
      const id = cleanId(h && h.episode_id);
      const at = stamp(h && h.updated_at, now);
      if (!id || at === null) return { error: "each history row needs episode_id and updated_at" };
      const position = h.position === undefined ? 0 : seconds(h.position);
      const duration = h.duration === undefined || h.duration === null ? null : seconds(h.duration);
      if (position === null || (h.duration != null && duration === null)) return { error: `bad position for ${id}` };
      history.push({ id, position, duration, finished: h.finished ? 1 : 0, deleted: h.deleted ? 1 : 0, at });
    }
  }
  if (body.follows !== undefined) {
    if (!Array.isArray(body.follows) || body.follows.length > MAX_ROWS) return { error: "follows must be an array of at most 500" };
    for (const f of body.follows) {
      const id = cleanId(f && f.series_id);
      const at = stamp(f && f.updated_at, now);
      if (!id || at === null) return { error: "each follows row needs series_id and updated_at" };
      follows.push({ id, following: f.following === false ? 0 : 1, at });
    }
  }
  if (body.queue !== undefined && body.queue !== null) {
    const q = body.queue;
    const at = stamp(q && q.updated_at, now);
    if (!q || !Array.isArray(q.items) || q.items.length > MAX_QUEUE || at === null) {
      return { error: "queue needs items (at most 500) and updated_at" };
    }
    const items = [];
    for (const i of q.items) {
      const id = cleanId(i);
      if (!id) return { error: "queue items are episode ids" };
      if (!items.includes(id)) items.push(id);
    }
    queue = { items, at };
  }
  return { device, history, follows, queue };
}

const HISTORY_UPSERT = `
INSERT INTO history (user_id, episode_id, position, duration, finished, deleted, updated_at, device, changed_at)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
ON CONFLICT (user_id, episode_id) DO UPDATE SET
  position = excluded.position, duration = excluded.duration, finished = excluded.finished,
  deleted = excluded.deleted, updated_at = excluded.updated_at, device = excluded.device,
  changed_at = excluded.changed_at
WHERE excluded.updated_at > history.updated_at
   OR (excluded.updated_at = history.updated_at AND excluded.device > history.device)`;

const FOLLOW_UPSERT = `
INSERT INTO follows (user_id, series_id, following, updated_at, device, changed_at)
VALUES (?1, ?2, ?3, ?4, ?5, ?6)
ON CONFLICT (user_id, series_id) DO UPDATE SET
  following = excluded.following, updated_at = excluded.updated_at, device = excluded.device,
  changed_at = excluded.changed_at
WHERE excluded.updated_at > follows.updated_at
   OR (excluded.updated_at = follows.updated_at AND excluded.device > follows.device)`;

async function readQueue(env, userId) {
  const meta = await env.DB.prepare("SELECT updated_at, device, changed_at FROM queue_meta WHERE user_id = ?1")
    .bind(userId)
    .first();
  if (!meta) return null;
  const { results } = await env.DB.prepare("SELECT episode_id FROM queue WHERE user_id = ?1 ORDER BY ord")
    .bind(userId)
    .all();
  return { items: results.map((r) => r.episode_id), updated_at: meta.updated_at, device: meta.device, changed_at: meta.changed_at };
}

function queueStatements(env, userId, items, at, device, now) {
  const out = [
    env.DB.prepare(
      "INSERT INTO queue_meta (user_id, updated_at, device, changed_at) VALUES (?1, ?2, ?3, ?4) " +
        "ON CONFLICT (user_id) DO UPDATE SET updated_at = excluded.updated_at, device = excluded.device, changed_at = excluded.changed_at",
    ).bind(userId, at, device, now),
    env.DB.prepare("DELETE FROM queue WHERE user_id = ?1").bind(userId),
  ];
  items.forEach((id, ord) => {
    out.push(env.DB.prepare("INSERT INTO queue (user_id, ord, episode_id) VALUES (?1, ?2, ?3)").bind(userId, ord, id));
  });
  return out;
}

/** PUT /v1/sync (merge = false) and POST /v1/sync/merge (merge = true). */
export async function handleUpload(auth, request, env, { merge = false } = {}) {
  const { body, error } = await readJson(request);
  if (error) return error;
  const now = Date.now();
  const up = parseUpload(body, now);
  if (up.error) return problem(400, "bad_request", up.error);
  const { userId } = auth;

  const statements = [];
  for (const h of up.history) {
    statements.push(
      env.DB.prepare(HISTORY_UPSERT).bind(userId, h.id, h.position, h.duration, h.finished, h.deleted, h.at, up.device, now),
    );
  }
  for (const f of up.follows) {
    statements.push(env.DB.prepare(FOLLOW_UPSERT).bind(userId, f.id, f.following, f.at, up.device, now));
  }

  let queueApplied = false;
  if (up.queue) {
    const current = await readQueue(env, userId);
    if (merge) {
      const items = current ? [...current.items] : [];
      for (const id of up.queue.items) if (!items.includes(id) && items.length < MAX_QUEUE) items.push(id);
      const at = Math.max(current ? current.updated_at : 0, up.queue.at);
      statements.push(...queueStatements(env, userId, items, at, up.device, now));
      queueApplied = true;
    } else if (
      !current ||
      up.queue.at > current.updated_at ||
      (up.queue.at === current.updated_at && up.device > current.device)
    ) {
      statements.push(...queueStatements(env, userId, up.queue.items, up.queue.at, up.device, now));
      queueApplied = true;
    }
  }

  let historyApplied = 0;
  let followsApplied = 0;
  if (statements.length) {
    const results = await env.DB.batch(statements);
    for (let i = 0; i < up.history.length; i++) historyApplied += results[i].meta.changes;
    for (let i = 0; i < up.follows.length; i++) followsApplied += results[up.history.length + i].meta.changes;
  }
  return json({
    server_time: now,
    applied: { history: historyApplied, follows: followsApplied, queue: queueApplied },
  });
}

/** GET /v1/sync?since=<server_time from the last read>; since=0 is everything. */
export async function handleRead(auth, url, env) {
  const raw = url.searchParams.get("since");
  const since = raw === null ? 0 : Number(raw);
  if (!Number.isInteger(since) || since < 0) return problem(400, "bad_request", "since must be a server_time");
  const now = Date.now();
  const { userId } = auth;
  // >= rather than >: a row written in the same millisecond as the last read
  // comes again rather than never. Applying a row twice changes nothing.
  const [h, f] = await env.DB.batch([
    env.DB.prepare(
      "SELECT episode_id, position, duration, finished, deleted, updated_at, device FROM history " +
        "WHERE user_id = ?1 AND changed_at >= ?2 ORDER BY changed_at",
    ).bind(userId, since),
    env.DB.prepare(
      "SELECT series_id, following, updated_at, device FROM follows WHERE user_id = ?1 AND changed_at >= ?2 ORDER BY changed_at",
    ).bind(userId, since),
  ]);
  const q = await readQueue(env, userId);
  return json({
    server_time: now,
    history: h.results.map((r) => ({ ...r, finished: !!r.finished, deleted: !!r.deleted })),
    follows: f.results.map((r) => ({ ...r, following: !!r.following })),
    queue: q && q.changed_at >= since ? { items: q.items, updated_at: q.updated_at, device: q.device } : null,
  });
}
