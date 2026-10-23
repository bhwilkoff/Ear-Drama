/**
 * eardrama-api: optional accounts and sync for Ear Drama (Decision 057).
 *
 * Ported from Archive Watch's worker/: one free Worker with D1, routes as
 * sibling modules called from one fetch(), Cloudflare rate-limit bindings
 * that store nothing, and a cron sweep that makes a deletion promise true.
 * What is new here is sign-in verified at the Worker: Archive Watch syncs on
 * each person's own cloud and its Worker has no accounts. docs/WORKER.md is
 * the contract.
 *
 * Every route lives under /v1. Listen Together rooms (M6) and shared plays
 * (M8) will be sibling modules on this Worker and this D1; their paths are
 * reserved below and answer 501 until then.
 */

import { authenticate, handleRefresh, handleSignIn, handleSignOut, sweepSessions } from "./auth.js";
import { handleRead, handleUpload } from "./sync.js";
import { handleAccount, handleDelete } from "./account.js";
import { clientAddress, corsHeaders, json, limited, originAllowed, problem, withCors } from "./http.js";

/** The routes for later milestones. Each becomes `handleX(url, request, env, auth)`. */
const RESERVED = [
  ["/v1/rooms", "M6 Listen Together"],
  ["/v1/plays", "M8 shared plays"],
];

async function route(request, env, url) {
  const { pathname } = url;
  const method = request.method;
  const ip = clientAddress(request);

  if (pathname === "/v1/health" && method === "GET") return json({ ok: true });

  const signIn = /^\/v1\/auth\/(apple|google)$/.exec(pathname);
  if ((signIn || pathname === "/v1/auth/refresh") && method === "POST") {
    if (await limited(env.AUTH_LIMITER, ip)) return problem(429, "rate_limited");
    return signIn ? handleSignIn(signIn[1], request, env) : handleRefresh(request, env);
  }

  for (const [prefix, what] of RESERVED) {
    if (pathname === prefix || pathname.startsWith(prefix + "/")) return problem(501, "not_yet", what);
  }

  const authed = {
    "POST /v1/auth/signout": (a) => handleSignOut(a, env),
    "GET /v1/account": (a) => handleAccount(a, env),
    "DELETE /v1/account": (a) => handleDelete(a, request, env),
    "GET /v1/sync": (a) => handleRead(a, url, env),
    "PUT /v1/sync": (a) => handleUpload(a, request, env),
    "POST /v1/sync/merge": (a) => handleUpload(a, request, env, { merge: true }),
  }[`${method} ${pathname}`];
  if (!authed) return problem(404, "not_found");

  const auth = await authenticate(request, env);
  if (auth.error) return auth.error;
  if (await limited(env.USER_LIMITER, auth.userId)) return problem(429, "rate_limited");
  return authed(auth);
}

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(sweepSessions(env));
  },

  async fetch(request, env) {
    const url = new URL(request.url);
    const origin = request.headers.get("origin");
    if (!originAllowed(origin, env)) return problem(403, "origin_not_allowed");

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: origin ? corsHeaders(origin) : {} });
    }
    if (await limited(env.EVERY_IP_LIMITER, clientAddress(request))) {
      return withCors(problem(429, "rate_limited"), origin);
    }
    let response;
    try {
      response = await route(request, env, url);
    } catch (e) {
      console.log("worker error", e && e.stack ? e.stack : String(e));
      response = problem(500, "server_error");
    }
    return withCors(response, origin);
  },
};
