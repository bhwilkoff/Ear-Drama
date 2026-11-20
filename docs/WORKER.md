# The Worker: accounts, sync, Listen Together rooms, and shared plays

`worker/` is Ear Drama's one backend: a Cloudflare Worker with a D1 database
that verifies Sign in with Apple and Sign in with Google, issues its own
session, and syncs listening history, the queue, and followed series
(Decision 057, LOOP-PLAN M5). Signing in is optional; nothing but Listen
Together runs for a listener who never signs in. It also holds the Listen
Together rooms for the web and Android (M6), which need no account, and the
invite-only shared plays (M8), which need one for every call.

It is ported from Archive Watch's `worker/`: one free Worker, routes as
sibling modules called from one `fetch()`, Cloudflare rate-limit bindings
that store nothing, and a cron sweep that makes a deletion promise true.
Archive Watch's sign-in never reached its Worker (its sync rides each
person's own cloud), so the sign-in verification here is new code, written
to the same rules.

The Worker is deployed at `https://eardrama-api.benwilkoff.workers.dev`
(`GET /v1/health` answered `{"ok":true}` on 2026-10-30). That proves the code
is live, not that sign-in works: which of the steps under
[Needs Ben](#needs-ben) are done (the D1 schema, the Apple and Google ids, the
secrets) is not recorded in this repository. Every step that touches
Cloudflare, Apple, or Google is the owner's.

## Files

| Path | What it holds |
|---|---|
| `worker/src/index.js` | the router, CORS gate, per-address limit, cron entry |
| `worker/src/auth.js` | sign-in, refresh, sign-out, `authenticate()`, the session sweep |
| `worker/src/jwt.js` | RS256 identity tokens against a JWKS, the Worker's HS256 tokens, ES256 for Apple revocation |
| `worker/src/sync.js` | upload (last write wins), the anonymous merge, read since |
| `worker/src/account.js` | the status row, deletion, Apple token revocation |
| `worker/src/http.js` | JSON responses, CORS, `limited()`, body parsing |
| `worker/src/room-protocol.js` | Listen Together's protocol and arbiter, pure: state, handoff, expiry, codes, clock, drift |
| `worker/src/rooms.js` | the rooms' HTTP and D1 adapter, and the room sweep |
| `worker/src/read-protocol.js` | read rooms' protocol and arbiter, pure: cursor, leading, parts, seats, late join, leader gone, codes, clock |
| `worker/src/read-rooms.js` | read rooms' transports: the `ReadRoom` Durable Object (sockets and polls) and the D1 polling fallback |
| `worker/tools/read-golden.mjs`, `worker/test/read-golden.json` | the read protocol's golden cases, shared by every client port |
| `worker/migrations/0006_read_rooms.sql` | the D1 schema for polled read rooms |
| `worker/src/plays.js` | shared plays' HTTP and D1 adapter, the take intake (`receiveTake`), publishing; deletion's plays step; the plays sweep |
| `worker/src/plays-seats.js` | classes that own productions (Decision 082): seats, the no-account seat routes, assignments, review, progress |
| `worker/src/take-relay.js` | the `TakeRelay` Durable Object: a take piped from the recording device to the director's device, in memory only |
| `worker/migrations/0007_seats_and_pass_through.sql` | seats, class productions, assignments, reviews; `play_takes` without its object key |
| `worker/src/plays-open.js` | the reads that need no account: an open invite, the finished-drama listing and one finished drama |
| `worker/src/plays-relay.js` | the cast sheet and the relay (C7), pure: part order, claims and their lapse, done, silent, reopen, completeness |
| `worker/src/plays-names.js` | the display-name deny list (the server's layer of the two-layer gate) |
| `worker/src/plays-audio.js` | a take's length and format, read from its own WAV or FLAC header, and `takeStream` (checked from its head, streamed, never held whole) |
| `worker/src/plays-archive.js` | the archive.org uploader (Decision 073): the cron lays items out, removes lines, rewrites credits; `sendFile` streams each line's file from a device |
| `worker/src/plays-manifest.js`, `worker/src/castable-manifest.json` | the castable manifest: script id, revision, title, source, rights evidence, and the SHA-256 of each cast sheet |
| `worker/tools/castable-manifest.mjs` | rebuilds the manifest from `catalog/plays/castable-scripts.json` |
| `worker/migrations/0001_accounts.sql` | the D1 schema for accounts and sync |
| `worker/migrations/0002_rooms.sql` | the D1 schema for rooms |
| `worker/migrations/0003_plays.sql` | the D1 schema for shared plays and classes |
| `worker/migrations/0004_archive_uploader.sql` | the uploader's job columns and `play_archive_files` |
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
| `/v1/rooms/*` | room key | | Listen Together; see [rooms](#listen-together-rooms) |
| `/v1/plays/*` | bearer | | shared plays and classes; see [shared plays](#shared-plays) |

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
not a list we keep, so a new table left out of deletion fails it. It finds a
person's columns from D1's own foreign keys (`user_id`, and any other column
that references `users`), so `OTHER_PERSON_COLUMNS` in `account.js` must name
each column that is not `user_id`.

For shared plays, a **submitted production** (it has an archive job) survives
any member's deletion (owner, 2026-10-29: "Account deletion should definitely
not remove their recordings from already submitted works"). The person's takes,
parts, directorship and job move to one `deleted-account` row (`DELETED_PERSON`
in `plays.js`) that has no identity or session, so no one can sign in as it and
no remaining member gains director rights; their member row goes, so their part
reads uncredited in the listing, and a published item's credits are cleared so
the uploader rewrites them without the name. The listing, takes and
archive.org item stay. Any other production with anyone else in it goes to the
member who joined first (their takes stay); one nobody else is in goes with them.
No take audio is on Cloudflare to delete (Decision 082). A teacher's classes go
with their account, and with them the classes' seats, productions, casting and
reviews. A report about the deleted person keeps its trail with
`target_user_id` cleared.

Sign in with Apple also asks that the app revoke the person's Apple tokens.
The Worker never keeps an Apple token, so the Apple client asks Apple for a
fresh authorization code just before deleting and sends it as
`apple_authorization_code` (with `apple_client_id` when it is the Services ID
rather than the bundle id). The Worker trades the code for a token and
revokes it. The rows are deleted whether or not Apple answers;
`apple_token_revoked` says what happened (`null` when the Apple key is not
configured, or for a Google account).

## Listen Together rooms

Rooms (LOOP-PLAN M6, Decision 058) let the web and Android listen together;
Apple devices use SharePlay and are meant to carry the same state shape. The
rooms are ported from Archive Watch's Watch Together (`worker/src/together.js`,
`docs/SHAREPLAY.md` §11, Decision 143 there): a host publishes the state, not
the playhead; the server is the clock; members poll and extrapolate; the room
carries the host's exact copy and every guest plays that file.

**No account.** Decision 057 requires an account "to record, cast, or publish
a shared play". Listening together is none of those, and SharePlay asks for no
account, so a room asks for none. Rooms take no bearer token.

**Polling on D1, not a socket.** Durable Objects are not on the free plan;
Workers KV can take a minute to show a pause; D1 is strongly consistent and
already bound. The host writes when the state changes; members read every
2 seconds, slowing to 10 when nothing has changed for a minute, and
extrapolate between reads.

**The protocol is pure.** `worker/src/room-protocol.js` imports nothing and
touches no network, store, or clock: the arbiter (`applyHostState`), host
handoff (`nextHost`), expiry, the code rules, the clock estimate, and drift
correction all take `now` and return values. `worker/src/rooms.js` is the HTTP
and D1 adapter and holds no rule. A test fails if the protocol file gains an
import, `fetch`, `WebSocket`, `env.`, `Date.now`, or `crypto.`. Each client
ports the protocol's rules beside its own transport.

### Endpoints

Every call but create and join sends the member key as `x-room-key`. The key
is returned once, by create or join, and stored only as its SHA-256.

| Method and path | Who | Body | Answer |
|---|---|---|---|
| `POST /v1/rooms` | anyone | `{ state: { episode_id, archive_id, file, position?, playing?, rate? } }` | the room, with `member_key`; the creator is host |
| `POST /v1/rooms/{code}/join` | anyone with the code | | the room, with `member_key`; `404 no_such_room`, `409 room_full`, `410 room_ended` |
| `GET /v1/rooms/{code}` | a member | | the room |
| `PUT /v1/rooms/{code}/state` | the host | any of `episode_id, archive_id, file, position, playing, rate` | the room; `403 host_only` for a guest |
| `POST /v1/rooms/{code}/leave` | a member | | `{ left: true, room_ended }` |
| `DELETE /v1/rooms/{code}` | the host | | `{ ended: true }` |

A key that is not a member of this room is `403 not_a_member`, including a
member who went quiet and was dropped: they join again with the code.

### The room message

What every read answers, and the shape SharePlay is meant to carry:

```json
{
  "v": 1,
  "code": "7KQ2MX",
  "role": "guest",
  "members": 3,
  "generation": 14,
  "state": {
    "episode_id": "suspense|1948-03-11",
    "archive_id": "OTRR_Suspense_Singles",
    "file": "Suspense 48-03-11 The Lodger.mp3",
    "position": 612.5,
    "playing": true,
    "rate": 1,
    "updated_at": 1761200000000
  },
  "server_time": 1761200004000
}
```

| Field | Meaning |
|---|---|
| `v` | protocol version; a client ignores fields it does not know |
| `code` | six Crockford Base32 characters, the only thing a person says aloud |
| `role` | `host` or `guest` for the key that asked; it changes to `host` on handoff, and the client then gives that person the controls |
| `members` | members present now, the host included |
| `generation` | bumped by the server on every state write; a client uses it only to notice change |
| `state.episode_id` | the catalog's episode id |
| `state.archive_id`, `state.file` | the host's copy. Every guest plays `https://archive.org/download/<archive_id>/<file>`, built by the client, over its own saved choice or a download of another copy |
| `state.position` | seconds, true at `updated_at` |
| `state.playing` | `true` playing, `false` paused |
| `state.rate` | the host's speed, one of 0.75, 1, 1.25, 1.5, 2 (Decision 062) |
| `state.updated_at` | the server's clock (ms) when `position` was true, set by the server |
| `server_time` | the server's clock (ms) when it answered: every read is a clock sample |

### Rules the clients rely on

- **The code is public; control is not.** Knowing the code lets you join and
  listen. Every state write needs the key of the current host; a guest's
  write is refused and the room is unchanged.
- **The host's copy, always.** A new `episode_id` must come with its
  `archive_id` and `file`, or the write is refused. A write that leaves out the
  copy keeps it. The copy is an archive.org identifier and a file name, never a
  URL; `..`, `.`, empty segments, a leading `/`, a backslash, and control
  characters are refused.
- **Where the host is now**: `position + (server_now - updated_at) / 1000 * rate`
  while `playing`, else `position`. A write that leaves out `position` keeps the
  playhead where that formula puts it.
- **The clock**: around each read, `offset = server_time - (t0 + t1) / 2`;
  keep the sample with the smallest round trip, never an average
  (`clockOffset`). `server_now` is the local clock plus that offset.
- **Drift correction** (`correction`), applied silently; nobody is asked to
  do anything:

  | Guest vs host | The player |
  |---|---|
  | host paused or playing | follows at once, never nudged |
  | under 150 ms | plays at the host's rate |
  | 150 ms to 2 s | host's rate x 0.97 if ahead, x 1.03 if behind, until inside 150 ms |
  | over 2 s | seeks |

- **The host is authoritative; a stalled guest catches up.** The room never
  waits for a straggler.
- **Presence.** A member's read counts as presence; the server writes it at
  most every 20 seconds. A member not heard from for 2 minutes has left. So
  every member, the host too, reads at least every 30 seconds.
- **Host handoff.** When the host leaves, or goes quiet for 2 minutes, the
  member present longest becomes host. When nobody is left, the room ends.
- **Size and expiry.** At most 20 members. A room whose state has not changed
  and that nobody has joined for 6 hours is ended on the next read (`410`) and
  deleted by the hourly sweep, with its members.
- **Codes.** `normalizeCode` drops spaces, `-` and `_`, uppercases, reads I and
  L as 1 and O as 0, and refuses U and anything outside the alphabet; every
  client must normalize the same way. 32^6 is 1,073,741,824 codes, drawn from a
  CSPRNG and checked against live rooms when issued. With 1,000 live rooms a
  guess lands 1 time in 1,073,741; at 20 joins a minute from one address that
  is more than two years of guessing.
- **What is stored.** A room row says what an episode is doing. A member row is
  a random id, the hash of a random key, and two times. No account, name, or
  address. Both go when the member leaves or the room ends.

## Read rooms (Decision 082)

A read room is a place in a script that a group reads together (PLAYS-DESIGN
§12): one cursor the leader moves, who holds which part, and the mode. Its
rules are `worker/src/read-protocol.js`, pure and golden-checked
(`worker/test/read-golden.json`, written by `node tools/read-golden.mjs`, one
file every client port reads). Two transports carry the same messages
(`worker/src/read-rooms.js`):

- **A Durable Object per room** (`ReadRoom`, SQLite-backed, binding
  `READ_ROOMS`): sockets through the hibernation API, presence in memory, the
  room's state in the object's own storage, ended by its alarm after 6 idle
  hours. It also answers HTTP polls, so a client without a socket joins the
  same room.
- **D1 polling** (`read_rooms`, migration 0006): used when the Worker has no
  `READ_ROOMS` binding. Writes are guarded by a version column, so the first
  claim still wins. The hourly sweep deletes idle rows.

No audio ever passes through or rests in either (owner 2026-11-19: storage is
archive.org). No account to read. A class room is opened by the account that
owns the class; its seats are the class's roster and, with `production_id`
(that class's production of the same script), its casting is that
production's assignments, both read from D1 when the room opens: `seats` and
`assignments` in the request are ignored. A seat joins, or takes a seat with
the `seat` message, only with that seat's key (`seat_key`, from
`/v1/plays/seat/claim`); otherwise `403 seat_key_required`. Seats added after
the room opened join the next room.

| Method and path | Who | Body | Answer |
|---|---|---|---|
| `POST /v1/read` | anyone; a class room needs its teacher's bearer token | `{ script_id, script_revision, cast, mode?, kind?, class_id?, seats?, assignments?, production_id? }` | the snapshot with `member_key` and `transport` (`socket` or `poll`); the creator leads |
| `POST /v1/read/{code}/join` | anyone with the code; a class seat with its key | `{ role?: "reader" or "screen", seat?, seat_key?, move?, name? }` | the snapshot with `member_key`; `409 room_full`, `joining_locked`, `seat_in_use`; `400 seat_required`; `403 seat_key_required`; `422 bad_name`; `404 no_such_room`; `410 room_ended` |
| `GET /v1/read/{code}` | a member (`x-read-key`) | | the snapshot (poll every second) |
| `POST /v1/read/{code}/send` | a member | a message | the snapshot (and `reply` for a ping), or the refusal |
| `GET /v1/read/{code}/socket` | a member, by upgrade | first message `{ type: "hello", key }` | snapshots on every change; a `poll_only` room answers `409` |
| `PUT /v1/read/{code}/takes/{takeId}` | a reader, in Record mode, for a line they hold (T5) | the audio with its `Content-Length`; `x-take: { lineID, frames, sampleRate, ... }` | `201` with `delivered: true` once the receiving device has it; `403 not_your_line`, `readers_only`, `school_consent_required` (an under-13 class); `409 not_recording`, `receiver_records_here`, `nobody_receiving`, `one_take_at_a_time`; the take checks of `PUT .../takes/:takeId` |
| `GET /v1/read/{code}/takes/inbox` | the receiving device (`you.receives`) | | the next take: its bytes, `x-take` its fields (`id`, `lineID`, `part`, `file`, `frames`, `sampleRate`, `capture: "room"`, `seat`, `member`); `204` after 25 s; `403 receivers_only` |
| `POST /v1/read/pair` | a TV (no account) | | `201 { pair_code, pair_key, expires_at }`; the key once, stored as its hash; READ_CREATE_LIMITER per address |
| `GET /v1/read/pair/{pair_code}` | the TV (`x-pair-key`) | | `{ paired: false, expires_at }` until a leader attaches it, then the room's snapshot with `member_key` (the TV joined as its screen, past a lock) and the pairing is gone; `404 no_such_pair`, `410 pair_expired` |
| `POST /v1/read/{code}/pair` | the leader or the owner | `{ code }`: the TV's pairing code, normalized as a room code | `{ paired: true }`; `403 leader_only`, `404 no_such_pair` (none, or used), `410 pair_expired`; READ_JOIN_LIMITER per address |

Messages: `cursor { line, base }`, `line-done { line, base }` (the holder's take ended; a line that is no longer the
cursor is marked done and the cursor stays, T7c), `again { line,
base }`, `mode { mode }`, `claim { part }`, `release { part }`, `lead { to }`,
`lock { locked }`, `read-open { open }` (the leader's "Read open parts", carried in the snapshot as `read_open`; the screen obeys it), `seat { seat, seat_key, move? }`, `ping { t0 }` (answered `pong {
t0, server_time }`), `end`. Refusals: `leader_only`, `stale` (with the current
cursor generation), `part_taken` (with the holder), `not_your_line`,
`class_assignments_only`, `readers_only`, `screens_do_not_lead`,
`not_a_member`, `seat_key_required`, `rate_limited`. The key never travels in a URL. The snapshot carries `leader_name` (the leader's seat label, or the room owner's own `owner_name` given when the room opens; else null) so readers see "Waiting for <name>", and `read_open`.

**Record in the room** (T5, PLAYS-DESIGN §12.10). A take crosses the Worker only from a reader who
holds the line (`recordRefusal`: Record mode, a reader, an adult's claimed part or a seat's
assignment with its range, any held line rather than only the cursor's) to the room's **receiver**
(`receiverOf`: a class's teacher, whoever leads; an adult room's leader), and nothing keeps it. A
room with a production pipes it through that production's `TakeRelay` and writes the take's row
(the teacher's account, credited to the seat; `capture: "room"`), so review, progress and Publish
see it; a room without one pipes it through its own relay (`read:{code}`) and writes nothing. An
under-13 class sends no seat's voice until the school's consent (Decision 059). Joins take an
optional adult `name` (40 characters, `plays-names.js`; `422 bad_name`), carried in
`members[].name`, in `you.name`, and as `leader_name` when the leader gave one; the snapshot also
carries `receiver` and `you.receives`. **A room that ended** answers `410 room_ended` for 6 hours
(the object keeps only the time it ended; the D1 row stays until the sweep); a code that never was
answers `404 no_such_room`. **Pairing a TV**: `read_pairs` (migration 0008), one row a code for 10
minutes, used once, swept hourly; a `paired` flag in a join body is dropped, so only a pairing lets
a screen past a lock.

## Shared plays

Phase 2 of the plays (LOOP-PLAN M8, Decisions 057 and 059,
`docs/PLAYS-DESIGN.md` §11): a production made on one device is recorded
across several, by people who came in with an invite link, or by a class's
seats (Decision 082). Every route but the open reads and the seat routes takes
a bearer token (Decision 057) and counts against `USER_LIMITER`. Only
`archive/files` calls archive.org, streaming one line's file.

**Castable only.** A production is made from a script id, its revision, and
its cast sheet (`[{ id, part }]`, every line in script order, `part` being
`role:NAME`, `sound`, or `directions` exactly as `js/plays-core.js`
`linePart` gives it). The Worker checks all three against
`src/castable-manifest.json`, which holds the SHA-256 of each castable
script's cast sheet; the title comes from the manifest, never from the client.
`node tools/castable-manifest.mjs` rebuilds the manifest whenever
`catalog/plays/castable-scripts.json` changes, and a test fails while the two
disagree. A revision the Worker does not have is `409 revision_mismatch` with
the current one.

**Takes pass through; nothing is kept** (Decision 082; owner 2026-11-19: *"We
are using archive.org for storage, not cloudflare."*). No R2, no audio in D1,
KV, or a Durable Object's storage, and no route serves take audio. A take's
D1 row holds its fields only, written once the take reached the director's
device. How a take moves:

1. The director's device (the teacher's, for a class) holds a **pickup** open:
   `GET /productions/:pid/takes/inbox`, a long poll answered with the next
   take (its bytes, its fields in the `x-take` header) or `204` after 25
   seconds. Up to 4 pickups at once.
2. A member's or seat's `PUT .../takes/:takeId` is refused with `409
   nobody_receiving` unless a pickup is waiting or the director's device was
   there in the last 10 seconds (the gap between two polls); the take stays
   on the recording device, which sends it again when both are present.
3. The Worker reads the take's head (64 KiB) against its `Content-Length`
   (required: `411 length_required`), judges the header (format, length,
   size), then pipes the rest to the pickup one chunk at a time, pulled by the
   director's reads. A body shorter or longer than declared errors the
   director's stream and answers the sender `502 not_delivered`; nothing is
   written.
4. Delivered: `201` with the take and `delivered: true`, and the row is
   written. The Worker kept nothing.

**Memory.** One `TakeRelay` Durable Object per production, all in memory and
never its storage. Each transfer holds the 64 KiB head and the chunk in the
pipe; at most 4 transfers at once per production and one in flight per sender
(`409 one_take_at_a_time`), so an object holds well under 1 MB of audio, never
a whole take, against the isolate's 128 MB. A waiting sender's body is not
read. An evicted object forgets its pickups, which only means the next take
is refused until the director's device polls again.

The **director's own take** is checked the same way and recorded, never
relayed (`delivered: false`); so is a performer's replacement of a published
line (P12), which then goes to archive.org from the performer's device.

### Endpoints

All under `/v1/plays`, all bearer except the open reads below. `:pid` is a production, `:part` a part id
(URL-encoded, so `role%3AHAMLET`).

| Method and path | Who | Body | Answer |
|---|---|---|---|
| `GET /consent` | anyone | | `{ version, text, uploads, publishes }`: the CC0 consent's version id, the owner's words, whether takes can pass through (the `TAKE_RELAY` binding), and whether Publish is (both archive.org keys set) |
| `POST /productions` | anyone | `{ script_id, script_revision, cast, display_name? }` | `201` the record; the caller directs |
| `GET /productions` | anyone | | `{ productions: [{ id, title, script_id, director, updated_at }] }`, the caller's |
| `GET /productions/:pid` | a member | | the record (below) |
| `POST /productions/:pid/invites` | the director | `{ expires_in_days? }` 1 to 30, default 7 | `201 { id, token, expires_at }`; the token is shown once |
| `DELETE /productions/:pid/invites/:id` | the director | | `204` |
| `POST /invites/view` | anyone with a token | `{ token }` | the cast sheet: `{ id, title, parts: [{ id, lineCount, status }], next, member }` |
| `POST /invites/claim` | anyone with a token | `{ token, part, display_name? }` | joins and claims `part`; the record |
| `POST /productions/:pid/claim` | a member | `{ part }` | claims `part` (a member may double parts); the record |
| `POST /productions/:pid/parts/:part/done` | the claimant | | the record |
| `POST /productions/:pid/parts/:part/silent` | the claimant, or anyone when it is next | | sound and directions only; the record |
| `POST /productions/:pid/parts/:part/reopen` | the part's performer or the director | | the record |
| `POST /productions/:pid/parts/:part/release` | the claimant | | the part is open again; the record |
| `POST /productions/:pid/consent` | a member | `{ version }` | `204`; `409 consent_version_mismatch` with the current version |
| `PUT /productions/:pid/takes/:takeId` | the claimant; on a published item, the line's performer (a replacement); in a class production, the teacher (any line, `seat` in `x-take` to credit a seat) | the audio with its `Content-Length`; `x-take: <the take's fields as JSON>` | `201` the take with `delivered`; `409 nobody_receiving`, `409 one_take_at_a_time`, `502 not_delivered`, `411 length_required`; a replacement also `403 not_your_take`, `409 consent_missing`, `409 removed_by_director` |
| `GET /productions/:pid/takes/inbox` | the director | | the next take: its bytes, `x-take` its fields (`id`, `lineID`, `part`, `file`, `frames`, `sampleRate`, `capture`, `seat`); `204` after 25 s with none; `409 too_many_pickups` past 4; `503 pass_through_unavailable` without `TAKE_RELAY` |
| `GET /productions/:pid/receiver` | a member | | `{ receiving, name }`: whether the director's app holds a pickup (or did in the last 10 s) and the director's chosen name; read from the relay's memory, nothing is written |
| `PUT /productions/:pid/assignments` | the director of a class production | `{ assignments: [{ part, from?, to?, seat }] }`: the whole casting; `from`/`to` are lines of that part (a split by scene); no line twice | `{ assignments }`; `422 not_a_class_production`, `422 bad_assignments` |
| `POST /productions/:pid/takes/:takeId/review` | the director of a class production | `{ state: "approved" or "again", note? }` (typed, up to 500 characters) | `{ take_id, state, note, reviewed_at }`; the latest review stands; the note is shown to that take's seat alone |
| `PUT /productions/:pid/archive/files/:lineId` | the director, or the line's take's performer | the line's chosen take, with its `Content-Length` | `200 { line_id, state: "sent", name, archive }`; `409 not_ready` (the cron has not laid the item out), `409 already_sent`, `409 reported_take`, `422 not_the_take`, `503 archive_busy` (check_limit), `503 archive_unavailable` / `502 archive_refused` (archive.org's answer, redacted) |
| `POST /productions/:pid/chosen` | the claimant | `{ take_id }` | the record |
| `POST /productions/:pid/publish` | the director | a class production: `{ credit_name? }` | `201 { status: "queued", take_ids, created_at }`; again, `200` and the same job; after `failed`, `200` and queued again; `503 publishing_unavailable` without both keys; a class production also `403 under_13_never_published`, `422 credit_name_required` |
| `POST /productions/:pid/archive/lines/:lineId/remove` | the line's performer, or the director | `{ reason? }`: `withdrawn` (default) or a report reason | `202 { line_id, state }`; `404 not_published` before the item is |
| `POST /reports` | a member | `{ production_id, take_id }` or `{ production_id, user_id }`, `reason`, `note?` | `201 { id }` |
| `POST /blocks`, `GET /blocks`, `DELETE /blocks/:userId` | anyone | `{ user_id }` | `204`; `{ blocked: [...] }`; `204` |
| `POST /classes` | anyone (the teacher) | `{ name, under13? }` | `201 { id, name, code, under13, school_consent }` |
| `GET /classes` | anyone | | `{ teaching, member_of }`; each taught class carries `code` and `school_consent` |
| `POST /classes/join` | anyone with the code | `{ code, display_name? }` | `{ id, name, under13 }` |
| `GET /classes/:id` | the teacher or a member | | the teacher sees the code, the account members, and `seats: [{ id, label, claimed, claimed_at }]`; a student, the name |
| `POST /classes/:id/seats` | the teacher | `{ labels: [...] }` or `{ text: "a pasted list" }` (one a line, or tab or semicolon apart) | `201 { seats, refused: [{ label, error }] }`; a name already there is skipped; `409 too_many_seats` past 64 |
| `DELETE /classes/:id/seats/:seat` | the teacher | | `204`; the seat's casting goes, its takes stay the teacher's |
| `POST /classes/:id/seats/:seat/release` | the teacher | | `204`; the device holding it is let go and the next may take it |
| `POST /classes/:id/productions` | the teacher | as `POST /productions` | `201` the record with `class_id`; every seat of the class is in it without an invite |
| `GET /classes/:id/progress` | the teacher | | `{ class_id, productions: [{ id, title, seats: [{ seat, label, parts: [{ part, lines, recorded, approved, again }] }] }] }`: counts only, never a ranking |
| `POST /classes/:id/school-consent` | the teacher | `{ reference? }` | `201`; `503 pending_owner_policy` until `SCHOOL_CONSENT_POLICY` is set |
| `DELETE /classes/:id/members/:userId` | the teacher, or that student | | `204` |

### Seats (no account; Decision 082)

`/v1/plays/seat/...`, handled by `src/plays-seats.js` before the sign-in gate.
A seat is a name the teacher typed; the student picks it with the class code
and gets a **seat key** once (24 random bytes, stored as SHA-256), sent after
that as `x-seat-key`. Listing and claiming count per address against
`SEAT_JOIN_LIMITER` (a class's size a minute, against code guessing); every
call with a key counts against `SEAT_LIMITER` by its seat, and a seat's takes
against `PLAY_UPLOAD_LIMITER` by its seat, never by address.

| Method and path | Body | Answer |
|---|---|---|
| `POST /seat/list` | `{ code }` | `{ class: { id, name }, seats: [{ id, label, taken }] }` |
| `POST /seat/claim` | `{ code, seat, move? }` | `201 { seat_key, seat, class: { id, name, under13 } }`; `409 seat_in_use` when another device holds it, unless `move: true` ("Move here"), after which the other device's key stops working |
| `GET /seat` | | `{ seat, class, productions: [{ id, title, scriptID, scriptRevision, assignments (this seat's), takes: [{ ...the take, chosen, review: { state, note, reviewed_at } or null }] }] }`; a released or moved key is `401 seat_key_required` |
| `PUT /seat/productions/:pid/takes/:takeId` | the audio with its `Content-Length`; `x-take` | passes through to the teacher's device as above; `403 not_assigned` for a line outside the seat's assignments (or in a production with none), `403 school_consent_required` in an under-13 class until the school's consent is recorded (Decision 059) |
| `GET /seat/productions/:pid/receiver` | | `{ receiving, name }` as above, for the teacher's app: a seat asks before it sends, and shows "sends when {name} is in Ear Drama" until it is `true`; another class's production is `404` |
| `POST /seat/productions/:pid/chosen` | `{ take_id }` (one of this seat's) | the seat's view; the student chooses which take is offered |

**Credit and consent (T6, PLAYS-DESIGN §12.11).** A take recorded in an adult room by a reader with no
account is written as a row of the room's production (the director's account owns it) with `credit`,
the name the reader gave on joining ("A reader" when none), and the same `credit` rides in the
take's `x-take` to the receiving device and in the record's `takes`. The record carries `credits:
[{ name, lines, consented: false }]` for the chosen takes that have one, and those takes never make
the director a `performer`. `POST /productions/:pid/publish` answers `409 { error: "consent_missing",
detail: [user ids], credits?: [names] }` while a performer has not agreed or a credited maker stands;
it queues only when both lists are empty. `POST /v1/read` with `production_id` and no `class_id`
needs the production's director's bearer token (`404 no_such_production` otherwise). Migration
`0009_take_credit.sql` adds the column.

A production the caller is not in, an unknown one, an invite that is unknown
or blocked, and a hidden take all answer `404`, so none can be told apart. (A
revoked or expired invite is a plain `410` on the open read below; the signed-in
`invites/view` and `invites/claim` still answer `404` for it.)

### Open reads (no account; owner, 2026-10-29)

*"On an invite link, they should be able to see everything. They just can't
contribute until they sign in."* and *"Finished ear dramas should definitely be
listed and credited. Why else would we record them?"* Four GET routes, handled
by `src/plays-open.js` before the sign-in gate (three: the take audio route
went with the R2 store, Decision 082); each counts against a per-address
limiter, not `USER_LIMITER`, and answers `429` past it. Every other method on
these paths is `401` like the rest of `/v1/plays`: claiming, recording,
uploading, reporting and blocking need an account.

| Method and path | Answer |
|---|---|
| `GET /open/invite` with header `x-invite: <token>` | the play: `{ id, scriptID, scriptRevision, title, source, parts: [{ id, lineCount, status, performer? }], members: [{ name, director }], takes: [{ id, lineID, part, frames, sampleRate }], chosen, next, archive, expires_at, server_time }`; `Cache-Control: private, max-age=30` |
| `GET /finished?limit=&cursor=` | `{ productions: [{ id, script_id, script_revision, title, source, credits: [{ part, name }], archive_url, published_at }], next_cursor }`; `limit` 1 to 50 (default 20); `Cache-Control: public, max-age=300, s-maxage=300` |
| `GET /finished/:pid` | one of the above, `404` if it is not (or no longer) finished |

- **The token rides a header**, never the path or query, so no access log holds
  it (the link carries it in the fragment for the same reason). Unknown or
  malformed: `404 invite_not_found`. Revoked or expired: `410 invite_gone`. An
  expired invite is kept 30 days after it lapses (the sweep waits) so it can say
  so; then it is forgotten (`404`).
- **No account ids leave.** Members are chosen names; a part's `performer` is the
  chosen name. Reading does not make the viewer a member or claim anything.
- **Only each line's chosen take**, never an older one.
- **Withheld from every anonymous viewer** (a viewer has no personal hidden
  set, so the rule is the strict one): a take anyone reported (even once the
  report is closed), every take by a person an open report names, and every take
  by anyone the inviter blocked or who blocked the inviter. Those takes are not
  listed.
- **Finished means** the archive job is `published` and at least one line is
  still on the item. The order is a stated rule: newest `published_at` first, ties
  by id descending, never engagement. The cursor is `published_at:id`.
- **The item's files and the read-along** (PLAYS-DESIGN §2.11 rule 6): the published item
  holds one file per line, `NNNN-PART.wav|flac` (archive.org adds an MP3 of each), where
  `NNNN` is the line's 1-based place in the script (`fileName(seq, ...)`, `seq` the line's
  index in the cast sheet plus one; a test pins it). That number plus `script_revision` is
  all a client needs to say which line a file speaks, so a finished drama's read-along
  follows file boundaries with no per-line timing stored. A line with no file (silent or
  removed) is a gap in the numbers, never a renumbering. `script_revision` is the revision
  the production was recorded against; the numbers mean nothing for another revision.
- **Credits** run part by part in script order, one `{ part, name }` for each
  performer chosen on a line still on the item. A removed line (P12) drops its
  credit, and a part whose every line is removed drops out. A deleted account's
  lines stay on the item, uncredited: their part reads `name: ""`, never a name.
- **Why the Worker and not a published file:** the listing is the one gatekeeper
  (`shared-data-plane-contract`). A static copy would be a second published copy that
  goes stale between publishes and could keep crediting a line after its removal.
  The site reads these routes directly; the edge cache (`s-maxage=300`) carries the
  load. A build-time copy for search engines is later work, written from these
  same routes.

**The record** is production.json, merged line by line from every member's
takes, with the field names Apple's `Production` and `js/plays-core.js`
already use: `id`, `scriptID`, `scriptRevision`, `title`, `created`
(Foundation seconds since 2001), `parts` (`{ status, performer? }` per part,
`performer` being the member's display name), `takes`, `chosen`, `roomTone`
(always empty: room tone stays on the device), and `listenedThrough` (always
false: listening through is the device's). A take carries `id`, `lineID`,
`part`, `file`, `created`, `frames`, `sampleRate`, `capture`, `heard`,
`loudness`, `peak`, and `bleed`. The Worker adds fields a phase 1 decoder
ignores: `director`, `members`, `next`, `hidden_takes`, `archive`,
`uploads` (whether takes can pass through, so a client can say so before anyone records), `class_id`, `assignments` (a class production's), `reviews` (the director's view of a class production: take id to `{ state, note, reviewed_at }`), `server_time`, `invites` (the director's view), and per take `user_id` and
`seat`, per part `user_id` and `claim_expires_at`. No take has an audio path: the audio is on the devices.

### Rules the clients rely on

- **The relay (C7, owner 2026-10-23).** Any open part may be claimed, in any
  order (`not_open` otherwise); `next` is the suggestion, the first open part
  in the order of `castParts`: speaking parts largest first, then sound, then
  directions. Nothing can be claimed while a part records. A claim lapses
  seven days after it is made and the part is open again; its takes stay. The
  hourly sweep deletes lapsed claims.
- **Done and silent (C6).** A speaking part is done only when
  every one of its lines has a chosen take. Only sound and directions may be
  left silent. A finished part reopens only while nothing records, for its
  performer or the director.
- **Invites.** 32 random bytes, base64url (43 characters), returned once and
  stored as SHA-256. Revocable; expire after 1 to 30 days (7 by default).
  Clients should carry the token in a link's fragment so it never reaches a
  server log. A production holds at most 64 members.
- **Takes.** Only the part's claimant uploads, only on a line of that part
  (in a class production, a seat on its assigned lines, and the teacher on
  any). A take passes through to the director's device (above). A take is mono WAV or FLAC
  and is read from its own header: at most 300 seconds (the longest castable
  speech, 644 words, is about 258 seconds at 150 words a minute) and 45 MB. A
  declared `frames` more than 50 ms from the audio, a `sampleRate` that
  differs, or a header that claims more audio than was sent is refused. A
  take whose bleed check fired (`bleed: true`) is refused, because it holds
  the device voice (PLAYS-DESIGN §5). A take id is used once: takes are
  immutable. A new take becomes its line's chosen take and the older ones
  stay; at most 10 takes a line. `PLAY_UPLOAD_LIMITER` counts uploads per
  person, and per seat.
- **Blocks.** A person who blocks someone stops seeing that person's takes
  (the record drops them and counts them in `hidden_takes`). An invite made by either of two people with a block between them
  does not work for the other. Blocking answers `204` whether or not the
  account exists.
- **Reports.** A member reports a take or another member, with a reason
  (`offensive`, `harassment`, `personal_information`, `not_a_performance`,
  `other`) and an optional note of up to 500 characters. A reported take is
  hidden from its reporter at once. Reports wait in `play_reports` for the
  owner; nothing is sent anywhere yet.
- **Names.** Display names (on a production, an invite claim, or a class
  join) and class names pass `plays-names.js`: at most 40 characters, no
  links, nothing that reads as the service, and no denied word after folding
  accents, case, and look-alike characters. The list is a seed.
- **Consent.** One row per person per production per version. Publishing
  needs every performer's consent at the current version, so new words mean
  consenting again.
- **Publishing.** Only a complete production (every part done or silent,
  every speaking line chosen), with no open report on a chosen take, queues a
  job, and only while both archive.org keys are set. The record's `archive`
  is `{ status, created_at, url, reason }`: `queued`, `uploading`,
  `published` (`url` is the item), or `failed` (`reason` says why).
- **The uploader** (`plays-archive.js`, Decision 073, Decision 082). The
  Worker holds no audio, so the work is split. The cron takes jobs whose
  backoff has passed and that no other run holds (a ten-minute lease), at most
  20 archive.org requests a run: it lays a queued job out (one file row a
  chosen take, `uploading`), carries out removals, and rewrites credits. The
  director's device then sends each pending line's file to `archive/files`
  (one at a time; `USER_LIMITER` paces a device at 120 calls a minute, so a
  150-line play takes a little over a minute), which checks it is the chosen
  take and streams it to archive.org; the last file sets the job `published`.
  A production is one item,
  `eardrama-<pid, lowercased>`, in `opensource_audio`, with `mediatype`
  audio, the script's `title`, `source`, and rights evidence (`rights`),
  `creator` and `credits` from the performers' chosen names, `licenseurl` CC0
  1.0, and `date`. Each line's chosen take is one file, `NNNN-PART.ext` in
  script order; only the last file of a first upload asks archive.org to
  derive. A file archive.org confirmed is `sent` and never sent again
  (`409 already_sent`); a retry lands on the same name. check_limit comes
  before a first upload's first file. A file archive.org refuses is answered
  to the device (`502`, or `503` to try later) and fails nothing. For the
  cron's removals and credits, 429, 5xx, and network errors back off (5
  minutes, doubling, at most 12 hours) and give up after 10; any other 4xx
  fails that line at once with archive.org's code.
  The keys go only in the `authorization: LOW` header and the metadata
  form, are never logged, and are redacted from any stored reason.
- **Replace and remove (P12).** On a published item, the performer of a
  line's take may upload a new take for that line (at the current consent),
  then send its file from their device, which overwrites the line's file (a
  different format deletes the old name first); the performer or the director may remove a line, and the
  uploader deletes the file (`x-archive-cascade-delete`, a `404` counts as
  gone) and keeps `removed_by` and `reason`. A line the director removed is
  not put back. A reported replacement is held until its report is closed (`409 reported_take`).
  When a performer has no line left, the item's credits are rewritten
  through the metadata write API. A refused change marks that line `failed`
  and leaves the item published.
- **Classes.** A class code is eight Crockford Base32 characters, normalized
  like room codes. A class marked `under13` (fixed when it is made) takes no
  student until its teacher records the school's consent, and that record can
  be made only once the owner sets `SCHOOL_CONSENT_POLICY` to the privacy
  policy's version. `PLAY_JOIN_LIMITER` counts invite views, invite claims,
  and class joins per person.
- **Class productions** (Decision 082). A class owns its productions: every
  seat of the class sees them without an invite, and nobody outside the class
  but its teacher. A production with assignments lets every assigned part
  record at once (claims do not apply); one without keeps the one-part relay
  (C7) for accounts and has nothing for a seat to record. A seat's take
  belongs to the teacher's account (`user_id`) and names its seat (`seat_id`).
  An under-13 class passes no seat's voice through until the school's consent
  is recorded, which waits on the owner's policy (P5): until then it uses one
  microphone, the teacher's device. **Publishing a class production**: only a
  class marked 13 and over (`403 under_13_never_published` otherwise; the
  teacher exports a file), every speaking line chosen, the teacher's own CC0
  consent at the current version, and a name to credit (`credit_name`, which
  passes the name filter and becomes the teacher's name in that production).
  Every line on the item is credited to that name; no seat's label reaches
  archive.org.

## Schema

`worker/migrations/0001_accounts.sql`, `0002_rooms.sql`, and `0003_plays.sql`.
Times are milliseconds.

| Table | Key | Columns |
|---|---|---|
| `users` | `id` | `created_at` |
| `identities` | `(provider, subject)` | `user_id`, `created_at` |
| `sessions` | `id` | `user_id`, `family`, `token_hash` (SHA-256 of the refresh token), `device`, `created_at`, `expires_at`, `revoked` |
| `history` | `(user_id, episode_id)` | `position`, `duration`, `finished`, `deleted`, `updated_at`, `device`, `changed_at` |
| `follows` | `(user_id, series_id)` | `following`, `updated_at`, `device`, `changed_at` |
| `queue_meta` | `user_id` | `updated_at`, `device`, `changed_at` |
| `queue` | `(user_id, ord)` | `episode_id` |
| `rooms` | `code` | `episode_id`, `archive_id`, `file`, `position`, `playing`, `rate`, `updated_at`, `generation`, `host_member`, `created_at`, `touched_at` |
| `room_members` | `id` | `code`, `key_hash` (SHA-256 of the member key), `joined_at`, `seen_at` |
| `play_productions` | `id` | `user_id` (the director), `script_id`, `script_revision`, `title`, `cast_sheet` (JSON `[[line id, part]]`), `created_at`, `updated_at`, `class_id` (a class production; deleted with the class) |
| `play_members` | `(production_id, user_id)` | `display_name`, `joined_at` |
| `play_invites` | `id` | `production_id`, `user_id` (its maker), `token_hash` (SHA-256), `created_at`, `expires_at`, `revoked` |
| `play_parts` | `(production_id, part)` | `status` (`recording`, `done`, `silent`; no row is open), `user_id`, `claimed_at` |
| `play_takes` | `(production_id, id)` | `user_id` (a seat's take: the teacher), `seat_id`, `line_id`, `part`, `file`, `content_type`, `bytes`, `frames`, `sample_rate`, `capture` (`direct`, `aec`, `room`), `heard`, `loudness`, `peak`, `created`, `uploaded_at`, `chosen` (one per line); no audio, no object key |
| `play_consents` | `(user_id, production_id, version)` | `consented_at` |
| `play_reports` | `id` | `user_id` (the reporter), `production_id`, `target_user_id` (cleared when that account goes), `take_id`, `reason`, `note`, `created_at`, `status` |
| `play_blocks` | `(user_id, blocked_id)` | `created_at` |
| `play_archive_jobs` | `production_id` | `user_id`, `status` (`queued`, `uploading`, `published`, `failed`), `take_ids`, `identifier`, `item_url`, `reason`, `attempts`, `next_attempt_at`, `lease_until`, `credits`, `published_at`, `created_at`, `updated_at` |
| `play_archive_files` | `(production_id, line_id)` | `seq`, `part`, `take_id`, `name`, `state` (`pending`, `sent`, `remove`, `removed`, `failed`), `stale_name`, `removed_by`, `reason`, `updated_at`; no person column |
| `play_classes` | `id` | `user_id` (the teacher), `name`, `code`, `under13`, `created_at` |
| `play_class_members` | `(class_id, user_id)` | `display_name`, `joined_at` |
| `play_school_consents` | `class_id` | `user_id` (the teacher who recorded it), `policy_version`, `reference`, `recorded_at` |
| `play_class_seats` | `(class_id, id)` | `label` (unique in the class, any case), `key_hash` (SHA-256 of the seat key; null while free), `claimed_at`, `created_at`; no person column |
| `play_assignments` | `(production_id, seq)` | `part`, `from_line`, `to_line`, `seat_id`; no person column |
| `play_reviews` | `(production_id, take_id)` | `state` (`approved`, `again`), `note`, `reviewed_at`; no person column |

No email, name, or address is stored, and no provider token. A person is a
provider and that provider's opaque `sub`. The two room tables, `read_rooms`,
`play_archive_files`, and the seat, assignment and review tables hold no person at all: no `user_id` and no column that
references `users`. `ANONYMOUS_TABLES` in `rooms.js`, `READ_ANONYMOUS_TABLES` in `read-rooms.js`, and
`PLAYS_ANONYMOUS_TABLES` in `plays.js` name them, and the deletion test fails
on a table that is in neither list nor `USER_TABLES`, or that gains a person
column. The display names on plays are the one name a person chooses to show,
and they are deleted with the account. The same person signing in with
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
| `SCHOOL_CONSENT_POLICY` | not set: the version of the privacy policy that covers school consent for students under 13. Until the owner sets it, no school consent can be recorded and no under-13 class takes a student |

Bindings: `DB` (D1); `READ_ROOMS` (the `ReadRoom` Durable Object, migration tag
`v1-read-rooms`, `new_sqlite_classes`; without it read rooms run on D1 polling);
and `TAKE_RELAY` (the `TakeRelay` Durable Object, migration tag `v2-take-relay`,
`new_sqlite_classes`, in memory only; without it no take passes through:
`uploads` is false and the inbox answers `503`). There is no R2 bucket: Decision
082 removed the take store (storage is archive.org).

A value starting `REPLACE_WITH` is never accepted as an audience, and a
provider with no real audience answers `503 not_configured` rather than
trusting anything.

Secrets, with `wrangler secret put` (never in git, never in `wrangler.toml`):

| Name | Meaning |
|---|---|
| `SESSION_SECRET` | signs access tokens; at least 32 characters (`openssl rand -base64 48`). Without it, sign-in answers `503` |
| `APPLE_PRIVATE_KEY` | the Sign in with Apple key (`.p8` contents), only for token revocation |
| `IA_S3_ACCESS_KEY`, `IA_S3_SECRET_KEY` | the Ear Drama archive.org account's S3 keys (archive.org/account/s3.php). Publish and the uploader stay closed until both are set |

Rate limits (`[[ratelimits]]`, Archive Watch's `limited()`; counts are kept
for the window only):

| Binding | Key | Limit |
|---|---|---|
| `EVERY_IP_LIMITER` | client address | 600 a minute, every route |
| `AUTH_LIMITER` | client address | 30 a minute, sign-in and refresh |
| `USER_LIMITER` | user id | 120 a minute, signed-in routes; per person so a classroom behind one school address is not one person |
| `ROOM_LIMITER` | client address | 300 a minute, every room route; a member polls about 30 times a minute, so this is a household |
| `ROOM_CREATE_LIMITER` | client address | 10 a minute, opening a room |
| `ROOM_JOIN_LIMITER` | client address | 20 a minute, joining; the floor under code guessing |
| `ROOM_MEMBER_LIMITER` | member id | 60 a minute, each member's own calls, so one device cannot use up a household's share |
| `PLAY_UPLOAD_LIMITER` | user id, or `seat:<class>:<seat>` | 30 a minute, take uploads |
| `PLAY_JOIN_LIMITER` | user id | 20 a minute, invite views and claims and class joins |
| `OPEN_READ_LIMITER` | client address | 60 a minute, an open invite's read and the finished listing, no account |
| `READ_IP_LIMITER` | client address | 3,000 a minute, every read room route, in place of `EVERY_IP_LIMITER` (a class of 40 polling once a second behind one school address) |
| `READ_JOIN_LIMITER` | client address | 60 a minute, joining a read room; a class's size, and the floor under code guessing |
| `READ_MEMBER_LIMITER` | member id | 120 a minute, each member's polls and messages, socket or HTTP |
| `READ_CREATE_LIMITER` | client address | 10 a minute, opening a read room |
| `SEAT_JOIN_LIMITER` | client address | 60 a minute, listing and claiming seats by class code; the floor under code guessing |
| `SEAT_LIMITER` | class and seat | 120 a minute, every call with a seat key |

Every five minutes (`*/5 * * * *`) the cron runs only the archive.org
uploader. The hourly one (`23 * * * *`) also deletes expired sessions, idle rooms, quiet
room members, rooms left with no member, idle polled read rooms, lapsed play claims, and expired
invites. A revoked session is
kept until it would have expired, because it is what recognizes a replayed
refresh token.

CORS: a request whose `Origin` is not allowed is refused with `403`, not just
denied the header. Smart-TV web packages send `Origin: null` and are refused
until a TV client signs in and the owner decides how they should.

## Tests

```sh
cd worker
npm ci
npm test                 # 378 tests in workerd with a local D1, local Durable Objects, and a fake archive.org
npm run test:mutations   # 247 deliberate breaks; every one must turn the suite red
node test/mutations.mjs --check              # every break still matches its source, nothing run
node test/mutations.mjs --only "name,name"   # just those, after fixing a survivor
node tools/castable-manifest.mjs             # after every rebuild of the castable scripts
```

The suite mints its own RSA keys and serves them in place of Apple's and
Google's key sets, so it needs no network and no real client id. It covers
forged, altered, expired, wrong-audience, wrong-issuer, `alg: none`, HS256
confusion, unknown-key, and wrong-nonce tokens; refresh rotation and replay;
last write wins, tombstones, clock clamping, `since`; the merge; deletion
leaving no row in any table; CORS; rate limits; and the sweep. For rooms:
create and join, a guest refused a state write, guests receiving the host's
copy, handoff when the host leaves or goes quiet, the last one out ending the
room, the size limit, idle expiry, the sweep, code randomness and
normalization, every room rate limit, the drift and clock rules, and that the
protocol file stays pure. For shared plays: the manifest matching the
catalog's castable file, and a production refused for an unknown script, an
old revision, or a cast sheet that is not the script's; the record's
production.json fields and its merge of every member's takes; members-only
reads; invites hashed, revoked, expiring, director-only, and blocked either
way; the relay order, claims while another records, the seven-day lapse and
its sweep, done, silent, reopen, and release; takes refused for a
non-claimant, another part's line, missing or stale consent, bleed, length,
size, a lying header, stereo, an unknown format, a reused id, and the eleventh
take of a line; the chosen take; reports and blocks hiding takes; the name
filter and its controls; publishing queued, the request making no network call; under-13
classes refused until a school consent exists, and that refused until the
policy is set; the rate limits; deletion's director handoff. Takes passing
through: a member's take reaching the waiting director byte for byte, refused
at once with nobody receiving, a cut body never delivered, a reused id refused
before any audio is read, the director's own take recorded and not relayed.
Seats and classes (`test/seats.test.js`): a pasted roster, the seat limit, a
seat key once and hashed, Move here, Release, class productions seen only by
their class, assignments and scene ranges, seats' takes passing through with
claims bypassed, one take in flight per seat, the under-13 refusal, review
notes shown to their seat alone, progress counts, the teacher's 13-and-over
publish under their own name with no seat's label on the item, limits by seat,
seat keys in class read rooms on both transports, and that no route, table, or
binding stores take audio. The uploader (`test/archive.test.js`) runs against
a fake archive.org that keeps every request: both keys or nothing; the cron
laying the item out with no request; one item with its metadata from data; one
file per line from the device, streamed whole, in script order, derived once;
check_limit before the first file; only the chosen take, from its director or
performer; a 503 SlowDown answered to the device with no line sent twice; a
refusal failing nothing; the cron's request budget, backoff, and giving up on
removals; the keys absent from every log, stored reason, and response; and
P12's replace, replace in another format, who may replace or remove, held
reports, the credits rewrite, a 404 on delete, and the job passing with the
production when the director's account goes. The scripts come from the castable file by their data,
never by name.
`.github/workflows/worker-test.yml` runs `npm test` on any change under
`worker/`. It has no Cloudflare credential and no deploy step.

## Needs Ben

Each of these is the owner's, in this order. The repository cannot show which are done.

1. **Cloudflare account**: use the account Archive Watch's Worker runs on, or
   a new one. `cd worker && npx wrangler login`.
2. **Create the database**: `npx wrangler d1 create eardrama`, then put the
   printed `database_id` in `worker/wrangler.toml` (an id is not a secret).
3. **Apply the schema**: `npx wrangler d1 migrations apply eardrama --remote`
   (the migrations: accounts, rooms, plays, the archive.org uploader,
   take-downs, read rooms, and seats with pass-through takes).
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
   sends, and nothing else; deleted at once on request. Listen Together rooms
   store what an episode is doing and an anonymous member key's hash, no
   account or address, deleted when the room ends or after six idle hours.
   Shared plays store each take's fields (never its audio, which passes
   through to the director's device), the display name a person chooses,
   their consent, reports and blocks they make, class membership, and a
   class's seat names, casting and the teacher's review notes; all deleted
   with the account (a class's with its teacher's).
10. **Shared plays (M8)**, each listed with its default in
    `docs/PLAYS-DESIGN.md` §11.6 (R2 is no longer a question: Decision 082);
    approve the CC0 consent words and give them a new `CONSENT_VERSION`; replace
    the seed deny list in `plays-names.js` with a vetted one; decide how
    reports reach you and how fast they are answered (guideline 1.2); set
    `SCHOOL_CONSENT_POLICY` once the privacy policy covers school consent; and
    put the Ear Drama archive.org keys in with
    `npx wrangler secret put IA_S3_ACCESS_KEY` and `... IA_S3_SECRET_KEY`,
    apply `0004_archive_uploader.sql`, and deploy; the first publish then
    makes the item.
