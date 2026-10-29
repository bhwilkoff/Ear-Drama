/**
 * The archive.org uploader (LOOP-PLAN P14 and P12, Decision 073,
 * docs/PLAYS-DESIGN.md §11.5). The cron takes publish jobs and makes one
 * archive.org item per production through the S3-like API, one file per line
 * in script order; it then carries out a performer's replacement or removal.
 *
 * RUNS ONLY WITH BOTH KEYS. Nothing here runs unless IA_S3_ACCESS_KEY and
 * IA_S3_SECRET_KEY are both set, and the same check is `publishes` for the
 * clients. The keys go only into the Authorization header and the metadata
 * form; nothing logs a header, a URL with a key, or a body, and every reason
 * stored from archive.org's answer passes through `redact` first.
 *
 * IDEMPOTENT BY NAME. The identifier is fixed by the production id and each
 * line's file name by its place in the script, so a retry sends to the same
 * name and archive.org overwrites it rather than adding a copy. A file
 * archive.org confirmed (2xx) is marked sent and never sent again, and a
 * lease keeps two cron runs off one job.
 *
 * POLITE. At most REQUESTS_PER_RUN requests to archive.org a run, one at a
 * time, with an honest User-Agent; check_limit before the first upload; 429,
 * 5xx (503 SlowDown is the one archive.org documents), and network errors back
 * off exponentially and give up after MAX_ATTEMPTS. Any other 4xx (a size
 * refusal, a refused key, an identifier someone else holds) is archive.org's
 * answer and is not retried. 404 on a delete means the file is already gone.
 */

import { castParts } from "./plays-relay.js";
import { MAX_TAKE_BYTES } from "./plays-audio.js";
import MANIFEST from "./castable-manifest.json";

export const IA_S3 = "https://s3.us.archive.org";
export const IA_METADATA = "https://archive.org/metadata";
/** Community Audio: the collection archive.org opens to any account's audio. */
export const IA_COLLECTION = "opensource_audio";
export const CC0_URL = "https://creativecommons.org/publicdomain/zero/1.0/";
export const USER_AGENT = "EarDramaWorker/1 (+https://eardrama.org)";
/** The five-minute trigger in wrangler.toml; the hourly one also sweeps. */
export const ARCHIVE_CRON = "*/5 * * * *";
export const REQUESTS_PER_RUN = 20;
export const MAX_ATTEMPTS = 10;
export const BACKOFF_MS = 5 * 60 * 1000;
export const MAX_BACKOFF_MS = 12 * 60 * 60 * 1000;
export const LEASE_MS = 10 * 60 * 1000;
/** Ear Drama's own ceiling on one item, checked before anything is sent. */
export const MAX_ITEM_BYTES = 20_000_000_000;

export const iaConfigured = (env) => !!(env.IA_S3_ACCESS_KEY && env.IA_S3_SECRET_KEY);

/**
 * `eardrama-` and the production id, lowercased: fixed when the production is
 * made, unique, free of any person's name, and 45 characters (archive.org
 * allows 100 of [A-Za-z0-9._-]). An archive.org identifier is permanent, so it
 * carries nothing that could change, like the title.
 */
export const identifierFor = (pid) => `eardrama-${String(pid).toLowerCase()}`;
export const itemUrl = (identifier) => `https://archive.org/details/${identifier}`;

const slug = (s) => String(s).replace(/[^A-Za-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 40) || "part";
/** `0042-HAMLET.wav`: the line's place in the script, so the item lists the play in order. */
export const fileName = (seq, part, ext) => `${String(seq).padStart(4, "0")}-${slug(part)}.${ext}`;
export const extOf = (contentType) => (contentType === "audio/flac" ? "flac" : "wav");

export const backoff = (attempts) => Math.min(BACKOFF_MS * 2 ** Math.max(0, attempts - 1), MAX_BACKOFF_MS);

/** Strips the keys from anything that might be stored or shown. */
export function redact(text, env) {
  let s = String(text ?? "");
  for (const k of [env.IA_S3_ACCESS_KEY, env.IA_S3_SECRET_KEY]) if (k) s = s.split(k).join("[redacted]");
  return s;
}

/** A header value archive.org stores as written: ASCII without edge spaces, else uri(...). */
export function metaValue(v) {
  const s = String(v);
  return /^[\x21-\x7e](?:[\x20-\x7e]*[\x21-\x7e])?$/.test(s) ? s : `uri(${encodeURIComponent(s)})`;
}

/** The item's metadata, every value from data: the script's record and the performers' chosen names. */
export function itemMeta(script, credits, createdAt) {
  const evidence = (script.rights?.evidence || []).map((e) => `${e.claim} ${e.src}`).join("; ");
  return {
    mediatype: "audio",
    collection: IA_COLLECTION,
    title: script.title,
    creator: [...new Set(credits.map((c) => c.name).filter(Boolean))],
    credits: credits.map((c) => (c.name ? `${c.part}: ${c.name}` : c.part)).join("; "),
    licenseurl: CC0_URL,
    rights: evidence,
    source: script.source || "",
    date: new Date(createdAt).toISOString().slice(0, 10),
  };
}

/** x-archive-meta headers; a list becomes numbered headers (x-archive-meta01-creator). */
export function metaHeaders(meta) {
  const h = {};
  for (const [k, v] of Object.entries(meta)) {
    if (Array.isArray(v)) v.forEach((x, i) => (h[`x-archive-meta${String(i + 1).padStart(2, "0")}-${k}`] = metaValue(x)));
    else if (v !== "") h[`x-archive-meta-${k}`] = metaValue(v);
  }
  return h;
}

/** archive.org's answer as one of: ok, transient (retry later), or refused (its final word). */
async function ask(env, url, init) {
  let r;
  try {
    r = await fetch(url, { ...init, headers: { "user-agent": USER_AGENT, ...init.headers } });
  } catch (e) {
    return { ok: false, transient: true, status: 0, reason: "network" };
  }
  if (r.ok) return { ok: true, status: r.status, response: r };
  const text = await r.text().catch(() => "");
  const code = /<Code>([^<]{1,80})<\/Code>/.exec(text)?.[1];
  const message = /<Message>([^<]{1,160})<\/Message>/.exec(text)?.[1];
  const reason = redact(["archive.org", r.status, code, message].filter(Boolean).join(" "), env).slice(0, 240);
  return { ok: false, transient: r.status === 429 || r.status >= 500, status: r.status, reason };
}

const auth = (env) => ({ authorization: `LOW ${env.IA_S3_ACCESS_KEY}:${env.IA_S3_SECRET_KEY}` });
const s3Url = (identifier, name) => `${IA_S3}/${identifier}/${encodeURIComponent(name)}`;

// The whole take is read first (45 MB at most) so archive.org gets a Content-Length, as S3 expects.
async function put(env, identifier, name, obj, extra) {
  const body = await obj.arrayBuffer();
  return ask(env, s3Url(identifier, name), {
    method: "PUT",
    body,
    headers: {
      ...auth(env),
      "content-type": obj.httpMetadata?.contentType || "application/octet-stream",
      "x-archive-size-hint": String(body.byteLength),
      "x-archive-keep-old-version": "0",
      ...extra,
    },
  });
}

const remove = (env, identifier, name) =>
  ask(env, s3Url(identifier, name), { method: "DELETE", headers: { ...auth(env), "x-archive-cascade-delete": "1" } });

/** check_limit: whether archive.org's queue for this item would refuse an upload now. */
async function overLimit(env, identifier) {
  const q = new URLSearchParams({ check_limit: "1", accesskey: env.IA_S3_ACCESS_KEY, bucket: identifier });
  const r = await ask(env, `${IA_S3}/?${q}`, { method: "GET", headers: {} });
  if (!r.ok) return r;
  const body = await r.response.json().catch(() => ({}));
  return body.over_limit ? { ok: false, transient: true, status: 503, reason: "archive.org over_limit" } : null;
}

/** Rewrites the item's credits through the metadata write API, after a performer leaves it. */
function patchCredits(env, identifier, meta) {
  const patch = [
    meta.creator.length ? { op: "add", path: "/creator", value: meta.creator } : { op: "remove", path: "/creator" },
    meta.credits ? { op: "add", path: "/credits", value: meta.credits } : { op: "remove", path: "/credits" },
  ];
  const body = new URLSearchParams({ "-target": "metadata", "-patch": JSON.stringify(patch), access: env.IA_S3_ACCESS_KEY, secret: env.IA_S3_SECRET_KEY });
  return ask(env, `${IA_METADATA}/${identifier}`, {
    method: "POST",
    body: body.toString(),
    headers: { "content-type": "application/x-www-form-urlencoded" },
  });
}

/** Each part with its performer's chosen name, in the cast sheet's order, for the files still on the item. */
async function creditsFor(env, p, cast) {
  const { results } = await env.DB.prepare(
    "SELECT f.part, m.display_name FROM play_archive_files f LEFT JOIN play_takes t ON t.production_id = f.production_id AND t.id = f.take_id " +
      "LEFT JOIN play_members m ON m.production_id = f.production_id AND m.user_id = t.user_id " +
      "WHERE f.production_id = ?1 AND f.state IN ('pending', 'sent') ORDER BY f.seq",
  )
    .bind(p.id)
    .all();
  const byPart = new Map();
  for (const r of results) {
    const names = byPart.get(r.part) || new Set();
    if (r.display_name) names.add(r.display_name);
    byPart.set(r.part, names);
  }
  const out = [];
  for (const { id } of castParts(cast)) {
    if (!byPart.has(id)) continue;
    const names = [...byPart.get(id)];
    if (!names.length) out.push({ part: id, name: "" });
    for (const name of names) out.push({ part: id, name });
  }
  return out;
}

const setJob = (env, pid, fields, now) => {
  const keys = Object.keys(fields);
  const sets = keys.map((k, i) => `${k} = ?${i + 3}`).join(", ");
  return env.DB.prepare(`UPDATE play_archive_jobs SET ${sets}, updated_at = ?2 WHERE production_id = ?1`)
    .bind(pid, now, ...keys.map((k) => fields[k]))
    .run();
};

function log(pid, what) {
  console.log(`archive ${pid}: ${what}`);
}

/** Seeds one file row per chosen take; a line already sent with the same take stays sent. */
async function seedFiles(env, job, p, now) {
  const takeIds = JSON.parse(job.take_ids);
  // json_each, not one variable a take: D1 binds at most 100, and a play has hundreds of lines.
  const { results } = await env.DB.prepare(
    "SELECT id, line_id, part, content_type, bytes FROM play_takes WHERE production_id = ?1 AND id IN (SELECT value FROM json_each(?2))",
  )
    .bind(p.id, job.take_ids)
    .all();
  if (results.length !== takeIds.length) return "take_missing";
  const total = results.reduce((n, t) => n + t.bytes, 0);
  if (total > MAX_ITEM_BYTES || results.some((t) => t.bytes > MAX_TAKE_BYTES)) return "too_large";
  const seq = new Map(p.cast.map(([id], i) => [id, i + 1]));
  const stmts = results.map((t) =>
    env.DB.prepare(
      "INSERT INTO play_archive_files (production_id, line_id, seq, part, take_id, name, state, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, 'pending', ?7) " +
        "ON CONFLICT (production_id, line_id) DO UPDATE SET state = CASE WHEN play_archive_files.take_id = excluded.take_id AND play_archive_files.state = 'sent' THEN 'sent' ELSE 'pending' END, " +
        "take_id = excluded.take_id, name = excluded.name, updated_at = excluded.updated_at",
    ).bind(p.id, t.line_id, seq.get(t.line_id) || 0, t.part, t.id, fileName(seq.get(t.line_id) || 0, t.part, extOf(t.content_type)), now),
  );
  for (let i = 0; i < stmts.length; i += 100) await env.DB.batch(stmts.slice(i, i + 100));
  return null;
}

/** One job's share of this run. Returns nothing; every outcome is written to D1. */
async function runJob(env, pid, now, budget) {
  const job = await env.DB.prepare("SELECT * FROM play_archive_jobs WHERE production_id = ?1").bind(pid).first();
  const row = await env.DB.prepare("SELECT * FROM play_productions WHERE id = ?1").bind(pid).first();
  if (!job || !row) return;
  const p = { ...row, cast: JSON.parse(row.cast_sheet) };
  const script = MANIFEST.scripts[p.script_id] || { title: p.title };
  const identifier = job.identifier || identifierFor(pid);

  if (job.status === "queued") {
    const refusal = await seedFiles(env, job, p, now);
    if (refusal) {
      await setJob(env, pid, { status: "failed", reason: refusal }, now);
      log(pid, `failed ${refusal}`);
      return;
    }
    await setJob(env, pid, { status: "uploading", identifier, reason: null, attempts: 0 }, now);
    job.status = "uploading";
  }
  const initial = job.status === "uploading";

  const { results: files } = await env.DB.prepare(
    "SELECT f.*, t.object_key, t.bytes FROM play_archive_files f LEFT JOIN play_takes t ON t.production_id = f.production_id AND t.id = f.take_id " +
      "WHERE f.production_id = ?1 AND f.state IN ('pending', 'remove') ORDER BY f.seq",
  )
    .bind(pid)
    .all();
  const { results: reports } = await env.DB.prepare(
    "SELECT DISTINCT take_id FROM play_reports WHERE production_id = ?1 AND status = 'open' AND take_id IS NOT NULL",
  )
    .bind(pid)
    .all();
  const reported = new Set(reports.map((r) => r.take_id));
  const sendable = files.filter((f) => f.state === "remove" || !reported.has(f.take_id));
  const held = files.length - sendable.length;
  const last = sendable.filter((f) => f.state === "pending").at(-1);

  /** A transient failure: back off, or give up after MAX_ATTEMPTS. The caller stops this job for the run. */
  const transient = async (r, f) => {
    const attempts = job.attempts + 1;
    if (attempts < MAX_ATTEMPTS) {
      await setJob(env, pid, { attempts, next_attempt_at: now + backoff(attempts), reason: r.reason }, now);
      log(pid, `retry ${attempts} after ${r.status}`);
      return;
    }
    const reason = `gave up after ${attempts} attempts: ${r.reason}`;
    if (initial) await setJob(env, pid, { status: "failed", attempts, reason }, now);
    else {
      await setJob(env, pid, { attempts: 0, reason, next_attempt_at: now + MAX_BACKOFF_MS }, now);
      if (f) await refused(f, reason);
    }
    log(pid, `gave up after ${r.status}`);
  };
  /** archive.org refused: a first upload fails the job; a later change fails that line alone. */
  const refused = async (f, reason) => {
    if (initial) {
      await setJob(env, pid, { status: "failed", reason }, now);
      log(pid, "failed");
      return true;
    }
    await env.DB.prepare("UPDATE play_archive_files SET state = 'failed', reason = ?3, updated_at = ?4 WHERE production_id = ?1 AND line_id = ?2")
      .bind(pid, f.line_id, reason, now)
      .run();
    return false;
  };

  if (sendable.some((f) => f.state === "pending") && budget.left > 0) {
    budget.left--;
    const limit = await overLimit(env, identifier);
    if (limit) return limit.transient ? transient(limit, sendable[0]) : void (await refused(sendable[0], limit.reason));
  }

  let progressed = false;
  let startCredits;
  for (const f of sendable) {
    if (budget.left <= 0) break;
    if (f.state === "remove") {
      budget.left--;
      const r = await remove(env, identifier, f.name);
      if (r.ok || r.status === 404) {
        await env.DB.prepare("UPDATE play_archive_files SET state = 'removed', updated_at = ?3 WHERE production_id = ?1 AND line_id = ?2 AND state = 'remove'")
          .bind(pid, f.line_id, now)
          .run();
        progressed = true;
        continue;
      }
      if (r.transient) return transient(r, f);
      if (await refused(f, r.reason)) return;
      continue;
    }
    if (!f.object_key) {
      if (await refused(f, "take_missing")) return;
      continue;
    }
    if (f.bytes > MAX_TAKE_BYTES) {
      if (await refused(f, "too_large")) return;
      continue;
    }
    if (f.stale_name) {
      budget.left--;
      const r = await remove(env, identifier, f.stale_name);
      if (!r.ok && r.status !== 404) {
        if (r.transient) return transient(r, f);
        if (await refused(f, r.reason)) return;
        continue;
      }
      await env.DB.prepare("UPDATE play_archive_files SET stale_name = NULL WHERE production_id = ?1 AND line_id = ?2").bind(pid, f.line_id).run();
      if (budget.left <= 0) break;
    }
    const obj = await env.TAKES.get(f.object_key);
    if (!obj) {
      if (await refused(f, "take_audio_missing")) return;
      continue;
    }
    budget.left--;
    if (initial && !startCredits) startCredits = await creditsFor(env, p, p.cast);
    const extra = initial ? { "x-archive-auto-make-bucket": "1", ...metaHeaders(itemMeta(script, startCredits, job.created_at)) } : {};
    // Only the last file of a first upload asks archive.org to make the MP3s, so the item derives once.
    if (initial && f !== last) extra["x-archive-queue-derive"] = "0";
    const r = await put(env, identifier, f.name, obj, extra);
    if (!r.ok) {
      if (r.transient) return transient(r, f);
      if (await refused(f, r.reason)) return;
      continue;
    }
    // A replacement that arrived while this one was sending stays pending.
    await env.DB.prepare(
      "UPDATE play_archive_files SET state = 'sent', reason = NULL, updated_at = ?4 WHERE production_id = ?1 AND line_id = ?2 AND take_id = ?3 AND state = 'pending'",
    )
      .bind(pid, f.line_id, f.take_id, now)
      .run();
    progressed = true;
  }

  const left = await env.DB.prepare("SELECT COUNT(*) AS n FROM play_archive_files WHERE production_id = ?1 AND state IN ('pending', 'remove')")
    .bind(pid)
    .first();
  const credits = await creditsFor(env, p, p.cast);
  const creditText = JSON.stringify(credits);
  if (initial) {
    if (left.n === 0) {
      await setJob(env, pid, { status: "published", item_url: itemUrl(identifier), published_at: now, credits: creditText, attempts: 0, reason: null }, now);
      log(pid, "published");
    } else if (progressed || held) {
      await setJob(env, pid, { attempts: 0, reason: held ? "reported_take" : null }, now);
    }
    return;
  }
  if (job.credits !== creditText) {
    // Cleared first, so a run that stops here leaves the job picked up again (runArchive: credits IS NULL).
    await setJob(env, pid, { credits: null }, now);
    if (budget.left <= 0) return;
    budget.left--;
    const r = await patchCredits(env, identifier, itemMeta(script, credits, job.created_at));
    if (!r.ok) return r.transient ? transient(r) : void (await setJob(env, pid, { credits: creditText, reason: r.reason }, now));
    await setJob(env, pid, { credits: creditText, attempts: 0, reason: held ? "reported_take" : null }, now);
    return;
  }
  if (progressed || held) await setJob(env, pid, { attempts: 0, reason: held ? "reported_take" : null }, now);
}

/**
 * The uploader's run (index.js `scheduled`). Takes the jobs whose backoff has
 * passed and that no other run holds, oldest first, until the run's request
 * budget is spent.
 */
export async function runArchive(env, now = Date.now(), requests = REQUESTS_PER_RUN) {
  if (!iaConfigured(env) || !env.TAKES) return;
  const { results } = await env.DB.prepare(
    "SELECT production_id FROM play_archive_jobs j WHERE next_attempt_at <= ?1 AND lease_until <= ?1 AND (status IN ('queued', 'uploading') " +
      "OR (status = 'published' AND (credits IS NULL OR EXISTS (SELECT 1 FROM play_archive_files f WHERE f.production_id = j.production_id AND f.state IN ('pending', 'remove'))))) " +
      "ORDER BY updated_at LIMIT 5",
  )
    .bind(now)
    .all();
  const budget = { left: requests };
  for (const { production_id: pid } of results) {
    if (budget.left <= 0) break;
    const lease = await env.DB.prepare("UPDATE play_archive_jobs SET lease_until = ?2 WHERE production_id = ?1 AND lease_until <= ?3")
      .bind(pid, now + LEASE_MS, now)
      .run();
    if (!lease.meta.changes) continue;
    try {
      await runJob(env, pid, now, budget);
    } catch (e) {
      console.log(`archive ${pid}: error ${redact(e && e.message, env).slice(0, 200)}`);
    } finally {
      await env.DB.prepare("UPDATE play_archive_jobs SET lease_until = 0 WHERE production_id = ?1").bind(pid).run();
    }
  }
}
