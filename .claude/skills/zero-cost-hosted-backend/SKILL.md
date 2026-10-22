---
name: zero-cost-hosted-backend
description: "Use when an app needs SHARED user data — accounts, public profiles, cross-user features (shared collections, moderation, matching, social rows) — the case per-ecosystem-sync-islands explicitly does not cover. Carries the three-way split (hosted Postgres for auth + user data ONLY; catalog as static published artifacts; media on a zero-egress CDN), the one-worker-per-job serverless seam (API proxy, account deletion, media upload, push dispatcher with two transports), proxy cache-key discipline, RLS role gating, the single-field username rule with the two-layer banned-words gate, and UI-ahead-of-backend shipping. Also static-first adapters on one free Worker (D1 rooms, /live 302, stateless MCP, tallies). Triggers on Supabase, hosted backend, user accounts, public profiles, shared collections, moderation, RLS, Cloudflare Worker, API proxy, account deletion, avatar upload, push dispatcher, username, banned words, \"do we need a backend\", D1, rate limit, cron sweep."
---

# Zero-cost hosted backend

How to run a multi-platform app with real shared user data on free
tiers, without a server you administer. Distilled from a production
app (BOBA Playbook) that shipped accounts, public collections,
moderation roles, and cross-platform push groundwork on exactly $0
of backend spend.

## First: do you even need this?

**`per-ecosystem-sync-islands` is the default.** If every piece of
user state is private to that user (favorites, progress, settings),
sync it on the user's OWN cloud — CloudKit for Apple platforms,
Google Drive App Data for Android/web — and run no backend at all.

Reach for THIS skill only when users must see **each other's** data:
public profiles at a URL, shared or public collections, user-to-user
matching, moderation queues, community submissions. That requires a
hosted store with access control — but not a big one, and not one
that does everything.

Record which route the app takes as a DECISIONS.md entry. The two
architectures don't mix well retroactively; choosing late means
migrating.

## The three-way split (the rule)

**Hosted Postgres holds auth + user data ONLY. The content catalog
is a static published artifact. Media lives on a zero-egress CDN.**

| Data | Home | Why |
|---|---|---|
| Auth, sessions | Hosted Postgres + its auth product (Supabase-shaped) | The only part that genuinely needs a server |
| User rows (collections, decks, prefs, profiles) | Same Postgres, RLS-protected | Small rows, low volume — free tier lasts years |
| Content catalog (the thing users browse) | Static JSON/SQLite published via Pages/CDN | Browsing must not cost a DB query; see `shared-data-plane-contract` |
| Images / media | Zero-egress object storage + CDN (R2-shaped) | Egress is what kills free tiers |
| — | **NOT the DB's storage product** | A media-heavy app exhausts DB-attached storage quota almost immediately; keep media off the database bill entirely |

The catalog stays static even after the backend exists. Users
browsing 20k items generate zero backend load; only writes (save,
designate, submit) touch Postgres.

## The serverless-worker seam

Everything a static site + a client can't do safely becomes a
**small serverless worker (Cloudflare-Workers-shaped), one worker
per job** — not one monolith function. Each worker is a page of
code with its own secrets, deploy, and failure domain. The
recurring four:

1. **Third-party API proxy.** Hides API keys the client must never
   hold, caches upstream responses, normalizes response shapes so
   all platforms parse one contract, and rate-limits so one user
   can't exhaust an upstream quota. Every external API the app
   consumes goes through one of these — clients never call a
   third party directly.
2. **Account deletion.** A store-listing requirement on both app
   stores, so build it early. Shape: verify the caller's Bearer JWT,
   then admin-delete the auth user with a service-role secret that
   exists only in the worker. Schema does the rest: user-owned
   tables `ON DELETE CASCADE`; audit/history tables `ON DELETE SET
   NULL` so the trail survives anonymously.
3. **Media upload.** Avatars and user images go through a
   size-capped worker straight into CDN object storage — never
   into Postgres, never into the DB's storage product.
4. **Push dispatcher.** ONE worker, two transports: APNs
   (HTTP/2 + JWT via Web Crypto) and FCM v1 (service-account
   token). Triggered by a DB webhook or cron over the event table;
   joins a `user_devices` table; batches per transport. The payload
   is **symmetric** — same type, same fields, and the deep link is
   the **identical string on every platform** (`appname://thing/{id}`),
   so notification handling is one code path per client, not a
   per-platform format.

Workers accept `Authorization: Bearer {jwt}` + JSON/bytes —
transport-agnostic, so adding a platform requires **zero server
changes**. Keep a per-worker table in the project docs (name, job,
consumers) once there are three or more.

## Proxy cache-key discipline

A caching proxy's cache key includes every query param. If
platforms send different values for the same logical request, they
**silently split the cache** and show different data for the same
entity at the same moment — in production this surfaced as three
platforms displaying 1, 2, and 11 listings for one item because
they sent `days=30`, `days=90`, and `days=30` against a 6-hour
cache. Rules:

- Params that don't change user-visible meaning get **fixed
  server-side defaults**; clients don't send them at all.
- If a param must vary, either normalize it out of the cache key or
  accept (and document) the divergence.
- When platforms disagree on displayed data, suspect the cache key
  before suspecting the upstream.

## Static-first Worker adapters (one free Worker, many thin routes)

The one-worker-per-job rule above is for jobs that hold SECRETS. A
different family needs no secret: routes that only translate files
the pipeline already publishes into a shape some other client
speaks. Those share ONE free Worker (plus its D1), each a small
module. Archive Watch runs six on one Worker (`index.js` counter,
`together.js` rooms, `live.js`, `xtream.js`, `mcp.js`, `tally.js`):

| Adapter | Shape | What makes it free |
|---|---|---|
| Watch-party rooms | D1 row per live room; host writes on state change, guests poll (see `cross-platform-multiplayer`) | D1 is strongly consistent; rows deleted when the room ends |
| `/live/<channel>` | 302 to the program airing now, at `?start=<computed offset>` from the published schedule | "Live TV" with no streaming server: the origin serves a file from a second |
| IPTV (Xtream / M3U / XMLTV) | Redirects + published list files | Lists are pre-built by the pipeline, one file per category |
| MCP endpoint | Stateless Streamable HTTP (JSON, no session id), reads published shards only | No storage, says nothing the apps would not show |
| Privacy tally | `day \| kind \| count`, nothing else | Counts what the server already receives to provide the feature |

Rules, each learned in production:

- **Pass lists through untouched.** `return new Response(r.body)`;
  parsing a 6 MB list per request exceeds the free plan's CPU
  allowance (10 ms). Pre-split in the pipeline (whole list,
  per-category list, 256 lookup shards) instead of filtering in
  the Worker.
- **Build-stamp cache keys.** Fetch every published file as
  `file?v=<build>` where `build` comes from a small manifest fetched
  with a short TTL. Then the edge can cache the big file for a day
  and still never serve a previous publish (a plain TTL served a
  stale full list for over an hour).
- **Rate-limit bindings on every unauthenticated route.** The free
  daily request budget is PER ACCOUNT and shared by every adapter;
  one looping script on one route takes all of them down.
  `[[ratelimits]]` bindings count per address for the window and
  store nothing. Size limits from real polling (a guest polling
  ~32/min makes 300/min a household, not a device), with a tighter
  second limiter on create routes.
- **Cron sweep for anything that promises deletion.** A row deleted
  "on the next read of that key" is never deleted if nobody reads it
  again. `[triggers] crons` + `scheduled()` sweeping stale rows is
  what makes a privacy-page promise ("deleted after six hours") true.
- **A counter never fails the request it counts** (try/catch, no
  rethrow), and never takes a new client-sent ping (the count comes
  from what the server already serves).
- **Know which host the Worker answers on.** AW's clients all
  pointed at the Pages domain and would have 404'd on every route;
  tests passed because they injected a base URL. Smoke-test against
  the deployed `*.workers.dev` origin.

Seed: `pulse/worker-example/` (counter + tallies + drop box, D1,
`schema.sql`, `wrangler.example.toml`). Add adapters as sibling
modules routed from its `fetch`; add `[triggers]` and
`[[ratelimits]]` to the toml when the first stateful or open route
lands.

## Auth conventions (per client)

- **One backend client singleton per platform** — views/composables
  never construct requests or hold tokens.
- **Refresh the JWT before EVERY worker / storage / edge-function
  call.** The auth SDK's auto-refresh covers only its own HTTP
  path; everything outside it gets a stale token that fails in
  confusing ways (storage errors that look like generic upload
  failures). This rule is repeated in AGENTS.md because it is the
  single most re-learned backend gotcha.
- **Tokens in the platform vault**: Keychain on Apple platforms,
  Tink-encrypted DataStore on Android — never UserDefaults /
  SharedPreferences (and EncryptedSharedPreferences is deprecated).

## Roles + moderation

- Roles live in a `user_profiles` table (`role`: user | moderator |
  admin). **Every privileged table enforces the role via RLS** — the
  server is the gate, always.
- The client fetches the role **post-auth and caches it in-memory
  for the session only**. Never persist a role client-side; a stale
  cached "admin" is a security bug and a stale "user" is a support
  ticket.
- Privileged mutations write to **correction/override tables**, not
  to the catalog itself. The catalog is a static artifact with a
  release cycle; corrections flow into the next publish. This
  decouples "a moderator fixed a record" from "we shipped a new
  bundle," and the correction tables double as the audit log.

## Usernames: one field, two-layer gate

**Username = display name = public handle. ONE field.** A separate
`display_name` inevitably drifts from the handle and confuses every
surface that shows either (the two-name UX of large chat platforms
is the cautionary tale). Derive an initial value from the email
local-part with collision suffixes (`ben` → `ben2`); OAuth users
without email get `user-{short-hash}`. Ship a debounced
availability-check RPC driving an inline status pill.

Because usernames are **public, persistent, and a harassment
vector**, gate them in two layers:

1. **Client-bundled JSON list** (a few hundred entries) — instant
   red pill while typing, zero network.
2. **Server table as the authoritative gate** inside the
   `check_username` / `set_username` RPCs — this is the real
   enforcement, and it survives client-bundle drift (an old app
   build can't bypass a newly banned term).

Reserve infrastructure terms (`admin`, `api`, `www`, route names)
in a separate reserved list — they're not slurs, but they collide
with URLs like `/u/{username}`.

## UI ahead of backend

It is legitimate to ship a settings toggle that persists to a
column **before** the pipeline consuming it exists (e.g., a
notification opt-in whose dispatcher is months away):

- Removing a toggle later is worse UX than shipping it dormant.
- The accumulated opt-in data is real signal when the backend lands.

Two conditions: track the gap explicitly (a deferred row in the
parity/backlog doc, not silence), and **never fake the feature's
output** — a dormant toggle is honest; a fabricated result is not.

## Free-tier viability

All of the above fits free tiers at hobby-to-small-community scale,
but each service has a ceiling you should know before designing:

- **Worker subrequest caps** (e.g., 50 subrequests per invocation
  on free plans) kill batch-crawl designs. Prefer **piggybacking
  one unit of background work on user-request paths**
  (`ctx.waitUntil`) over cron jobs that grind a whole dataset —
  it stays under caps by construction and scales with real usage.
  (`provenance-honest-market-data` builds a whole data asset on
  this pattern.)
- **DB free-tier storage** is fine for rows, fatal for media —
  hence the CDN rule above.
- **Zero-egress object storage** is the piece that makes image-heavy
  apps free; egress-billed buckets are the trap.

When a ceiling approaches, the escape valve is per-service and
incremental — upgrade the one service, not the architecture.
