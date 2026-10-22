---
name: per-ecosystem-sync-islands
description: "Use when adding sync of user state (favorites, progress, playlists, preferences) across devices, when adding sign-in, or when tempted to stand up a sync backend. Carries the sync-islands architecture (CloudKit private DB for Apple, Google Drive App Data for Android+Web — the user's own cloud, no server to run), the query-free CloudKit record pattern that replaced a never-worked CKQuery design, tombstones + last-writer-wins merge, optional sign-in gating only sync, and user-visible sync status. Also the web bridging both islands (CloudKit JS + Drive, one merge, tombstones both ways, per-environment CloudKit JS tokens). Triggers on CloudKit, sync, iCloud, Drive App Data, sign in with Apple, sign in with Google, favorites sync, cross-device, \"needs a backend\", tombstone, last writer wins, CloudKit JS, web sign in with Apple, Android OAuth client SHA-1."
---

# Per-Ecosystem Sync Islands

Sync user state per ecosystem, each island on the **user's own free
cloud**. No custom backend — nothing to provision, pay for, secure,
or operate — and the developer never sees the data. Production-
verified (iPhone ↔ Apple TV households).

## The architecture

There are exactly TWO islands (Apple/CloudKit and Android+Web/Drive
App Data) — adding a platform never adds a third island; it joins an
existing one.

| Island | Mechanism | Server to run |
|---|---|---|
| **Apple** (iOS + iPadOS + macOS + tvOS) | CloudKit **private database** (the user's iCloud) | none |
| **Android** | Google Drive **App Data folder** (Sign in with Google + Credential Manager, `drive.appdata` scope) | none |
| **Web** | the SAME Drive App Data folder, via Google Identity Services token + Drive REST from the static site | none — just a public OAuth client ID |

- Drive App Data is the exact analog of CloudKit's private DB: a
  hidden, per-app folder in the user's own account.
- Web + Android sharing one Drive folder means a user signed into
  the same Google account converges across them for free — a bonus,
  not a backend. Namespace per platform only if isolation is wanted.
- **No cross-ecosystem sync between NATIVE apps.** Apple syncs with
  Apple, Google with Google. Accept the asymmetry; record it in
  PARITY.md. A neutral backend is the explicitly-rejected alternative
  (unneeded complexity for personal-state payloads). The one exception
  is a client, not a server: the web can sign in to BOTH islands (see
  "The web bridges the islands").

## The non-negotiables

1. **Local-first.** SwiftData / Room+DataStore / IndexedDB is the
   source of truth on-device; the cloud is an upsert/merge mirror.
   Everything works offline.
2. **Sign-in is optional and gates ONLY sync.** Browse, play, save —
   all work signed-out. The sign-in button lives in Settings →
   Account, not in front of any content verb.
3. **Sync status is user-visible, never silent.** A "Last sync /
   last error / Sync Now" row in Settings. The original production
   sync was broken for WEEKS because every pull failed inside a
   silent `catch` — devices pushed but never converged, and nothing
   surfaced it. Observable state (`@Observable` sync service) is
   what made it debuggable.
4. **Account deletion** must exist once sign-in exists (App Store +
   Play requirement): delete all cloud data + sign out.
5. **People's data outlives the owner's interest.** Offer an export of
   everything a person made (favorites, lists, progress) in a form they
   can read without the app (JSON or CSV), and state on the website what
   happens to their data if the app stops being maintained. Data in the
   person's own iCloud / Drive is most of this promise; the export and
   the sentence are the rest.

## The CloudKit pattern that actually works

**Never use `CKQuery` for whole-store pulls.** `CKQuery` with
`NSPredicate(value: true)` requires a queryable index on
`recordName` that CloudKit never auto-creates — every pull fails
with "recordName is not marked queryable," and if your error
handling is quiet, it fails invisibly forever.

Use **fixed-ID records fetched directly** instead:

- One record type (e.g. `AppSync`), a small fixed set of record IDs
  (`tombstones`, `favorites`, `playlists`, `progress`), each holding
  a JSON blob payload.
- Pull = `fetch(withRecordIDs:)` — no queries, no indexes, no schema
  surprises.
- Push = save the changed records (server-record-changed → refetch,
  merge, retry).
- Adding a new synced data type = a new key inside an existing blob
  or one more fixed record — **no schema deploy**.

Merge semantics (same model on Drive App Data — store one JSON file
and merge the same way):

- **Tombstones for deletions**: a removed favorite writes a
  tombstone (id + deletedAt); merge = union of favorites MINUS live
  tombstones; a re-add newer than its tombstone clears it. Without
  tombstones, deletions resurrect on every pull.
- **Last-writer-wins by `modifiedAt`** for structured records
  (playlists, progress) — per record, not per store.
- **Union** for grow-only sets.

Sync triggers: app foreground + debounced after local edits + a slow
timer (e.g. 60s) while active. Push notifications/subscriptions are
an optimization, not the spine.

## Operational gotchas (each cost real time)

- **Deploy the CloudKit schema to Production** before TestFlight/
  App Review builds — the Development environment only serves
  development-signed builds. Symptom of forgetting: sync works from
  Xcode, silently fails for TestFlight users.
- **Don't mix environments when testing cross-device**: two devices
  must run same-channel builds (both dev or both prod).
- The CloudKit container ID is shared across the universal target —
  one container = free iPhone ↔ Apple TV ↔ Mac sync. macOS joins the
  Apple island for free by pointing at the SAME iCloud container; it
  is NOT a new island and needs no new sync code. Don't create
  per-platform containers.
- Sign in with Apple on tvOS: use the UIKit
  `ASAuthorizationController` path; test the button's legibility —
  an unreadable sign-in button means users never sign in and you'll
  chase "sync doesn't work" for a week (real incident).
- Gate the whole service behind a single
  `entitlementConfigured`-style flag (default false) so simulator
  builds stay green before the human adds capabilities in Xcode —
  capability-gated features can live in the tree without breaking
  anyone.

## The web bridges the islands

The browser is the one client that can hold both clouds (Archive
Watch, Decision 102, verified on hardware):

- **Apple island from the web:** Apple's CloudKit JS signs the viewer
  in with Apple and reads/writes the SAME container, record type and
  fixed-ID blobs the Apple apps use. No server of ours, no Apple
  secret in the page; the API token is public by design.
- **Google island from the web:** the same Drive App Data file
  Android uses.
- **One merge function** (one JS module) applied to both, so a browser
  signed into both is where the islands converge. Tombstones travel
  BOTH ways; a store that union-merges without them resurrects every
  deletion. Grep every sync client's header for "tombstones not yet"
  style TODOs; AW's Android + web had inherited the pre-tombstone
  design.
- Two buttons, not one: a viewer in one ecosystem sees one button do
  everything they need.

Traps:

- **A CloudKit JS API token belongs to ONE environment.** The iCloud
  dashboard opens on Development by default; the web client configures
  `production` (matching the shipped apps' deployed schema). A
  Development token renders the Sign in with Apple button and fails
  every request. Also: allow Sign in with Apple on the token and set
  its allowed origins (add localhost only for local testing).
- **A feature gated on a credential nobody has is never tested.** AW's
  Drive sync sat dormant for months behind a missing OAuth client; when
  switched on, it dropped the consent `PendingIntent` Google returns on
  EVERY first authorization, so the one path every user takes was the
  untested one. Before calling a dormant feature done, drive its
  first-run path with a real credential on a real device.
- **An Android OAuth client is keyed on package + ONE signing
  certificate.** Register the Play app-signing key, the upload key, and
  the debug package/key separately. Missing the Play signing one fails
  only in production. Google allows a package + SHA-1 pair in only one
  Cloud project, so decide which project owns Android before adding a
  second scope.
- **Keep `drive.appdata` the only scope**: it is non-sensitive, so the
  consent screen needs no verification and has no 100-user cap. Adding a
  sensitive scope to that project changes both.
- **Exclude the merge's own writes from the sync trigger**, or applying
  a pull schedules the next push forever.

Sign-in flows themselves (PKCE vs Device Code, redirect scheme,
refresh-token persistence, the missing-credential state): see
`authentication` "Installed-app OAuth to third-party providers".
