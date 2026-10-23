import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { appleClaims, call, env, googleClaims, installProviderKeys, keys, mint, signIn } from "./helpers.js";
import { b64urlEncode, sha256Hex } from "../src/jwt.js";

beforeEach(() => {
  installProviderKeys();
});
afterEach(() => vi.restoreAllMocks());

async function apple(token, extra = {}) {
  return call("POST", "/v1/auth/apple", { body: { id_token: token, ...extra } });
}

async function reason(r) {
  return (await r.json()).detail;
}

describe("Sign in with Apple", () => {
  it("CONTROL: a well-formed token is accepted and makes an account", async () => {
    const r = await apple(await mint(appleClaims("apple-sub-ok")));
    expect(r.status).toBe(200);
    const s = await r.json();
    expect(s.created).toBe(true);
    expect(s.access_token).toBeTruthy();
    expect(s.refresh_token).toBeTruthy();
  });

  it("the same subject signs in to the same account", async () => {
    const a = await signIn("apple-sub-twice");
    const b = await signIn("apple-sub-twice");
    expect(b.user_id).toBe(a.user_id);
    expect(b.created).toBe(false);
  });

  it("a token signed by a key Apple did not publish is refused", async () => {
    const r = await apple(await mint(appleClaims("x"), { key: keys.forger }));
    expect(r.status).toBe(401);
    expect(await reason(r)).toBe("bad_signature");
  });

  it("a payload altered after signing is refused", async () => {
    const good = await mint(appleClaims("victim"));
    const [h, , s] = good.split(".");
    const forged = `${h}.${b64urlEncode(JSON.stringify(appleClaims("attacker")))}.${s}`;
    const r = await apple(forged);
    expect(r.status).toBe(401);
    expect(await reason(r)).toBe("bad_signature");
  });

  it("an expired token is refused", async () => {
    const past = Math.floor(Date.now() / 1000) - 3600;
    const r = await apple(await mint(appleClaims("x", { iat: past - 600, exp: past })));
    expect(r.status).toBe(401);
    expect(await reason(r)).toBe("expired");
  });

  it("a token for another app's audience is refused", async () => {
    const r = await apple(await mint(appleClaims("x", { aud: "com.someone.else" })));
    expect(r.status).toBe(401);
    expect(await reason(r)).toBe("bad_audience");
  });

  it("a token from another issuer is refused", async () => {
    const r = await apple(await mint(appleClaims("x", { iss: "https://evil.example" })));
    expect(r.status).toBe(401);
    expect(await reason(r)).toBe("bad_issuer");
  });

  it("alg none is refused", async () => {
    const head = b64urlEncode(JSON.stringify({ alg: "none", kid: keys.apple.kid }));
    const body = b64urlEncode(JSON.stringify(appleClaims("x")));
    const r = await apple(`${head}.${body}.`);
    expect(r.status).toBe(401);
    expect(await reason(r)).toBe("bad_alg");
  });

  it("an HS256 token keyed with Apple's public key is refused", async () => {
    const r = await apple(await mint(appleClaims("x"), { header: { alg: "HS256" } }));
    expect(r.status).toBe(401);
    expect(await reason(r)).toBe("bad_alg");
  });

  it("an unknown key id is refused", async () => {
    const r = await apple(await mint(appleClaims("x"), { header: { kid: "nobody" } }));
    expect(r.status).toBe(401);
    expect(await reason(r)).toBe("unknown_key");
  });

  it("garbage is refused", async () => {
    for (const t of ["", "a.b", "a.b.c", "....", "x".repeat(9000)]) {
      const r = await apple(t);
      expect(r.status, t.slice(0, 10)).toBe(401);
    }
  });

  it("the nonce must match, raw (web) or hashed (native)", async () => {
    const raw = "raw-nonce-123";
    const hashed = await sha256Hex(raw);
    expect((await apple(await mint(appleClaims("n1", { nonce: hashed })), { nonce: raw })).status).toBe(200);
    expect((await apple(await mint(appleClaims("n2", { nonce: raw })), { nonce: raw })).status).toBe(200);
    const bad = await apple(await mint(appleClaims("n3", { nonce: hashed })), { nonce: "another" });
    expect(bad.status).toBe(401);
    expect(await reason(bad)).toBe("bad_nonce");
    const missing = await apple(await mint(appleClaims("n4")), { nonce: raw });
    expect(missing.status).toBe(401);
  });

  it("a placeholder audience is never accepted", async () => {
    const r = await call("POST", "/v1/auth/apple", {
      body: { id_token: await mint(appleClaims("x", { aud: "REPLACE_WITH_APPLE_SERVICES_ID" })) },
      envOverride: { APPLE_AUDIENCES: "REPLACE_WITH_APPLE_SERVICES_ID" },
    });
    expect(r.status).toBe(503);
  });

  it("no account is made by a refused token", async () => {
    const before = await env.DB.prepare("SELECT COUNT(*) AS n FROM users").first();
    await apple(await mint(appleClaims("nope", { aud: "wrong" })));
    const after = await env.DB.prepare("SELECT COUNT(*) AS n FROM users").first();
    expect(after.n).toBe(before.n);
  });
});

describe("Sign in with Google", () => {
  it("CONTROL: a well-formed token is accepted", async () => {
    const r = await call("POST", "/v1/auth/google", {
      body: { id_token: await mint(googleClaims("g-ok"), { key: keys.google }) },
    });
    expect(r.status).toBe(200);
  });

  it("both of Google's issuer spellings are accepted", async () => {
    const r = await call("POST", "/v1/auth/google", {
      body: { id_token: await mint(googleClaims("g-bare", { iss: "accounts.google.com" }), { key: keys.google }) },
    });
    expect(r.status).toBe(200);
  });

  it("an Apple-signed token cannot sign in as Google", async () => {
    const r = await call("POST", "/v1/auth/google", {
      body: { id_token: await mint(googleClaims("g-x"), { key: keys.apple }) },
    });
    expect(r.status).toBe(401);
  });

  it("the wrong audience, an expired token, and the wrong issuer are refused", async () => {
    const past = Math.floor(Date.now() / 1000) - 3600;
    for (const [over, why] of [
      [{ aud: "someone-else.apps.googleusercontent.com" }, "bad_audience"],
      [{ iat: past - 60, exp: past }, "expired"],
      [{ iss: "https://appleid.apple.com" }, "bad_issuer"],
    ]) {
      const r = await call("POST", "/v1/auth/google", {
        body: { id_token: await mint(googleClaims("g-bad", over), { key: keys.google }) },
      });
      expect(r.status, why).toBe(401);
      expect(await reason(r)).toBe(why);
    }
  });

  it("the same person on Apple and Google is two accounts (no linking yet)", async () => {
    const a = await signIn("same-sub", "apple");
    const g = await signIn("same-sub", "google");
    expect(a.user_id).not.toBe(g.user_id);
  });
});

describe("the Worker's own session", () => {
  it("an access token opens the account; none, a forged one, or an expired one does not", async () => {
    const s = await signIn("session-1");
    expect((await call("GET", "/v1/account", { token: s.access_token })).status).toBe(200);
    expect((await call("GET", "/v1/account")).status).toBe(401);

    const [h, p] = s.access_token.split(".");
    const claims = JSON.parse(atob(p.replace(/-/g, "+").replace(/_/g, "/")));
    const other = b64urlEncode(JSON.stringify({ ...claims, sub: "someone-else" }));
    expect((await call("GET", "/v1/account", { token: `${h}.${other}.${s.access_token.split(".")[2]}` })).status).toBe(401);

    const { signHS256 } = await import("../src/jwt.js");
    const wrongKey = await signHS256(claims, "a-different-secret-that-is-long-enough!!");
    expect((await call("GET", "/v1/account", { token: wrongKey })).status).toBe(401);

    const past = Math.floor(Date.now() / 1000) - 7200;
    const expired = await signHS256({ ...claims, iat: past, exp: past + 3600 }, env.SESSION_SECRET);
    const r = await call("GET", "/v1/account", { token: expired });
    expect(r.status).toBe(401);
    expect(await reason(r)).toBe("expired");
  });

  it("refresh rotates the pair, and the old refresh token is spent", async () => {
    const s = await signIn("refresh-1");
    const r1 = await call("POST", "/v1/auth/refresh", { body: { refresh_token: s.refresh_token } });
    expect(r1.status).toBe(200);
    const s2 = await r1.json();
    expect(s2.refresh_token).not.toBe(s.refresh_token);
    expect(s2.user_id).toBe(s.user_id);
    expect((await call("GET", "/v1/account", { token: s2.access_token })).status).toBe(200);
    // The pre-rotation access token belonged to the spent session.
    expect((await call("GET", "/v1/account", { token: s.access_token })).status).toBe(401);
  });

  it("a replayed refresh token ends the whole sign-in", async () => {
    const s = await signIn("replay-1");
    const s2 = await (await call("POST", "/v1/auth/refresh", { body: { refresh_token: s.refresh_token } })).json();
    const replay = await call("POST", "/v1/auth/refresh", { body: { refresh_token: s.refresh_token } });
    expect(replay.status).toBe(401);
    expect(await reason(replay)).toBe("reused");
    // The thief's replay also ends the legitimate holder's newer session.
    expect((await call("GET", "/v1/account", { token: s2.access_token })).status).toBe(401);
    expect((await call("POST", "/v1/auth/refresh", { body: { refresh_token: s2.refresh_token } })).status).toBe(401);
  });

  it("an unknown refresh token is refused", async () => {
    expect((await call("POST", "/v1/auth/refresh", { body: { refresh_token: "nope" } })).status).toBe(401);
  });

  it("sign-out ends the access token at once", async () => {
    const s = await signIn("signout-1");
    expect((await call("POST", "/v1/auth/signout", { token: s.access_token })).status).toBe(204);
    expect((await call("GET", "/v1/account", { token: s.access_token })).status).toBe(401);
    expect((await call("POST", "/v1/auth/refresh", { body: { refresh_token: s.refresh_token } })).status).toBe(401);
  });

  it("a weak or missing SESSION_SECRET refuses to issue sessions", async () => {
    const r = await call("POST", "/v1/auth/apple", {
      body: { id_token: await mint(appleClaims("weak")) },
      envOverride: { SESSION_SECRET: "short" },
    });
    expect(r.status).toBe(503);
  });
});
