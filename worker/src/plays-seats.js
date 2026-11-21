/**
 * A class owns its productions, and its students are seats (Decision 082,
 * PLAYS-DESIGN §12.4). Owner, 2026-11-19: a class owns a production, visible
 * only to its seats; parts a teacher assigns may all record at once; a seat
 * (a name the teacher typed) records without an account, its takes belonging
 * to the teacher's account.
 *
 * A SEAT is a label the teacher typed: no account, email, birth date, photo,
 * or voice outside the class's production. A student picks it with the class
 * code and gets a seat key once, stored only as its SHA-256. A second device
 * asking for a held seat is refused unless it asks to move ("Move here"), and
 * then the first device's key stops working. The teacher can release a seat.
 *
 * CASTING. A class production's assignments give a part, or a scene range of
 * it, to a seat; every assigned part may record at once, so the C7 claims do
 * not apply. A production without assignments has nothing a seat can record.
 *
 * LIMITS by seat, never only by address: a class sits behind one school
 * address. Picking a seat has a per-address floor (SEAT_JOIN_LIMITER) against
 * code guessing; every seat call after that counts its seat (SEAT_LIMITER),
 * and a seat's takes count apart from everyone else's (PLAY_UPLOAD_LIMITER).
 */

import { json, limited, problem, readJson } from "./http.js";
import { randomToken, sha256Hex } from "./jwt.js";
import { nameRefusal } from "./plays-names.js";
import { cleanAssignments, MAX_SEATS } from "./read-protocol.js";
import { chooseStatements, createProduction, normalizeClassCode, parseTakeMeta, production, receiveTake, receiverOf, takeOut, touch } from "./plays.js";
import { partOf } from "./plays-relay.js";

export const SEAT_KEY_HEADER = "x-seat-key";
export const REVIEW_STATES = ["approved", "again"];
export const MAX_NOTE = 500;
const SEAT_KEY = /^[A-Za-z0-9_-]{16,64}$/;

/* ---- Reading ---- */

export async function seatsOf(env, classId) {
  const { results } = await env.DB.prepare("SELECT id, label, key_hash, claimed_at, created_at FROM play_class_seats WHERE class_id = ?1 ORDER BY created_at, label")
    .bind(classId)
    .all();
  return results;
}

/** The seat a key opens, with its class; null for an unknown, released, or moved key. */
export async function seatByKey(env, key) {
  if (typeof key !== "string" || !SEAT_KEY.test(key)) return null;
  return env.DB.prepare(
    "SELECT s.id, s.label, s.class_id, c.user_id AS teacher, c.name AS class_name, c.under13, sc.class_id AS consent FROM play_class_seats s " +
      "JOIN play_classes c ON c.id = s.class_id LEFT JOIN play_school_consents sc ON sc.class_id = c.id WHERE s.key_hash = ?1",
  )
    .bind(await sha256Hex(key))
    .first();
}

/** Whether `key` opens `seatId` of `classId` (read rooms ask this before a seat joins). */
export async function seatKeyOpens(env, classId, seatId, key) {
  const s = await seatByKey(env, key);
  return !!s && s.class_id === classId && s.id === seatId;
}

export async function assignmentRows(env, pid) {
  const { results } = await env.DB.prepare("SELECT part, from_line, to_line, seat_id FROM play_assignments WHERE production_id = ?1 ORDER BY seq")
    .bind(pid)
    .all();
  return results.map((a) => ({ part: a.part, from: a.from_line, to: a.to_line, seat: a.seat_id }));
}

/** The line indexes an assignment covers: its part's lines, within its range. */
function covered(cast, a) {
  const at = (id) => cast.findIndex(([l]) => l === id);
  const lo = a.from ? at(a.from) : 0;
  const hi = a.to ? at(a.to) : cast.length - 1;
  const out = [];
  for (let i = lo; i <= hi; i++) if (cast[i][1] === a.part) out.push(i);
  return out;
}

/** Whether `seatId` is assigned the line `lineID` (its part, inside the range). */
export function assignedTo(cast, assignments, seatId, lineID) {
  const i = cast.findIndex(([l]) => l === lineID);
  if (i < 0) return false;
  return assignments.some((a) => a.seat === seatId && a.part === cast[i][1] && covered(cast, a).includes(i));
}

export async function reviewsFor(env, pid) {
  const { results } = await env.DB.prepare("SELECT take_id, state, note, reviewed_at FROM play_reviews WHERE production_id = ?1").bind(pid).all();
  return Object.fromEntries(results.map((r) => [r.take_id, { state: r.state, note: r.note, reviewed_at: r.reviewed_at }]));
}

export async function teacherClass(env, classId, userId) {
  const c = await env.DB.prepare("SELECT * FROM play_classes WHERE id = ?1").bind(classId).first();
  if (!c) return { error: problem(404, "class_not_found") };
  if (c.user_id !== userId) return { error: problem(403, "teacher_only") };
  return { c };
}

const seatOut = (s) => ({ id: s.id, label: s.label, claimed: !!s.key_hash, claimed_at: s.claimed_at || null });

/* ---- The teacher's seats ---- */

/** Labels from a pasted list: one a line (or a tab or semicolon apart), trimmed, empties dropped, duplicates once. */
export function pastedLabels(body) {
  const raw = Array.isArray(body.labels) ? body.labels : typeof body.text === "string" ? body.text.split(/\r?\n|\t|;/) : null;
  if (!raw || raw.length > 500) return null;
  const seen = new Set();
  const out = [];
  for (const l of raw) {
    if (typeof l !== "string") return null;
    const label = l.trim().replace(/\s+/g, " ");
    if (!label || seen.has(label.toLowerCase())) continue;
    seen.add(label.toLowerCase());
    out.push(label);
  }
  return out;
}

/** POST /v1/plays/classes/:id/seats { labels: [...] } or { text: "pasted list" }. */
async function addSeats(auth, request, env, classId, now) {
  const t = await teacherClass(env, classId, auth.userId);
  if (t.error) return t.error;
  const { body, error } = await readJson(request, 64 * 1024);
  if (error) return error;
  const labels = pastedLabels(body);
  if (!labels) return problem(400, "bad_request", "labels is a list of names, or text is a pasted list");
  const have = await seatsOf(env, classId);
  const taken = new Set(have.map((s) => s.label.toLowerCase()));
  const refused = [];
  const fresh = [];
  for (const label of labels) {
    if (taken.has(label.toLowerCase())) continue;
    const why = label.length > 40 || /[\u0000-\u001f\u007f]/.test(label) ? "bad_label" : nameRefusal(label);
    if (why) refused.push({ label, error: why });
    else fresh.push(label);
  }
  if (have.length + fresh.length > MAX_SEATS) return problem(409, "too_many_seats", MAX_SEATS);
  const stmts = fresh.map((label, i) =>
    env.DB.prepare("INSERT INTO play_class_seats (class_id, id, label, created_at) VALUES (?1, ?2, ?3, ?4) ON CONFLICT DO NOTHING").bind(
      classId,
      randomToken(9),
      label,
      now + i,
    ),
  );
  if (stmts.length) await env.DB.batch(stmts);
  return json({ seats: (await seatsOf(env, classId)).map(seatOut), refused }, 201);
}

/** DELETE /v1/plays/classes/:id/seats/:seat: the seat and its casting go; takes it made stay the teacher's. */
async function removeSeat(auth, env, classId, seatId) {
  const t = await teacherClass(env, classId, auth.userId);
  if (t.error) return t.error;
  const r = await env.DB.prepare("DELETE FROM play_class_seats WHERE class_id = ?1 AND id = ?2").bind(classId, seatId).run();
  if (!r.meta.changes) return problem(404, "no_such_seat");
  await env.DB.prepare("DELETE FROM play_assignments WHERE seat_id = ?2 AND production_id IN (SELECT id FROM play_productions WHERE class_id = ?1)")
    .bind(classId, seatId)
    .run();
  return new Response(null, { status: 204 });
}

/** POST /v1/plays/classes/:id/seats/:seat/release: the device holding it is let go, and the next one can take it. */
async function releaseSeat(auth, env, classId, seatId) {
  const t = await teacherClass(env, classId, auth.userId);
  if (t.error) return t.error;
  const r = await env.DB.prepare("UPDATE play_class_seats SET key_hash = NULL, claimed_at = NULL WHERE class_id = ?1 AND id = ?2").bind(classId, seatId).run();
  if (!r.meta.changes) return problem(404, "no_such_seat");
  return new Response(null, { status: 204 });
}

/* ---- Class productions, casting, review, progress ---- */

/** POST /v1/plays/classes/:id/productions: the teacher's; every seat of the class is in it without an invite. */
async function createClassProduction(auth, request, env, classId, now) {
  const t = await teacherClass(env, classId, auth.userId);
  if (t.error) return t.error;
  return createProduction(auth, request, env, now, classId);
}

/** PUT /v1/plays/productions/:id/assignments { assignments: [{ part, from?, to?, seat }] }: the whole casting, replaced. */
export async function putAssignments(auth, request, env, p, now) {
  if (p.user_id !== auth.userId) return problem(403, "director_only");
  if (!p.class_id) return problem(422, "not_a_class_production");
  const { body, error } = await readJson(request, 256 * 1024);
  if (error) return error;
  const seats = (await seatsOf(env, p.class_id)).map((s) => ({ id: s.id, label: s.label }));
  const clean = cleanAssignments(body.assignments, p.cast, seats);
  if (!clean) return problem(422, "bad_assignments");
  await env.DB.batch([
    env.DB.prepare("DELETE FROM play_assignments WHERE production_id = ?1").bind(p.id),
    ...clean.map((a, i) =>
      env.DB.prepare("INSERT INTO play_assignments (production_id, seq, part, from_line, to_line, seat_id) VALUES (?1, ?2, ?3, ?4, ?5, ?6)").bind(
        p.id,
        i,
        a.part,
        a.from,
        a.to,
        a.seat,
      ),
    ),
    touch(env, p.id, now),
  ]);
  return json({ assignments: await assignmentRows(env, p.id) });
}

/** POST /v1/plays/productions/:id/takes/:take/review { state, note? }: Approve or Again; the note is shown to the take's seat alone. */
export async function review(auth, request, env, p, takeId, now) {
  if (p.user_id !== auth.userId) return problem(403, "director_only");
  if (!p.class_id) return problem(422, "not_a_class_production");
  const { body, error } = await readJson(request, 8 * 1024);
  if (error) return error;
  if (!REVIEW_STATES.includes(body.state)) return problem(400, "bad_request", `state is one of ${REVIEW_STATES.join(", ")}`);
  const note = body.note === undefined ? "" : body.note;
  if (typeof note !== "string" || note.length > MAX_NOTE || /[\u0000-\u0009\u000b-\u001f\u007f]/.test(note)) return problem(400, "bad_request", "note");
  const t = await env.DB.prepare("SELECT id FROM play_takes WHERE production_id = ?1 AND id = ?2").bind(p.id, takeId).first();
  if (!t) return problem(404, "no_such_take");
  await env.DB.prepare(
    "INSERT INTO play_reviews (production_id, take_id, state, note, reviewed_at) VALUES (?1, ?2, ?3, ?4, ?5) " +
      "ON CONFLICT (production_id, take_id) DO UPDATE SET state = excluded.state, note = excluded.note, reviewed_at = excluded.reviewed_at",
  )
    .bind(p.id, takeId, body.state, note.trim(), now)
    .run();
  return json({ take_id: takeId, state: body.state, note: note.trim(), reviewed_at: now });
}

/**
 * GET /v1/plays/classes/:id/progress: per production, per seat, per part, counts only
 * (R3c §4.5; learner-experience-design §5): the lines assigned, those with a take,
 * and those whose chosen take is approved or asked again. Never a ranking.
 */
async function progress(auth, env, classId) {
  const t = await teacherClass(env, classId, auth.userId);
  if (t.error) return t.error;
  return json(await classProgress(env, classId));
}

/** The progress counts, for the route and the class export. */
export async function classProgress(env, classId) {
  const labels = Object.fromEntries((await seatsOf(env, classId)).map((s) => [s.id, s.label]));
  const { results: prods } = await env.DB.prepare("SELECT id, title, cast_sheet FROM play_productions WHERE class_id = ?1 ORDER BY created_at").bind(classId).all();
  const out = [];
  for (const row of prods) {
    const cast = JSON.parse(row.cast_sheet);
    const assignments = await assignmentRows(env, row.id);
    const { results: takes } = await env.DB.prepare("SELECT id, line_id, seat_id, chosen FROM play_takes WHERE production_id = ?1").bind(row.id).all();
    const reviews = await reviewsFor(env, row.id);
    const seats = new Map();
    for (const a of assignments) {
      const lines = covered(cast, a).map((i) => cast[i][0]);
      const mine = takes.filter((k) => k.seat_id === a.seat && lines.includes(k.line_id));
      const chosen = mine.filter((k) => k.chosen);
      const parts = seats.get(a.seat) || new Map();
      const c = parts.get(a.part) || { part: a.part, lines: 0, recorded: 0, approved: 0, again: 0 };
      c.lines += lines.length;
      c.recorded += new Set(mine.map((k) => k.line_id)).size;
      c.approved += chosen.filter((k) => reviews[k.id]?.state === "approved").length;
      c.again += chosen.filter((k) => reviews[k.id]?.state === "again").length;
      parts.set(a.part, c);
      seats.set(a.seat, parts);
    }
    out.push({
      id: row.id,
      title: row.title,
      seats: [...seats].map(([seat, parts]) => ({ seat, label: labels[seat] ?? null, parts: [...parts.values()] })),
    });
  }
  return { class_id: classId, productions: out };
}

/** The class subroutes past plays.js's own; null when none matches. */
export async function classHandlers(auth, request, env, seg, now) {
  const [, b, c, d, e] = seg;
  const m = request.method;
  if (!b) return null;
  if (c === "seats" && !d && m === "POST") return addSeats(auth, request, env, b, now);
  if (c === "seats" && d && !e && m === "DELETE") return removeSeat(auth, env, b, d);
  if (c === "seats" && d && e === "release" && seg.length === 5 && m === "POST") return releaseSeat(auth, env, b, d);
  if (c === "productions" && !d && m === "POST") return createClassProduction(auth, request, env, b, now);
  if (c === "progress" && !d && m === "GET") return progress(auth, env, b);
  return null;
}

/** The teacher's roster, for getClass. */
export async function rosterFor(env, classId) {
  return (await seatsOf(env, classId)).map(seatOut);
}

/* ---- Seats, without an account: /v1/plays/seat/... ---- */

async function classByCode(env, code) {
  return env.DB.prepare("SELECT id, name, under13 FROM play_classes WHERE code = ?1").bind(normalizeClassCode(code)).first();
}

/** POST /v1/plays/seat/list { code }: the class's seat names to pick from, and which are taken. */
async function listSeats(request, env) {
  const { body, error } = await readJson(request, 4 * 1024);
  if (error) return error;
  const c = await classByCode(env, body.code);
  if (!c) return problem(404, "class_not_found");
  return json({ class: { id: c.id, name: c.name }, seats: (await seatsOf(env, c.id)).map((s) => ({ id: s.id, label: s.label, taken: !!s.key_hash })) });
}

/** POST /v1/plays/seat/claim { code, seat, move? }: the seat key, returned once. */
async function claimSeat(request, env, now) {
  const { body, error } = await readJson(request, 4 * 1024);
  if (error) return error;
  const c = await classByCode(env, body.code);
  if (!c) return problem(404, "class_not_found");
  const s = typeof body.seat === "string" ? await env.DB.prepare("SELECT id, label, key_hash FROM play_class_seats WHERE class_id = ?1 AND id = ?2").bind(c.id, body.seat).first() : null;
  if (!s) return problem(404, "no_such_seat");
  // "Lucy is already in on another device": Move here takes it, and the other device's key stops working.
  if (s.key_hash && body.move !== true) return problem(409, "seat_in_use");
  const key = randomToken(24);
  const r = await env.DB.prepare(
    "UPDATE play_class_seats SET key_hash = ?3, claimed_at = ?4 WHERE class_id = ?1 AND id = ?2 AND (key_hash IS ?5)",
  )
    .bind(c.id, s.id, await sha256Hex(key), now, s.key_hash)
    .run();
  if (!r.meta.changes) return problem(409, "seat_in_use");
  return json({ seat_key: key, seat: { id: s.id, label: s.label }, class: { id: c.id, name: c.name, under13: !!c.under13 } }, 201);
}

/** GET /v1/plays/seat: the seat's class productions, its own casting, and its takes with the teacher's review and note. */
async function seatHome(env, seat) {
  const { results: prods } = await env.DB.prepare(
    "SELECT id, title, script_id, script_revision FROM play_productions WHERE class_id = ?1 ORDER BY created_at",
  )
    .bind(seat.class_id)
    .all();
  const productions = [];
  for (const row of prods) {
    const assignments = (await assignmentRows(env, row.id)).filter((a) => a.seat === seat.id);
    const { results: takes } = await env.DB.prepare("SELECT * FROM play_takes WHERE production_id = ?1 AND seat_id = ?2 ORDER BY uploaded_at")
      .bind(row.id, seat.id)
      .all();
    const reviews = await reviewsFor(env, row.id);
    productions.push({
      id: row.id,
      title: row.title,
      scriptID: row.script_id,
      scriptRevision: row.script_revision,
      assignments,
      takes: takes.map((t) => {
        const { user_id, ...out } = takeOut(row.id, t);
        return { ...out, chosen: !!t.chosen, review: reviews[t.id] || null };
      }),
    });
  }
  return json({ seat: { id: seat.id, label: seat.label }, class: { id: seat.class_id, name: seat.class_name, under13: !!seat.under13 }, productions });
}

/** The class production a seat may act in, or a refusal. Another class's production and no production look the same. */
async function seatProduction(env, seat, pid) {
  const p = await production(env, pid);
  if (!p || p.class_id !== seat.class_id) return { error: problem(404, "not_found") };
  return { p };
}

/** PUT /v1/plays/seat/productions/:id/takes/:takeId: a seat's take passes through to the teacher's device. */
async function seatTake(request, env, seat, pid, takeId, now) {
  if (await limited(env.PLAY_UPLOAD_LIMITER, `seat:${seat.class_id}:${seat.id}`)) return problem(429, "rate_limited");
  const { p, error } = await seatProduction(env, seat, pid);
  if (error) return error;
  // Decision 059: an under-13 voice leaves a device only under the school's consent, which waits on P5.
  if (seat.under13 && !seat.consent) return problem(403, "school_consent_required");
  const meta = parseTakeMeta(request.headers.get("x-take"));
  if (!meta) return problem(400, "bad_request", "x-take must be the take's fields as JSON");
  const part = partOf(p.cast, meta.lineID);
  if (!part) return problem(422, "no_such_line");
  if (meta.part !== undefined && meta.part !== part) return problem(422, "line_is_another_part", part);
  // Claims do not apply: an assigned line records whenever its seat is ready (owner ruling 3).
  if (!assignedTo(p.cast, await assignmentRows(env, p.id), seat.id, meta.lineID)) return problem(403, "not_assigned");
  const who = { userId: p.user_id, seatId: seat.id, sender: `seat:${seat.class_id}:${seat.id}`, direct: false };
  return receiveTake(env, request, p, takeId, meta, part, who, now);
}

/** POST /v1/plays/seat/productions/:id/chosen { take_id }: the student chooses which of their takes is offered. */
async function seatChoose(request, env, seat, pid, now) {
  const { p, error } = await seatProduction(env, seat, pid);
  if (error) return error;
  const { body, error: bad } = await readJson(request, 4 * 1024);
  if (bad) return bad;
  const t = await env.DB.prepare("SELECT line_id, seat_id FROM play_takes WHERE production_id = ?1 AND id = ?2").bind(p.id, body.take_id).first();
  if (!t || t.seat_id !== seat.id) return problem(404, "no_such_take");
  await env.DB.batch([...chooseStatements(env, p.id, t.line_id, body.take_id), touch(env, p.id, now)]);
  return seatHome(env, seat);
}

/** Every /v1/plays/seat route: no account, the seat key in `x-seat-key`. */
export async function handleSeat(url, request, env, ip) {
  const now = Date.now();
  const m = request.method;
  const seg = url.pathname.slice("/v1/plays/seat".length).split("/").filter(Boolean);
  const [a, b, c, d] = seg;
  if ((a === "list" || a === "claim") && !b && m === "POST") {
    if (await limited(env.SEAT_JOIN_LIMITER, ip)) return problem(429, "rate_limited");
    return a === "list" ? listSeats(request, env) : claimSeat(request, env, now);
  }
  const seat = await seatByKey(env, request.headers.get(SEAT_KEY_HEADER));
  if (!seat) return problem(401, "seat_key_required");
  if (await limited(env.SEAT_LIMITER, `${seat.class_id}:${seat.id}`)) return problem(429, "rate_limited");
  if (!a && m === "GET") return seatHome(env, seat);
  if (a === "productions" && b && c === "takes" && d && seg.length === 4 && m === "PUT") return seatTake(request, env, seat, b, d, now);
  if (a === "productions" && b && c === "receiver" && seg.length === 3 && m === "GET") {
    const { p, error } = await seatProduction(env, seat, b);
    return error || json(await receiverOf(env, p));
  }
  if (a === "productions" && b && c === "chosen" && seg.length === 3 && m === "POST") return seatChoose(request, env, seat, b, now);
  return problem(404, "not_found");
}

export const isSeatRoute = (pathname) => pathname === "/v1/plays/seat" || pathname.startsWith("/v1/plays/seat/");
