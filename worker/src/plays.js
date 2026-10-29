/**
 * Shared plays, phase 2: invite-only productions across devices (LOOP-PLAN M8,
 * docs/PLAYS-DESIGN.md §11). The HTTP, D1, and R2 adapter; the relay's rules
 * are in plays-relay.js, the name gate in plays-names.js, the audio check in
 * plays-audio.js.
 *
 * AN ACCOUNT IS REQUIRED (Decision 057): every route here is signed in.
 *
 * INVITE ONLY. A production is seen by its members: the director who made it
 * and whoever came in with an invite token. A token is 256 random bits,
 * returned once, stored as its SHA-256, revocable, and expiring.
 *
 * TAKES ARE OBJECTS, NOT ROWS. A take's audio goes to the TAKES bucket (R2:
 * free egress, 10 GB-month free); D1's row holds its metadata and object key.
 * D1 holds 500 MB a database on the free plan, under an hour of 24-bit mono
 * takes at 48 kHz, so audio never goes in it. The bucket is a placeholder until
 * the owner turns R2 on (it asks for a payment method on file; research 08c
 * Q8); without it, an upload answers 503 and nothing else changes.
 *
 * Nothing here calls archive.org. Publishing queues a job record whose status
 * is `pending_owner_account` until the Ear Drama account exists.
 */

import { json, limited, problem, readJson } from "./http.js";
import { randomToken, sha256Hex } from "./jwt.js";
import { castHash } from "./plays-manifest.js";
import { nameRefusal, cleanName } from "./plays-names.js";
import { MAX_TAKE_BYTES, MAX_TAKE_SECONDS, readTakeAudio } from "./plays-audio.js";
import {
  CLAIM_TTL_MS,
  castParts,
  claimRefusal,
  finishRefusal,
  incomplete,
  isClaimant,
  next,
  parseCast,
  partOf,
  reopenRefusal,
  silentRefusal,
  statusOf,
} from "./plays-relay.js";
import MANIFEST from "./castable-manifest.json";

/** Tables that hold no person's rows; test/account.test.js checks they reference no user. */
export const PLAYS_ANONYMOUS_TABLES = ["play_orphan_objects"];

/**
 * The CC0 consent (Decision 059). The version id is what a person agreed to;
 * the words are the owner's to write and approve, and until then the text is
 * this marked placeholder, never invented copy. Changing the words means a new
 * version id, and every performer must consent again before the play is
 * published. Uploading a take to the members needs no consent (Decision 072).
 */
export const CONSENT_VERSION = "cc0-2026-10-29";
export const CONSENT_TEXT = `Publishing puts this play on the Internet Archive.
- Your recording will be public. You can replace it with a new take or remove it later, but copies others have already made can't be called back.
- You dedicate it to the public domain (CC0). Anyone may copy, change, or sell it, for any purpose and without credit, including training AI and cloning voices.
- It must be your own live voice: no synthetic or cloned voices, and no imitating a real person.
- You're 13 or older, or your teacher has recorded your school's consent.`;

/** Every version ever served, so a consent recorded at a placeholder never counts (Decision 059). */
const CONSENT_TEXTS = {
  "cc0-placeholder-1": "OWNER: the CC0 consent words are pending the owner's approval (Decision 059).",
  [CONSENT_VERSION]: CONSENT_TEXT,
};
export const consentApproved = (version) => typeof CONSENT_TEXTS[version] === "string" && !CONSENT_TEXTS[version].startsWith("OWNER:");

export const INVITE_DEFAULT_DAYS = 7;
export const INVITE_MAX_DAYS = 30;
export const MAX_MEMBERS = 64;
export const MAX_TAKES_PER_LINE = 10;
export const MAX_PRODUCTIONS = 100;
export const REPORT_REASONS = ["offensive", "harassment", "personal_information", "not_a_performance", "other"];
const DAY_MS = 24 * 60 * 60 * 1000;
/** Seconds between 1970 and 2001: production.json dates are Foundation's. */
const REFERENCE_DATE_S = 978307200;
const foundation = (ms) => ms / 1000 - REFERENCE_DATE_S;
const ID = /^[A-Za-z0-9_-]{8,64}$/;
const CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
export const CLASS_CODE_LENGTH = 8;

/* ---- Reading ---- */

async function production(env, id) {
  const p = await env.DB.prepare("SELECT * FROM play_productions WHERE id = ?1").bind(id).first();
  if (!p) return null;
  return { ...p, cast: JSON.parse(p.cast_sheet) };
}

const member = (env, pid, userId) =>
  env.DB.prepare("SELECT display_name, joined_at FROM play_members WHERE production_id = ?1 AND user_id = ?2").bind(pid, userId).first();

async function partRows(env, pid) {
  const { results } = await env.DB.prepare("SELECT part, status, user_id, claimed_at FROM play_parts WHERE production_id = ?1")
    .bind(pid)
    .all();
  return Object.fromEntries(results.map((r) => [r.part, r]));
}

async function chosenLines(env, pid) {
  const { results } = await env.DB.prepare("SELECT line_id FROM play_takes WHERE production_id = ?1 AND chosen = 1").bind(pid).all();
  return new Set(results.map((r) => r.line_id));
}

/** Who `userId` has blocked, and who has blocked them. */
async function blockSets(env, userId) {
  const { results } = await env.DB.prepare("SELECT user_id, blocked_id FROM play_blocks WHERE user_id = ?1 OR blocked_id = ?1")
    .bind(userId)
    .all();
  return {
    blocked: new Set(results.filter((r) => r.user_id === userId).map((r) => r.blocked_id)),
    blockedBy: new Set(results.filter((r) => r.blocked_id === userId).map((r) => r.user_id)),
  };
}

/** Takes `userId` does not see: those of people they blocked, and those they reported. */
async function hiddenFrom(env, userId, pid) {
  const { blocked } = await blockSets(env, userId);
  const { results } = await env.DB.prepare(
    "SELECT take_id FROM play_reports WHERE user_id = ?1 AND production_id = ?2 AND take_id IS NOT NULL",
  )
    .bind(userId, pid)
    .all();
  const reported = new Set(results.map((r) => r.take_id));
  return (t) => blocked.has(t.user_id) || reported.has(t.id);
}

function takeOut(pid, t) {
  return {
    id: t.id,
    lineID: t.line_id,
    part: t.part,
    file: t.file,
    created: t.created,
    frames: t.frames,
    sampleRate: t.sample_rate,
    capture: t.capture,
    heard: JSON.parse(t.heard),
    loudness: t.loudness,
    peak: t.peak,
    bleed: false,
    user_id: t.user_id,
    audio: `/v1/plays/productions/${encodeURIComponent(pid)}/takes/${encodeURIComponent(t.id)}/audio`,
  };
}

/**
 * The production record, merged line by line from every member's takes, with
 * production.json's field names (Apple's Production, js/plays-core.js) so a
 * client decodes it with the model it already has. Fields past those are the
 * Worker's own and a phase 1 decoder ignores them.
 */
async function recordFor(env, p, userId, now) {
  const [rows, members, takes, job] = await Promise.all([
    partRows(env, p.id),
    env.DB.prepare("SELECT user_id, display_name, joined_at FROM play_members WHERE production_id = ?1 ORDER BY joined_at")
      .bind(p.id)
      .all()
      .then((r) => r.results),
    env.DB.prepare("SELECT * FROM play_takes WHERE production_id = ?1 ORDER BY uploaded_at").bind(p.id).all().then((r) => r.results),
    env.DB.prepare("SELECT status, created_at FROM play_archive_jobs WHERE production_id = ?1").bind(p.id).first(),
  ]);
  const hidden = await hiddenFrom(env, userId, p.id);
  const names = Object.fromEntries(members.map((m) => [m.user_id, m.display_name]));
  const parts = {};
  for (const { id } of castParts(p.cast)) {
    const status = statusOf(rows, id, now);
    const r = rows[id];
    const s = { status };
    if (status !== "open" && r) {
      if (names[r.user_id]) s.performer = names[r.user_id];
      s.user_id = r.user_id;
      if (status === "recording") s.claim_expires_at = r.claimed_at + CLAIM_TTL_MS;
    }
    parts[id] = s;
  }
  const visible = takes.filter((t) => !hidden(t));
  const chosen = {};
  for (const t of visible) if (t.chosen) chosen[t.line_id] = t.id;
  const out = {
    id: p.id,
    scriptID: p.script_id,
    scriptRevision: p.script_revision,
    title: p.title,
    created: foundation(p.created_at),
    parts,
    takes: visible.map((t) => takeOut(p.id, t)),
    chosen,
    roomTone: [],
    listenedThrough: false,
    director: p.user_id,
    members: members.map((m) => ({ user_id: m.user_id, display_name: m.display_name, director: m.user_id === p.user_id })),
    next: next(p.cast, rows, now),
    hidden_takes: takes.length - visible.length,
    archive: job ? { status: job.status, created_at: job.created_at } : null,
    uploads: !!env.TAKES,
    server_time: now,
  };
  if (p.user_id === userId) {
    const { results } = await env.DB.prepare(
      "SELECT id, created_at, expires_at, revoked FROM play_invites WHERE production_id = ?1 ORDER BY created_at",
    )
      .bind(p.id)
      .all();
    out.invites = results.map((i) => ({ ...i, revoked: !!i.revoked }));
  }
  return out;
}

/* ---- Productions ---- */

async function createProduction(auth, request, env, now) {
  const { body, error } = await readJson(request, 2 * 1024 * 1024);
  if (error) return error;
  const entry = typeof body.script_id === "string" && Object.hasOwn(MANIFEST.scripts, body.script_id) ? MANIFEST.scripts[body.script_id] : null;
  if (!entry) return problem(422, "not_castable");
  if (body.script_revision !== entry.revision) return problem(409, "revision_mismatch", entry.revision);
  const cast = parseCast(body.cast);
  if (!cast) return problem(400, "bad_request", "cast is [{ id, part }] in script order");
  if ((await castHash(cast)) !== entry.cast) return problem(422, "cast_mismatch");
  const refusal = nameRefusal(body.display_name);
  if (refusal) return problem(422, refusal);
  const count = await env.DB.prepare("SELECT COUNT(*) AS n FROM play_productions WHERE user_id = ?1").bind(auth.userId).first();
  if (count.n >= MAX_PRODUCTIONS) return problem(409, "too_many_productions");

  const id = crypto.randomUUID().toUpperCase();
  await env.DB.batch([
    env.DB.prepare(
      "INSERT INTO play_productions (id, user_id, script_id, script_revision, title, cast_sheet, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?7)",
    ).bind(id, auth.userId, body.script_id, entry.revision, entry.title, JSON.stringify(cast), now),
    env.DB.prepare("INSERT INTO play_members (production_id, user_id, display_name, joined_at) VALUES (?1, ?2, ?3, ?4)").bind(
      id,
      auth.userId,
      cleanName(body.display_name),
      now,
    ),
  ]);
  return json(await recordFor(env, await production(env, id), auth.userId, now), 201);
}

async function listProductions(auth, env) {
  const { results } = await env.DB.prepare(
    "SELECT p.id, p.title, p.script_id, p.user_id AS director, p.updated_at FROM play_productions p " +
      "JOIN play_members m ON m.production_id = p.id WHERE m.user_id = ?1 ORDER BY p.updated_at DESC",
  )
    .bind(auth.userId)
    .all();
  return json({ productions: results });
}

/** Sets a part's row, or clears it to open. */
const setPart = (env, pid, part, status, userId, now) =>
  status === null
    ? env.DB.prepare("DELETE FROM play_parts WHERE production_id = ?1 AND part = ?2").bind(pid, part)
    : env.DB.prepare(
        "INSERT INTO play_parts (production_id, part, status, user_id, claimed_at) VALUES (?1, ?2, ?3, ?4, ?5) " +
          "ON CONFLICT (production_id, part) DO UPDATE SET status = excluded.status, user_id = excluded.user_id, claimed_at = excluded.claimed_at",
      ).bind(pid, part, status, userId, now);

const touch = (env, pid, now) => env.DB.prepare("UPDATE play_productions SET updated_at = ?2 WHERE id = ?1").bind(pid, now);

async function claim(env, p, userId, part, now) {
  const rows = await partRows(env, p.id);
  const refusal = claimRefusal(p.cast, rows, part, now);
  if (refusal) return problem(409, refusal.error, refusal.detail);
  await env.DB.batch([setPart(env, p.id, part, "recording", userId, now), touch(env, p.id, now)]);
  return null;
}

async function claimAsMember(auth, request, env, p, now) {
  const { body, error } = await readJson(request, 8 * 1024);
  if (error) return error;
  const refused = await claim(env, p, auth.userId, body.part, now);
  return refused || json(await recordFor(env, p, auth.userId, now));
}

async function partAction(auth, env, p, part, action, now) {
  if (!castParts(p.cast).some((x) => x.id === part)) return problem(404, "no_such_part");
  const rows = await partRows(env, p.id);
  let refusal;
  let status;
  if (action === "done") {
    refusal = finishRefusal(p.cast, rows, part, auth.userId, await chosenLines(env, p.id), now);
    status = "done";
  } else if (action === "silent") {
    refusal = silentRefusal(p.cast, rows, part, auth.userId, now);
    status = "silent";
  } else if (action === "reopen") {
    refusal = reopenRefusal(p.cast, rows, part, auth.userId, p.user_id, now);
    status = "recording";
  } else if (action === "release") {
    refusal = isClaimant(rows, part, auth.userId, now) ? null : { error: "not_your_claim" };
    status = null;
  } else return problem(404, "not_found");
  if (refusal) return problem(409, refusal.error, refusal.detail);
  await env.DB.batch([setPart(env, p.id, part, status, auth.userId, now), touch(env, p.id, now)]);
  return json(await recordFor(env, p, auth.userId, now));
}

/* ---- Invites ---- */

async function createInvite(auth, request, env, p, now) {
  if (p.user_id !== auth.userId) return problem(403, "director_only");
  const { body, error } = await readJson(request, 4 * 1024);
  if (error) return error;
  const days = body.expires_in_days === undefined ? INVITE_DEFAULT_DAYS : Number(body.expires_in_days);
  if (!Number.isInteger(days) || days < 1 || days > INVITE_MAX_DAYS) return problem(400, "bad_request", `expires_in_days is 1 to ${INVITE_MAX_DAYS}`);
  const token = randomToken(32);
  const id = randomToken(12);
  const expires = now + days * DAY_MS;
  await env.DB.prepare(
    "INSERT INTO play_invites (id, production_id, user_id, token_hash, created_at, expires_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
  )
    .bind(id, p.id, auth.userId, await sha256Hex(token), now, expires)
    .run();
  return json({ id, token, expires_at: expires }, 201);
}

async function revokeInvite(auth, env, p, inviteId) {
  if (p.user_id !== auth.userId) return problem(403, "director_only");
  const r = await env.DB.prepare("UPDATE play_invites SET revoked = 1 WHERE id = ?1 AND production_id = ?2").bind(inviteId, p.id).run();
  return r.meta.changes ? new Response(null, { status: 204 }) : problem(404, "not_found");
}

/**
 * The production an invite token opens for `userId`, or null. An unknown,
 * revoked, or expired token, and one whose maker and holder have a block
 * between them either way, all look the same: not found.
 */
async function redeem(env, token, userId, now) {
  if (typeof token !== "string" || token.length < 20 || token.length > 100) return null;
  const inv = await env.DB.prepare("SELECT production_id, user_id, expires_at, revoked FROM play_invites WHERE token_hash = ?1")
    .bind(await sha256Hex(token))
    .first();
  if (!inv || inv.revoked || inv.expires_at <= now) return null;
  const { blocked, blockedBy } = await blockSets(env, userId);
  if (blocked.has(inv.user_id) || blockedBy.has(inv.user_id)) return null;
  return production(env, inv.production_id);
}

/** POST /v1/plays/invites/view { token }: the cast sheet, for deciding which part to take. */
async function viewInvite(auth, request, env, now) {
  if (await limited(env.PLAY_JOIN_LIMITER, auth.userId)) return problem(429, "rate_limited");
  const { body, error } = await readJson(request, 4 * 1024);
  if (error) return error;
  const p = await redeem(env, body.token, auth.userId, now);
  if (!p) return problem(404, "invite_not_found");
  const rows = await partRows(env, p.id);
  return json({
    id: p.id,
    scriptID: p.script_id,
    scriptRevision: p.script_revision,
    title: p.title,
    parts: castParts(p.cast).map(({ id, lineCount }) => ({ id, lineCount, status: statusOf(rows, id, now) })),
    next: next(p.cast, rows, now),
    member: !!(await member(env, p.id, auth.userId)),
  });
}

/** POST /v1/plays/invites/claim { token, part, display_name? }: join and take one part. */
async function claimByInvite(auth, request, env, now) {
  if (await limited(env.PLAY_JOIN_LIMITER, auth.userId)) return problem(429, "rate_limited");
  const { body, error } = await readJson(request, 4 * 1024);
  if (error) return error;
  const p = await redeem(env, body.token, auth.userId, now);
  if (!p) return problem(404, "invite_not_found");
  const refusal = nameRefusal(body.display_name);
  if (refusal) return problem(422, refusal);
  if (!(await member(env, p.id, auth.userId))) {
    const n = await env.DB.prepare("SELECT COUNT(*) AS n FROM play_members WHERE production_id = ?1").bind(p.id).first();
    if (n.n >= MAX_MEMBERS) return problem(409, "production_full");
    const rows = await partRows(env, p.id);
    const r = claimRefusal(p.cast, rows, body.part, now);
    if (r) return problem(409, r.error, r.detail);
    await env.DB.prepare(
      "INSERT INTO play_members (production_id, user_id, display_name, joined_at) VALUES (?1, ?2, ?3, ?4) ON CONFLICT DO NOTHING",
    )
      .bind(p.id, auth.userId, cleanName(body.display_name), now)
      .run();
  }
  const refused = await claim(env, p, auth.userId, body.part, now);
  return refused || json(await recordFor(env, p, auth.userId, now));
}

/* ---- Takes ---- */

function parseTakeMeta(raw) {
  let m;
  try {
    m = JSON.parse(raw || "");
  } catch {
    return null;
  }
  if (!m || typeof m !== "object" || Array.isArray(m) || typeof m.lineID !== "string") return null;
  if (m.capture !== undefined && !["direct", "aec"].includes(m.capture)) return null;
  const heard = m.heard === undefined ? {} : m.heard;
  if (!heard || typeof heard !== "object" || Array.isArray(heard) || Object.keys(heard).length > 64) return null;
  for (const [k, v] of Object.entries(heard)) if (k.length > 64 || typeof v !== "string" || v.length > 64) return null;
  const num = (v, lo, hi) => v === undefined || v === null || (typeof v === "number" && Number.isFinite(v) && v >= lo && v <= hi);
  if (!num(m.loudness, -200, 20) || !num(m.peak, 0, 16) || !num(m.frames, 0, 1e9) || !num(m.sampleRate, 0, 400000)) return null;
  if (!num(m.created, -1e10, 1e10)) return null;
  if (m.file !== undefined && (typeof m.file !== "string" || !/^[A-Za-z0-9._-]{1,100}$/.test(m.file))) return null;
  return { ...m, heard, capture: m.capture || "direct" };
}

/** PUT /v1/plays/productions/:id/takes/:takeId, the audio as the body, the take's fields in `x-take`. */
async function uploadTake(auth, request, env, p, takeId, now) {
  if (await limited(env.PLAY_UPLOAD_LIMITER, auth.userId)) return problem(429, "rate_limited");
  if (!env.TAKES) return problem(503, "storage_not_configured");
  if (!ID.test(takeId)) return problem(400, "bad_request", "take id");
  const meta = parseTakeMeta(request.headers.get("x-take"));
  if (!meta) return problem(400, "bad_request", "x-take must be the take's fields as JSON");
  const part = partOf(p.cast, meta.lineID);
  if (!part) return problem(422, "no_such_line");
  if (meta.part !== undefined && meta.part !== part) return problem(422, "line_is_another_part", part);
  if (!isClaimant(await partRows(env, p.id), part, auth.userId, now)) return problem(403, "not_your_claim");
  // No CC0 consent here (Decision 072): a take on the Worker reaches only this
  // production's members. The consent is asked before publishing, which goes beyond them.
  // A take the bleed check flagged holds the device voice, which is never stored (§5 rule 2, §8 rule 3).
  if (meta.bleed === true) return problem(422, "bleed_flagged");

  if (Number(request.headers.get("content-length") || 0) > MAX_TAKE_BYTES) return problem(413, "too_large");
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.length > MAX_TAKE_BYTES) return problem(413, "too_large");
  const audio = readTakeAudio(bytes);
  if (!audio) return problem(415, "unsupported_audio", "mono WAV or FLAC");
  if (audio.frames / audio.sampleRate > MAX_TAKE_SECONDS) return problem(413, "take_too_long", `${MAX_TAKE_SECONDS} s`);
  if (meta.sampleRate && meta.sampleRate !== audio.sampleRate) return problem(422, "audio_mismatch", "sampleRate");
  if (meta.frames !== undefined && Math.abs(meta.frames - audio.frames) > audio.sampleRate * 0.05) {
    return problem(422, "audio_mismatch", "frames");
  }

  const count = await env.DB.prepare("SELECT COUNT(*) AS n FROM play_takes WHERE production_id = ?1 AND line_id = ?2")
    .bind(p.id, meta.lineID)
    .first();
  if (count.n >= MAX_TAKES_PER_LINE) return problem(409, "too_many_takes");

  const key = `plays/${p.id}/${takeId}-${randomToken(6)}.${audio.ext}`;
  await env.TAKES.put(key, bytes, { httpMetadata: { contentType: audio.type } });
  const file = meta.file || `${takeId}.${audio.ext}`;
  const ins = await env.DB.prepare(
    "INSERT INTO play_takes (production_id, id, user_id, line_id, part, file, object_key, content_type, bytes, frames, sample_rate, " +
      "capture, heard, loudness, peak, created, uploaded_at, chosen) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, 0) " +
      "ON CONFLICT DO NOTHING",
  )
    .bind(
      p.id,
      takeId,
      auth.userId,
      meta.lineID,
      part,
      file,
      key,
      audio.type,
      bytes.length,
      audio.frames,
      audio.sampleRate,
      meta.capture,
      JSON.stringify(meta.heard),
      meta.loudness ?? null,
      meta.peak ?? 0,
      meta.created ?? foundation(now),
      now,
    )
    .run();
  // A take id is used once (§8 rule 5): the object key is new on every upload,
  // so a reused id never touches the first take's audio, and its row stays.
  if (!ins.meta.changes) {
    await env.TAKES.delete(key);
    return problem(409, "take_exists");
  }
  // A new take becomes the line's chosen one; the older takes stay (§8 rule 5).
  await env.DB.batch([...chooseStatements(env, p.id, meta.lineID, takeId), touch(env, p.id, now)]);
  const row = await env.DB.prepare("SELECT * FROM play_takes WHERE production_id = ?1 AND id = ?2").bind(p.id, takeId).first();
  return json(takeOut(p.id, row), 201);
}

const chooseStatements = (env, pid, lineID, takeId) => [
  env.DB.prepare("UPDATE play_takes SET chosen = 0 WHERE production_id = ?1 AND line_id = ?2 AND chosen = 1").bind(pid, lineID),
  env.DB.prepare("UPDATE play_takes SET chosen = 1 WHERE production_id = ?1 AND id = ?2").bind(pid, takeId),
];

async function chooseTake(auth, request, env, p, now) {
  const { body, error } = await readJson(request, 4 * 1024);
  if (error) return error;
  const t = await env.DB.prepare("SELECT line_id, part FROM play_takes WHERE production_id = ?1 AND id = ?2").bind(p.id, body.take_id).first();
  if (!t) return problem(404, "no_such_take");
  if (!isClaimant(await partRows(env, p.id), t.part, auth.userId, now)) return problem(403, "not_your_claim");
  await env.DB.batch([...chooseStatements(env, p.id, t.line_id, body.take_id), touch(env, p.id, now)]);
  return json(await recordFor(env, p, auth.userId, now));
}

async function takeAudio(auth, env, p, takeId) {
  const t = await env.DB.prepare("SELECT id, user_id, object_key, content_type FROM play_takes WHERE production_id = ?1 AND id = ?2")
    .bind(p.id, takeId)
    .first();
  if (!t || (await hiddenFrom(env, auth.userId, p.id))(t)) return problem(404, "no_such_take");
  if (!env.TAKES) return problem(503, "storage_not_configured");
  const obj = await env.TAKES.get(t.object_key);
  if (!obj) return problem(404, "no_such_take");
  return new Response(obj.body, { headers: { "content-type": t.content_type, "cache-control": "private, max-age=3600" } });
}

/* ---- Consent and publishing ---- */

async function consent(auth, request, env, p, now) {
  const { body, error } = await readJson(request, 4 * 1024);
  if (error) return error;
  if (body.version !== CONSENT_VERSION) return problem(409, "consent_version_mismatch", CONSENT_VERSION);
  await env.DB.prepare(
    "INSERT INTO play_consents (user_id, production_id, version, consented_at) VALUES (?1, ?2, ?3, ?4) ON CONFLICT DO NOTHING",
  )
    .bind(auth.userId, p.id, CONSENT_VERSION, now)
    .run();
  return new Response(null, { status: 204 });
}

/** POST /v1/plays/productions/:id/publish: queues the archive.org upload; calls nothing. */
async function publish(auth, env, p, now) {
  if (p.user_id !== auth.userId) return problem(403, "director_only");
  const job = await env.DB.prepare("SELECT status, take_ids, created_at FROM play_archive_jobs WHERE production_id = ?1").bind(p.id).first();
  if (job) return json({ status: job.status, take_ids: JSON.parse(job.take_ids), created_at: job.created_at });
  const left = incomplete(p.cast, await partRows(env, p.id), await chosenLines(env, p.id), now);
  if (left) return problem(409, "incomplete", left);
  const { results: chosen } = await env.DB.prepare("SELECT id, user_id FROM play_takes WHERE production_id = ?1 AND chosen = 1 ORDER BY line_id")
    .bind(p.id)
    .all();
  const { results: reported } = await env.DB.prepare(
    "SELECT DISTINCT take_id FROM play_reports WHERE production_id = ?1 AND status = 'open' AND take_id IS NOT NULL",
  )
    .bind(p.id)
    .all();
  const flagged = new Set(reported.map((r) => r.take_id));
  const held = chosen.filter((t) => flagged.has(t.id)).map((t) => t.id);
  if (held.length) return problem(409, "reported_take", held);
  const performers = [...new Set(chosen.map((t) => t.user_id))];
  const { results: agreed } = await env.DB.prepare("SELECT user_id, version FROM play_consents WHERE production_id = ?1 AND version = ?2")
    .bind(p.id, CONSENT_VERSION)
    .all();
  const ok = new Set(agreed.filter((r) => consentApproved(r.version)).map((r) => r.user_id));
  const missing = performers.filter((u) => !ok.has(u));
  if (missing.length) return problem(409, "consent_missing", missing);
  const takeIds = chosen.map((t) => t.id);
  await env.DB.prepare(
    "INSERT INTO play_archive_jobs (production_id, user_id, status, take_ids, created_at, updated_at) VALUES (?1, ?2, 'pending_owner_account', ?3, ?4, ?4)",
  )
    .bind(p.id, auth.userId, JSON.stringify(takeIds), now)
    .run();
  return json({ status: "pending_owner_account", take_ids: takeIds, created_at: now }, 201);
}

/* ---- Reports and blocks (App Store guideline 1.2) ---- */

async function report(auth, request, env, now) {
  const { body, error } = await readJson(request, 8 * 1024);
  if (error) return error;
  if (typeof body.production_id !== "string" || !(await member(env, body.production_id, auth.userId))) {
    return problem(404, "not_found");
  }
  if (!REPORT_REASONS.includes(body.reason)) return problem(400, "bad_request", `reason is one of ${REPORT_REASONS.join(", ")}`);
  const note = typeof body.note === "string" ? body.note.trim() : "";
  if (note.length > 500 || /[\u0000-\u0009\u000b-\u001f]/.test(note)) return problem(400, "bad_request", "note");
  let target;
  let takeId = null;
  if (typeof body.take_id === "string" && body.user_id === undefined) {
    const t = await env.DB.prepare("SELECT user_id FROM play_takes WHERE production_id = ?1 AND id = ?2").bind(body.production_id, body.take_id).first();
    if (!t) return problem(404, "no_such_take");
    target = t.user_id;
    takeId = body.take_id;
  } else if (typeof body.user_id === "string" && body.take_id === undefined) {
    if (body.user_id === auth.userId || !(await member(env, body.production_id, body.user_id))) return problem(404, "no_such_member");
    target = body.user_id;
  } else return problem(400, "bad_request", "report a take_id or a user_id");
  const id = randomToken(12);
  await env.DB.prepare(
    "INSERT INTO play_reports (id, user_id, production_id, target_user_id, take_id, reason, note, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
  )
    .bind(id, auth.userId, body.production_id, target, takeId, body.reason, note, now)
    .run();
  return json({ id }, 201);
}

async function block(auth, request, env, now) {
  const { body, error } = await readJson(request, 4 * 1024);
  if (error) return error;
  if (typeof body.user_id !== "string" || body.user_id === auth.userId) return problem(400, "bad_request", "user_id");
  // Answers the same whether or not the account exists, so a block cannot probe for one.
  await env.DB.prepare(
    "INSERT INTO play_blocks (user_id, blocked_id, created_at) SELECT ?1, ?2, ?3 WHERE EXISTS (SELECT 1 FROM users WHERE id = ?2) ON CONFLICT DO NOTHING",
  )
    .bind(auth.userId, body.user_id, now)
    .run();
  return new Response(null, { status: 204 });
}

/* ---- Teacher classes (Decision 059) ---- */

export function classCode(bytes) {
  return [...bytes].map((b) => CODE_ALPHABET[b % 32]).join("");
}

export const normalizeClassCode = (raw) =>
  typeof raw === "string" ? raw.toUpperCase().replace(/[\s-]/g, "").replace(/O/g, "0").replace(/[IL]/g, "1") : "";

async function createClass(auth, request, env, now) {
  const { body, error } = await readJson(request, 4 * 1024);
  if (error) return error;
  const name = cleanName(body.name);
  if (!name) return problem(400, "bad_request", "name");
  const refusal = nameRefusal(name);
  if (refusal) return problem(422, refusal);
  if (body.under13 !== undefined && typeof body.under13 !== "boolean") return problem(400, "bad_request", "under13 is true or false");
  const id = crypto.randomUUID();
  for (let attempt = 0; attempt < 3; attempt++) {
    const bytes = new Uint8Array(CLASS_CODE_LENGTH);
    crypto.getRandomValues(bytes);
    const code = classCode(bytes);
    const r = await env.DB.prepare(
      "INSERT INTO play_classes (id, user_id, name, code, under13, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6) ON CONFLICT (code) DO NOTHING",
    )
      .bind(id, auth.userId, name, code, body.under13 ? 1 : 0, now)
      .run();
    if (r.meta.changes) return json({ id, name, code, under13: !!body.under13, school_consent: false }, 201);
  }
  return problem(503, "try_again");
}

async function joinClass(auth, request, env, now) {
  if (await limited(env.PLAY_JOIN_LIMITER, auth.userId)) return problem(429, "rate_limited");
  const { body, error } = await readJson(request, 4 * 1024);
  if (error) return error;
  const c = await env.DB.prepare(
    "SELECT c.id, c.user_id, c.name, c.under13, s.class_id AS consent FROM play_classes c " +
      "LEFT JOIN play_school_consents s ON s.class_id = c.id WHERE c.code = ?1",
  )
    .bind(normalizeClassCode(body.code))
    .first();
  if (!c) return problem(404, "class_not_found");
  if (c.user_id === auth.userId) return problem(409, "you_teach_this_class");
  // Decision 059: under 13, only with the school's consent on record.
  if (c.under13 && !c.consent) return problem(403, "school_consent_required");
  const refusal = nameRefusal(body.display_name);
  if (refusal) return problem(422, refusal);
  await env.DB.prepare(
    "INSERT INTO play_class_members (class_id, user_id, display_name, joined_at) VALUES (?1, ?2, ?3, ?4) ON CONFLICT DO NOTHING",
  )
    .bind(c.id, auth.userId, cleanName(body.display_name), now)
    .run();
  return json({ id: c.id, name: c.name, under13: !!c.under13 });
}

async function schoolConsent(auth, request, env, classId, now) {
  const c = await env.DB.prepare("SELECT user_id FROM play_classes WHERE id = ?1").bind(classId).first();
  if (!c) return problem(404, "class_not_found");
  if (c.user_id !== auth.userId) return problem(403, "teacher_only");
  // The record is a placeholder for the privacy policy that covers school
  // consent (Decision 059); until the owner names its version, none is taken.
  if (!env.SCHOOL_CONSENT_POLICY) return problem(503, "pending_owner_policy");
  const { body, error } = await readJson(request, 4 * 1024);
  if (error) return error;
  const reference = typeof body.reference === "string" ? body.reference.trim() : "";
  if (reference.length > 120 || /[\u0000-\u001f]/.test(reference)) return problem(400, "bad_request", "reference");
  await env.DB.prepare(
    "INSERT INTO play_school_consents (class_id, user_id, policy_version, reference, recorded_at) VALUES (?1, ?2, ?3, ?4, ?5) " +
      "ON CONFLICT (class_id) DO UPDATE SET user_id = excluded.user_id, policy_version = excluded.policy_version, reference = excluded.reference, recorded_at = excluded.recorded_at",
  )
    .bind(classId, auth.userId, env.SCHOOL_CONSENT_POLICY, reference, now)
    .run();
  return json({ class_id: classId, policy_version: env.SCHOOL_CONSENT_POLICY, recorded_at: now }, 201);
}

async function getClass(auth, env, classId) {
  const c = await env.DB.prepare(
    "SELECT c.*, s.policy_version FROM play_classes c LEFT JOIN play_school_consents s ON s.class_id = c.id WHERE c.id = ?1",
  )
    .bind(classId)
    .first();
  if (!c) return problem(404, "class_not_found");
  if (c.user_id === auth.userId) {
    const { results } = await env.DB.prepare(
      "SELECT user_id, display_name, joined_at FROM play_class_members WHERE class_id = ?1 ORDER BY joined_at",
    )
      .bind(classId)
      .all();
    return json({ id: c.id, name: c.name, code: c.code, under13: !!c.under13, school_consent: !!c.policy_version, members: results });
  }
  const m = await env.DB.prepare("SELECT 1 FROM play_class_members WHERE class_id = ?1 AND user_id = ?2").bind(classId, auth.userId).first();
  if (!m) return problem(404, "class_not_found");
  return json({ id: c.id, name: c.name, under13: !!c.under13 });
}

async function listClasses(auth, env) {
  const [t, m] = await env.DB.batch([
    env.DB.prepare("SELECT c.id, c.name, c.code, c.under13, s.policy_version FROM play_classes c LEFT JOIN play_school_consents s ON s.class_id = c.id WHERE c.user_id = ?1 ORDER BY c.created_at").bind(auth.userId),
    env.DB.prepare(
      "SELECT c.id, c.name, c.under13 FROM play_class_members m JOIN play_classes c ON c.id = m.class_id WHERE m.user_id = ?1 ORDER BY m.joined_at",
    ).bind(auth.userId),
  ]);
  const flag = (r) => ({ ...r, under13: !!r.under13 });
  const taught = ({ policy_version, ...r }) => ({ ...flag(r), school_consent: !!policy_version });
  return json({ teaching: t.results.map(taught), member_of: m.results.map(flag) });
}

async function removeClassMember(auth, env, classId, userId) {
  const c = await env.DB.prepare("SELECT user_id FROM play_classes WHERE id = ?1").bind(classId).first();
  if (!c || (c.user_id !== auth.userId && userId !== auth.userId)) return problem(404, "class_not_found");
  await env.DB.prepare("DELETE FROM play_class_members WHERE class_id = ?1 AND user_id = ?2").bind(classId, userId).run();
  return new Response(null, { status: 204 });
}

/* ---- Routing ---- */

/** Every /v1/plays route; the caller is already signed in (index.js). */
export async function handlePlays(url, request, env, auth) {
  let seg;
  try {
    seg = url.pathname.slice("/v1/plays".length).split("/").filter(Boolean).map(decodeURIComponent);
  } catch {
    return problem(400, "bad_request", "path");
  }
  const m = request.method;
  const now = Date.now();
  const [a, b, c, d, e] = seg;

  if (a === "consent" && !b && m === "GET") return json({ version: CONSENT_VERSION, text: CONSENT_TEXT, uploads: !!env.TAKES, publishes: !!env.IA_ACCESS });
  if (a === "invites" && b === "view" && !c && m === "POST") return viewInvite(auth, request, env, now);
  if (a === "invites" && b === "claim" && !c && m === "POST") return claimByInvite(auth, request, env, now);
  if (a === "reports" && !b && m === "POST") return report(auth, request, env, now);
  if (a === "blocks" && !b && m === "POST") return block(auth, request, env, now);
  if (a === "blocks" && !b && m === "GET") {
    const { results } = await env.DB.prepare("SELECT blocked_id FROM play_blocks WHERE user_id = ?1").bind(auth.userId).all();
    return json({ blocked: results.map((r) => r.blocked_id) });
  }
  if (a === "blocks" && b && !c && m === "DELETE") {
    await env.DB.prepare("DELETE FROM play_blocks WHERE user_id = ?1 AND blocked_id = ?2").bind(auth.userId, b).run();
    return new Response(null, { status: 204 });
  }

  if (a === "classes") {
    if (!b && m === "POST") return createClass(auth, request, env, now);
    if (!b && m === "GET") return listClasses(auth, env);
    if (b === "join" && !c && m === "POST") return joinClass(auth, request, env, now);
    if (b && !c && m === "GET") return getClass(auth, env, b);
    if (b && c === "school-consent" && !d && m === "POST") return schoolConsent(auth, request, env, b, now);
    if (b && c === "members" && d && !e && m === "DELETE") return removeClassMember(auth, env, b, d);
    return problem(404, "not_found");
  }

  if (a !== "productions") return problem(404, "not_found");
  if (!b && m === "POST") return createProduction(auth, request, env, now);
  if (!b && m === "GET") return listProductions(auth, env);

  // Everything below is a member's. Not a member and no such production look the same.
  const p = await production(env, b);
  if (!p || !(await member(env, p.id, auth.userId))) return problem(404, "not_found");
  if (!c && m === "GET") return json(await recordFor(env, p, auth.userId, now));
  if (c === "invites" && !d && m === "POST") return createInvite(auth, request, env, p, now);
  if (c === "invites" && d && !e && m === "DELETE") return revokeInvite(auth, env, p, d);
  if (c === "claim" && !d && m === "POST") return claimAsMember(auth, request, env, p, now);
  if (c === "parts" && d && e && m === "POST" && seg.length === 5) return partAction(auth, env, p, d, e, now);
  if (c === "takes" && d && !e && m === "PUT") return uploadTake(auth, request, env, p, d, now);
  if (c === "takes" && d && e === "audio" && seg.length === 5 && m === "GET") return takeAudio(auth, env, p, d);
  if (c === "chosen" && !d && m === "POST") return chooseTake(auth, request, env, p, now);
  if (c === "consent" && !d && m === "POST") return consent(auth, request, env, p, now);
  if (c === "publish" && !d && m === "POST") return publish(auth, env, p, now);
  return problem(404, "not_found");
}

/* ---- Account deletion and the sweep ---- */

/**
 * Before an account's rows go (account.js): its productions with anyone else
 * in them pass to the member who joined first, and the audio of every take
 * that is about to lose its row is deleted from the bucket. A failed object
 * deletion is queued in play_orphan_objects for the sweep, never left behind
 * unindexed. Returns statements for the deletion batch.
 */
export async function playsBeforeDeletion(env, userId) {
  await env.DB.prepare(
    "UPDATE play_productions SET user_id = (SELECT m.user_id FROM play_members m WHERE m.production_id = play_productions.id AND m.user_id <> ?1 ORDER BY m.joined_at, m.user_id LIMIT 1) " +
      "WHERE user_id = ?1 AND EXISTS (SELECT 1 FROM play_members m WHERE m.production_id = play_productions.id AND m.user_id <> ?1)",
  )
    .bind(userId)
    .run();
  const { results } = await env.DB.prepare(
    "SELECT object_key FROM play_takes WHERE user_id = ?1 OR production_id IN (SELECT id FROM play_productions WHERE user_id = ?1)",
  )
    .bind(userId)
    .all();
  const keys = results.map((r) => r.object_key);
  const orphans = await deleteObjects(env, keys);
  const now = Date.now();
  return orphans.map((k) => env.DB.prepare("INSERT OR IGNORE INTO play_orphan_objects (object_key, queued_at) VALUES (?1, ?2)").bind(k, now));
}

/** Deletes objects from the bucket; returns the keys that could not be deleted. */
async function deleteObjects(env, keys) {
  if (!keys.length) return [];
  if (!env.TAKES) return keys;
  const failed = [];
  for (let i = 0; i < keys.length; i += 1000) {
    const chunk = keys.slice(i, i + 1000);
    try {
      await env.TAKES.delete(chunk);
    } catch {
      failed.push(...chunk);
    }
  }
  return failed;
}

/** The hourly sweep: lapsed claims reopen, expired invites go, orphaned objects are retried. */
export async function sweepPlays(env, now = Date.now()) {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM play_parts WHERE status = 'recording' AND claimed_at < ?1").bind(now - CLAIM_TTL_MS),
    env.DB.prepare("DELETE FROM play_invites WHERE expires_at < ?1").bind(now),
  ]);
  const { results } = await env.DB.prepare("SELECT object_key FROM play_orphan_objects LIMIT 1000").all();
  const keys = results.map((r) => r.object_key);
  const failed = new Set(await deleteObjects(env, keys));
  const done = keys.filter((k) => !failed.has(k));
  if (done.length) {
    await env.DB.batch(done.map((k) => env.DB.prepare("DELETE FROM play_orphan_objects WHERE object_key = ?1").bind(k)));
  }
}
