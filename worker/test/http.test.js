import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test";
import worker from "../src/index.js";
import { call, env, installProviderKeys, signIn } from "./helpers.js";

beforeEach(() => {
  installProviderKeys();
});
afterEach(() => vi.restoreAllMocks());

describe("CORS: eardrama.org and localhost only", () => {
  for (const origin of ["https://eardrama.org", "https://www.eardrama.org", "http://localhost:8080", "http://127.0.0.1:5173", "http://localhost"]) {
    it(`grants ${origin}`, async () => {
      const pre = await call("OPTIONS", "/v1/sync", { origin });
      expect(pre.status).toBe(204);
      expect(pre.headers.get("access-control-allow-origin")).toBe(origin);
      expect(pre.headers.get("access-control-allow-headers")).toContain("authorization");
      const r = await call("GET", "/v1/health", { origin });
      expect(r.headers.get("access-control-allow-origin")).toBe(origin);
    });
  }

  for (const origin of [
    "https://evil.example",
    "https://eardrama.org.evil.example",
    "http://eardrama.org",
    "https://localhost.evil.example",
    "http://localhost.evil.example:80",
    "null",
  ]) {
    it(`refuses ${origin}`, async () => {
      const pre = await call("OPTIONS", "/v1/sync", { origin });
      expect(pre.status).toBe(403);
      expect(pre.headers.get("access-control-allow-origin")).toBeNull();
      const s = await signIn(`cors-${origin}`);
      const r = await call("GET", "/v1/sync", { origin, token: s.access_token });
      expect(r.status).toBe(403);
    });
  }

  it("CONTROL: a native app (no Origin) is served, with no CORS header", async () => {
    const r = await call("GET", "/v1/health");
    expect(r.status).toBe(200);
    expect(r.headers.get("access-control-allow-origin")).toBeNull();
  });
});

describe("rate limits", () => {
  const deny = { limit: async () => ({ success: false }) };
  const allow = { limit: async () => ({ success: true }) };

  it("sign-in is limited per address", async () => {
    const r = await call("POST", "/v1/auth/apple", { body: { id_token: "x" }, envOverride: { AUTH_LIMITER: deny } });
    expect(r.status).toBe(429);
  });

  it("a signed-in person is limited per account, keyed by user id", async () => {
    const s = await signIn("limit-1");
    const seen = [];
    const spy = { limit: async ({ key }) => (seen.push(key), { success: false }) };
    const r = await call("GET", "/v1/sync", { token: s.access_token, envOverride: { USER_LIMITER: spy } });
    expect(r.status).toBe(429);
    expect(seen).toEqual([s.user_id]);
  });

  it("every route has the per-address floor", async () => {
    const r = await call("GET", "/v1/health", { envOverride: { EVERY_IP_LIMITER: deny } });
    expect(r.status).toBe(429);
  });

  it("CONTROL: with every limiter allowing, the same calls pass", async () => {
    const s = await signIn("limit-2");
    const r = await call("GET", "/v1/sync", {
      token: s.access_token,
      envOverride: { USER_LIMITER: allow, EVERY_IP_LIMITER: allow, AUTH_LIMITER: allow },
    });
    expect(r.status).toBe(200);
  });

  it("the real binding from wrangler.toml counts: the 31st sign-in a minute from one address is refused", async () => {
    let last;
    for (let i = 0; i < 31; i++) last = await call("POST", "/v1/auth/refresh", { body: { refresh_token: "x" }, ip: "192.0.2.77" });
    expect(last.status).toBe(429);
  });
});

describe("routing", () => {
  it("rooms (M6) and plays (M8) are reserved, not built", async () => {
    for (const p of ["/v1/rooms", "/v1/rooms/ABCD", "/v1/plays/123"]) {
      const r = await call("GET", p);
      expect(r.status, p).toBe(501);
    }
  });

  it("unknown paths are 404 and never reach auth", async () => {
    expect((await call("GET", "/v1/nothing")).status).toBe(404);
    expect((await call("GET", "/")).status).toBe(404);
  });
});

describe("the daily sweep", () => {
  it("deletes expired sessions and keeps live and recently revoked ones", async () => {
    const live = await signIn("sweep-live");
    const now = Date.now();
    await env.DB.prepare(
      "INSERT INTO sessions (id, user_id, family, token_hash, device, created_at, expires_at) VALUES ('old', ?1, 'old', 'h-old', '', ?2, ?3)",
    )
      .bind(live.user_id, now - 100 * 86400_000, now - 1000)
      .run();
    const ctx = createExecutionContext();
    await worker.scheduled(createScheduledController(), env, ctx);
    await waitOnExecutionContext(ctx);
    expect(await env.DB.prepare("SELECT id FROM sessions WHERE id = 'old'").first()).toBeNull();
    expect((await call("GET", "/v1/account", { token: live.access_token })).status).toBe(200);
  });
});
