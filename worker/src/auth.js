/**
 * Sign-in, verified at the Worker (Decision 057).
 *
 * A client signs in with Apple or Google on its own platform and sends the
 * provider's identity token here. The Worker checks it against the provider's
 * published keys (signature, issuer, audience, expiry, nonce), then hands back
 * its own pair: a one-hour access token and a sixty-day refresh token. Clients
 * refresh before every call whose access token has under five minutes left
 * (AGENTS.md hard rule), through their one API client, one refresh at a time.
 *
 * Stored about a person: the provider name and its opaque `sub`. Never the
 * email, the name, or the provider's tokens.
 */

import { TokenError, verifyIdentityToken, signHS256, verifyHS256, sha256Hex, randomToken } from "./jwt.js";
import { json, problem, readJson } from "./http.js";

export const PROVIDERS = {
  apple: {
    jwksUrl: "https://appleid.apple.com/auth/keys",
    issuers: ["https://appleid.apple.com"],
    audiencesVar: "APPLE_AUDIENCES",
  },
  google: {
    jwksUrl: "https://www.googleapis.com/oauth2/v3/certs",
    issuers: ["https://accounts.google.com", "accounts.google.com"],
    audiencesVar: "GOOGLE_AUDIENCES",
  },
};

const ACCESS_TTL_S = 60 * 60;
const REFRESH_TTL_MS = 60 * 24 * 60 * 60 * 1000;
const ISSUER = "eardrama-worker";
const AUDIENCE = "eardrama";

export function audiences(env, provider) {
  return String(env[PROVIDERS[provider].audiencesVar] || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

function sessionSecret(env) {
  const s = env.SESSION_SECRET;
  return typeof s === "string" && s.length >= 32 ? s : null;
}

export function cleanDevice(v) {
  if (typeof v !== "string") return "";
  return v.replace(/[^\w .:-]/g, "").slice(0, 64);
}

/** Apple native clients put SHA-256(raw nonce) in the request; web puts it raw. */
async function nonceMatches(claim, nonce) {
  if (typeof claim !== "string") return false;
  return claim === nonce || claim === (await sha256Hex(nonce));
}

async function issueSession(env, userId, device, family = null) {
  const now = Date.now();
  const id = crypto.randomUUID();
  const refresh = randomToken(32);
  await env.DB.prepare(
    "INSERT INTO sessions (id, user_id, family, token_hash, device, created_at, expires_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
  )
    .bind(id, userId, family || id, await sha256Hex(refresh), device, now, now + REFRESH_TTL_MS)
    .run();
  const nowS = Math.floor(now / 1000);
  const access = await signHS256(
    { iss: ISSUER, aud: AUDIENCE, sub: userId, sid: id, iat: nowS, exp: nowS + ACCESS_TTL_S },
    sessionSecret(env),
  );
  return {
    access_token: access,
    access_expires_at: (nowS + ACCESS_TTL_S) * 1000,
    refresh_token: refresh,
    refresh_expires_at: now + REFRESH_TTL_MS,
    user_id: userId,
  };
}

/** POST /v1/auth/apple and /v1/auth/google: { id_token, nonce?, device? } */
export async function handleSignIn(provider, request, env) {
  if (!sessionSecret(env)) return problem(503, "not_configured", "SESSION_SECRET is not set");
  const { body, error } = await readJson(request, 16 * 1024);
  if (error) return error;
  if (typeof body.id_token !== "string") return problem(400, "bad_request", "id_token is required");

  let claims;
  try {
    claims = await verifyIdentityToken(body.id_token, {
      jwksUrl: PROVIDERS[provider].jwksUrl,
      issuers: PROVIDERS[provider].issuers,
      audiences: audiences(env, provider),
    });
  } catch (e) {
    if (e instanceof TokenError) {
      if (e.reason === "jwks_unavailable") return problem(503, "provider_unavailable");
      if (e.reason === "audience_not_configured") return problem(503, "not_configured", `${provider} audience`);
      return problem(401, "invalid_token", e.reason);
    }
    throw e;
  }
  if (body.nonce !== undefined) {
    if (typeof body.nonce !== "string" || !(await nonceMatches(claims.nonce, body.nonce))) {
      return problem(401, "invalid_token", "bad_nonce");
    }
  }

  const device = cleanDevice(body.device);
  const now = Date.now();
  let created = false;
  let row = await env.DB.prepare("SELECT user_id FROM identities WHERE provider = ?1 AND subject = ?2")
    .bind(provider, claims.sub)
    .first();
  if (!row) {
    const userId = crypto.randomUUID();
    await env.DB.batch([
      env.DB.prepare("INSERT INTO users (id, created_at) VALUES (?1, ?2)").bind(userId, now),
      env.DB.prepare(
        "INSERT INTO identities (provider, subject, user_id, created_at) VALUES (?1, ?2, ?3, ?4) ON CONFLICT DO NOTHING",
      ).bind(provider, claims.sub, userId, now),
    ]);
    row = await env.DB.prepare("SELECT user_id FROM identities WHERE provider = ?1 AND subject = ?2")
      .bind(provider, claims.sub)
      .first();
    if (row.user_id === userId) created = true;
    else await env.DB.prepare("DELETE FROM users WHERE id = ?1").bind(userId).run(); // lost a race
  }
  const session = await issueSession(env, row.user_id, device);
  return json({ ...session, provider, created });
}

/** POST /v1/auth/refresh: { refresh_token } -> a new pair; the old one is spent. */
export async function handleRefresh(request, env) {
  if (!sessionSecret(env)) return problem(503, "not_configured", "SESSION_SECRET is not set");
  const { body, error } = await readJson(request, 4 * 1024);
  if (error) return error;
  if (typeof body.refresh_token !== "string" || body.refresh_token.length > 256) {
    return problem(400, "bad_request", "refresh_token is required");
  }
  const hash = await sha256Hex(body.refresh_token);
  const s = await env.DB.prepare(
    "SELECT id, user_id, family, device, expires_at, revoked FROM sessions WHERE token_hash = ?1",
  )
    .bind(hash)
    .first();
  if (!s) return problem(401, "invalid_refresh");
  if (s.revoked) {
    // A spent token came back: someone holds a copy. End every session of
    // this sign-in (OAuth 2.0 Security BCP, refresh token rotation).
    await env.DB.prepare("UPDATE sessions SET revoked = 1 WHERE family = ?1").bind(s.family).run();
    return problem(401, "invalid_refresh", "reused");
  }
  if (s.expires_at < Date.now()) return problem(401, "invalid_refresh", "expired");
  const spent = await env.DB.prepare("UPDATE sessions SET revoked = 1 WHERE id = ?1 AND revoked = 0").bind(s.id).run();
  if (!spent.meta || spent.meta.changes !== 1) return problem(401, "invalid_refresh", "reused");
  return json(await issueSession(env, s.user_id, s.device || "", s.family));
}

/**
 * The caller's user id from `Authorization: Bearer <access token>`, or a 401.
 * The session row is read on every call, so signing out or deleting the
 * account ends an access token at once rather than an hour later.
 */
export async function authenticate(request, env) {
  const secret = sessionSecret(env);
  if (!secret) return { error: problem(503, "not_configured", "SESSION_SECRET is not set") };
  const h = request.headers.get("authorization") || "";
  const m = /^Bearer ([A-Za-z0-9_.-]+)$/.exec(h);
  if (!m) return { error: problem(401, "unauthorized") };
  let claims;
  try {
    claims = await verifyHS256(m[1], secret, { issuer: ISSUER, audience: AUDIENCE });
  } catch (e) {
    if (e instanceof TokenError) return { error: problem(401, "unauthorized", e.reason) };
    throw e;
  }
  const s = await env.DB.prepare(
    "SELECT user_id FROM sessions WHERE id = ?1 AND user_id = ?2 AND revoked = 0 AND expires_at > ?3",
  )
    .bind(claims.sid, claims.sub, Date.now())
    .first();
  if (!s) return { error: problem(401, "unauthorized", "session_ended") };
  return { userId: claims.sub, sessionId: claims.sid };
}

/** POST /v1/auth/signout: ends this session (its whole rotation family). */
export async function handleSignOut(auth, env) {
  const s = await env.DB.prepare("SELECT family FROM sessions WHERE id = ?1").bind(auth.sessionId).first();
  if (s) await env.DB.prepare("UPDATE sessions SET revoked = 1 WHERE family = ?1").bind(s.family).run();
  return new Response(null, { status: 204 });
}

/**
 * The daily sweep: expired sessions are deleted. A revoked one is kept until
 * it would have expired, because it is what recognizes a replayed token.
 */
export async function sweepSessions(env, now = Date.now()) {
  await env.DB.prepare("DELETE FROM sessions WHERE expires_at < ?1").bind(now).run();
}
