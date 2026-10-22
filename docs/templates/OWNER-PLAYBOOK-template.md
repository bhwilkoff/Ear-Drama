# [APP NAME] owner playbook

<!-- Seed for docs/OWNER-PLAYBOOK.md (you create it from this file when
     the first store launch is in sight). The agent keeps it current;
     the owner reads it.

     Learned in Tidbits Trivia's six-platform launch (2026). Its first
     owner playbook listed 90 minutes of owner work. A few hours later
     it was 20, because most of the items had been filed with the owner
     by mistake: a rules deploy the agent's own authenticated CLI could
     run, a key pair the agent could generate, a product decision an
     existing rule already answered, and three items that were already
     done. This template exists so that list starts short.

     Replace every [FILL IN] and delete the FILL notes. -->

I want the owner's time spent only on what a person has to do.

A launch touches six consoles, three payment processors and a dozen
secrets. Almost all of it is work the agent can do from the command
line: create the version, upload the build, set the metadata, submit
for review, promote the track, deploy the rules, generate the keys.
What is left over is small and specific. It is the part where a store,
a bank or a law needs a human being to be the one who said yes.

**The owner's list is short, and everything else is the agent's.**

---

## The split

| Only the owner can do it | The agent does it from the CLI |
|---|---|
| Create and pay for developer accounts (Apple Developer Program, Play Console, Microsoft Partner Center, Samsung, LG) | Create the App Store version, upload the build, submit for review (`docs/APPLE-SUBMISSION-CLI.md`) |
| Sign agreements and accept updated terms (Paid Apps, Play Developer Distribution, Partner Center) | Promote a tested Play build to production (`tools/play_promote.py`, `docs/store/play-api-key-setup.md`) |
| Banking, tax forms, and a merchant-of-record application | Submit the Windows MSIX (`docs/windows/WINDOWS-STORE-SUBMISSION.md`) |
| Answer the privacy questionnaires (App Privacy, Play Data safety) truthfully | Write listing copy, keywords, and release notes |
| Make declarations a console demands a person make (content rating, export compliance, government or news apps, ads) | Generate screenshots (`docs/store/STORE-SCREENSHOTS.md`) |
| Record a demo video when a reviewer asks for one | Create IAP products, prices and localizations through the store APIs |
| Create a key or secret that only a dashboard can issue, and paste it where the agent says | Deploy backend rules, generate key pairs, set repo secrets it can create itself |
| Make a product decision no existing rule answers | Read every console's live state and keep this page true |

**The full ship is CLI.** The agent never asks the owner to press
Submit for Review or Promote. If a step looks like it needs a person,
the agent checks whether the store API or an authenticated CLI on the
machine can do it before filing it here. An item on the owner's list
that the agent could have done costs the owner an hour of attention.
That is the most common mistake this page makes.

And the cost of the split is real. The agent's CLI access means it
holds live credentials for every store. So the owner creates the keys,
scopes them to what the pipeline needs, and can revoke them in one
place ([FILL IN: where the revocation list lives]).

---

## How each owner item is written

Every item says three things:

1. **What it is**, in one sentence.
2. **Exactly where it lives**: the console, the menu path, the field.
3. **What stays broken until it is done.** This is the line that
   matters. It lets the owner order the list by consequence.

Tag each item with one of these:

| Tag | Meaning |
|---|---|
| `[KEY]` | A key or secret. The owner creates it and pastes it. The agent never sees the dashboard it came from. |
| `[MONEY]` | Financial or legal. Only the owner can sign it. |
| `[DECIDE]` | A product decision. It changes what gets built, so nothing has been. |
| `[WAIT]` | Waiting on an outside party. Nobody here can speed it up. |

---

## Launch status

<!-- FILL: the agent rewrites this table from each store's own console
     or API on every pass. Never from memory, and never from the last
     version of this page. -->

Read from each store's console on [FILL IN: date].

| Platform | Version | State (from the console) |
|---|---|---|
| Web | (continuous) | [FILL IN] |
| iOS / iPadOS | [FILL IN] | [FILL IN: e.g. WAITING_FOR_REVIEW] |
| macOS | [FILL IN] | [FILL IN] |
| tvOS | [FILL IN] | [FILL IN] |
| Android | [FILL IN] | [FILL IN: track and rollout] |
| Windows | [FILL IN] | [FILL IN] |

**Docs drift. Consoles do not.** Tidbits Trivia's playbook once said
the Windows build was "in certification" while Partner Center said it
was live. Every state on this page is read back from the store, the
API, or the live endpoint before it is written.

---

## Outstanding owner items

<!-- FILL: order by what unblocks what. Keep the count in the heading
     honest ("exactly two"). Move finished items to "Already done"
     with the date and how it was verified. -->

### [FILL IN: item] `[TAG]`

- **What:** [FILL IN]
- **Where:** [FILL IN: console > menu > field]
- **Broken until done:** [FILL IN]
- **How the agent verifies it:** [FILL IN: the command whose output
  changes when it is done]

---

## Owner decisions

<!-- FILL: before anything lands here, the agent re-reads DECISIONS.md
     and the binding design docs. An unapplied rule is the most
     expensive kind of blocker, because nobody re-reads the rule. When
     a rule already answers the question, the agent applies it, logs
     the decision, and moves the item to "Already done". -->

### [FILL IN: question] `[DECIDE]`

- **The choice:** [FILL IN]
- **What each answer builds:** [FILL IN]
- **The agent's recommendation and why:** [FILL IN]

---

## Already done (do not redo)

<!-- FILL: each line says what, when, and how it was verified (read
     back from the API, not inferred). This section is what stops the
     next pass from redoing finished work. -->

- [FILL IN]

---

## Lessons that came with the launch

These are the traps that turned into owner items, or looked like
owner items and were not. Most are one-time setups. Each one cost real
time on a real launch.

### Consoles and review

- **Do not re-cut a version while the others are in review.** Bumping
  the version to add one platform pulls every in-review build back out
  of the queue to change a number. Bring the lagging platform up to
  the in-review version instead.
- **An in-app purchase rides in exactly one review submission.**
  Attaching products to a version that is already `WAITING_FOR_REVIEW`
  pulls it out of the queue. Attach them to the next version.
  "Ready to Submit" means the product was never submitted. Apple
  reviews a first IAP only alongside a binary, and rejects one without
  a review screenshot. The full choreography is
  `docs/store/IAP-RELEASE-CHOREOGRAPHY.md`.
- **Enable a capability on the App ID before adding its entitlement.**
  Adding `aps-environment` or `associated-domains` to the project
  before the capability is on the App ID breaks the signed cloud
  build. The agent can do both through the App Store Connect API, in
  that order.
- **APNs may not need a new key.** Enabling APNs on an existing
  Apple Developer auth key (Certificates, Identifiers & Profiles > Keys) lets the `.p8` already on disk send pushes. A
  `.p8` downloads exactly once. The proof it works is Apple answering
  `BadDeviceToken` to a fake token, rather than `InvalidProviderToken`.
- **Microsoft add-ons wait for the base app.** For a Game-type
  product, add-ons cannot be created until the base app is published.
  Two traps reappear on any fresh product: the Submission Options page
  has a *required* `runFullTrust` justification, and the red "access
  policies document is not present in the config set" banner is an
  Xbox Live configuration blocker cleared under **Xbox services >
  Test**, not in any submission section
  (`docs/windows/WINDOWS-STORE-SUBMISSION.md`).
- **Join Apple's Small Business Program** (App Store Connect >
  Business) before the first sale. It takes the commission from 30 to
  15 percent under $1M a year. It is an owner item because it is an
  agreement.

### Links and associations

- **`assetlinks.json` needs the Play App Signing fingerprint**, not
  only the upload key's. With only the upload key, App Links verify
  for local installs and fail for everyone who installed from Play.
  Verify with Google's Digital Asset Links API, reading both
  fingerprints back.
- **Verify Universal Links from Apple's CDN**, not from the header on
  your own server. GitHub Pages serves the extensionless
  `apple-app-site-association` as `application/octet-stream`, which
  looked fatal. Reading the file back from Apple's CDN showed Apple
  accepted it, which saved a DNS migration that was about to become
  an owner item.

### Payments and webhooks

- **The owner creates the webhook secret, the agent does the rest.** A
  merchant-of-record webhook secret must match a value created in that
  dashboard, so the owner generates it (`openssl rand -hex 32`), pastes
  it into the dashboard, and sets it as the backend secret. Then an
  unsigned test POST tells the agent it landed: 503 while the secret
  is missing, 401 (bad signature) once it is set. 401 is the success
  signal.
- **Return 503, never drop, while a secret is missing.** A backend that
  answers 503 makes the processor retry, so no purchase is lost while
  the owner item is open.
- **Webhooks are scoped per mode.** A test-mode webhook does not fire
  in live mode. Going live means creating the live-mode hook too.
- **Entitlements fail open.** A backend hiccup must never revoke a
  paying member. Store product IDs must match exactly what the app
  queries on every store.

### Scheduled senders

- **A sender that no-ops without its secrets goes live the moment they
  exist.** A notification cron that exits early when a secret is
  missing is safe to ship. But the day the last secret lands, the next
  scheduled run sends real notifications to real people. Give every
  sender a dry-run flag, and tell the owner the day it arms.

---

## The ship commands

<!-- FILL: adjust to the platforms in DECISIONS.md 014. The agent runs
     these. They are here so the owner can see what "shipping" means. -->

Bump both version numbers in `AppVersion.xcconfig`, `versionCode` and
`versionName` in `android/app/build.gradle.kts`, and run
`python3 tools/stamp_msix_version.py` for Windows. Then:

| Platform | Command | Where it lands |
|---|---|---|
| Web | (automatic on push to `main`) | [FILL IN: your domain] |
| iOS, macOS, tvOS | `gh workflow run appstore-build.yml`, then `appstore-submit.yml` (`docs/APPLE-SUBMISSION-CLI.md`) | Submitted for review |
| Android | `gh workflow run play-release.yml`, then `python3 tools/play_promote.py --version-code N --to production` after a person has used the internal build | Play production |
| Windows | `gh workflow run windows-store.yml -f submit=true -f commit=true` (copy it from `docs/windows/workflows/`) | Public in the Microsoft Store |

Anything less than the full Windows command succeeds while shipping
nothing. Only an Apple release that auto-releases and the committed
Windows submission become public without another step, so the agent
confirms those two before running them.

Bring back the owner list with a count, and keep it short.
