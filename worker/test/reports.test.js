// Reports reach a person (Decision 088.6): the count the hourly workflow asks for, and the owner's answers
// (worker/ops/reports.json, run by tools/reports.py), judged by what the Worker's own routes say afterward. What an
// answer does to a published item is in archive.test.js.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { call, env, githubToken, installProviderKeys, ownerOp, signIn } from "./helpers.js";
import { claimByInvite, createProduction, firstPart, invite, linesFor, newTakeId, record, secondPart } from "./plays-helpers.js";

beforeEach(async () => {
  installProviderKeys();
  await env.DB.prepare("DELETE FROM play_reports").run();
});
afterEach(() => vi.restoreAllMocks());

let n = 0;
const person = (label) => signIn(`reports-${label}-${n++}`);
const count = async (extra = {}) => {
  const r = await call("GET", "/v1/operator/reports/count", { token: await githubToken("reports.yml"), ...extra });
  expect(r.status, await r.clone().text()).toBe(200);
  return r.json();
};

async function seedTake(pid, userId, part, { seat = null, credit = null } = {}) {
  const id = newTakeId();
  const line = linesFor(part)[0];
  await env.DB.batch([
    env.DB.prepare("UPDATE play_takes SET chosen = 0 WHERE production_id = ?1 AND line_id = ?2").bind(pid, line),
    env.DB.prepare(
      "INSERT INTO play_takes (production_id, id, user_id, seat_id, line_id, part, file, content_type, bytes, frames, sample_rate, capture, created, uploaded_at, chosen, credit) " +
        "VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 'audio/wav', 10, 4800, 48000, 'direct', 0, ?8, 1, ?9)",
    ).bind(pid, id, userId, seat, line, part, `${id}.wav`, Date.now(), credit),
  ]);
  return id;
}

/** Pat directs and has a take of the first part; Zoë holds the second part with a take; one live invite. */
async function setup(label) {
  const director = await person(`${label}-dir`);
  const zoe = await person(`${label}-zoe`);
  const p = await createProduction(director, { display_name: "Pat" });
  const inv = await invite(director, p.id);
  expect((await claimByInvite(zoe, inv.token, firstPart, { display_name: "Zoë" })).status).toBe(200);
  const patTake = await seedTake(p.id, director.user_id, secondPart);
  const zoeTake = await seedTake(p.id, zoe.user_id, firstPart);
  return { director, zoe, p, inv, patTake, zoeTake };
}

async function report(s, body) {
  const r = await call("POST", "/v1/plays/reports", { token: s.access_token, body: { reason: "harassment", note: "PLANTED-NOTE-7", ...body } });
  expect(r.status, await r.clone().text()).toBe(201);
  return (await r.json()).id;
}
const show = async (id) => (await ownerOp("show", { id, now: Date.now() }))[0];
/** The values tools/reports.py reads from `show` and gives the answer. */
const answer = async (op, id) => {
  const r = await show(id);
  await ownerOp(op, { id, production: r.production_id, take: r.take_id, target: r.target_user_id, seat: r.seat, credit: r.credit, reason: r.reason, now: Date.now() });
};
const status = async (id) => (await env.DB.prepare("SELECT status FROM play_reports WHERE id = ?1").bind(id).first()).status;
const openInvite = async (token) => {
  const r = await call("GET", "/v1/plays/open/invite", { headers: { "x-invite": token } });
  return { status: r.status, body: await r.json() };
};

describe("the count the hourly workflow asks for", () => {
  it("is how many reports are open: 0, then 1, then 2, then 1 when one is answered", async () => {
    const { director, zoe, p, zoeTake } = await setup("count");
    expect(await count()).toEqual({ open: 0 });
    const first = await report(director, { production_id: p.id, take_id: zoeTake });
    expect(await count()).toEqual({ open: 1 });
    await report(zoe, { production_id: p.id, user_id: director.user_id });
    expect(await count()).toEqual({ open: 2 });
    await ownerOp("dismiss", { id: first });
    expect(await count()).toEqual({ open: 1 });
  });

  it("says nothing but the number, since the answer becomes a public issue", async () => {
    const { director, p, zoeTake } = await setup("quiet");
    await report(director, { production_id: p.id, take_id: zoeTake });
    expect(Object.keys(await count())).toEqual(["open"]);
  });

  it("costs one read: no write, no Durable Object", async () => {
    const sql = [];
    const DB = new Proxy(env.DB, {
      get(db, k) {
        if (k === "prepare") return (s) => (sql.push(s), db.prepare(s));
        const v = db[k];
        return typeof v === "function" ? (...a) => { throw new Error(`D1 ${String(k)} ${a.length}`); } : v;
      },
    });
    const none = new Proxy({}, { get() { throw new Error("a Durable Object was asked"); } });
    await count({ envOverride: { DB, READ_ROOMS: none, TAKE_RELAY: none } });
    expect(sql.length).toBe(1);
    expect(sql[0]).toMatch(/^SELECT/);
  });

  it("is read only", async () => {
    for (const method of ["POST", "DELETE", "PUT"]) {
      expect((await call(method, "/v1/operator/reports/count", { token: await githubToken("reports.yml"), body: method === "DELETE" ? undefined : {} })).status).toBe(405);
    }
  });
});

describe("the owner's answers (worker/ops/reports.json)", () => {
  it("list and show read what the owner needs", async () => {
    const { director, p, zoeTake } = await setup("read");
    const id = await report(director, { production_id: p.id, take_id: zoeTake });
    expect((await ownerOp("list"))[0]).toMatchObject({ id, reason: "harassment", kind: "take", class: 0, archive: null });
    expect(await show(id)).toMatchObject({ note: "PLANTED-NOTE-7", reporter_name: "Pat", target_name: "Zoë", take_id: zoeTake, part: firstPart, names_director: 0, live_invites: 1, their_takes: 1 });
    expect((await ownerOp("count"))[0].n).toBe(1);
  });

  it("dismiss closes one report and changes nothing else", async () => {
    const { director, zoe, p, zoeTake } = await setup("dismiss");
    const one = await report(director, { production_id: p.id, take_id: zoeTake });
    const two = await report(director, { production_id: p.id, user_id: zoe.user_id });
    await answer("dismiss", one);
    expect([await status(one), await status(two)]).toEqual(["dismissed", "open"]);
    expect((await record(zoe, p.id)).takes.map((t) => t.id)).toContain(zoeTake);
  });

  it("remove-take takes one take out of the record for everyone and closes every report of it", async () => {
    const { director, zoe, p, inv, patTake, zoeTake } = await setup("take");
    const a = await report(director, { production_id: p.id, take_id: zoeTake });
    const b = await report(director, { production_id: p.id, take_id: zoeTake });
    const other = await report(zoe, { production_id: p.id, take_id: patTake });
    await answer("remove-take", a);
    expect([await status(a), await status(b), await status(other)]).toEqual(["acted", "acted", "open"]);
    const rec = await record(zoe, p.id);
    expect(rec.takes.map((t) => t.id)).not.toContain(zoeTake);
    expect(rec.chosen[linesFor(firstPart)[0]]).toBeUndefined();
    // The other person's take stands, and Zoë is still in the production.
    expect((await record(director, p.id)).takes.map((t) => t.id)).toContain(patTake);
    expect(rec.members.map((m) => m.display_name)).toEqual(["Pat", "Zoë"]);
    expect((await openInvite(inv.token)).status).toBe(200);
  });

  it("remove-member takes out the person, their takes and their part, and closes the door they came in by", async () => {
    const { director, zoe, p, inv, patTake, zoeTake } = await setup("member");
    const a = await report(director, { production_id: p.id, user_id: zoe.user_id });
    const b = await report(director, { production_id: p.id, take_id: zoeTake });
    await answer("remove-member", a);
    expect([await status(a), await status(b)]).toEqual(["acted", "acted"]);
    expect((await call("GET", `/v1/plays/productions/${p.id}`, { token: zoe.access_token })).status).toBe(404);
    expect((await claimByInvite(zoe, inv.token, firstPart)).status).toBe(404);
    const rec = await record(director, p.id);
    expect(rec.takes.map((t) => t.id)).toEqual([patTake]);
    expect(rec.members.map((m) => m.display_name)).toEqual(["Pat"]);
    expect(rec.parts[firstPart].status).toBe("open");
    // The rest of the production goes on: a new invite brings someone else in.
    const next = await invite(director, p.id);
    expect((await claimByInvite(await person("member-new"), next.token, firstPart)).status).toBe(200);
  });

  it("remove-maker takes out one seat's, or one named reader's, takes and nobody else's", async () => {
    const { director, zoe, p, patTake } = await setup("maker");
    const ann = await seedTake(p.id, director.user_id, firstPart, { credit: "Ann" });
    const id = await report(zoe, { production_id: p.id, take_id: ann });
    await answer("remove-maker", id);
    expect(await status(id)).toBe("acted");
    const ids = (await record(director, p.id)).takes.map((t) => t.id);
    expect(ids).not.toContain(ann);
    expect(ids).toContain(patTake);
    const seat = await seedTake(p.id, director.user_id, firstPart, { seat: "s1" });
    const id2 = await report(zoe, { production_id: p.id, take_id: seat });
    await answer("remove-maker", id2);
    const after = (await record(director, p.id)).takes.map((t) => t.id);
    expect(after).not.toContain(seat);
    expect(after).toContain(patTake);
  });

  it("unshare closes every invite; the people already in it keep it", async () => {
    const { director, zoe, p, inv } = await setup("unshare");
    const second = await invite(director, p.id);
    const id = await report(zoe, { production_id: p.id, user_id: director.user_id });
    await answer("unshare", id);
    expect(await status(id)).toBe("acted");
    expect((await openInvite(inv.token)).status).toBe(410);
    expect((await openInvite(second.token)).status).toBe(410);
    expect((await record(zoe, p.id)).members.length).toBe(2);
  });

  it("another production's rows are never touched", async () => {
    const a = await setup("scope-a");
    const b = await setup("scope-b");
    const bid = await report(b.director, { production_id: b.p.id, take_id: b.zoeTake });
    for (const op of ["remove-take", "remove-member", "unshare"]) {
      const id = await report(a.director, { production_id: a.p.id, take_id: a.zoeTake });
      await answer(op, id).catch((e) => { throw new Error(`${op}: ${e.message}`); });
      if (op === "remove-take") a.zoeTake = await seedTake(a.p.id, a.zoe.user_id, firstPart);
      if (op === "remove-member") a.zoeTake = a.patTake;
    }
    expect(await status(bid)).toBe("open");
    expect((await record(b.zoe, b.p.id)).takes.map((t) => t.id)).toContain(b.zoeTake);
    expect((await openInvite(b.inv.token)).status).toBe(200);
  });
});
