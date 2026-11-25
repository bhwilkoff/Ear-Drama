# DRAFT: Ear Drama data inventory

**DRAFT record (R3d, 2026-11-21; revised the same day for Decision 084). Read from the code, not from
intentions.** "Proposed" rows below are now built unless marked not built. Every field Ear Drama's server (the Worker,
`worker/`) or apps keep that could describe a person, where it lives, why it
exists, and how long it stays. The retention column says what the code does
today; where a draft rule in `retention-policy-draft.md` would change it, the
change is marked **Proposed**.

Sources: `worker/migrations/0001` to `0009`, `worker/src/account.js`
(`USER_TABLES`, `OTHER_PERSON_COLUMNS`), `worker/src/auth.js`, `plays.js`,
`plays-seats.js`, `read-rooms.js`, `take-relay.js`, `takedown.js`,
`plays-archive.js`, `docs/WORKER.md`, `docs/EXPORT.md`, `privacy/index.html`.

Legend for **Who**: A = a signed-in adult (or teen 13+); T = a teacher
(always signed in); S = a student seat (no account); R = an anonymous reader
in a read room or Listen Together; X = a take-down requester.

## 1. On the Worker (Cloudflare D1, server side)

### 1.1 Accounts and sync (Decision 057)

| Table.column | Who | What it holds | Why | How long (today) |
|---|---|---|---|---|
| `users.id`, `created_at`, `seen_at`, `idle_notice_at` | A, T | A random id of ours, never a provider's id; when made; the last sign-in or refresh; an idle notice | To own synced rows; the 3-year idle rule | Until the person deletes the account (`DELETE /v1/account`), or 3 idle years after a 30-day notice |
| `identities.provider`, `subject` | A, T | "apple" or "google", and that provider's opaque account number (`sub`) | To recognize the same person at next sign-in | Until account deletion |
| `sessions.token_hash`, `family`, `device`, `created_at`, `expires_at`, `revoked` | A, T | SHA-256 of a refresh token; device kind ("web", "iphone", "ipad"; never a device's name) | To keep a person signed in; detect a stolen token | 60 days per session (`REFRESH_TTL_MS`); swept hourly after expiry (`sweepSessions`) |
| `history.*` | A, T | Episode id, where they stopped, duration, finished, device kind, timestamps | Cross-device sync | Until removed by the person, or account deletion. **Proposed:** no change (the person's own data) |
| `follows.*` | A, T | Followed series ids | Sync | Same |
| `queue`, `queue_meta` | A, T | Ordered episode ids | Sync | Same |

Not stored: name, email, photo, birth date, address, the provider's tokens.
Sign in with Apple's "Hide My Email" address and Google's email arrive inside
the identity token and are not written anywhere (`auth.js`; privacy page).

### 1.2 Listen Together rooms (D1, web and Android)

| Table.column | Who | What | Why | How long |
|---|---|---|---|---|
| `rooms.*` | R | Episode, file, position, playing, speed; no person | Shared playback | Deleted within the hour after 6 idle hours or when empty |
| `room_members.id`, `key_hash`, `joined_at`, `seen_at` | R | A random id and the hash of a random key | Membership | Gone 2 minutes after last heard; deleted within the hour |

### 1.3 Read rooms (Durable Object storage, or D1 `read_rooms` fallback)

| Field | Who | What | Why | How long |
|---|---|---|---|---|
| Room state: cast sheet, cursor, mode, members (random id, key hash, role, part held) | R, S, T | Place in a script; who holds which part | The shared cursor | Durable Object: `deleteAll()` on end or after 6 idle hours (`ROOM_IDLE_MS`); an ended room keeps only `ended_at` for 6 hours. D1 fallback: swept hourly after 6 idle hours |
| `members[].name` (adult rooms), `leader_name`, seat labels | R, T, S | A name a reader typed on joining (40 characters, name filter), or a seat's label | "Waiting for Ana"; credit | Same as the room |
| `read_room_objects.*` | none | A room's code and when to look at it next | The sweep that erases a room whose alarm was lost | Until the room's object holds nothing |
| `read_pairs.*` | none | TV pairing code, hash of the TV's key | Pair a TV | 10 minutes, used once, swept hourly |

No audio is written to a Durable Object, KV, or D1. A take in transit through
`TakeRelay` is held in memory only (at most a 64 KiB head and the chunk in
the pipe; `take-relay.js`).

### 1.4 Shared plays and classes (Decisions 059, 066, 082, 083)

| Table.column | Who | What | Why | How long (today) |
|---|---|---|---|---|
| `play_productions.*` | A, T | Director's user id, script id and revision, title (from our manifest), cast sheet, `class_id` | A production | Until the director deletes it (`DELETE /productions/:id`, before it is submitted) or the director's account is deleted (then passed on or deleted, WORKER.md "Account deletion"); a class production goes with its class unless submitted |
| `play_members.display_name`, `joined_at` | A | A chosen name (name filter, 40 characters, may be empty) | Credits; who is in it | Until the person leaves or deletes the account |
| `play_invites.token_hash`, `expires_at` | A | Hash of an invite token | Invite links | 1 to 30 days, then kept 30 days to answer "expired", then swept |
| `play_parts.*` | A, T | Who claimed a part, status | The relay | A claim lapses after 7 days; rows go with the production |
| `play_takes.*` (no audio) | A, T, S, R | Take fields: line, part, file name, format, bytes, frames, sample rate, `capture`, `heard`, loudness, peak, created; `user_id` (for a seat's take, the teacher's); `seat_id`; `credit` (an anonymous adult reader's typed name) | Review, progress, publishing | Until the production or account is deleted, or with the class; a submitted production keeps its takes' fields without `seat_id` |
| `play_consents.*` | A | User id, production, consent text version, time | Proof of each performer's CC0 consent | Until account deletion |
| `play_reports.*` | A | Reporter, production, target user, take, reason, note (500 characters) | App Store guideline 1.2 | Reporter's row goes with the reporter's account; target is cleared (anonymous) when the target's account goes; otherwise kept. **Proposed:** close-out and a time limit (retention draft §4) |
| `play_blocks.*` | A | Who blocked whom | Safety | Until either account is deleted |
| `play_archive_jobs.*`, `play_archive_files.*` | A, T | Upload state, archive.org identifier and URL, credits text, file names; for a class, when the teacher confirmed every performer agreed and the school's media release | Publishing to archive.org (13 and over only) | Kept while the item exists (the owner's ruling keeps the ear drama); the published item itself is on archive.org and public |

### 1.5 Classes and seats (Decision 082)

| Table.column | Who | What | Why | How long (today) |
|---|---|---|---|---|
| `play_classes.name`, `code`, `under13`, `created_at` | T | The class's name as the teacher typed it, a join code, the under-13 flag | Running a class | Until Delete class, the end date (`ends_on`, default July 31; `touched_at`, `notice_at` for the idle rule), 12 months idle after a 30-day notice, a school's request, or the teacher's account deletion |
| `play_class_members.display_name` | A | A signed-in member's chosen name (older path: joining a class with an account) | Roster | Until removed by the teacher or account deletion |
| `play_class_seats.label` | S | **A name the teacher typed** (a first name, nickname, or "Group 3") | The student picks their name | Until the teacher removes the seat or the class goes |
| `play_class_seats.key_hash`, `claimed_at` | S | SHA-256 of the seat key; when claimed | One device holds a seat | Cleared when the teacher releases the seat |
| `play_assignments.*` | S | Which seat reads which part | Casting | With the production |
| `play_reviews.state`, `note` | T, S | Approve or Again, and **a typed note from the teacher to one student** | Teacher feedback | With the production or the class; on a submitted production, deleted when the class goes |
| `play_school_consents.policy_version`, `reference`, `recorded_at` | T | That a teacher recorded school authorization for an under-13 class, against which policy version; optional school name or agreement number | COPPA school authorization | With the class. `reference` is required (FTC FAQ N.3). No row can be written until `SCHOOL_CONSENT_POLICY` is set at deploy |

### 1.6 Take-downs (Decision 074)

| Table.column | Who | What | Why | How long |
|---|---|---|---|---|
| `takedown_cases.name`, `org`, `email`, `phone`, `address`, `signature` | X | Requester's details | Answer the request; DMCA | Blanked 3 years after the case closes (`RETAIN_MS`, `sweepTakedowns`); the case's outcome stays without a name |

### 1.7 Things the Worker sees but does not keep

| What | Where | How long |
|---|---|---|
| IP address | Cloudflare rate-limit bindings count requests per address per minute | Not stored by us; the counter lasts the minute. Cloudflare's own handling is under its terms |
| Take audio | `TakeRelay` memory, in flight | Only while it moves; never written |
| Worker logs | `console.log` in four places: archive job progress (production id), a redacted error, uncaught errors, `[readdiag]` (local dev only) | `wrangler.toml` has no `[observability]` block, so logs are not persisted by us; live tail only. **To verify in the Cloudflare dashboard (owner).** |

### 1.8 The age question

Not on the Worker: only "under 13 or not" is kept on the device (web `localStorage` `ed.over13`, Apple
`UserDefaults`, Android preferences) and never sent (PLAYS-DESIGN §12.12 item 8).

## 2. On devices (never sent to Ear Drama unless noted)

| What | Platform | Where | How long |
|---|---|---|---|
| History, queue, follows, speed | All | Browser local storage; app storage | Until cleared |
| Plays recorded on the device: every take and the mix | Web, iOS, iPadOS, macOS, Android | IndexedDB; app storage | Until the person deletes them |
| A class's takes, received on the teacher's device | Teacher's device | Same | **Until the teacher deletes them; this is where student voices live.** |
| A student's own takes on the device that recorded them | Student's device (often a shared school device) | Same | Until deleted on that device. (Shared-device clearing, R3d D5, is not built: the owner's Q6) |
| Seat key | Web: per tab; Apple, Android: memory only in a room (082c); Keychain or Keystore only when a student records at home (083) | | Tab or app run; home relay: until sent |
| Scripts a person added or cast by ear, each with the text as pasted, the text being added, and for one cast by ear its episode and place (Decision 088.3) | Web (Apple and Android with R4-6 and R4-7) | IndexedDB; app storage | Until the person deletes them (the text being added: until it becomes a script or is emptied); in the person's own export; never sent |
| Sign-in session | Web: local storage and IndexedDB, encrypted; Apple: Keychain; Android: Keystore-held key | | Until sign-out or deletion |
| Script marks and Pencil ink | Web, Apple, Android (ink: Apple) | Device | Until deleted; in the person's own export |
| Synthetic stand-in voices (Kokoro model) | Downloaded model only | Device | The model is kept; a stand-in's audio is never stored (Decision 055) |

## 3. Other companies that receive requests

| Company | What they receive | When |
|---|---|---|
| Cloudflare | Every Worker request (IP, the request) | Sign-in, sync, rooms, plays, classes, take-downs |
| GitHub (Pages, Releases) | Page and catalog requests (IP) | Opening the website; apps refreshing the catalog and downloading the Kokoro model |
| Internet Archive | Audio requests (IP); published recordings and their credits | Listening; a teacher or performer publishing |
| Wikimedia Commons, Library of Congress, Smithsonian | Image requests (IP) | Pictures of shows and people |
| Apple, Google | Sign-in (their own terms) | Only when a person chooses to sign in |
| Google Cast | The receiver framework | Only on a TV receiver page (`cast/`) |

None of them receives a student's name, a seat, or a take from Ear Drama,
except the Internet Archive for a 13-and-over class recording the teacher
publishes.
