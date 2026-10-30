import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { call, env, installProviderKeys, signIn } from "./helpers.js";
import { OTHER_PERSON_COLUMNS, USER_TABLES } from "../src/account.js";
import { ANONYMOUS_TABLES as ROOM_TABLES } from "../src/rooms.js";
import { DELETED_PERSON, PLAYS_ANONYMOUS_TABLES, sweepPlays } from "../src/plays.js";
import { claimByInvite, consent, createProduction, firstPart, invite, linesFor, record, upload } from "./plays-helpers.js";

const ANONYMOUS_TABLES = [...ROOM_TABLES, ...PLAYS_ANONYMOUS_TABLES];

let appleCalls;
beforeEach(() => {
  appleCalls = [];
  installProviderKeys({
    extra: async (url, init) => {
      if (url === "https://appleid.apple.com/auth/token") {
        appleCalls.push(["token", Object.fromEntries(new URLSearchParams(init.body))]);
        return Response.json({ refresh_token: "apple-refresh-xyz", access_token: "apple-access" });
      }
      if (url === "https://appleid.apple.com/auth/revoke") {
        appleCalls.push(["revoke", Object.fromEntries(new URLSearchParams(init.body))]);
        return new Response(null, { status: 200 });
      }
      return null;
    },
  });
});
afterEach(() => vi.restoreAllMocks());

/** Every table D1 holds for us, from the schema itself, not from a list we keep. */
async function allTables() {
  const { results } = await env.DB.prepare(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' AND name <> 'd1_migrations'",
  ).all();
  return results.map((r) => r.name);
}

/** Every column of `t` that holds a person's id: user_id, and any column D1 says references users(id). */
async function personColumns(t) {
  if (t === "users") return ["id"];
  const cols = (await env.DB.prepare(`PRAGMA table_info(${t})`).all()).results.map((c) => c.name);
  const fks = (await env.DB.prepare(`PRAGMA foreign_key_list(${t})`).all()).results.filter((f) => f.table === "users").map((f) => f.from);
  return [...new Set([...(cols.includes("user_id") ? ["user_id"] : []), ...fks])];
}

async function rowsFor(userId) {
  const out = {};
  for (const t of await allTables()) {
    if (ANONYMOUS_TABLES.includes(t)) continue;
    const cols = await personColumns(t);
    if (!cols.length) {
      out[t] = "NO USER COLUMN";
      continue;
    }
    const where = cols.map((c) => `${c} = ?1`).join(" OR ");
    out[t] = (await env.DB.prepare(`SELECT COUNT(*) AS n FROM ${t} WHERE ${where}`).bind(userId).first()).n;
  }
  return out;
}

/** Take objects in the bucket for one production. */
async function objectsIn(pid) {
  return (await env.TAKES.list({ prefix: `plays/${pid}/` })).objects.map((o) => o.key);
}

let partnerCount = 0;

/**
 * Gives `s` a row in every plays table: a production it directs (with an
 * invite, a claim, a consent, and a take; another with a queued upload), a report and a
 * block, a class it teaches with a school consent, and a class it joined.
 * Its partner is another account, made here, so a second account's rows can
 * be checked untouched without the two reporting each other.
 */
async function fillPlays(s) {
  const partner = await signIn(`partner-${s.user_id}-${partnerCount++}`);
  const p = await createProduction(s);
  await invite(s, p.id);
  const mine = await call("POST", `/v1/plays/productions/${p.id}/claim`, { token: s.access_token, body: { part: firstPart } });
  expect(mine.status).toBe(200);
  expect((await consent(s, p.id)).status).toBe(204);
  expect((await upload(s, p.id, linesFor(firstPart)[0])).status).toBe(201);
  // A second production of theirs that was submitted: its job keeps it past their deletion.
  const filed = await createProduction(s);
  await env.DB.prepare("INSERT INTO play_archive_jobs (production_id, user_id, status, take_ids, created_at, updated_at) VALUES (?1, ?2, 'queued', '[]', 1, 1)")
    .bind(filed.id, s.user_id)
    .run();
  // A report and a block, both about the partner, in the partner's production.
  const theirs = await createProduction(partner);
  const inv = await invite(partner, theirs.id);
  expect((await claimByInvite(s, inv.token, firstPart)).status).toBe(200);
  const rep = await call("POST", "/v1/plays/reports", {
    token: s.access_token,
    body: { production_id: theirs.id, user_id: partner.user_id, reason: "other" },
  });
  expect(rep.status).toBe(201);
  expect((await call("POST", "/v1/plays/blocks", { token: s.access_token, body: { user_id: partner.user_id } })).status).toBe(204);
  // Classes: one taught, with the school's consent; one joined.
  const policy = { SCHOOL_CONSENT_POLICY: "test-policy-1" };
  const taught = await (await call("POST", "/v1/plays/classes", { token: s.access_token, body: { name: "Room 4", under13: true } })).json();
  const sc = await call("POST", `/v1/plays/classes/${taught.id}/school-consent`, { token: s.access_token, body: {}, envOverride: policy });
  expect(sc.status).toBe(201);
  const other = await (await call("POST", "/v1/plays/classes", { token: partner.access_token, body: { name: "Drama club" } })).json();
  expect((await call("POST", "/v1/plays/classes/join", { token: s.access_token, body: { code: other.code } })).status).toBe(200);
  return { production: p, filed, partner, theirs };
}

async function fill(s) {
  const t = Date.now() - 1000;
  const r = await call("PUT", "/v1/sync", {
    token: s.access_token,
    body: {
      history: [{ episode_id: "x|1", position: 3, updated_at: t }],
      follows: [{ series_id: "x", updated_at: t }],
      queue: { items: ["x|1"], updated_at: t },
    },
  });
  expect(r.status).toBe(200);
}

describe("account deletion (App Store 5.1.1(v))", () => {
  it("every table that holds a person's rows is in USER_TABLES", async () => {
    const tables = await allTables();
    const missing = tables.filter((t) => t !== "users" && !USER_TABLES.includes(t) && !ANONYMOUS_TABLES.includes(t));
    expect(missing).toEqual([]);
  });

  it("every person column other than user_id is one deletion names", async () => {
    for (const t of await allTables()) {
      if (t === "users") continue;
      for (const col of await personColumns(t)) {
        if (col === "user_id") {
          expect(USER_TABLES, t).toContain(t);
          continue;
        }
        expect(OTHER_PERSON_COLUMNS.some(([tt, c]) => tt === t && c === col), `${t}.${col}`).toBe(true);
      }
    }
  });

  it("a table outside USER_TABLES holds no person: no user_id and no column referencing users", async () => {
    for (const t of ANONYMOUS_TABLES) {
      const cols = (await env.DB.prepare(`PRAGMA table_info(${t})`).all()).results.map((c) => c.name);
      expect(cols.length, t).toBeGreaterThan(0);
      expect(cols, t).not.toContain("user_id");
      expect(await personColumns(t), t).toEqual([]);
    }
  });

  it("CONTROL: before deletion, the account has rows in every table", async () => {
    const s = await signIn("del-control");
    await fill(s);
    await fillPlays(s);
    const rows = await rowsFor(s.user_id);
    for (const [t, n] of Object.entries(rows)) expect(n, t).toBeGreaterThan(0);
  });

  it("deletion removes the person's take audio from the bucket", async () => {
    const s = await signIn("del-audio");
    const { production } = await fillPlays(s);
    expect((await objectsIn(production.id)).length).toBe(1);
    expect((await call("DELETE", "/v1/account", { token: s.access_token })).status).toBe(200);
    expect(await objectsIn(production.id)).toEqual([]);
  });

  it("a failed bucket deletion is queued and the sweep finishes it; the rows still go", async () => {
    const s = await signIn("del-audio-fail");
    const { production } = await fillPlays(s);
    const failing = {
      delete: async () => {
        throw new Error("bucket down");
      },
    };
    expect((await call("DELETE", "/v1/account", { token: s.access_token, envOverride: { TAKES: failing } })).status).toBe(200);
    for (const [t, n] of Object.entries(await rowsFor(s.user_id))) expect(n, t).toBe(0);
    const queued = (await env.DB.prepare("SELECT object_key FROM play_orphan_objects").all()).results.map((r) => r.object_key);
    const [key] = await objectsIn(production.id);
    expect(queued).toContain(key);
    await sweepPlays(env);
    expect(await objectsIn(production.id)).toEqual([]);
    expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM play_orphan_objects").first()).n).toBe(0);
  });

  it("a director's production with others in it passes to the first to join, with their takes", async () => {
    const director = await signIn("del-director");
    const actor = await signIn("del-actor");
    const p = await createProduction(director);
    const inv = await invite(director, p.id);
    expect((await claimByInvite(actor, inv.token, firstPart, { display_name: "Pat" })).status).toBe(200);
    expect((await consent(actor, p.id)).status).toBe(204);
    const up = await upload(actor, p.id, linesFor(firstPart)[0]);
    expect(up.status).toBe(201);
    expect((await call("DELETE", "/v1/account", { token: director.access_token })).status).toBe(200);
    const rec = await record(actor, p.id);
    expect(rec.director).toBe(actor.user_id);
    expect(rec.takes.map((t) => t.id)).toEqual([up.takeId]);
    expect((await objectsIn(p.id)).length).toBe(1);
  });

  it("a submitted production stays when its only member deletes their account; an unsubmitted one goes", async () => {
    const s = await signIn("del-submitted");
    const { production, filed } = await fillPlays(s);
    const taken = await env.DB.prepare("SELECT COUNT(*) AS n FROM play_takes WHERE production_id = ?1").bind(filed.id).first();
    await env.DB.prepare(
      "INSERT INTO play_takes (production_id, id, user_id, line_id, part, file, object_key, content_type, bytes, frames, sample_rate, capture, created, uploaded_at, chosen) " +
        "VALUES (?1, 'T1', ?2, 'L1', 'P', 'T1.wav', ?3, 'audio/wav', 1, 1, 48000, 'direct', 0, 1, 1)",
    )
      .bind(filed.id, s.user_id, `plays/${filed.id}/T1`)
      .run();
    await env.TAKES.put(`plays/${filed.id}/T1`, new Uint8Array(4));
    expect(taken.n).toBe(0);
    expect((await call("DELETE", "/v1/account", { token: s.access_token })).status).toBe(200);
    expect(await env.DB.prepare("SELECT id FROM play_productions WHERE id = ?1").bind(production.id).first()).toBeNull();
    expect((await env.DB.prepare("SELECT user_id FROM play_productions WHERE id = ?1").bind(filed.id).first()).user_id).toBe(DELETED_PERSON);
    expect((await env.DB.prepare("SELECT user_id FROM play_archive_jobs WHERE production_id = ?1").bind(filed.id).first()).user_id).toBe(DELETED_PERSON);
    expect((await env.DB.prepare("SELECT user_id FROM play_takes WHERE production_id = ?1").bind(filed.id).first()).user_id).toBe(DELETED_PERSON);
    expect(await objectsIn(filed.id)).toEqual([`plays/${filed.id}/T1`]);
    expect(await env.DB.prepare("SELECT 1 FROM identities WHERE user_id = ?1 OR user_id = ?2").bind(s.user_id, DELETED_PERSON).first()).toBeNull();
  });

  it("the deleted-person row is no one's account: it has no identity and no session", async () => {
    const s = await signIn("del-nobody");
    await fillPlays(s);
    await call("DELETE", "/v1/account", { token: s.access_token });
    for (const t of ["identities", "sessions"]) {
      expect((await env.DB.prepare(`SELECT COUNT(*) AS n FROM ${t} WHERE user_id = ?1`).bind(DELETED_PERSON).first()).n, t).toBe(0);
    }
  });

  it("CONTROL: a production nobody else is in goes with its director", async () => {
    const director = await signIn("del-solo");
    const p = await createProduction(director);
    await call("DELETE", "/v1/account", { token: director.access_token });
    expect(await env.DB.prepare("SELECT id FROM play_productions WHERE id = ?1").bind(p.id).first()).toBeNull();
  });

  it("a report about a deleted person stays, anonymous", async () => {
    const reporter = await signIn("del-reporter");
    const { partner, theirs } = await fillPlays(reporter);
    await call("DELETE", "/v1/account", { token: partner.access_token });
    const r = await env.DB.prepare("SELECT target_user_id, production_id FROM play_reports WHERE user_id = ?1").bind(reporter.user_id).first();
    expect(r).toMatchObject({ target_user_id: null, production_id: theirs.id });
  });

  it("deletion leaves no row in any table, and another account is untouched", async () => {
    const s = await signIn("del-1");
    const keep = await signIn("del-keep");
    await fill(s);
    await fill(keep);
    await fillPlays(s);
    await fillPlays(keep);
    const before = await rowsFor(keep.user_id);

    const r = await call("DELETE", "/v1/account", { token: s.access_token });
    expect(r.status).toBe(200);
    expect(await r.json()).toMatchObject({ deleted: true, apple_token_revoked: null });

    const after = await rowsFor(s.user_id);
    for (const [t, n] of Object.entries(after)) expect(n, t).toBe(0);
    expect(await rowsFor(keep.user_id)).toEqual(before);
  });

  it("the deleted account's tokens stop working at once and cannot write rows back", async () => {
    const s = await signIn("del-2");
    await call("DELETE", "/v1/account", { token: s.access_token });
    const write = await call("PUT", "/v1/sync", {
      token: s.access_token,
      body: { history: [{ episode_id: "x|1", updated_at: Date.now() - 1 }] },
    });
    expect(write.status).toBe(401);
    expect((await call("POST", "/v1/auth/refresh", { body: { refresh_token: s.refresh_token } })).status).toBe(401);
    for (const [t, n] of Object.entries(await rowsFor(s.user_id))) expect(n, t).toBe(0);
  });

  it("signing in again after deletion is a new, empty account", async () => {
    const s = await signIn("del-3");
    await fill(s);
    await call("DELETE", "/v1/account", { token: s.access_token });
    const again = await signIn("del-3");
    expect(again.created).toBe(true);
    expect(again.user_id).not.toBe(s.user_id);
    const out = await (await call("GET", "/v1/sync?since=0", { token: again.access_token })).json();
    expect(out.history).toHaveLength(0);
  });

  it("with Apple configured, the Apple token is traded and revoked", async () => {
    const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
    const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
    const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----`;
    const s = await signIn("del-apple");
    const r = await call("DELETE", "/v1/account", {
      token: s.access_token,
      body: { apple_authorization_code: "code-123" },
      envOverride: { APPLE_TEAM_ID: "TEAMID1234", APPLE_KEY_ID: "KEYID12345", APPLE_PRIVATE_KEY: pem },
    });
    expect(await r.json()).toMatchObject({ deleted: true, apple_token_revoked: true });
    expect(appleCalls.map((c) => c[0])).toEqual(["token", "revoke"]);
    expect(appleCalls[0][1]).toMatchObject({ code: "code-123", client_id: "app.eardrama.test" });
    expect(appleCalls[1][1]).toMatchObject({ token: "apple-refresh-xyz", token_type_hint: "refresh_token" });

    // The client secret is a real ES256 JWT that Apple could verify with our key.
    const [h, p, sig] = appleCalls[0][1].client_secret.split(".");
    const dec = (x) => Uint8Array.from(atob(x.replace(/-/g, "+").replace(/_/g, "/") + "==".slice(0, (4 - (x.length % 4)) % 4)), (c) => c.charCodeAt(0));
    const ok = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pair.publicKey, dec(sig), new TextEncoder().encode(`${h}.${p}`));
    expect(ok).toBe(true);
    expect(JSON.parse(new TextDecoder().decode(dec(p)))).toMatchObject({ iss: "TEAMID1234", sub: "app.eardrama.test", aud: "https://appleid.apple.com" });
    for (const [t, n] of Object.entries(await rowsFor(s.user_id))) expect(n, t).toBe(0);
  });

  it("a failed Apple revocation still deletes every row", async () => {
    const s = await signIn("del-apple-fail");
    const r = await call("DELETE", "/v1/account", {
      token: s.access_token,
      body: { apple_authorization_code: "code" },
      envOverride: { APPLE_TEAM_ID: "T", APPLE_KEY_ID: "K", APPLE_PRIVATE_KEY: "not a key" },
    });
    expect(await r.json()).toMatchObject({ deleted: true, apple_token_revoked: false });
    for (const [t, n] of Object.entries(await rowsFor(s.user_id))) expect(n, t).toBe(0);
  });
});

describe("the account status row", () => {
  it("names the provider, the counts, and the last sync", async () => {
    const s = await signIn("status-1", "google");
    let a = await (await call("GET", "/v1/account", { token: s.access_token })).json();
    expect(a).toMatchObject({ providers: ["google"], counts: { history: 0, follows: 0 }, last_sync_at: null });
    await fill(s);
    a = await (await call("GET", "/v1/account", { token: s.access_token })).json();
    expect(a.counts).toEqual({ history: 1, follows: 1 });
    expect(a.last_sync_at).toBeGreaterThan(0);
  });
});
