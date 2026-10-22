/**
 * OPTIONAL EXAMPLE — a Cloudflare Worker (free tier + D1) that gives Pulse the
 * three things no store API can: a privacy-first page-view counter, anonymous
 * server-side tallies, and a DROP BOX for vendors that only DELIVER reports
 * (Roku's Looker dashboards). Nothing in the template deploys it; adopt it only
 * if you want those readers (web_usage, counter_tallies, roku_engagement).
 *
 *   wrangler d1 create pulse
 *   wrangler d1 execute pulse --remote --file=schema.sql
 *   wrangler secret put INGEST_TOKEN        # also the repo secret PULSE_INGEST_TOKEN
 *   wrangler deploy                         # set ALLOW_ORIGIN in wrangler.toml first
 *
 * THE PRIVACY RULE: every row is `day | shape | count`. No IP, cookie, session
 * or visitor id, user agent, referrer, country or time of day — nothing can be
 * joined to a person, to another row, or to a second visit, including by us.
 * A usage number must come from something a server ALREADY receives to provide
 * the feature, never from an app sending a new count. Say so on your privacy
 * page, in exactly these terms.
 *
 * A DEPLOY IS NOT LIVE WHEN WRANGLER SAYS SO. Negative controls run against a
 * route that does not exist yet fall through to the root handler and "pass".
 * Poll the root until it lists the new routes before believing any result.
 */

// A path becomes one of a small FIXED set. Anything unrecognised is "/other",
// never the raw path: an unbounded key space is how a counter becomes a log.
// Edit SURFACES for your app's routes.
const SURFACES = ["/browse", "/search", "/library", "/about", "/item", "/settings"];

function shape(raw, origin) {
  // A page LOAD is its own key, so a visit and a route view can never be
  // summed: one visit that walks six surfaces is one visit and seven views.
  if (raw === "(visit)") return "(visit)";
  let p;
  try { p = new URL(raw, origin).pathname.toLowerCase(); } catch { return "/other"; }
  if (p === "" || p === "/" || p === "/index.html") return "/";
  for (const s of SURFACES) if (p === s || p.startsWith(s + "/")) return s;
  return "/other";
}

const cors = (env) => ({
  "Access-Control-Allow-Origin": env.ALLOW_ORIGIN || "*",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
});

/** Call from your OWN feature handlers: tally(env, "rooms", "room"). A failed
 *  count never fails the request it counts. */
export async function tally(env, name, kind) {
  try {
    await env.DB.prepare(
      "INSERT INTO tallies (day, name, kind, count) VALUES (?1, ?2, ?3, 1) " +
      "ON CONFLICT(day, name, kind) DO UPDATE SET count = count + 1"
    ).bind(new Date().toISOString().slice(0, 10), name, kind).run();
  } catch { /* a counter is not worth a failed request */ }
}

const since = (url, dflt) => {
  const days = Math.min(400, Math.max(1, Number(url.searchParams.get("days") || dflt)));
  return new Date(Date.now() - days * 864e5).toISOString().slice(0, 10);
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const h = cors(env);
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: h });

    // The beacon: 204, no body, and a failure is never visible to a reader.
    if (url.pathname === "/beacon" && request.method === "POST") {
      const path = shape(url.searchParams.get("p") || "/", env.ALLOW_ORIGIN || url.origin);
      try {
        await env.DB.prepare(
          "INSERT INTO views (day, path, count) VALUES (?1, ?2, 1) " +
          "ON CONFLICT(day, path) DO UPDATE SET count = count + 1"
        ).bind(new Date().toISOString().slice(0, 10), path).run();
      } catch { /* a counter is not worth an error page */ }
      return new Response(null, { status: 204, headers: h });
    }

    // Read sides: public, because there is nothing in them about anybody.
    if (url.pathname === "/views") {
      const s = since(url, 60);
      const { results } = await env.DB.prepare(
        "SELECT day, path, count FROM views WHERE day >= ?1 ORDER BY day, path").bind(s).all();
      return Response.json({ since: s, rows: results || [] }, { headers: { ...h, "Cache-Control": "public, max-age=300" } });
    }
    if (url.pathname === "/tally-daily") {
      const s = since(url, 90);
      const { results } = await env.DB.prepare(
        "SELECT day, kind, count FROM tallies WHERE name = ?1 AND day >= ?2 ORDER BY day"
      ).bind(url.searchParams.get("name") || "", s).all();
      return Response.json({ since: s, rows: results || [] }, { headers: { ...h, "Cache-Control": "public, max-age=300" } });
    }

    /* ── the vendor drop box ─────────────────────────────────────────────
     * Roku has no analytics API; Looker delivers by schedule to email, a
     * webhook, S3 or SFTP. S3 means real AWS (the form has no custom endpoint,
     * so R2 cannot stand in); the webhook is free because this Worker exists.
     * THE BODY IS STORED RAW and parsed offline: the payload shape was not
     * documented, and an ingest that guesses a schema fails silently on the
     * one delivery that matters. The collector reads /drops and acks (deletes)
     * only on --apply, and never acks a payload it could not parse. */
    const authed = env.INGEST_TOKEN && url.searchParams.get("t") === env.INGEST_TOKEN;
    if (url.pathname.startsWith("/ingest/") && request.method === "POST") {
      // 404, not 403: an unauthenticated prober learns nothing.
      if (!authed) return new Response("not found", { status: 404 });
      const vendor = url.pathname.slice(8).toLowerCase().replace(/[^a-z0-9_-]/g, "").slice(0, 32) || "unknown";
      const body = await request.text();
      // D1 caps a row near 1 MB. Too big is REFUSED, never truncated: half a
      // report read as a whole one is the quiet wrong number Pulse exists to prevent.
      const tooBig = body.length > 900000;
      await env.DB.prepare(
        "INSERT INTO drops (vendor, received, content_type, bytes, body) VALUES (?1, ?2, ?3, ?4, ?5)"
      ).bind(vendor, new Date().toISOString(), request.headers.get("content-type") || "",
             body.length, tooBig ? "" : body).run();
      return Response.json({ stored: !tooBig, bytes: body.length, refused: tooBig ? "over 900000 bytes" : null });
    }
    if (url.pathname === "/drops") {
      if (!authed) return new Response("not found", { status: 404 });
      if (request.method === "POST") {                       // ack = delete
        const id = Number(url.searchParams.get("id") || 0);
        if (!id) return Response.json({ error: "id required" }, { status: 400 });
        await env.DB.prepare("DELETE FROM drops WHERE id = ?1").bind(id).run();
        return Response.json({ deleted: id });
      }
      const vendor = url.searchParams.get("vendor") || "";
      const q = vendor
        ? env.DB.prepare("SELECT * FROM drops WHERE vendor = ?1 ORDER BY id LIMIT 20").bind(vendor)
        : env.DB.prepare("SELECT * FROM drops ORDER BY id LIMIT 20");
      const { results } = await q.all();
      return Response.json({ rows: results || [] });
    }

    // The root names every route, so a deploy can be confirmed live.
    return new Response("pulse: /beacon, /views, /tally-daily, /ingest/<vendor>, /drops",
                        { headers: { ...h, "Content-Type": "text/plain" } });
  },
};
