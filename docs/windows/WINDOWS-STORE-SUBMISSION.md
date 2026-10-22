# Windows Microsoft Store submission (CLI)

> **Adaptation**: replace `AppName.*` with your project names, `appname:` /
> `your-domain.example` with your scheme/domain, and work §1's checklist top to
> bottom for your own Partner Center account. Everything else (the workflow
> shapes, the ordering, and every gotcha) is battle-tested as-is (shipped and
> certified for Tidbits Trivia, 2026). Where a paragraph cites specific version
> numbers or dates, that is evidence from the app that paid for the lesson, not
> something to reproduce.

The Windows twin of `docs/CLOUD-SUBMISSION.md` (Apple) and the
`play-cli-submission` skill (Android). Same shape as both: **a manual
bootstrap once, then every ship is a CLI command.**

- **Package + submit:** `.github/workflows/windows-store.yml` (copy it in from
  `docs/windows/workflows/`; you create this)
- **Iterate/verify:** `.github/workflows/windows-repl.yml` (same)
- **Identity:** `windows/AppName.App/AppxManifest.xml`
- **Version:** `tools/stamp_msix_version.py` ← `AppVersion.xcconfig`

---

## The shape of it (and how it differs from Apple/Play)

| | Apple | Play | **Microsoft Store** |
|---|---|---|---|
| Create the app | ASC API can | Console only | **Partner Center only** |
| First submission | API | API | **Manual, incl. age ratings** |
| Signing | You sign (.p12) | You sign (upload key) | **Microsoft signs; no cert needed** |
| Beta channel | TestFlight | Internal track | **Private audience + package flights** |
| Later ships | CLI | CLI | **CLI (`msstore`)** |

Two things are genuinely better than Apple/Play: **no signing certificate
to manage** (the Store re-signs), and **flight rollout halt/finalize are
first-class**. One thing is worse: **the API cannot create the app**, and
it refuses to drive submissions until one full manual submission exists.

---

## §0. Bootstrap checklist (once per app)

Track your own state here; when every box is checked, every ship is the §2
CLI command and you never repeat §1.

- [ ] App reserved in Partner Center. Record the **Store ID** (`9N…`), and the
  product type you chose (a "game" product type provisions Xbox Live config;
  see gotcha #12 before picking it for anything game-adjacent).
- [ ] Real identity copied into `AppxManifest.xml` (Name, Publisher,
  PublisherDisplayName), verified on a Windows CI package build.
- [ ] `MSSTORE_PRODUCT_ID` repo **variable** set to the Store ID.
- [ ] (If you use https deep links) appUriHandler in the manifest +
  `/.well-known/windows-app-web-link` naming the real PackageFamilyName,
  serving 200 live.
- [ ] **Auth spike PASSED (§1.1):** `msstore apps list` returns the product.
- [ ] **4 Store secrets set (§1.5)**. Rotate the client secret if its value ever
  passed through a session transcript or log.
- [ ] **First submission completed manually**, all sections Complete (Pricing,
  Properties, Age ratings, Packages, Store listings, Submission Options; see
  gotchas #11–#12 for the two blockers no checklist names). Set publishing to
  "as soon as it passes certification" (see §2).
- [ ] Verify an https external-open on a real Windows box (the one thing no CI
  can check).

---

## §1. Bootstrap (once, mostly manual: OWNER ACTION)

These cannot be automated. Do them in order; step 1 is a spike that
de-risks everything after it.

### 1.1 Spike the auth FIRST (do this before anything else)

There is a live, unresolved Microsoft-side failure (`AADSTS7000118`,
"Resource application 'Spark-PROD' is not allowed to be used by tenant
…") that has been reported since ~July 2025 with no fix other than
Microsoft support intervention. It presents as a correctly-configured app
registration that still 401s. **Find out before investing in listings.**

1. Partner Center → associate an **Entra tenant** (create one free from
   Partner Center if there isn't one). A personal MSA will NOT work. A
   personal account with zero associated tenants is the classic starting
   state; associate the auto-created **Default Directory** tenant via a
   cloud-only Global Admin.
2. Entra admin center → **Identity → Applications → App registrations** →
   **New registration** (name it e.g. `appname-store-ci`). Copy the
   **Application (client) ID**, and the **Tenant ID** from Identity →
   Overview.
3. Partner Center → **Account settings → User management → Microsoft
   Entra applications** → add that app registration and give it the
   **Manager** role. *Skipping this is the #1 silent failure: the token
   issues fine and every API call 401s.*
4. Entra → the app → **Certificates & secrets** → **New client secret**.
   Copy it immediately (it is shown once).
5. Partner Center → **Account settings → Identifiers** → copy the
   **Seller ID**.

Then verify from any machine (the CLI is cross-platform:
`brew install microsoft/msstore-cli/msstore-cli`):

```bash
msstore reconfigure --tenantId <T> --sellerId <S> --clientId <C> --clientSecret <CS>
msstore apps list          # must list your apps. If this 401s, STOP: it's 1.1's bug.
```

> **Payout and tax are OWNER-ONLY**: the payout/tax profile lives under the
> gear → Account settings and is visible only to the account-owner identity.
> It is absent entirely for the CI Entra identity. Paid apps and add-ons will
> not certify until the owner completes it.

### 1.2 Reserve the name

Partner Center → **Create a new app** → reserve your app name.

> Reservation holds for **3 months**. This starts a clock, so don't do it
> before the auth spike passes.

### 1.3 Copy the real identity into the manifest

Partner Center → **Product management → View app identity details**. Copy
**Package/Identity/Name**, **Publisher**, and **PublisherDisplayName**
verbatim into `windows/AppName.App/AppxManifest.xml`.

> Values are **case- and whitespace-sensitive**, and a mismatch fails the
> upload with a generic error that does not name the offending field. The
> committed `CN=AppNameDev` is a dev placeholder for sideload only.

### 1.4 First submission (MANUAL)

Build the package (`gh workflow run windows-store.yml`, then
`gh run download <id> -n appname-msix`) and upload it by hand in Partner
Center, completing the listing, screenshots, and the **age-ratings
questionnaire**. The API refuses to drive submissions until this exists.

### 1.5 Record the secrets

Repo → Settings → Secrets and variables → Actions:

| Kind | Name | From |
|---|---|---|
| Secret | `MSSTORE_TENANT_ID` | Entra → Overview |
| Secret | `MSSTORE_CLIENT_ID` | the app registration |
| Secret | `MSSTORE_CLIENT_SECRET` | Certificates & secrets |
| Secret | `MSSTORE_SELLER_ID` | Partner Center → Identifiers |
| **Variable** | `MSSTORE_PRODUCT_ID` | Partner Center product URL / `msstore apps list` |

> Client secrets **expire** (≤24 months; MS suggests <12) and will break
> the pipeline silently when they do. `msstore` also supports certificate
> auth (`--certificateThumbprint` / `--certificateFilePath`), which is
> worth moving to if this becomes a recurring interruption.

---

## §2. Shipping (CLI, every time)

```bash
# 1. Bump the version. The Store reserves the 4th segment, so two builds of
#    the same marketing version are indistinguishable. Every upload needs a
#    MARKETING_VERSION bump.
vim AppVersion.xcconfig
python3 tools/stamp_msix_version.py

# 2. Package only (no Store contact); verify it builds and installs.
gh workflow run windows-store.yml

# 3. Package + submit as a DRAFT (nothing goes live).
gh workflow run windows-store.yml -f submit=true

# 4. Publish for real.
gh workflow run windows-store.yml -f submit=true -f commit=true
```

`submit` defaults to **false** and `commit` defaults to **false** (draft),
because an accidental publish reaches real users and cannot be un-shipped.

### Step 4 is not optional, and skipping it is SILENT

**A run without `-f commit=true` succeeds while shipping nothing.** In the app
this template comes from, four green runs across two weeks did exactly that.
Each one:

1. **deleted the previous uncommitted draft** (`Deleting existing Submission`),
2. uploaded a fresh package, then
3. printed `Skipping submission commit.` and exited 0.

Net effect: the Store served a three-week-old version while the repo moved on,
and every run in the Actions list was a green check. The owner found it, not
the pipeline. The workflow states the outcome in the run summary and raises a
warning annotation whenever a run did not actually submit. But the rule is
simpler than that: **`-f submit=true -f commit=true` or it did not ship.**

### …and step 4 still is not the end: the PUBLISHING HOLD

Committing a submission gets it *certified*, not *live*. A submission carries a
`targetPublishMode`, and a product's can be **"Don't publish this submission
until I select Publish now"**, so an update passes certification and then sits
at *Update ready to publish* indefinitely, one manual click short of users. A
second silent stall, layered under the `commit=true` one.

**`msstore` cannot fix this.** The `publish` command's entire option set is
`--inputFile`, `--appId`, `--noCommit`, `--flightId`,
`--packageRolloutPercentage`. There is no publish-mode flag. The mode is
submission metadata inherited from the previous submission, so it must be
changed **once, in Partner Center**, and it then carries forward:

> Product overview → Certification status → **Modify publishing time** →
> *Publish this submission as soon as it passes certification* → **Apply**

The banner is the tell: "will start publishing **as soon as it passes
certification**" (good) versus "when you click on **Publish now**" (stalled).

So the full update recipe, end to end:

1. Bump `MARKETING_VERSION` in `AppVersion.xcconfig`, run `tools/stamp_msix_version.py`.
2. `gh workflow run windows-store.yml -f submit=true -f commit=true`.
3. Confirm the log says `Submission Status - Certification` and `Submission
   commit success!`, not `Skipping submission commit.`
4. Confirm the overview banner says publishing happens automatically.
5. When certification passes, confirm **Manage packages** shows the new
   version live.

Partner Center → **Manage packages** shows the version that is actually live.
That page, not a green Actions run, is the ground truth.

---

## §3. Beta testing (the TestFlight analogue)

Two mechanisms; use both.

- **Private audience:** the listing is invisible and unavailable to
  anyone outside your group. This is the closest TestFlight equivalent.
  **Partner Center UI only:** Pricing and availability → Visibility →
  Private audience. Add testers by Microsoft account email.
- **Package flights:** different packages to subsets of that audience
  (alpha/beta/prod rings). **Fully CLI-driven:**

```bash
msstore flights create <productId> "Beta" --group-ids <groupId>
msstore flights list <productId>
gh workflow run windows-store.yml -f submit=true -f commit=true -f flight=<flightId>

# Staged rollout, halt, finalize
msstore flights submission rollout update <productId> <flightId> --percentage 25
msstore flights submission rollout halt <productId> <flightId>
msstore flights submission rollout finalize <productId> <flightId>
```

---

## §4. Gotchas (pre-paid)

1. **`AADSTS7000118` / Spark-PROD:** unresolved Microsoft-side tenant
   enrolment bug; blocks everything, no code workaround. Spike it first (§1.1).
2. **Identity mismatch** → generic error naming no field. Copy verbatim.
3. **`PublishSingleFile` is incompatible with MSIX.** `windows-store.yml`
   publishes multi-file on purpose; `windows-build.yml` keeps single-file
   for the direct-download `.exe`. Don't unify them.
4. **CLI updates are FREE-PRODUCTS-ONLY.** Fine for a free app, but it
   constrains any future paid tier (add-ons inside a free app still work).
5. **Never edit an API-created submission in the web UI.** It permanently
   breaks API control of that submission and can wedge it into a state
   needing delete + recreate. Pick one control plane: CLI.
6. **4th version segment must be 0**; first segment must be non-zero.
7. **No cert needed**, but the sideload signing in the workflow is what
   makes the artifact installable for testing. The Store discards it.
8. **`msstore init` does not support Avalonia** (WinUI/MAUI/Flutter/
   Electron/RN/PWA/UWP only). Skip `init`/`package` and hand the CLI a
   pre-built `.msix`. This is a supported, documented path.
9. **No crash analytics** unless you ship `.msixupload` with `.appxsym`.
10. **WACK on CI is unverified.** Docs recommend the Windows App
    Certification Kit before submitting, but `appcert.exe` wants elevation
    and there's no official headless-CI guidance. Let Store certification
    be the gate; the first manual submission (§1.4) surfaces manifest
    problems.
11. **Submission Options has a REQUIRED `runFullTrust` justification.
    It keeps the section "Incomplete" until you fill it.** Any packaged
    Win32 / desktop-bridge app (an Avalonia/.NET MSIX) auto-declares
    `runFullTrust`; you cannot remove it, you must justify it. Partner
    Center → the submission → **Submission Options** → "Why do you need the
    runFullTrust capability?" It has a **500-char cap** (a longer paste truncates
    mid-sentence). An honest one-liner works: it's the standard capability
    for a packaged classic desktop app to run its own managed code; no
    elevation, no access to other apps' data. Filling it flips the section
    to Complete.
12. **The red banner "The access policies document is not present in the
    config set. This document is required for all publish operations." is
    an Xbox-Live-config blocker, NOT a submission-checklist item. And it
    persists through reloads with every section Complete.** It appears when
    the product type is a **Game**: Partner Center provisions an Xbox Live
    config whose "access policies document" is only generated when you
    publish that config to the private test sandbox. FIX: left-nav
    **Xbox services** → scroll to the bottom → click **Test** ("Success"
    appears; this publishes to the private sandbox only, never retail). The
    "Xbox Creators Program" row reading Complete in the submission checklist
    does NOT cover this. Documented MS cause (Q&A 303156), not a support
    ticket.

---

## §5. Direct download (unchanged, parallel channel)

The Store is the no-SmartScreen path. `windows-build.yml` still produces
the single-file `.exe` for GitHub Releases; see WINDOWS-PLAYBOOK §6 for
the Velopack/winget plan. The two channels share the app but not the
package: **Store = MSIX (multi-file), direct = single-file `.exe`.**

---

## §6. After the identity exists: the https deep-link twin

`appname://` can be registered from day one (AppxManifest →
windows.protocol). The **https twin** (`your-domain.example/item/x` opening
the app) must WAIT for the Store identity, because `windows.appUriHandler`
needs `/.well-known/windows-app-web-link` naming the **PackageFamilyName**,
and the PFN is `Name` + a hash of the *real* Partner Center Publisher. It
does not exist until §1.3. Publishing a guessed PFN fails silently and
unverifiably, which is worse than not shipping it.

Once §1.3 is done:

1. Add to `AppxManifest.xml` inside `<Extensions>` (the scaffold carries this
   block with a placeholder host):
   ```xml
   <uap3:Extension Category="windows.appUriHandler">
     <uap3:AppUriHandler>
       <uap3:Host Name="your-domain.example" />
     </uap3:AppUriHandler>
   </uap3:Extension>
   ```
   (add `xmlns:uap3` + `uap3` to `IgnorableNamespaces`)
2. Add `.well-known/windows-app-web-link` to the site root (served as
   JSON, no extension), alongside the existing `assetlinks.json`:
   ```json
   [{ "packageFamilyName": "<PFN from Partner Center>", "paths": [ "*" ] }]
   ```
3. Verify an external open with a REAL link on a REAL Windows box. A
   deep-link parser and inbox can be unit-tested, but the OS handing the
   URL over cannot.

---

## §7. In-app purchases (Store add-ons) on Windows

Every trap below was hit for real; the architecture they force is already in
the scaffold (`AppName.Windows`).

### The two purchase routes

- **In-app (Store add-ons):** the WinRT edge asks `StoreContext` for the
  app's add-ons and matches `InAppOfferToken` against your product ids.
  Works only in the **packaged MSIX** installed from the Store.
- **Web purchase** (if your app has one): buy on your site, sign in in-app
  with the same account, and a remote entitlement read grants access. This is the only
  route the direct-download `.exe` has, and the one its paywall empty-state
  should name.

### How the WinRT edge is isolated (do not "simplify" this)

`Windows.Services.Store` needs a `net10.0-windows10.0.x` TFM. **That TFM
cannot go on `AppName.App`.** It was tried, gated across four
`windows-latest` runs, and reverted, because it breaks every publish and the
publish is the ship:

- `NETSDK1083`: the TFM defaults `RuntimeIdentifiers` to the UWP-era
  `win10-x64;win10-x86;win10-arm;win10-arm64` that .NET 5 deleted. Fix: name
  `win-x64`.
- `CS0104`: WinRT defines its own `StorePurchaseResult`, so
  `using Windows.Services.Store` makes every mention of your own type
  ambiguous. Fix: alias the namespace
  (`using WinRTStore = Windows.Services.Store;`).
- `MSB4062 ExpandPriContent`: the killer. The TFM turns on MSBuild's
  Appx/PRI targets, whose task assembly ships with Visual Studio and **not**
  with the dotnet CLI SDK. `WindowsPackageType=None`,
  `EnableMsixTooling=false` and `EnableDefaultPriItems=false` did not stop it.

**The shape of that last one is what the fix exploits: PRI indexing runs over
`@(Content)`, and `AppName.App` links shared assets as Content.** So the TFM
lives in **`windows/AppName.Windows/`**, a class library with *no content
items*, which never runs the task. Keep it that way; adding a `Content` item
there re-arms MSB4062.

`AppName.App` stays on `net10.0` and therefore **cannot reference it** (a
`net10.0` project may not reference `net10.0-windows`). The app loads it with
`Assembly.LoadFrom` instead, and falls back to an inert implementation when
the file is absent, which is the correct answer for the Mac head, the
headless tests, and the `.exe` alike.

The reflective names are a contract: define them once in a Core contract
class and guard from both ends: compile-time (the gateway fails to build if
its namespace/class drift from the contract) and test-time (a contract test
loads the real built assembly and asserts the type, interface, and
constructor shape; it runs on the Mac head).

`EnableWindowsTargeting=true` is what lets that library compile on the Mac at
all (`NETSDK1100` otherwise). The Windows SDK ref pack is a NuGet download
and only has to resolve, never run.

### Packaging

`windows-store.yml` publishes the library separately and stages exactly three
files into the MSIX layout: `AppName.Windows.dll`, `WinRT.Runtime.dll`,
`Microsoft.Windows.SDK.NET.dll` (~25MB, almost all the SDK projection: the
price of WinRT). It throws if any is missing.

**`windows-build.yml` deliberately does NOT carry them.** The direct-download
`.exe` has no package identity, so the gateway refuses anyway and the payload
would be dead weight.

### The API traps inside the gateway

- **`GetAssociatedStoreProductsAsync`, NOT `GetStoreProductsAsync`.** The
  latter's second argument is Microsoft's **Store IDs** (`9N…`), not the
  developer-chosen product ids. Querying it with your own ids matches
  nothing and returns an empty paywall with no error anywhere. The
  association query returns the app's own add-ons; filter on
  `InAppOfferToken`, which IS your id.
- **A subscription is a `Durable` add-on** carrying
  `StoreSku.SubscriptionInfo`. "Subscription" is not a product kind. So ONE
  query covers lifetime and subscription plans, the exact opposite of Play
  Billing, which throws on a mixed INAPP+SUBS list and shipped two crashing
  Android releases before that was understood. Do not harmonize them.
- **Every path degrades to "unknown", never "no".** The entitlement gate
  fails OPEN, so a plumbing error can never lock out a paying customer.
- **`Package.Current` is the availability probe**, not
  `StoreContext.GetDefault()`. The latter can hand back a context in an
  unpackaged process and only fail one call deeper.

### Verifying it

- **Product ids:** `gh workflow run windows-store-addons.yml` reads the
  add-ons back from the Store's own API and fails if any configured id has no
  matching add-on. `msstore` has no add-on commands; this is the legacy
  submission API on the same four secrets. **No API can list add-ons once one
  is a subscription**, so confirm those by eye in Partner Center. Read the
  record back from the vendor's endpoint rather than trusting the config
  (the same lesson as AASA/assetlinks).
- **A real purchase is NOT verifiable from CI.** `StoreContext` returns
  products only to a Store-installed package, so it cannot be exercised on
  the Mac head, in headless tests, on `windows-latest`, or from the `.exe`:
  **only by installing the certified MSIX from the Store on real Windows**.
  Everything above verifies the layers underneath that gap; the purchase
  itself is an owner check after the update goes live.
