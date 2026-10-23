# The Worker: accounts and sync

`worker/` is Ear Drama's one backend: a Cloudflare Worker with a D1 database
that verifies Sign in with Apple and Sign in with Google, issues its own
session, and syncs listening history, the queue, and followed series
(Decision 057, LOOP-PLAN M5). Signing in is optional; nothing here runs for a
listener who never signs in.

It is ported from Archive Watch's `worker/`: one free Worker, routes as
sibling modules called from one `fetch()`, Cloudflare rate-limit bindings
that store nothing, and a cron sweep that makes a deletion promise true.
Archive Watch's sign-in never reached its Worker (its sync rides each
person's own cloud), so the sign-in verification here is new code, written
to the same rules.

Nothing is deployed. Every step that touches Cloudflare, Apple, or Google is
the owner's, listed under [Needs Ben](#needs-ben).

## Files

| Path | What it holds |
|---|---|
| `worker/src/index.js` | the router, CORS gate, per-address limit, cron entry; reserved paths for rooms and plays |
| `worker/src/auth.js` | sign-in, refresh, sign-out, `authenticate()`, the session sweep |
| `worker/src/jwt.js` | RS256 identity tokens against a JWKS, the Worker's HS256 tokens, ES256 for Apple revocation |
| `worker/src/sync.js` | upload (last write wins), the anonymous merge, read since |
| `worker/src/account.js` | the status row, deletion, Apple token revocation |
| `worker/src/http.js` | JSON responses, CORS, `limited()`, body parsing |
| `worker/migrations/0001_accounts.sql` | the D1 schema |
| `worker/test/*.test.js` | the suite (vitest inside workerd, a throwaway local D1) |
| `worker/test/mutations.mjs` | negative controls: breaks each guarantee and expects the suite to fail |

## Endpoints

All JSON. A browser may call only from an allowed origin; native apps send no
`Origin` and are served. Signed-in routes take `Authorization: Bearer
<access_token>`. Errors are `{ "error": "<code>", "detail"?: "..." }`.

| Method and path | Auth | Body | Answer |
|---|---|---|---|
| `GET /v1/health` | none | | `{ ok: true }` |
| `POST /v1/auth/apple` | none | `{ id_token, nonce?, device? }` | session (below) |
| `POST /v1/auth/google` | none | `{ id_token, nonce?, device? }` | session |
| `POST /v1/auth/refresh` | none | `{ refresh_token }` | a new session; the old refresh token is spent |
| `POST /v1/auth/signout` | bearer | | `204`; this sign-in's tokens stop working |
| `GET /v1/account` | bearer | | `{ user_id, created_at, providers, counts: { history, follows }, last_sync_at }` |
| `DELETE /v1/account` | bearer | `{ apple_authorization_code?, apple_client_id? }` | `{ deleted: true, apple_token_revoked: true \| false \| null }` |
| `GET /v1/sync?since=<server_time>` | bearer | | `{ server_time, history: [...], follows: [...], queue }` |
| `PUT /v1/sync` | bearer | upload (below) | `{ server_time, applied: { history, follows, queue } }` |
| `POST /v1/sync/merge` | bearer | upload | the same; see [the anonymous merge](#the-anonymous-merge) |
| `/v1/rooms/*` | | | `501`, reserved for Listen Together (M6) |
| `/v1/plays/*` | | | `501`, reserved for shared plays (M8) |

**Session**: `{ access_token, access_expires_at, refresh_token,
refresh_expires_at, user_id, provider?, created? }`. Times are milliseconds.
The access token lasts one hour, the refresh token sixty days and is replaced
on every refresh. `created: true` means this sign-in made the account.

**Upload**:

```json
{
  "device": "iphone",
  "history": [{ "episode_id": "suspense|1948-03-11", "position": 612.5,
                "duration": 1795, "finished": false, "deleted": false,
                "updated_at": 1761200000000 }],
  "follows": [{ "series_id": "suspense", "following": true, "updated_at": 1761200000000 }],
  "queue": { "items": ["suspense|1948-03-11"], "updated_at": 1761200000000 }
}
```

Every part is optional. At most 500 history rows, 500 follows, and 500 queue
items per upload; anything malformed refuses the whole upload with `400`.

### Rules the clients rely on

- **Refresh before every call.** The one API client on each platform checks
  `access_expires_at` before each Worker call and refreshes when under five
  minutes remain (AGENTS.md hard rule). Refreshes go one at a time: a refresh
  token sent twice is treated as stolen, and every session of that sign-in
  ends (refresh-token rotation, OAuth 2.0 Security BCP).
- **Last write wins, per row,** by the client's `updated_at`. An
  `updated_at` later than the server's clock is clamped to it, so a phone
  with a wrong clock cannot win forever. Equal stamps settle by device name,
  so the result does not depend on which upload lands first.
- **Removals are tombstones**: `deleted: true` for history,
  `following: false` for follows. A row is never removed by leaving it out.
- **The queue wins or loses whole**, by its own `updated_at`.
- **Read with `since` = the last answer's `server_time`.** `since` compares
  the server's write time, not `updated_at`, so a late upload carrying an old
  stamp still reaches every device. A row may come twice; applying it twice
  changes nothing.
- **The nonce**: send the raw nonce. Apple's native flow puts its SHA-256 in
  the token; the web flow puts it raw; both are accepted. Clients should
  always send one.

### The anonymous merge

A listener who never signs in keeps history on the device. On sign-in the
client sends everything it kept to `POST /v1/sync/merge` once, then reads
`GET /v1/sync?since=0`. History and follows merge row by row exactly as a
`PUT` does, so the newer position of each episode wins whichever side it came
from. The queue is the one difference: the device's items are added after the
account's, never replacing them, so signing in never empties a queue someone
built on another device.

### Account deletion

`DELETE /v1/account` removes every row that names the person, in one batch,
from every table, and the schema's `ON DELETE CASCADE` is the second lock. The
account's tokens stop working at once (each call reads the session row), so
nothing can write rows back. The test counts rows in every table D1 holds,
not a list we keep, so a new table left out of deletion fails it.

Sign in with Apple also asks that the app revoke the person's Apple tokens.
The Worker never keeps an Apple token, so the Apple client asks Apple for a
fresh authorization code just before deleting and sends it as
`apple_authorization_code` (with `apple_client_id` when it is the Services ID
rather than the bundle id). The Worker trades the code for a token and
revokes it. The rows are deleted whether or not Apple answers;
`apple_token_revoked` says what happened (`null` when the Apple key is not
configured, or for a Google account).

## Schema

`worker/migrations/0001_accounts.sql`. Times are milliseconds.

| Table | Key | Columns |
|---|---|---|
| `users` | `id` | `created_at` |
| `identities` | `(provider, subject)` | `user_id`, `created_at` |
| `sessions` | `id` | `user_id`, `family`, `token_hash` (SHA-256 of the refresh token), `device`, `created_at`, `expires_at`, `revoked` |
| `history` | `(user_id, episode_id)` | `position`, `duration`, `finished`, `deleted`, `updated_at`, `device`, `changed_at` |
| `follows` | `(user_id, series_id)` | `following`, `updated_at`, `device`, `changed_at` |
| `queue_meta` | `user_id` | `updated_at`, `device`, `changed_at` |
| `queue` | `(user_id, ord)` | `episode_id` |

No email, name, or address is stored, and no provider token. A person is a
provider and that provider's opaque `sub`. The same person signing in with
Apple and then Google gets two accounts; linking them is a later decision.

A new migration is a new numbered file; never edit one that has been applied.

## Configuration

`worker/wrangler.toml` `[vars]` (not secret; placeholders until the owner
fills them):

| Name | Meaning |
|---|---|
| `APPLE_AUDIENCES` | comma-separated `aud` values: the bundle id (`app.eardrama`) and the Services ID for web and Android |
| `GOOGLE_AUDIENCES` | comma-separated Google OAuth client ids: web, iOS, and the web id Android requests |
| `ALLOWED_ORIGINS` | browser origins; `http://localhost` and `http://127.0.0.1` on any port are always allowed |
| `APPLE_TEAM_ID`, `APPLE_KEY_ID` | only for Apple token revocation |

A value starting `REPLACE_WITH` is never accepted as an audience, and a
provider with no real audience answers `503 not_configured` rather than
trusting anything.

Secrets, with `wrangler secret put` (never in git, never in `wrangler.toml`):

| Name | Meaning |
|---|---|
| `SESSION_SECRET` | signs access tokens; at least 32 characters (`openssl rand -base64 48`). Without it, sign-in answers `503` |
| `APPLE_PRIVATE_KEY` | the Sign in with Apple key (`.p8` contents), only for token revocation |

Rate limits (`[[ratelimits]]`, Archive Watch's `limited()`; counts are kept
for the window only):

| Binding | Key | Limit |
|---|---|---|
| `EVERY_IP_LIMITER` | client address | 600 a minute, every route |
| `AUTH_LIMITER` | client address | 30 a minute, sign-in and refresh |
| `USER_LIMITER` | user id | 120 a minute, signed-in routes; per person so a classroom behind one school address is not one person |

The cron (`23 4 * * *`, daily) deletes expired sessions. A revoked session is
kept until it would have expired, because it is what recognizes a replayed
refresh token.

CORS: a request whose `Origin` is not allowed is refused with `403`, not just
denied the header. Smart-TV web packages send `Origin: null` and are refused
until a TV client signs in and the owner decides how they should.

## Tests

```sh
cd worker
npm ci
npm test                 # 66 tests in workerd with a local D1
npm run test:mutations   # 11 deliberate breaks; every one must turn the suite red
```

The suite mints its own RSA keys and serves them in place of Apple's and
Google's key sets, so it needs no network and no real client id. It covers
forged, altered, expired, wrong-audience, wrong-issuer, `alg: none`, HS256
confusion, unknown-key, and wrong-nonce tokens; refresh rotation and replay;
last write wins, tombstones, clock clamping, `since`; the merge; deletion
leaving no row in any table; CORS; rate limits; and the sweep.
`.github/workflows/worker-test.yml` runs `npm test` on any change under
`worker/`. It has no Cloudflare credential and no deploy step.

## Needs Ben

Each of these is the owner's, in this order. None has been done.

1. **Cloudflare account**: use the account Archive Watch's Worker runs on, or
   a new one. `cd worker && npx wrangler login`.
2. **Create the database**: `npx wrangler d1 create eardrama`, then put the
   printed `database_id` in `worker/wrangler.toml` (an id is not a secret).
3. **Apply the schema**: `npx wrangler d1 migrations apply eardrama --remote`.
4. **Sign in with Apple**: in the Apple Developer account, enable Sign in with
   Apple on `app.eardrama`; create a Services ID for the web and Android, with
   `eardrama.org` as its domain and return URL. Put the Services ID in
   `APPLE_AUDIENCES` beside `app.eardrama`. Then remake the provisioning
   profiles and uncomment `CODE_SIGN_ENTITLEMENTS` in `project.yml` (the
   entitlement stays off until then: a signed build naming it fails).
5. **Apple revocation key** (for deletion): create a Sign in with Apple key;
   put the Team ID and Key ID in `APPLE_TEAM_ID` / `APPLE_KEY_ID`, then
   `npx wrangler secret put APPLE_PRIVATE_KEY` and paste the `.p8` contents.
   Keep the `.p8` out of the repository.
6. **Google**: in Google Cloud, create OAuth client ids (Web for eardrama.org
   with `localhost` for development; iOS for `app.eardrama`; Android with the
   Play signing SHA-1). Put the web and iOS ids in `GOOGLE_AUDIENCES`. Android
   asks Credential Manager for a token addressed to the web id, so the Android
   id itself does not go in the list. Archive Watch's
   `docs/google-oauth-setup.md` walks the console.
7. **Session secret**: `openssl rand -base64 48 | npx wrangler secret put SESSION_SECRET`.
8. **Deploy**: `npx wrangler deploy`, then attach a route or custom domain
   (for example `api.eardrama.org`) and smoke-test `GET /v1/health` against
   that host, not a test base URL (zero-cost-hosted-backend: know which host
   the Worker answers on).
9. **Privacy policy**: the page must say what is stored: a provider and its
   opaque id, listening positions, the queue, follows, the device name the app
   sends, and nothing else; deleted at once on request.
