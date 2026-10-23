/**
 * Responses, CORS, and rate limits shared by every route.
 *
 * CORS answers only eardrama.org (and localhost for development). Archive
 * Watch's rooms answered `*` because a room code is public; here every route
 * past sign-in carries a person's token, so a page on another origin gets no
 * CORS grant and a request it makes anyway is refused outright.
 */

export function json(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...headers },
  });
}

export function problem(status, error, detail) {
  return json(detail ? { error, detail } : { error }, status);
}

const LOCAL = /^http:\/\/(localhost|127\.0\.0\.1)(:\d{1,5})?$/;

export function originAllowed(origin, env) {
  if (!origin) return true; // native apps and curl send none
  if (LOCAL.test(origin)) return true;
  const list = String(env.ALLOWED_ORIGINS || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  return list.includes(origin);
}

export function corsHeaders(origin) {
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "GET, PUT, POST, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, content-type, x-room-key",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
}

/** Adds the CORS grant to a response for an allowed browser origin. */
export function withCors(response, origin) {
  if (!origin) return response;
  const r = new Response(response.body, response);
  for (const [k, v] of Object.entries(corsHeaders(origin))) r.headers.set(k, v);
  return r;
}

/**
 * Archive Watch's `limited()`: Cloudflare's rate limiter keeps a per-key count
 * for its window and writes nothing down. A missing binding (local dev without
 * the toml) is not a limit.
 */
export async function limited(binding, key) {
  if (!binding) return false;
  const { success } = await binding.limit({ key });
  return !success;
}

export function clientAddress(request) {
  return request.headers.get("cf-connecting-ip") || "unknown";
}

export async function readJson(request, maxBytes = 512 * 1024) {
  const len = Number(request.headers.get("content-length") || 0);
  if (len > maxBytes) return { error: problem(413, "too_large") };
  let text;
  try {
    text = await request.text();
  } catch {
    return { error: problem(400, "bad_request", "unreadable body") };
  }
  if (text.length > maxBytes) return { error: problem(413, "too_large") };
  if (!text) return { body: {} };
  try {
    const body = JSON.parse(text);
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return { error: problem(400, "bad_request", "body must be a JSON object") };
    }
    return { body };
  } catch {
    return { error: problem(400, "bad_request", "body is not JSON") };
  }
}
