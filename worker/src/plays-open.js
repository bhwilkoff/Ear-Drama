/**
 * Plays that need no account (owner, 2026-10-29): an open invite shows
 * everything, and finished ear dramas are listed and credited. Every route
 * here is a GET and writes nothing; claiming, recording, uploading, reporting
 * and blocking stay in plays.js behind an account (Decision 057).
 *
 * THE INVITE READ. The token rides the `x-invite` header, never the path, so no
 * access log holds it (the link carries it in the fragment for the same reason).
 * Unknown token: 404. Revoked or expired: 410. A viewer sees the play, its
 * parts and their states, who is in by chosen name, and the chosen takes,
 * playable. No account ids leave this file.
 *
 * WHAT AN ANONYMOUS VIEWER NEVER HEARS. A signed-in person's hidden set is
 * personal (their reports, their blocks). A viewer with no account has none,
 * so the rule is the strict one: a take anyone reported, a take by a person an
 * open report names, and a take by anyone the inviter and that person have
 * blocked between them, are all withheld.
 *
 * THE FINISHED LISTING. Published productions, newest published first, a rule
 * stated here and never changed by engagement. A line the archive item no
 * longer carries (removed, P12) has no credit; a line whose performer deleted
 * their account stays on the item and is credited to no one.
 */

import { json, problem } from "./http.js";
import { sha256Hex } from "./jwt.js";
import { castParts, next, statusOf } from "./plays-relay.js";
import MANIFEST from "./castable-manifest.json";

export const INVITE_HEADER = "x-invite";
export const FINISHED_DEFAULT = 20;
export const FINISHED_MAX = 50;
export const OPEN_AUDIO_PATH = "/v1/plays/open/invite/takes";
const INVITE_CACHE = "private, max-age=30";
const AUDIO_CACHE = "private, max-age=300";
const FINISHED_CACHE = "public, max-age=300, s-maxage=300";
const CURSOR = /^(\d{1,16}):([A-Za-z0-9_-]{8,64})$/;

/** Is this one of the routes that need no account? Reads only. */
export const isOpenRoute = (pathname, method) =>
  method === "GET" &&
  (pathname === "/v1/plays/finished" || pathname.startsWith("/v1/plays/finished/") || pathname.startsWith("/v1/plays/open/"));

/** The audio route streams a lot of small files, so it counts apart from the reads. */
export const isOpenAudio = (pathname) => pathname.startsWith(`${OPEN_AUDIO_PATH}/`);

/* ---- The open invite ---- */

/** { p } for a live invite, { gone: true } for a revoked or expired one, null for no such invite. */
async function openInvite(env, token, now) {
  if (typeof token !== "string" || token.length < 20 || token.length > 100) return null;
  const inv = await env.DB.prepare("SELECT production_id, user_id, expires_at, revoked FROM play_invites WHERE token_hash = ?1")
    .bind(await sha256Hex(token))
    .first();
  if (!inv) return null;
  if (inv.revoked || inv.expires_at <= now) return { gone: true };
  const p = await env.DB.prepare("SELECT * FROM play_productions WHERE id = ?1").bind(inv.production_id).first();
  if (!p) return null;
  return { p: { ...p, cast: JSON.parse(p.cast_sheet) }, inviter: inv.user_id, expires_at: inv.expires_at };
}

const gone = () => json({ error: "invite_gone" }, 410, { "cache-control": INVITE_CACHE });

/** Takes a viewer with no account must not hear: see the header of this file. */
async function withheld(env, pid, inviter) {
  const [reports, blocks] = await Promise.all([
    env.DB.prepare("SELECT take_id, target_user_id, status FROM play_reports WHERE production_id = ?1")
      .bind(pid)
      .all()
      .then((r) => r.results),
    env.DB.prepare("SELECT user_id, blocked_id FROM play_blocks WHERE user_id = ?1 OR blocked_id = ?1")
      .bind(inviter)
      .all()
      .then((r) => r.results),
  ]);
  const takes = new Set(reports.filter((r) => r.take_id).map((r) => r.take_id));
  const people = new Set(reports.filter((r) => !r.take_id && r.status === "open" && r.target_user_id).map((r) => r.target_user_id));
  for (const b of blocks) people.add(b.user_id === inviter ? b.blocked_id : b.user_id);
  return (t) => takes.has(t.id) || people.has(t.user_id);
}

async function visibleChosen(env, p, inviter) {
  const { results } = await env.DB.prepare("SELECT * FROM play_takes WHERE production_id = ?1 AND chosen = 1 ORDER BY uploaded_at")
    .bind(p.id)
    .all();
  const hide = await withheld(env, p.id, inviter);
  return results.filter((t) => !hide(t));
}

async function viewOpenInvite(request, env, now) {
  const found = await openInvite(env, request.headers.get(INVITE_HEADER), now);
  if (!found) return problem(404, "invite_not_found");
  if (found.gone) return gone();
  const { p, inviter } = found;
  const [rows, members, job] = await Promise.all([
    env.DB.prepare("SELECT part, status, user_id, claimed_at FROM play_parts WHERE production_id = ?1")
      .bind(p.id)
      .all()
      .then((r) => Object.fromEntries(r.results.map((x) => [x.part, x]))),
    env.DB.prepare("SELECT user_id, display_name FROM play_members WHERE production_id = ?1 ORDER BY joined_at")
      .bind(p.id)
      .all()
      .then((r) => r.results),
    env.DB.prepare("SELECT status, item_url FROM play_archive_jobs WHERE production_id = ?1").bind(p.id).first(),
  ]);
  const takes = await visibleChosen(env, p, inviter);
  const names = Object.fromEntries(members.map((m) => [m.user_id, m.display_name]));
  const chosen = {};
  for (const t of takes) chosen[t.line_id] = t.id;
  return json(
    {
      id: p.id,
      scriptID: p.script_id,
      scriptRevision: p.script_revision,
      title: p.title,
      source: MANIFEST.scripts[p.script_id]?.source ?? null,
      parts: castParts(p.cast).map(({ id, lineCount }) => {
        const status = statusOf(rows, id, now);
        const part = { id, lineCount, status };
        if (status !== "open" && rows[id] && names[rows[id].user_id]) part.performer = names[rows[id].user_id];
        return part;
      }),
      members: members.map((m) => ({ name: m.display_name, director: m.user_id === p.user_id })),
      takes: takes.map((t) => ({
        id: t.id,
        lineID: t.line_id,
        part: t.part,
        frames: t.frames,
        sampleRate: t.sample_rate,
        audio: `${OPEN_AUDIO_PATH}/${encodeURIComponent(t.id)}/audio`,
      })),
      chosen,
      next: next(p.cast, rows, now),
      archive: job ? { status: job.status, url: job.item_url } : null,
      expires_at: found.expires_at,
      server_time: now,
    },
    200,
    { "cache-control": INVITE_CACHE },
  );
}

async function openTakeAudio(request, env, takeId, now) {
  const found = await openInvite(env, request.headers.get(INVITE_HEADER), now);
  if (!found) return problem(404, "invite_not_found");
  if (found.gone) return gone();
  const t = (await visibleChosen(env, found.p, found.inviter)).find((x) => x.id === takeId);
  if (!t) return problem(404, "no_such_take");
  if (!env.TAKES) return problem(503, "storage_not_configured");
  const obj = await env.TAKES.get(t.object_key);
  if (!obj) return problem(404, "no_such_take");
  return new Response(obj.body, { headers: { "content-type": t.content_type, "cache-control": AUDIO_CACHE } });
}

/* ---- Finished ear dramas ---- */

/** Each production's credits, part by part in script order: `{ part, name }`, name "" when no one is credited. */
async function creditsOf(env, ids) {
  const { results } = await env.DB.prepare(
    "SELECT f.production_id, f.part, m.display_name FROM play_archive_files f " +
      "LEFT JOIN play_takes t ON t.production_id = f.production_id AND t.id = f.take_id " +
      "LEFT JOIN play_members m ON m.production_id = f.production_id AND m.user_id = t.user_id " +
      "WHERE f.production_id IN (SELECT value FROM json_each(?1)) AND f.state IN ('pending', 'sent') ORDER BY f.production_id, f.seq",
  )
    .bind(JSON.stringify(ids))
    .all();
  const by = new Map(ids.map((id) => [id, new Map()]));
  for (const r of results) {
    const parts = by.get(r.production_id);
    const names = parts.get(r.part) || new Set();
    if (r.display_name) names.add(r.display_name);
    parts.set(r.part, names);
  }
  return new Map(
    [...by].map(([id, parts]) => [
      id,
      [...parts].flatMap(([part, names]) => (names.size ? [...names].map((name) => ({ part, name })) : [{ part, name: "" }])),
    ]),
  );
}

async function finishedFrom(env, rows) {
  const credits = await creditsOf(env, rows.map((r) => r.id));
  return rows.map((r) => ({
    id: r.id,
    script_id: r.script_id,
    title: r.title,
    source: MANIFEST.scripts[r.script_id]?.source ?? null,
    credits: credits.get(r.id),
    archive_url: r.item_url,
    published_at: r.published_at,
  }));
}

/** A production is finished once its job is published and at least one line is still on the item. */
const FINISHED =
  "SELECT j.production_id AS id, j.item_url, j.published_at, p.script_id, p.title FROM play_archive_jobs j " +
  "JOIN play_productions p ON p.id = j.production_id WHERE j.status = 'published' AND j.item_url IS NOT NULL AND j.published_at IS NOT NULL " +
  "AND EXISTS (SELECT 1 FROM play_archive_files f WHERE f.production_id = j.production_id AND f.state IN ('pending', 'sent'))";

async function listFinished(url, env) {
  const rawLimit = url.searchParams.get("limit");
  const limit = rawLimit === null ? FINISHED_DEFAULT : Number(rawLimit);
  if (!Number.isInteger(limit) || limit < 1 || limit > FINISHED_MAX) return problem(400, "bad_request", `limit is 1 to ${FINISHED_MAX}`);
  const rawCursor = url.searchParams.get("cursor");
  const cursor = rawCursor === null ? null : CURSOR.exec(rawCursor);
  if (rawCursor !== null && !cursor) return problem(400, "bad_request", "cursor");
  const stmt = cursor
    ? env.DB.prepare(`${FINISHED} AND (j.published_at, j.production_id) < (?1, ?2) ORDER BY j.published_at DESC, j.production_id DESC LIMIT ?3`).bind(
        Number(cursor[1]),
        cursor[2],
        limit + 1,
      )
    : env.DB.prepare(`${FINISHED} ORDER BY j.published_at DESC, j.production_id DESC LIMIT ?1`).bind(limit + 1);
  const { results } = await stmt.all();
  const page = results.slice(0, limit);
  const last = page[page.length - 1];
  return json(
    {
      productions: await finishedFrom(env, page),
      next_cursor: results.length > limit ? `${last.published_at}:${last.id}` : null,
    },
    200,
    { "cache-control": FINISHED_CACHE },
  );
}

async function getFinished(env, pid) {
  const row = await env.DB.prepare(`${FINISHED} AND j.production_id = ?1`).bind(pid).first();
  if (!row) return problem(404, "not_found");
  const [one] = await finishedFrom(env, [row]);
  return json(one, 200, { "cache-control": FINISHED_CACHE });
}

/** Every route that needs no account (index.js gates them by `isOpenRoute`). */
export async function handleOpen(url, request, env) {
  let seg;
  try {
    seg = url.pathname.slice("/v1/plays/".length).split("/").filter(Boolean).map(decodeURIComponent);
  } catch {
    return problem(400, "bad_request", "path");
  }
  const [a, b, c, d, e] = seg;
  if (a === "finished" && !b) return listFinished(url, env);
  if (a === "finished" && b && !c) return getFinished(env, b);
  if (a === "open" && b === "invite" && !c) return viewOpenInvite(request, env, Date.now());
  if (a === "open" && b === "invite" && c === "takes" && d && e === "audio" && seg.length === 5) return openTakeAudio(request, env, d, Date.now());
  return problem(404, "not_found");
}
