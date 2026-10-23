/**
 * The account: what the status row shows, and deletion.
 *
 * DELETION REMOVES EVERY ROW (App Store guideline 5.1.1(v), Decision 035).
 * Each table is named here and deleted from in one batch, and the schema's
 * ON DELETE CASCADE is the second lock. When a table that holds a person's
 * rows is added, it is added to USER_TABLES; test/account.test.js counts the
 * rows in EVERY table after a deletion, so a table left out fails it.
 *
 * Sign in with Apple also asks that the app revoke the person's Apple tokens
 * when the account goes. The Worker never keeps an Apple token, so the client
 * sends a fresh authorization code with the request; the Worker trades it for
 * a token and revokes that. The row deletion never waits on Apple: if the
 * revocation fails, the account is still gone, and the response says so.
 */

import { json, problem, readJson } from "./http.js";
import { audiences } from "./auth.js";
import { signES256 } from "./jwt.js";

/** Children first; `users` last. */
export const USER_TABLES = ["history", "follows", "queue", "queue_meta", "sessions", "identities"];

export async function handleAccount(auth, env) {
  const { userId } = auth;
  const user = await env.DB.prepare("SELECT created_at FROM users WHERE id = ?1").bind(userId).first();
  if (!user) return problem(401, "unauthorized", "session_ended");
  const [ids, h, f] = await env.DB.batch([
    env.DB.prepare("SELECT provider FROM identities WHERE user_id = ?1").bind(userId),
    env.DB.prepare("SELECT COUNT(*) AS n, MAX(changed_at) AS last FROM history WHERE user_id = ?1 AND deleted = 0").bind(userId),
    env.DB.prepare("SELECT COUNT(*) AS n, MAX(changed_at) AS last FROM follows WHERE user_id = ?1 AND following = 1").bind(userId),
  ]);
  const q = await env.DB.prepare("SELECT changed_at FROM queue_meta WHERE user_id = ?1").bind(userId).first();
  const lastSync = Math.max(h.results[0].last || 0, f.results[0].last || 0, q ? q.changed_at : 0) || null;
  return json({
    user_id: userId,
    created_at: user.created_at,
    providers: ids.results.map((r) => r.provider),
    counts: { history: h.results[0].n, follows: f.results[0].n },
    last_sync_at: lastSync,
  });
}

/** DELETE /v1/account: { apple_authorization_code?, apple_client_id? } */
export async function handleDelete(auth, request, env) {
  const { body, error } = await readJson(request, 8 * 1024);
  if (error) return error;
  const { userId } = auth;

  let appleRevoked = null;
  if (typeof body.apple_authorization_code === "string" && body.apple_authorization_code) {
    appleRevoked = await revokeApple(env, body.apple_authorization_code, body.apple_client_id);
  }

  await env.DB.batch([
    ...USER_TABLES.map((t) => env.DB.prepare(`DELETE FROM ${t} WHERE user_id = ?1`).bind(userId)),
    env.DB.prepare("DELETE FROM users WHERE id = ?1").bind(userId),
  ]);
  return json({ deleted: true, apple_token_revoked: appleRevoked });
}

/**
 * Trade the code for a refresh token, then revoke it
 * (developer.apple.com/documentation/sign_in_with_apple/revoke_tokens).
 * Returns true, false (tried and failed), or null when not configured.
 */
export async function revokeApple(env, code, requestedClientId) {
  if (!env.APPLE_TEAM_ID || !env.APPLE_KEY_ID || !env.APPLE_PRIVATE_KEY) return null;
  const allowed = audiences(env, "apple").filter((a) => !a.startsWith("REPLACE_WITH"));
  const clientId = typeof requestedClientId === "string" && allowed.includes(requestedClientId) ? requestedClientId : allowed[0];
  if (!clientId) return null;
  try {
    const now = Math.floor(Date.now() / 1000);
    const secret = await signES256(
      { kid: env.APPLE_KEY_ID },
      { iss: env.APPLE_TEAM_ID, iat: now, exp: now + 300, aud: "https://appleid.apple.com", sub: clientId },
      env.APPLE_PRIVATE_KEY,
    );
    const form = (o) => new URLSearchParams(o).toString();
    const headers = { "content-type": "application/x-www-form-urlencoded" };
    const t = await fetch("https://appleid.apple.com/auth/token", {
      method: "POST",
      headers,
      body: form({ client_id: clientId, client_secret: secret, code, grant_type: "authorization_code" }),
    });
    if (!t.ok) return false;
    const tok = await t.json();
    const token = tok.refresh_token || tok.access_token;
    if (!token) return false;
    const r = await fetch("https://appleid.apple.com/auth/revoke", {
      method: "POST",
      headers,
      body: form({
        client_id: clientId,
        client_secret: secret,
        token,
        token_type_hint: tok.refresh_token ? "refresh_token" : "access_token",
      }),
    });
    return r.ok;
  } catch {
    return false;
  }
}
