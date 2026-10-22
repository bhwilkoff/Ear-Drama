# CloudKit and Sign in with Apple setup

I want a person's favorites, playlists and progress to follow them from
one Apple device to the next, stored in their own iCloud account where
we never see it. Decision 015 (per-ecosystem sync on the user's own
cloud) is the rule. This runbook is the one-time setup that makes it
real, plus the checks that prove it works.

In Archive Watch, where this lesson was learned, the first version never worked.
It stored one CKRecord per favorite and pulled with
`CKQuery(predicate: NSPredicate(value: true))`. That query needs a
queryable index on `recordName`, which CloudKit never creates on its own.
Every pull failed ("recordName is not marked queryable"), a silent
`catch` hid it, pushes worked, pulls returned nothing, and devices never
converged.

Fixed-ID records fetched by ID. No queries, no indexes.

## The shape that works

- One record type (for example `AppSync`) with a few FIXED record IDs:
  `tombstones`, `favorites`, `playlists`, `progress`. Each holds a JSON
  payload.
- Fetch those records directly by record ID. Merge semantics stay the
  same as a per-row design.
- Surface sync errors in Settings, Account: a "Last sync" line, the
  error text when there is one, and a Sync Now button. A sync failure
  that only reaches the console is a sync failure nobody fixes.

The cost: a whole collection is one record, so very large libraries
eventually need to split into more fixed IDs. For personal-scale data
(a few hundred saved items) one record per collection is fine.

## Owner step: deploy the schema to Production

TestFlight and App Store builds talk to the PRODUCTION CloudKit
environment, which never auto-creates record types. Only
Xcode-run Development builds create them, just in time.

1. Run any development build once while signed in to iCloud, so the
   record types exist in Development.
2. CloudKit Dashboard (icloud.developer.apple.com), container
   `iCloud.com.example.appname`, Schema, **Deploy Schema Changes...** to
   Production.

Until this is done, every TestFlight build shows a schema or container
error under Settings, Account.

An Xcode-installed device build (Development) and a TestFlight build
(Production) live in DIFFERENT environments and never see each other's
data. Test cross-device sync with two builds from the same channel.

## Step 1: capabilities

In Xcode, target `AppName`, Signing & Capabilities:

- **+ Capability, Sign in with Apple.**
- **+ Capability, iCloud**, check **CloudKit**, add the container
  `iCloud.com.example.appname`. It must match the container ID constant
  in your sync service (you create this, for example
  `apple/Core/Sync/CloudKitSyncService.swift`) AND the container in
  `AppName.entitlements`. A container ID that differs between code and
  entitlements is the classic reason sync silently does nothing.
- These also need enabling on the App ID in the Apple Developer portal.
  Xcode's automatic signing usually does this.

## Step 2: the entitlement gate

Ship the sync code gated off (a constant such as
`CloudSync.entitlementConfigured = false`) until Step 1 is done.
Touching `CKContainer` without the entitlement traps at launch, so the
gate keeps simulator and unsigned builds clean. With the gate off, Sign
in with Apple still works in the UI but every CloudKit call no-ops,
which looks exactly like "saved data isn't syncing."

Flip the gate to `true` once the capability is provisioned. If a device
build then **crashes on launch**, the iCloud (CloudKit) capability and
container are not on the App ID. Finish Step 1 and rebuild.

## What sync does

- Two-way sync on launch, after sign-in, on every foreground, after
  each edit (debounced about 2 seconds), and on a 60-second timer while
  active.
- Favorites merge as a union. Playlists merge last-writer-wins by
  `modifiedAt`, so removals propagate. Progress merges last-writer-wins
  by `lastWatchedAt`.
- Deletions propagate through tombstones. Removing a favorite or
  editing a playlist writes a tombstone that syncs everywhere, so a
  deletion beats a stale cloud copy instead of resurrecting. A re-add
  newer than the tombstone clears it.
- Not yet: APNs push subscriptions for instant sync while both devices
  sit idle. The timer and foreground sync cover the realistic flow.
  `CKDatabaseSubscription` plus the remote-notification background mode
  is the next step when you want it.

## Device test checklist

Two devices on the SAME iCloud account, both signed in through
Settings, Account, both from the same build channel:

1. **Add.** Favorite an item on device A. Within about a minute (or on
   foregrounding B) it appears in Library on device B.
2. **Delete.** Un-favorite it on A. It disappears on B and does NOT come
   back. Same for removing an item from a playlist.
3. **Re-add wins.** Favorite it again on A. It reappears on B and stays.
4. **Progress.** Watch or read for a few minutes on A. The resume point
   shows on B.
5. CloudKit Dashboard, private database, shows the tombstone payload
   after a delete.

## Why this shape

Sign-in is Apple-native only and optional. It gates nothing but sync
itself, and the data lives in the person's own private CloudKit
database. See Decision 015, the `per-ecosystem-sync-islands` skill, and
§10.2 of `docs/templates/TVOS-DESIGN-template.md`.

Run the checklist on two real devices before you call it done.
