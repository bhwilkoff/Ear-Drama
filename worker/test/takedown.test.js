import { describe, expect, it } from "vitest";
import { createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test";
import worker from "../src/index.js";
import { call, env } from "./helpers.js";
import { sweepTakedowns } from "../src/takedown.js";

const TOKEN = "test-only-takedown-token";
const notice = {
  kind: "copyright", links: "https://eardrama.org/series/x", work: "My Show",
  name: "Jane Requester", email: "jane@example.com", phone: "555-0100",
  address: "12 Private Lane", goodFaith: true, accurate: true, signature: "Jane Requester",
};
const send = (body, extra) => call("POST", "/v1/takedown", { body, ...extra });
const owner = (method, path, body) => call(method, path, { body, token: TOKEN });
const row = (ref) => env.DB.prepare("SELECT * FROM takedown_cases WHERE ref = ?1").bind(ref).first();

describe("take-down cases", () => {
  it("the form needs no credential and returns a case number", async () => {
    const r = await send(notice);
    expect(r.status).toBe(200);
    const { ref } = await r.json();
    expect(ref).toMatch(/^TD-[0-9A-Z]{8}$/);
    expect((await row(ref)).complete).toBe(1);
  });

  for (const k of ["links", "name", "email", "work", "address", "phone", "goodFaith", "accurate", "signature"]) {
    it(`a notice without ${k} is refused and says so`, async () => {
      const short = { ...notice };
      delete short[k];
      const r = await send(short);
      expect(r.status).toBe(400);
      expect((await r.json()).field).toBe(k);
    });
  }

  it("a privacy request needs a reason, not a sworn statement, and is not a notice", async () => {
    const base = { kind: "other", links: "x", name: "A", email: "a@b.co" };
    expect((await (await send(base)).json()).field).toBe("reason");
    const r = await send({ ...base, reason: "That is me" });
    expect(r.status).toBe(200);
    expect((await row((await r.json()).ref)).complete).toBe(0);
  });

  it("a filled trap field looks accepted and stores nothing", async () => {
    const n = async () => (await env.DB.prepare("SELECT COUNT(*) n FROM takedown_cases").first()).n;
    const before = await n();
    const r = await send({ ...notice, website: "http://spam" });
    expect(r.status).toBe(200);
    expect(await n()).toBe(before);
  });

  it("the form is rate limited per address", async () => {
    const deny = { limit: async () => ({ success: false }) };
    const r = await send(notice, { envOverride: { TAKEDOWN_LIMITER: deny } });
    expect(r.status).toBe(429);
  });

  it("no valid token, no answer", async () => {
    const { ref } = await (await send(notice)).json();
    for (const [m, p, b] of [["GET", "/v1/takedown/cases"], ["GET", `/v1/takedown/cases/${ref}`],
      ["POST", `/v1/takedown/cases/${ref}`, { status: "closed" }], ["POST", "/v1/takedown/cases", { links: "x" }]]) {
      expect((await call(m, p, { body: b })).status).toBe(403);
      expect((await call(m, p, { body: b, token: "wrong-token-of-any-length!!" })).status).toBe(403);
    }
  });

  it("the check's list carries nobody's details; the owner's read has them", async () => {
    const { ref } = await (await send(notice)).json();
    const list = await (await owner("GET", "/v1/takedown/cases")).json();
    expect(list.cases.some((c) => c.ref === ref)).toBe(true);
    expect(JSON.stringify(list)).not.toMatch(/Jane|jane@|555-0100|Private Lane/);
    expect((await (await owner("GET", `/v1/takedown/cases/${ref}`)).json()).email).toBe("jane@example.com");
  });

  it("an outcome is recorded and an unknown status refused", async () => {
    const { ref } = await (await send(notice)).json();
    expect((await owner("POST", `/v1/takedown/cases/${ref}`, { status: "nonsense" })).status).toBe(400);
    expect((await owner("POST", `/v1/takedown/cases/${ref}`, { status: "removed", verdict: [{ id: "x" }] })).status).toBe(200);
    const r = await row(ref);
    expect(r.status).toBe("removed");
    expect(r.closed_ms).toBeGreaterThan(0);
  });

  it("details are kept three years after a case closes, then erased; open cases are never swept", async () => {
    const YEAR = 365 * 24 * 3600 * 1000;
    const { ref } = await (await send(notice)).json();
    const open = await (await send(notice)).json();
    await owner("POST", `/v1/takedown/cases/${ref}`, { status: "closed" });
    const closed = (await row(ref)).closed_ms;
    await sweepTakedowns(env, closed + 2 * YEAR);
    expect((await row(ref)).email).toBe("jane@example.com");
    await sweepTakedowns(env, closed + 3 * YEAR + 1000);
    const swept = await row(ref);
    expect(swept.email || swept.name || swept.phone || swept.address || swept.signature || swept.work).toBeFalsy();
    expect(swept.status).toBe("closed");
    expect((await row(open.ref)).email).toBe("jane@example.com");
  });

  it("the hourly cron erases details three years after a case closed", async () => {
    const { ref } = await (await send(notice)).json();
    await env.DB.prepare("UPDATE takedown_cases SET status = 'closed', closed_ms = ?2 WHERE ref = ?1")
      .bind(ref, Date.now() - 3 * 365 * 24 * 3600 * 1000 - 5000).run();
    const ctx = createExecutionContext();
    await worker.scheduled(createScheduledController(), env, ctx);
    await waitOnExecutionContext(ctx);
    expect((await row(ref)).email).toBeNull();
  });
});
