# The release choreography for in-app purchases across stores

Launching one paid tier on Apple + Play + Microsoft simultaneously is a
COORDINATION problem before it is a code problem. Every rule below is a
lesson a real multi-store IAP launch paid for (Tidbits Club, 2026: three
products on four store fronts). The per-store API traps live in Decision 039;
the client-side empty-products diagnosis lives in `IAP-TROUBLESHOOTING.md`.
This doc is the sequencing.

## The critical path is financial, and it is OWNER-ONLY

Nothing returns products until the money paperwork is done, and it fails
silently. The store answers success with zero products, which looks exactly
like a broken client:

- **Apple**: the Paid Applications agreement (Agreements, Tax, and Banking)
  must be Active. Until then, App Store Connect returns NOTHING for every
  product of every app on the account.
- **Play**: a payments profile must be linked before products activate.
- **Microsoft**: the payout + tax profile lives under gear → Account settings
  and is visible ONLY to the account-owner identity. It does not exist in
  the UI for the CI/Entra identity, so an agent cannot even see whether it's
  done. Paid add-ons will not certify without it.

Put these at the TOP of the OWNER list at the start of the monetization
phase, not when the paywall renders empty.

## Rule 1: An IAP product rides in exactly ONE review submission

On Apple, a new in-app purchase / subscription attaches to a specific app
review submission, and it can be attached to only one at a time. If iOS,
macOS, and tvOS submissions are all in flight, the products ride ONE of
them. The other platforms' reviews see an app referencing products that
are not in their submission, and either starve (products never approve for
that platform) or bounce.

**Ship serially until the products are approved once**: submit the platform
that carries the products, wait for approval (products go Approved
account-wide), then submit the remaining platforms. After that first
approval, parallel submissions are fine again.

## Rule 2: "Ready to Submit" means it was NEVER submitted

A product state of *Ready to Submit* is not a queue position; it means the
product has never been attached to any submission. The check that tells the
truth is the review submission's ITEM LIST (App Store Connect → the
submission → items), not the product's state page. A launch shipped with
the app approved and the products still sitting in Ready to Submit
(because nothing ever attached them) renders a paywall with zero products
in production.

Before submitting an IAP-bearing release: open the submission, confirm the
products are listed as items IN it.

## Rule 3: Per-platform settings exist; verify every platform separately

App Store Connect settings you'd assume are app-wide can be per-platform.
The License Agreement (standard EULA vs custom) is set PER PLATFORM. Set it
on iOS, leave it unset on macOS/tvOS, and the non-iOS submissions carry the wrong
terms. After changing any listing-level setting for a subscription launch,
walk EACH platform's page and confirm it took.

## Rule 4: The store's empty answer has two different meanings

`products(for:)` (and its Play/Windows equivalents) fails two ways: the
call THROWS (connectivity/entitlement: the client's problem), or it
SUCCEEDS WITH AN EMPTY LIST (the store answered; the account/product state
is the problem). The paywall must render these differently and log which
one happened, or every backend-side cause gets debugged as a client bug.
Full diagnosis tree: `IAP-TROUBLESHOOTING.md`. Retry the empty case on a
cold launch. App Review hit a cold-start empty that a single retry with
backoff fixed (a real rejection).

## Rule 5: The query layer is per-store; the entitlement model is shared

Decision 039 in full. Play Billing: one query PER product type (mixed
INAPP+SUBS throws, main-thread, only on a real Play-provisioned device).
Microsoft: ONE query for everything (`GetAssociatedStoreProductsAsync`; a
subscription is a `Durable` add-on, so filtering by a "subscription" kind
returns nothing, silently). Apple: one `products(for:)` with all ids. Write
each from that store's docs; never port a sibling's shape.

Shared across all of them: the entitlement gate FAILS OPEN (a plumbing
error can never lock out a paying customer), and every store's product ids
are verified by reading them back from the store's own API, not by
trusting the constants in the code (`docs/windows/workflows/windows-store-addons.yml` is the
Windows read-back; `asc` API listing works for Apple; Play's console for
Android; no Play API lists them cleanly either).

## Rule 6: Purchases are only testable on each store's REAL provisioning path

Every store has a gap no local run can cross:

| Store | Local run shows | Only the real path shows |
|---|---|---|
| Apple | Xcode StoreKit config (scheme-attached; TestFlight and home-screen launches bypass it) | TestFlight/production against real ASC state |
| Play | Emulators cannot see Play Billing AT ALL | A physical Play-provisioned device (Firebase Test Lab works: `tools/testlab-android.sh`) |
| Microsoft | `StoreContext` refuses unpackaged processes; CI has no Store identity | The certified MSIX installed FROM the Store |

Plan an owner verification pass on each store's real path after each
platform's release goes live. It is the last unverifiable-from-CI step,
every time.

## Rule 7: Deletion must cover the paid state too

Account deletion (a review requirement, Decision 035) interacts with IAP:
deleting an account must not orphan a paid entitlement silently, and the
deletion must be verified by READING THE RECORD BACK (a backend "delete"
that writes null can be a no-op that review catches). The anonymous
account holds entitlements too.

## The launch-order checklist

1. OWNER: financial agreements on every store (top of the phase).
2. Products created on every store; ids identical where the stores allow.
3. Client queries written per-store (Rule 5), gated fail-open.
4. Read-back verification of ids from each store's API.
5. Apple: attach products to ONE platform's submission; ship it; wait.
6. Remaining Apple platforms + Play + Microsoft, serially or parallel per
   Rule 1; per-platform settings walked (Rule 3).
7. Owner purchase-verification on each real provisioning path (Rule 6).
8. PARITY.md: the paywall, the entitlement gate, AND the restore/manage
   surface each get a row per platform.
