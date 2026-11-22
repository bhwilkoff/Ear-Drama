// Retention and deletion (Decision 084; owner 2026-11-21: "I don't mind deleting the info about
// who recorded what, but we need to be able to keep the recorded Ear Dramas in our database.").
// Delete class, Delete production, the class end date, the idle sweeps, the class export, the
// operator's school-request route, the 13+ publish confirmations, and the school's reference.
// Scripts come from the castable file by their data, never by name.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { call, env, installProviderKeys, signIn } from "./helpers.js";
import { claimByInvite, createBody, createProduction, invite, order } from "./plays-helpers.js";
import { isSpeaking } from "../src/plays-relay.js";
import { ACCOUNT_IDLE_MS, CLASS_IDLE_MS, NOTICE_MS, endDateRefusal, endsAt, schoolYearEnd, sweepRetention } from "../src/plays-retention.js";
import { DELETED_PERSON } from "../src/plays.js";
import { createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test";
import worker from "../src/index.js";

const KEYS = { IA_S3_ACCESS_KEY: "TESTIAACCESSret", IA_S3_SECRET_KEY: "TESTIASECRETret" };
const OP = { authorization: "Bearer test-only-operator-token" };
const DAY = 24 * 60 * 60 * 1000;

beforeEach(() => {
  installProviderKeys();
});
afterEach(() => vi.restoreAllMocks());

let n = 0;
const person = (label) => signIn(`ret-${label}-${n++}`);
const [partA, partB] = order.filter(isSpeaking);
const count = async (sql, ...b) => (await env.DB.prepare(sql).bind(...b).first()).n;

/** A class with three seats, one production cast to two of them, a seat take on each part, and a review note. */
async function classWithWork(label, { under13 = false } = {}) {
  const teacher = await person(label);
  const c = await (await call("POST", "/v1/plays/classes", { token: teacher.access_token, body: { name: "Room 9", under13 } })).json();
  const seats = Object.fromEntries(
    (await (await call("POST", `/v1/plays/classes/${c.id}/seats`, { token: teacher.access_token, body: { labels: ["Lucy", "Tom", "Ana"] } })).json()).seats.map((s) => [s.label, s.id]),
  );
  const made = async () => {
    const r = await call("POST", `/v1/plays/classes/${c.id}/productions`, { token: teacher.access_token, body: createBody({ display_name: "Ms. Ortiz" }) });
    expect(r.status, await r.clone().text()).toBe(201);
    const p = await r.json();
    const a = await call("PUT", `/v1/plays/productions/${p.id}/assignments`, {
      token: teacher.access_token,
      body: { assignments: [{ part: partA, seat: seats.Lucy }, { part: partB, seat: seats.Tom }] },
    });
    expect(a.status).toBe(200);
    const line = (part) => createBody().cast.find((x) => x.part === part).id;
    const now = Date.now();
    await env.DB.batch(
      [
        [`T-${p.id.slice(0, 6)}-a`, seats.Lucy, line(partA), partA],
        [`T-${p.id.slice(0, 6)}-b`, seats.Tom, line(partB), partB],
      ].map(([id, seat, lineId, part]) =>
        env.DB.prepare(
          "INSERT INTO play_takes (production_id, id, user_id, seat_id, line_id, part, file, content_type, bytes, frames, sample_rate, capture, created, uploaded_at, chosen) " +
            "VALUES (?1, ?2, ?3, ?4, ?5, ?6, 'x.wav', 'audio/wav', 100, 48000, 48000, 'room', 0, ?7, 1)",
        ).bind(p.id, id, teacher.user_id, seat, lineId, part, now),
      ),
    );
    const rv = await call("POST", `/v1/plays/productions/${p.id}/takes/T-${p.id.slice(0, 6)}-a/review`, {
      token: teacher.access_token,
      body: { state: "again", note: "Lucy, slower on the second line" },
    });
    expect(rv.status).toBe(200);
    return p;
  };
  return { teacher, c, seats, made };
}

/** Marks a production submitted and published, as the uploader would leave it. */
async function publishedNow(p, userId) {
  const now = Date.now();
  await env.DB.batch([
    env.DB.prepare(
      "INSERT INTO play_archive_jobs (production_id, user_id, status, take_ids, created_at, updated_at, item_url, published_at) VALUES (?1, ?2, 'published', '[]', ?3, ?3, ?4, ?3)",
    ).bind(p.id, userId, now, `https://archive.org/details/eardrama-${p.id.toLowerCase()}`),
    env.DB.prepare(
      "INSERT INTO play_archive_files (production_id, line_id, seq, part, take_id, name, state, updated_at) VALUES (?1, 'L-kept', 1, ?2, 'T-kept', '0001-A.wav', 'sent', ?3)",
    ).bind(p.id, partA, now),
  ]);
}

/** Every row the class left, by table; a deleted class leaves zero in each. */
async function classRows(classId, pids) {
  const marks = pids.map((_, i) => `?${i + 1}`).join(",");
  const per = async (t) => count(`SELECT COUNT(*) AS n FROM ${t} WHERE production_id IN (${marks})`, ...pids);
  return {
    classes: await count("SELECT COUNT(*) AS n FROM play_classes WHERE id = ?1", classId),
    seats: await count("SELECT COUNT(*) AS n FROM play_class_seats WHERE class_id = ?1", classId),
    members: await count("SELECT COUNT(*) AS n FROM play_class_members WHERE class_id = ?1", classId),
    consents: await count("SELECT COUNT(*) AS n FROM play_school_consents WHERE class_id = ?1", classId),
    productions: await count(`SELECT COUNT(*) AS n FROM play_productions WHERE id IN (${marks})`, ...pids),
    takes: await per("play_takes"),
    reviews: await per("play_reviews"),
    assignments: await per("play_assignments"),
  };
}

const ZERO = { classes: 0, seats: 0, members: 0, consents: 0, productions: 0, takes: 0, reviews: 0, assignments: 0 };

/** The published production is kept whole but for who recorded what. */
async function expectKeptWithoutSeats(p) {
  const row = await env.DB.prepare("SELECT class_id, title FROM play_productions WHERE id = ?1").bind(p.id).first();
  expect(row).not.toBeNull();
  expect(row.class_id).toBeNull();
  expect(await count("SELECT COUNT(*) AS n FROM play_takes WHERE production_id = ?1", p.id)).toBe(2);
  expect(await count("SELECT COUNT(*) AS n FROM play_takes WHERE production_id = ?1 AND seat_id IS NOT NULL", p.id)).toBe(0);
  expect(await count("SELECT COUNT(*) AS n FROM play_reviews WHERE production_id = ?1", p.id)).toBe(0);
  expect(await count("SELECT COUNT(*) AS n FROM play_assignments WHERE production_id = ?1", p.id)).toBe(0);
  expect(await count("SELECT COUNT(*) AS n FROM play_archive_jobs WHERE production_id = ?1", p.id)).toBe(1);
  expect(await count("SELECT COUNT(*) AS n FROM play_archive_files WHERE production_id = ?1", p.id)).toBe(1);
  expect((await call("GET", `/v1/plays/finished/${p.id}`)).status).toBe(200);
}

describe("Delete class: who recorded what goes, the published ear drama stays", () => {
  it("only the teacher deletes a class; it takes seats, names, members, the school's record, casting, notes and every unsubmitted production", async () => {
    const { teacher, c, made } = await classWithWork("del-class", { under13: true });
    const p = await made();
    const other = await person("del-class-other");
    const policy = { SCHOOL_CONSENT_POLICY: "privacy-test-2" };
    expect((await call("POST", `/v1/plays/classes/${c.id}/school-consent`, { token: teacher.access_token, body: { reference: "District DPA" }, envOverride: policy })).status).toBe(201);
    expect((await call("DELETE", `/v1/plays/classes/${c.id}`, { token: other.access_token })).status).toBe(403);
    expect((await call("DELETE", "/v1/plays/classes/no-such-class", { token: teacher.access_token })).status).toBe(404);
    expect((await classRows(c.id, [p.id])).seats).toBe(3);
    expect((await call("DELETE", `/v1/plays/classes/${c.id}`, { token: teacher.access_token })).status).toBe(204);
    expect(await classRows(c.id, [p.id])).toEqual(ZERO);
    expect((await call("GET", `/v1/plays/classes/${c.id}`, { token: teacher.access_token })).status).toBe(404);
  });

  it("a submitted production of the class stays, detached, with its takes but without their seats, notes or casting", async () => {
    const { teacher, c, made } = await classWithWork("del-kept");
    const kept = await made();
    const gone = await made();
    await publishedNow(kept, teacher.user_id);
    expect((await call("DELETE", `/v1/plays/classes/${c.id}`, { token: teacher.access_token })).status).toBe(204);
    await expectKeptWithoutSeats(kept);
    expect(await classRows(c.id, [gone.id])).toEqual(ZERO);
    expect(JSON.stringify(await (await call("GET", `/v1/plays/finished/${kept.id}`)).json())).not.toMatch(/Lucy|Tom|Ana/);
  });
});

describe("Delete production (the director)", () => {
  it("only the director deletes, every row of it goes, and a submitted production is refused", async () => {
    const director = await person("del-prod");
    const other = await person("del-prod-other");
    const p = await createProduction(director, { display_name: "Pat" });
    const kept = await createProduction(director, { display_name: "Pat" });
    await env.DB.prepare("INSERT INTO play_archive_jobs (production_id, user_id, status, take_ids, created_at, updated_at) VALUES (?1, ?2, 'queued', '[]', 1, 1)")
      .bind(kept.id, director.user_id)
      .run();
    expect((await call("DELETE", `/v1/plays/productions/${p.id}`, { token: other.access_token })).status).toBe(404);
    const member = await person("del-prod-member");
    const inv = await invite(director, p.id);
    expect((await claimByInvite(member, inv.token, order[0], { display_name: "Zoe" })).status).toBe(200);
    const notDirector = await call("DELETE", `/v1/plays/productions/${p.id}`, { token: member.access_token });
    expect(notDirector.status).toBe(403);
    expect((await notDirector.json()).error).toBe("director_only");
    const refused = await call("DELETE", `/v1/plays/productions/${kept.id}`, { token: director.access_token });
    expect(refused.status).toBe(409);
    expect((await refused.json()).error).toBe("submitted");
    expect(await count("SELECT COUNT(*) AS n FROM play_productions WHERE id = ?1", kept.id)).toBe(1);
    expect((await call("DELETE", `/v1/plays/productions/${p.id}`, { token: director.access_token })).status).toBe(204);
    expect(await count("SELECT COUNT(*) AS n FROM play_productions WHERE id = ?1", p.id)).toBe(0);
    expect(await count("SELECT COUNT(*) AS n FROM play_members WHERE production_id = ?1", p.id)).toBe(0);
  });

  it("a teacher deletes one class production; a member who is not the director cannot", async () => {
    const { teacher, c, made } = await classWithWork("del-cprod");
    const p = await made();
    expect((await call("DELETE", `/v1/plays/productions/${p.id}`, { token: teacher.access_token })).status).toBe(204);
    expect((await classRows(c.id, [p.id])).takes).toBe(0);
    expect((await classRows(c.id, [p.id])).reviews).toBe(0);
    expect((await classRows(c.id, [p.id])).seats).toBe(3);
  });
});

describe("the class end date", () => {
  it("defaults to the July 31 that closes the school year; the day after it is when it may go", () => {
    expect(schoolYearEnd(Date.UTC(2026, 10, 21))).toBe("2027-07-31");
    expect(schoolYearEnd(Date.UTC(2027, 7, 1))).toBe("2028-07-31");
    expect(schoolYearEnd(Date.UTC(2027, 6, 31, 23))).toBe("2027-07-31");
    expect(endsAt("2027-07-31")).toBe(Date.UTC(2027, 7, 1, 12));
    const now = Date.UTC(2026, 10, 21);
    expect(endDateRefusal("2027-08-30", now)).toBeNull();
    expect(endDateRefusal("2027-02-30", now)).toBe("bad_end_date");
    expect(endDateRefusal("2026-11-01", now)).toBe("end_date_past");
    expect(endDateRefusal("2028-11-21", now)).toBe("end_date_too_far");
  });

  it("a new class carries it; only its teacher changes it, within the limits", async () => {
    const t = await person("ends");
    const other = await person("ends-other");
    const c = await (await call("POST", "/v1/plays/classes", { token: t.access_token, body: { name: "Room 2" } })).json();
    expect(c.ends_on).toBe(schoolYearEnd(Date.now()));
    const later = new Date(Date.now() + 200 * DAY).toISOString().slice(0, 10);
    expect((await call("PATCH", `/v1/plays/classes/${c.id}`, { token: other.access_token, body: { ends_on: later } })).status).toBe(403);
    const bad = await call("PATCH", `/v1/plays/classes/${c.id}`, { token: t.access_token, body: { ends_on: "2001-01-01" } });
    expect(bad.status).toBe(422);
    expect((await bad.json()).error).toBe("end_date_past");
    const ok = await call("PATCH", `/v1/plays/classes/${c.id}`, { token: t.access_token, body: { ends_on: later } });
    expect(ok.status).toBe(200);
    expect((await (await call("GET", `/v1/plays/classes/${c.id}`, { token: t.access_token })).json()).ends_on).toBe(later);
    expect((await (await call("GET", "/v1/plays/classes", { token: t.access_token })).json()).teaching[0]).toMatchObject({ ends_on: later, deletes_on: null });
  });

  it("the sweep deletes a class the day after it ends, never before, and never its published production", async () => {
    const ending = await classWithWork("sweep-end");
    const kept = await ending.made();
    await publishedNow(kept, ending.teacher.user_id);
    const staying = await classWithWork("sweep-stay");
    const now = Date.now();
    const today = new Date(now).toISOString().slice(0, 10);
    const yesterday2 = new Date(now - 2 * DAY).toISOString().slice(0, 10);
    await env.DB.prepare("UPDATE play_classes SET ends_on = ?2 WHERE id = ?1").bind(ending.c.id, yesterday2).run();
    await env.DB.prepare("UPDATE play_classes SET ends_on = ?2 WHERE id = ?1").bind(staying.c.id, today).run();
    await sweepRetention(env, now);
    expect(await count("SELECT COUNT(*) AS n FROM play_classes WHERE id = ?1", ending.c.id)).toBe(0);
    expect(await count("SELECT COUNT(*) AS n FROM play_class_seats WHERE class_id = ?1", ending.c.id)).toBe(0);
    await expectKeptWithoutSeats(kept);
    expect(await count("SELECT COUNT(*) AS n FROM play_classes WHERE id = ?1", staying.c.id)).toBe(1);
  });
});

describe("idle classes: twelve months, after a thirty-day notice", () => {
  const age = (classId, at) =>
    env.DB.batch([
      env.DB.prepare("UPDATE play_classes SET touched_at = ?2, created_at = ?2, ends_on = '2999-07-31' WHERE id = ?1").bind(classId, at),
      env.DB.prepare("UPDATE play_productions SET updated_at = ?2 WHERE class_id = ?1").bind(classId, at),
      env.DB.prepare("UPDATE play_class_seats SET claimed_at = NULL WHERE class_id = ?1").bind(classId),
    ]);

  it("notice first, shown in the teacher's list; deleted only once the notice has run; the published production stays", async () => {
    const { teacher, c, made } = await classWithWork("idle");
    const kept = await made();
    await publishedNow(kept, teacher.user_id);
    const now = Date.now();
    await age(c.id, now - CLASS_IDLE_MS + NOTICE_MS - DAY);
    await sweepRetention(env, now);
    expect(await count("SELECT COUNT(*) AS n FROM play_classes WHERE id = ?1", c.id)).toBe(1);
    const listed = (await (await call("GET", "/v1/plays/classes", { token: teacher.access_token })).json()).teaching[0];
    expect(listed.deletes_on).toBe(new Date(now + NOTICE_MS).toISOString().slice(0, 10));
    await sweepRetention(env, now + NOTICE_MS - DAY);
    expect(await count("SELECT COUNT(*) AS n FROM play_classes WHERE id = ?1", c.id)).toBe(1);
    await sweepRetention(env, now + NOTICE_MS + DAY);
    expect(await count("SELECT COUNT(*) AS n FROM play_classes WHERE id = ?1", c.id)).toBe(0);
    await expectKeptWithoutSeats(kept);
  });

  it("the teacher opening the class ends the notice, and the next sweep keeps it", async () => {
    const { teacher, c } = await classWithWork("idle-back");
    const now = Date.now();
    await age(c.id, now - CLASS_IDLE_MS - 3 * DAY);
    await sweepRetention(env, now - NOTICE_MS - DAY);
    expect((await env.DB.prepare("SELECT notice_at FROM play_classes WHERE id = ?1").bind(c.id).first()).notice_at).not.toBeNull();
    expect((await call("GET", `/v1/plays/classes/${c.id}`, { token: teacher.access_token })).status).toBe(200);
    expect((await env.DB.prepare("SELECT notice_at FROM play_classes WHERE id = ?1").bind(c.id).first()).notice_at).toBeNull();
    await sweepRetention(env, now);
    expect(await count("SELECT COUNT(*) AS n FROM play_classes WHERE id = ?1", c.id)).toBe(1);
  });

  it("a production's activity counts as the class's, and ends a notice already running", async () => {
    const { c, made } = await classWithWork("idle-prod");
    await made();
    const now = Date.now();
    await age(c.id, now - 2 * CLASS_IDLE_MS);
    await env.DB.prepare("UPDATE play_productions SET updated_at = ?2 WHERE class_id = ?1").bind(c.id, now - DAY).run();
    await sweepRetention(env, now);
    expect((await env.DB.prepare("SELECT notice_at FROM play_classes WHERE id = ?1").bind(c.id).first()).notice_at).toBeNull();
    await age(c.id, now - 2 * CLASS_IDLE_MS);
    await sweepRetention(env, now);
    expect((await env.DB.prepare("SELECT notice_at FROM play_classes WHERE id = ?1").bind(c.id).first()).notice_at).toBe(now);
    await env.DB.prepare("UPDATE play_productions SET updated_at = ?2 WHERE class_id = ?1").bind(c.id, now + DAY).run();
    await sweepRetention(env, now + NOTICE_MS + 2 * DAY);
    const row = await env.DB.prepare("SELECT notice_at FROM play_classes WHERE id = ?1").bind(c.id).first();
    expect(row).not.toBeNull();
    expect(row.notice_at).toBeNull();
  });

  it("a class idle for years still gets its full notice before it goes", async () => {
    const { c } = await classWithWork("idle-old");
    const now = Date.now();
    await age(c.id, now - 3 * CLASS_IDLE_MS);
    await sweepRetention(env, now);
    expect(await count("SELECT COUNT(*) AS n FROM play_classes WHERE id = ?1", c.id)).toBe(1);
    await sweepRetention(env, now + NOTICE_MS - DAY);
    expect(await count("SELECT COUNT(*) AS n FROM play_classes WHERE id = ?1", c.id)).toBe(1);
  });

  it("the hourly cron runs the retention sweep", async () => {
    const { c } = await classWithWork("idle-cron");
    await env.DB.prepare("UPDATE play_classes SET ends_on = '2001-07-31' WHERE id = ?1").bind(c.id).run();
    const ctx = createExecutionContext();
    await worker.scheduled(createScheduledController({ cron: "23 * * * *" }), env, ctx);
    await waitOnExecutionContext(ctx);
    expect(await count("SELECT COUNT(*) AS n FROM play_classes WHERE id = ?1", c.id)).toBe(0);
  });
});

describe("idle accounts: three years, after a thirty-day notice any sign-in cancels", () => {
  it("deleted as if its owner had; a sign-in in the notice keeps it; the deleted-account row is never swept", async () => {
    const idle = await person("acct-idle");
    const back = await person("acct-back");
    const now = Date.now();
    await env.DB.prepare("INSERT OR IGNORE INTO users (id, created_at) VALUES (?1, 0)").bind(DELETED_PERSON).run();
    await env.DB.prepare("UPDATE users SET seen_at = ?2 WHERE id IN (?1, ?3)").bind(idle.user_id, now - ACCOUNT_IDLE_MS + NOTICE_MS - DAY, back.user_id).run();
    await env.DB.prepare("UPDATE users SET seen_at = 0 WHERE id = ?1").bind(DELETED_PERSON).run();
    await sweepRetention(env, now);
    expect(await count("SELECT COUNT(*) AS n FROM users WHERE id = ?1 AND idle_notice_at IS NOT NULL", idle.user_id)).toBe(1);
    expect(await count("SELECT COUNT(*) AS n FROM users WHERE id = ?1 AND idle_notice_at IS NOT NULL", DELETED_PERSON)).toBe(0);
    await env.DB.prepare("UPDATE users SET idle_notice_at = 1 WHERE id = ?1").bind(DELETED_PERSON).run();
    expect(await count("SELECT COUNT(*) AS n FROM users WHERE id = ?1", idle.user_id)).toBe(1);
    expect((await call("POST", "/v1/auth/refresh", { body: { refresh_token: back.refresh_token } })).status).toBe(200);
    await sweepRetention(env, now + NOTICE_MS + DAY);
    expect(await count("SELECT COUNT(*) AS n FROM users WHERE id = ?1", idle.user_id)).toBe(0);
    expect(await count("SELECT COUNT(*) AS n FROM identities WHERE user_id = ?1", idle.user_id)).toBe(0);
    expect(await count("SELECT COUNT(*) AS n FROM users WHERE id = ?1", back.user_id)).toBe(1);
    expect(await count("SELECT COUNT(*) AS n FROM users WHERE id = ?1", DELETED_PERSON)).toBe(1);
  });
});

describe("an account already past three idle years gets its notice before it goes", () => {
  it("the first sweep only gives the notice; deleted only once the notice has run", async () => {
    const long = await person("acct-long");
    const now = Date.now();
    await env.DB.prepare("UPDATE users SET seen_at = ?2, idle_notice_at = NULL WHERE id = ?1").bind(long.user_id, now - ACCOUNT_IDLE_MS - 10 * DAY).run();
    await sweepRetention(env, now);
    expect(await count("SELECT COUNT(*) AS n FROM users WHERE id = ?1 AND idle_notice_at IS NOT NULL", long.user_id)).toBe(1);
    await sweepRetention(env, now + NOTICE_MS - DAY);
    expect(await count("SELECT COUNT(*) AS n FROM users WHERE id = ?1", long.user_id)).toBe(1);
    await sweepRetention(env, now + NOTICE_MS + DAY);
    expect(await count("SELECT COUNT(*) AS n FROM users WHERE id = ?1", long.user_id)).toBe(0);
  });
});

describe("the teacher's class export", () => {
  it("only the teacher; seat labels, casting, progress, review states and notes; no audio", async () => {
    const { teacher, c, made } = await classWithWork("export");
    const p = await made();
    const other = await person("export-other");
    expect((await call("GET", `/v1/plays/classes/${c.id}/export`, { token: other.access_token })).status).toBe(403);
    const r = await call("GET", `/v1/plays/classes/${c.id}/export`, { token: teacher.access_token });
    expect(r.status).toBe(200);
    const x = await r.json();
    expect(x.format).toBe("eardrama-class-export");
    expect(x.class).toMatchObject({ id: c.id, name: "Room 9", under13: false, ends_on: c.ends_on, school_authorization: null });
    expect(x.seats.map((s) => s.label)).toEqual(["Lucy", "Tom", "Ana"]);
    const prod = x.productions.find((q) => q.id === p.id);
    expect(prod.assignments.map((a) => a.seat_label).sort()).toEqual(["Lucy", "Tom"]);
    expect(prod.takes.find((k) => k.seat_label === "Lucy").review).toMatchObject({ state: "again", note: "Lucy, slower on the second line" });
    expect(prod.progress.length).toBe(2);
    const text = JSON.stringify(x);
    for (const k of ["key_hash", "object_key", "user_id", "bytes"]) expect(text).not.toContain(k);
  });
});

describe("a school's deletion request: the operator route", () => {
  it("needs the operator token; finds by code or the school's reference; deletes as Delete class does", async () => {
    const { teacher, c, made } = await classWithWork("operator", { under13: true });
    const kept = await made();
    await publishedNow(kept, teacher.user_id);
    const policy = { SCHOOL_CONSENT_POLICY: "privacy-test-3" };
    expect((await call("POST", `/v1/plays/classes/${c.id}/school-consent`, { token: teacher.access_token, body: { reference: "Lakeview District NDPA" }, envOverride: policy })).status).toBe(201);
    expect((await call("GET", `/v1/operator/classes?code=${c.code}`)).status).toBe(403);
    expect((await call("GET", `/v1/operator/classes?code=${c.code}`, { headers: { authorization: "Bearer test-only-takedown-token" } })).status).toBe(403);
    expect((await call("GET", `/v1/operator/classes?code=${c.code}`, { headers: OP, envOverride: { OPERATOR_TOKEN: undefined } })).status).toBe(403);
    const byCode = await (await call("GET", `/v1/operator/classes?code=${c.code.toLowerCase()}`, { headers: OP })).json();
    expect(byCode.classes.map((x) => x.id)).toEqual([c.id]);
    expect(JSON.stringify(byCode)).not.toMatch(/Lucy|Tom|Ana/);
    const byRef = await (await call("GET", "/v1/operator/classes?reference=lakeview%20district%20ndpa", { headers: OP })).json();
    expect(byRef.classes.map((x) => x.id)).toEqual([c.id]);
    const d = await call("DELETE", `/v1/operator/classes/${c.id}`, { headers: OP });
    expect(d.status).toBe(200);
    expect(await classRows(c.id, [])).toMatchObject({ classes: 0, seats: 0, consents: 0 });
    await expectKeptWithoutSeats(kept);
    expect((await call("DELETE", `/v1/operator/classes/${c.id}`, { headers: OP })).status).toBe(404);
  });
});

describe("13 and over: the teacher's two confirmations before a class publishes (owner 2026-11-21)", () => {
  it("every performer agreed AND a media release for each performer under 18; both are recorded on the job", async () => {
    const { teacher, c } = await classWithWork("confirm");
    const r0 = await call("POST", `/v1/plays/classes/${c.id}/productions`, { token: teacher.access_token, body: createBody({ display_name: "Ms. Ortiz" }) });
    const p = await r0.json();
    const publish = (body) => call("POST", `/v1/plays/productions/${p.id}/publish`, { token: teacher.access_token, envOverride: KEYS, body });
    for (const body of [{}, { performers_agreed: true }, { media_release: true }, { performers_agreed: "yes", media_release: true }]) {
      const r = await publish(body);
      expect(r.status).toBe(422);
      expect((await r.json()).error).toBe("confirmations_required");
    }
    expect(await count("SELECT COUNT(*) AS n FROM play_archive_jobs WHERE production_id = ?1", p.id)).toBe(0);
    const stmts = createBody()
      .cast.filter((x) => isSpeaking(x.part))
      .map((x, i) =>
        env.DB.prepare(
          "INSERT INTO play_takes (production_id, id, user_id, line_id, part, file, content_type, bytes, frames, sample_rate, capture, created, uploaded_at, chosen) " +
            "VALUES (?1, ?2, ?3, ?4, ?5, 'x.wav', 'audio/wav', 100, 4800, 48000, 'room', 0, 1, 1)",
        ).bind(p.id, `CF-${i}`, teacher.user_id, x.id, x.part),
      );
    for (let i = 0; i < stmts.length; i += 100) await env.DB.batch(stmts.slice(i, i + 100));
    await call("POST", `/v1/plays/productions/${p.id}/consent`, { token: teacher.access_token, body: { version: (await (await call("GET", "/v1/plays/consent", { token: teacher.access_token })).json()).version } });
    const ok = await publish({ performers_agreed: true, media_release: true });
    expect(ok.status, await ok.clone().text()).toBe(201);
    const job = await env.DB.prepare("SELECT performers_agreed_at, media_release_at FROM play_archive_jobs WHERE production_id = ?1").bind(p.id).first();
    expect(job.performers_agreed_at).toBeGreaterThan(0);
    expect(job.media_release_at).toBeGreaterThan(0);
  });
});

describe("an under-13 class: the school or district's authorization, named (FTC COPPA FAQ N.3)", () => {
  it("the teacher must record which authorization; an empty reference is refused", async () => {
    const t = await person("ref");
    const c = await (await call("POST", "/v1/plays/classes", { token: t.access_token, body: { name: "Grade 3", under13: true } })).json();
    const policy = { SCHOOL_CONSENT_POLICY: "privacy-test-4" };
    for (const reference of [undefined, "", "   "]) {
      const r = await call("POST", `/v1/plays/classes/${c.id}/school-consent`, { token: t.access_token, body: { reference }, envOverride: policy });
      expect(r.status).toBe(422);
      expect((await r.json()).error).toBe("reference_required");
    }
    expect((await call("POST", `/v1/plays/classes/${c.id}/school-consent`, { token: t.access_token, body: { reference: "Board approval 2026-09" }, envOverride: policy })).status).toBe(201);
  });
});
