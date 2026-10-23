import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { call, env, installProviderKeys, signIn } from "./helpers.js";
import { USER_TABLES } from "../src/account.js";
import { ANONYMOUS_TABLES } from "../src/rooms.js";

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

async function rowsFor(userId) {
  const out = {};
  for (const t of await allTables()) {
    if (ANONYMOUS_TABLES.includes(t)) continue;
    const cols = (await env.DB.prepare(`PRAGMA table_info(${t})`).all()).results.map((c) => c.name);
    const col = cols.includes("user_id") ? "user_id" : t === "users" ? "id" : null;
    if (!col) {
      out[t] = "NO USER COLUMN";
      continue;
    }
    out[t] = (await env.DB.prepare(`SELECT COUNT(*) AS n FROM ${t} WHERE ${col} = ?1`).bind(userId).first()).n;
  }
  return out;
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

  it("a table outside USER_TABLES holds no person: it has no user_id column", async () => {
    for (const t of ANONYMOUS_TABLES) {
      const cols = (await env.DB.prepare(`PRAGMA table_info(${t})`).all()).results.map((c) => c.name);
      expect(cols.length, t).toBeGreaterThan(0);
      expect(cols, t).not.toContain("user_id");
    }
  });

  it("CONTROL: before deletion, the account has rows in every table", async () => {
    const s = await signIn("del-control");
    await fill(s);
    const rows = await rowsFor(s.user_id);
    for (const [t, n] of Object.entries(rows)) expect(n, t).toBeGreaterThan(0);
  });

  it("deletion leaves no row in any table, and another account is untouched", async () => {
    const s = await signIn("del-1");
    const keep = await signIn("del-keep");
    await fill(s);
    await fill(keep);
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
