/**
 * Retention (Decision 084; owner 2026-11-21: "I don't mind deleting the info
 * about who recorded what, but we need to be able to keep the recorded Ear
 * Dramas in our database. That should work, given that identifiable
 * information is not accessible via the recordings.").
 *
 * WHO RECORDED WHAT GOES; THE EAR DRAMA STAYS. Deleting a class (its teacher,
 * its end date, a year idle, or a school's request through the operator route)
 * deletes its seats and their names, class membership, the school's
 * authorization record, and every production of the class that was never
 * submitted. A SUBMITTED production (it has an archive job) is detached first:
 * its takes lose their seat (take-to-seat links), its review notes and casting
 * go, and the production, its takes' fields, its job and its archive.org files
 * stay. Its credits already carry only the teacher's chosen name (Decision 082).
 *
 * The schedule: a class ends the day after `ends_on` (by default the July 31
 * that closes its school year); a class idle 12 months goes after a 30-day
 * notice its teacher sees in the class list; an account idle 3 years goes, as
 * if its owner had deleted it, 30 days after its notice, and any sign-in in
 * between cancels it. A school's request is the owner's operator route
 * (operator.yml, by GitHub OIDC), done within 30 days (docs/WORKER.md "A school asks").
 */

import { json, problem, readJson } from "./http.js";
import { classProgress, rosterFor, teacherClass } from "./plays-seats.js";
import { deleteAccount } from "./account.js";
import { githubCaller } from "./github-oidc.js";

const DAY_MS = 24 * 60 * 60 * 1000;
export const CLASS_IDLE_MS = 365 * DAY_MS;
export const ACCOUNT_IDLE_MS = 3 * 365 * DAY_MS;
export const NOTICE_MS = 30 * DAY_MS;
/** The longest a teacher may set an end date ahead of today. */
export const MAX_END_DAYS = 400;
export const SWEEP_BATCH = 25;
const DELETED_PERSON = "deleted-account";
const DATE = /^(\d{4})-(\d{2})-(\d{2})$/;

/* ---- Dates ---- */

export const dateOf = (ms) => new Date(ms).toISOString().slice(0, 10);

/** The July 31 that closes the US school year (August to July) holding `ms`. */
export function schoolYearEnd(ms) {
  const d = new Date(ms);
  const y = d.getUTCFullYear() + (d.getUTCMonth() >= 7 ? 1 : 0);
  return `${y}-07-31`;
}

/** When a class ending on `endsOn` may go: noon UTC the next day, after that day has ended in every US time zone. */
export function endsAt(endsOn) {
  const m = DATE.exec(endsOn || "");
  if (!m) return Infinity;
  return Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]) + 1, 12);
}

/** A valid end date a teacher may set: a real date, not before today, at most MAX_END_DAYS ahead. */
export function endDateRefusal(endsOn, now) {
  const m = DATE.exec(typeof endsOn === "string" ? endsOn : "");
  if (!m) return "bad_end_date";
  const ms = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  if (dateOf(ms) !== endsOn) return "bad_end_date";
  if (endsOn < dateOf(now - DAY_MS)) return "end_date_past";
  if (ms > now + MAX_END_DAYS * DAY_MS) return "end_date_too_far";
  return null;
}

/** The date a class in notice will be deleted, for the teacher's list. */
export const deletesOn = (noticeAt) => (noticeAt ? dateOf(noticeAt + NOTICE_MS) : null);

/** The class's last use: its teacher, its productions, its seats. */
const ACTIVITY =
  "MAX(COALESCE(c.touched_at, c.created_at), " +
  "COALESCE((SELECT MAX(p.updated_at) FROM play_productions p WHERE p.class_id = c.id), 0), " +
  "COALESCE((SELECT MAX(s.claimed_at) FROM play_class_seats s WHERE s.class_id = c.id), 0))";

/* ---- Deleting ---- */

/** Statements deleting the productions `where` picks (a subquery of ids), child rows first; the cascade is the second lock. */
function productionStatements(env, where, ...binds) {
  const tables = ["play_reviews", "play_assignments", "play_takes", "play_parts", "play_consents", "play_invites", "play_members", "play_archive_jobs"];
  return [
    ...tables.map((t) => env.DB.prepare(`DELETE FROM ${t} WHERE production_id IN (${where})`).bind(...binds)),
    env.DB.prepare(`DELETE FROM play_productions WHERE id IN (${where})`).bind(...binds),
  ];
}

const SUBMITTED = "SELECT production_id FROM play_archive_jobs";

/** Deletes a class and who recorded what in it; a submitted production of the class stays, detached and without seats. */
export async function deleteClass(env, classId) {
  const submitted = `SELECT id FROM play_productions WHERE class_id = ?1 AND id IN (${SUBMITTED})`;
  const unsubmitted = `SELECT id FROM play_productions WHERE class_id = ?1 AND id NOT IN (${SUBMITTED})`;
  await env.DB.batch([
    env.DB.prepare(`UPDATE play_takes SET seat_id = NULL WHERE production_id IN (${submitted})`).bind(classId),
    env.DB.prepare(`DELETE FROM play_reviews WHERE production_id IN (${submitted})`).bind(classId),
    env.DB.prepare(`DELETE FROM play_assignments WHERE production_id IN (${submitted})`).bind(classId),
    env.DB.prepare(`UPDATE play_productions SET class_id = NULL WHERE class_id = ?1 AND id IN (${SUBMITTED})`).bind(classId),
    ...productionStatements(env, unsubmitted, classId),
    env.DB.prepare("DELETE FROM play_class_seats WHERE class_id = ?1").bind(classId),
    env.DB.prepare("DELETE FROM play_class_members WHERE class_id = ?1").bind(classId),
    env.DB.prepare("DELETE FROM play_school_consents WHERE class_id = ?1").bind(classId),
    env.DB.prepare("DELETE FROM play_classes WHERE id = ?1").bind(classId),
  ]);
}

/** Deletes one production that was never submitted, with every row of it. */
export async function deleteProduction(env, pid) {
  await env.DB.batch(productionStatements(env, `SELECT id FROM play_productions WHERE id = ?1 AND id NOT IN (${SUBMITTED})`, pid));
}

/* ---- The teacher's and director's routes ---- */

/** DELETE /v1/plays/classes/:id (the teacher). */
export async function deleteClassRoute(auth, env, classId) {
  const t = await teacherClass(env, classId, auth.userId);
  if (t.error) return t.error;
  await deleteClass(env, classId);
  return new Response(null, { status: 204 });
}

/** PATCH /v1/plays/classes/:id { ends_on }: the teacher changes or extends the end date. */
export async function setEndDate(auth, request, env, classId, now) {
  const t = await teacherClass(env, classId, auth.userId);
  if (t.error) return t.error;
  const { body, error } = await readJson(request, 4 * 1024);
  if (error) return error;
  const refusal = endDateRefusal(body.ends_on, now);
  if (refusal) return problem(422, refusal);
  await env.DB.prepare("UPDATE play_classes SET ends_on = ?2, touched_at = ?3, notice_at = NULL WHERE id = ?1").bind(classId, body.ends_on, now).run();
  return json({ id: classId, ends_on: body.ends_on, deletes_on: null });
}

/** The teacher opened the class: the idle clock restarts and any notice ends (written at most hourly). */
export const touchClass = (env, classId, now) =>
  env.DB.prepare("UPDATE play_classes SET touched_at = ?2, notice_at = NULL WHERE id = ?1 AND (touched_at IS NULL OR touched_at < ?2 - 3600000 OR notice_at IS NOT NULL)")
    .bind(classId, now)
    .run();

/** DELETE /v1/plays/productions/:id (the director): a submitted one stays (its lines are removed one by one, P12). */
export async function deleteProductionRoute(auth, env, p) {
  if (p.user_id !== auth.userId) return problem(403, "director_only");
  if (await env.DB.prepare("SELECT 1 FROM play_archive_jobs WHERE production_id = ?1").bind(p.id).first()) return problem(409, "submitted");
  await deleteProduction(env, p.id);
  return new Response(null, { status: 204 });
}

/**
 * GET /v1/plays/classes/:id/export (the teacher): the class's data as one file, for the
 * school (AB 1584, NDPA Exhibit D). Seat labels, casting, progress, takes' fields with
 * review states and notes. No audio: none is stored (Decision 082).
 */
export async function exportClass(auth, env, classId, now) {
  const t = await teacherClass(env, classId, auth.userId);
  if (t.error) return t.error;
  const c = t.c;
  const seats = (await rosterFor(env, classId)).map((s) => ({ id: s.id, label: s.label }));
  const label = Object.fromEntries(seats.map((s) => [s.id, s.label]));
  const consent = await env.DB.prepare("SELECT policy_version, reference, recorded_at FROM play_school_consents WHERE class_id = ?1").bind(classId).first();
  const progress = await classProgress(env, classId);
  const { results: prods } = await env.DB.prepare(
    "SELECT p.id, p.title, p.script_id, p.script_revision, p.created_at, j.status, j.item_url FROM play_productions p LEFT JOIN play_archive_jobs j ON j.production_id = p.id WHERE p.class_id = ?1 ORDER BY p.created_at",
  )
    .bind(classId)
    .all();
  const productions = [];
  for (const p of prods) {
    const [{ results: assignments }, { results: takes }, { results: reviews }] = await env.DB.batch([
      env.DB.prepare("SELECT part, from_line, to_line, seat_id FROM play_assignments WHERE production_id = ?1 ORDER BY seq").bind(p.id),
      env.DB.prepare("SELECT id, line_id, part, seat_id, chosen, created, frames, sample_rate, uploaded_at FROM play_takes WHERE production_id = ?1 ORDER BY uploaded_at").bind(p.id),
      env.DB.prepare("SELECT take_id, state, note, reviewed_at FROM play_reviews WHERE production_id = ?1").bind(p.id),
    ]);
    const review = Object.fromEntries(reviews.map((r) => [r.take_id, { state: r.state, note: r.note, reviewed_at: r.reviewed_at }]));
    productions.push({
      id: p.id,
      title: p.title,
      script_id: p.script_id,
      script_revision: p.script_revision,
      created_at: p.created_at,
      archive: p.status ? { status: p.status, url: p.item_url } : null,
      assignments: assignments.map((a) => ({ part: a.part, from: a.from_line, to: a.to_line, seat: a.seat_id, seat_label: label[a.seat_id] ?? null })),
      progress: (progress.productions.find((x) => x.id === p.id) || { seats: [] }).seats,
      takes: takes.map((k) => ({
        id: k.id,
        line_id: k.line_id,
        part: k.part,
        seat: k.seat_id,
        seat_label: k.seat_id ? label[k.seat_id] ?? null : null,
        chosen: !!k.chosen,
        created: k.created,
        received_at: k.uploaded_at,
        seconds: k.sample_rate ? Math.round((k.frames / k.sample_rate) * 100) / 100 : null,
        review: review[k.id] || null,
      })),
    });
  }
  return json({
    format: "eardrama-class-export",
    version: 1,
    exported_at: now,
    audio: "none: takes pass through to the teacher's device and are never stored",
    class: {
      id: c.id,
      name: c.name,
      under13: !!c.under13,
      created_at: c.created_at,
      ends_on: c.ends_on,
      school_authorization: consent ? { policy_version: consent.policy_version, reference: consent.reference, recorded_at: consent.recorded_at } : null,
    },
    seats,
    productions,
  });
}

/* ---- A school's deletion request: the owner's operator route ---- */

export const isOperatorRoute = (pathname) => pathname === "/v1/operator" || pathname.startsWith("/v1/operator/");

/**
 * The owner's tools, run only by .github/workflows/operator.yml with its GitHub OIDC token (github-oidc.js),
 * for a school that writes to ask:
 * GET /v1/operator/classes?code=… or ?reference=… finds the classes (no seat names);
 * DELETE /v1/operator/classes/:id deletes one exactly as its teacher's Delete class does.
 */
export async function handleOperator(url, request, env) {
  if (url.pathname === "/v1/operator/reports/count") return reportsCount(url, request, env);
  const caller = await githubCaller(request, env, url, "operator");
  if (!caller) return problem(403, "forbidden");
  const m = request.method;
  const seg = url.pathname.slice("/v1/operator".length).split("/").filter(Boolean);
  if (seg[0] !== "classes") return problem(404, "not_found");
  if (seg.length === 1 && m === "GET") {
    const code = url.searchParams.get("code");
    const reference = (url.searchParams.get("reference") || "").trim();
    const base =
      "SELECT c.id, c.name, c.code, c.under13, c.created_at, c.ends_on, s.reference FROM play_classes c LEFT JOIN play_school_consents s ON s.class_id = c.id ";
    let q;
    if (code) q = env.DB.prepare(`${base}WHERE c.code = ?1`).bind(code.toUpperCase().replace(/[\s-]/g, ""));
    else if (reference) q = env.DB.prepare(`${base}WHERE s.reference = ?1 COLLATE NOCASE ORDER BY c.created_at LIMIT 200`).bind(reference);
    else return problem(400, "bad_request", "code or reference");
    const { results } = await q.all();
    return json({ classes: results.map((r) => ({ ...r, under13: !!r.under13 })) });
  }
  if (seg.length === 2 && m === "DELETE") {
    const c = await env.DB.prepare("SELECT id FROM play_classes WHERE id = ?1").bind(seg[1]).first();
    if (!c) return problem(404, "class_not_found");
    await deleteClass(env, c.id);
    // The audit trail: who dispatched which run, in the Worker's private log, never the public Actions log.
    console.log(JSON.stringify({ operator: "delete_class", class_id: c.id, actor: caller.actor, run_id: caller.run_id }));
    return json({ deleted: true, class_id: c.id, deleted_at: Date.now() });
  }
  return problem(404, "not_found");
}

/**
 * GET /v1/operator/reports/count, asked hourly by .github/workflows/reports.yml (Decision 088.6): how many reports
 * wait, and nothing else, because the answer becomes a public issue. One read, no write.
 */
async function reportsCount(url, request, env) {
  if (!(await githubCaller(request, env, url, "reports"))) return problem(403, "forbidden");
  if (request.method !== "GET") return problem(405, "method_not_allowed");
  const { n } = await env.DB.prepare("SELECT COUNT(*) AS n FROM play_reports WHERE status = 'open'").first();
  return json({ open: n });
}

/* ---- The hourly sweep ---- */

/** Classes past their end date or a year idle after notice, and accounts three years idle after notice. */
export async function sweepRetention(env, now = Date.now()) {
  const cutoff = dateOf(now - DAY_MS - 12 * 60 * 60 * 1000);
  const ended = await env.DB.prepare("SELECT id FROM play_classes WHERE ends_on IS NOT NULL AND ends_on <= ?1 LIMIT ?2").bind(cutoff, SWEEP_BATCH).all();
  await env.DB.batch([
    env.DB.prepare(`UPDATE play_classes AS c SET notice_at = NULL WHERE notice_at IS NOT NULL AND ${ACTIVITY} > notice_at`),
    env.DB.prepare(`UPDATE play_classes AS c SET notice_at = ?1 WHERE notice_at IS NULL AND ${ACTIVITY} < ?2`).bind(now, now - CLASS_IDLE_MS + NOTICE_MS),
    env.DB.prepare("UPDATE users SET idle_notice_at = ?1 WHERE idle_notice_at IS NULL AND seen_at < ?2 AND id <> ?3").bind(now, now - ACCOUNT_IDLE_MS + NOTICE_MS, DELETED_PERSON),
  ]);
  const idle = await env.DB.prepare(`SELECT c.id FROM play_classes c WHERE c.notice_at <= ?1 AND ${ACTIVITY} < ?2 LIMIT ?3`)
    .bind(now - NOTICE_MS, now - CLASS_IDLE_MS, SWEEP_BATCH)
    .all();
  for (const { id } of [...ended.results, ...idle.results]) await deleteClass(env, id);
  const gone = await env.DB.prepare("SELECT id FROM users WHERE idle_notice_at <= ?1 AND seen_at < ?2 AND id <> ?3 LIMIT ?4")
    .bind(now - NOTICE_MS, now - ACCOUNT_IDLE_MS, DELETED_PERSON, SWEEP_BATCH)
    .all();
  for (const { id } of gone.results) await deleteAccount(env, id);
}
