# Secrets plan: nothing to remember, nothing in git, nothing in cleartext

Research, 2026-11-22. No code changed. Written in answer to the owner:

> "I do not want to set or keep track of keys and passwords for this repo. Can
> you research the best way to do this so that I can keep these keys safe and
> hope not putting them into the repo itself?"

The rule it serves is AGENTS.md's hard rule: **secrets never in git, and never
in cleartext on disk.** Two incidents prompted it: an agent tried to mint an
`OPERATOR_TOKEN` (Decision 084) into the Keychain and `wrangler secret put`,
and the session's classifier refused; and `tools/asc_release.py status` could
not run because `ASC_KEY_ID` / `ASC_ISSUER_ID` were not in the agent's shell.

Every value below is listed by **name and location only**. No secret was read
or printed while writing this.

## Status (2026-11-22)

**Done by the owner:** step 1, `wrangler login --use-keyring` (the token is in
the Keychain; no plaintext `default.toml`).

**Built (on a branch; not deployed):**

- **Worker, GitHub OIDC** (`worker/src/github-oidc.js`, Decision 085). The
  operator and take-down case routes take only a GitHub Actions OIDC token:
  GitHub's JWKS (fetched and cached), `aud` = the Worker's origin, and
  `repository` + `repository_id` (`1430156519`), `ref` = `refs/heads/main`,
  `job_workflow_ref` = exactly `operator.yml` or `takedown-check.yml`, and
  `event_name` (operator: `workflow_dispatch`; take-down: `schedule` or
  `workflow_dispatch`) pinned as constants. `OPERATOR_TOKEN` and
  `TAKEDOWN_TOKEN` are gone from the code; a stored value set on the Worker is
  refused (tested). Tests: `worker/test/github-oidc.test.js`; 12 new or
  rewritten `oidc:`/`084:` mutants, all caught.
- **`.github/workflows/operator.yml`** (`action` = `list` | `delete-class`,
  `reference`, `code`, `class_id`; `id-token: write`, `contents: read`). The
  log masks the code and reference and prints class ids, dates and counts
  only. `docs/WORKER.md` "A school asks" is rewritten for it.
- **`takedown-check.yml`** asks for the OIDC token (`id-token: write`) and no
  longer reads `secrets.TAKEDOWN_TOKEN`. `catalog/tools/takedown_cases.py`
  gets the token in CI only and no longer reads `~/.config/eardrama/takedown.env`;
  the owner's `open`, `list`, `show` and `decide` read and write the private
  record in D1 through the owner's own wrangler login.
- **`tools/secrets.sh`**: `list`, `gen SESSION_SECRET`, `put-file NAME FILE`
  (`APPLE_PRIVATE_KEY`, `IA_S3_ACCESS_KEY`, `IA_S3_SECRET_KEY`),
  `keychain-import-asc [P8] [ISSUER_ID] [--delete]`, `renew-signing`.
  `tools/ci_make_signing_p12.py` now takes the key as `ASC_KEY_P8` and the
  password as `P12_PASSWORD` (`-`). Test: `tools/test_secrets_sh.py` (every
  recipe against a fake store; five negative controls).
- **`tools/test_no_secrets.py`** with `tools/no_secrets_allowlist.txt`, the
  `.githooks/pre-commit` hook, and `.github/workflows/secrets-check.yml` (both
  tests on every push and pull request). It proves each rule on planted samples
  before scanning.

**Enable the hook once per clone** (an isolated agent may not change the shared
git config, so the main thread or the owner runs it in the main checkout):

```sh
git config core.hooksPath .githooks
```

**What remains for the owner** (no value is typed or seen):

1. Add the permission entries below (3d): the project rules and the
   `autoMode.allow` sentence in `~/.claude/settings.json`. Permission changes
   are the owner's.
2. Approve, in one message, deleting the plaintext files:
   `~/.config/eardrama/takedown.env`,
   `~/.appstoreconnect/private_keys/aw-ci-p12.password` (for Ear Drama), and the
   `.p8` once `tools/secrets.sh keychain-import-asc <issuer id> --delete` has
   put it in the Keychain.

**What remains for the main thread:**

1. Merge, then run `git config core.hooksPath .githooks` in the main checkout.
2. Deploy in one step with the merge: `cd worker && npx wrangler deploy`. The
   old Worker needs the token and the new workflows send none, so a scheduled
   take-down check between the merge and the deploy fails (red, harmless);
   dispatch `takedown-check.yml` after the deploy to prove it.
3. Prove the operator route: `gh workflow run operator.yml -f action=list -f
   reference=no-such-school` answers `0 class(es)`.
4. Then delete the old values: `npx wrangler secret delete TAKEDOWN_TOKEN`,
   `gh secret delete TAKEDOWN_TOKEN` (`OPERATOR_TOKEN` was never set).
5. Plan items not in this batch: retire `asc-credentials.env` and
   `~/.config/play/PLAY_SERVICE_ACCOUNT.json` from tools and docs; public ids
   to repository variables; `android-build.yml`'s `KEYSTORE_*` names; turn on
   non-provider patterns; Play on Workload Identity Federation (phase 2).
6. `AGENTS.md` is 19 bytes under its 24,000-byte limit, so the hard rule's
   "Check: `tools/test_no_secrets.py`" mark needs a trim elsewhere first.

**Where this plan was wrong, found while building:**

- The audience is the Worker's origin, not a fixed `eardrama-operator` name:
  it needs no config and a token for one host is useless at another.
- `renew-signing distribution|mac_installer` cannot renew one: both `.p12`s
  share `APPLE_P12_PASSWORD`, so a new password for one breaks the other. It
  renews both.
- `keychain-import-asc` cannot take everything from the `.p8`: the issuer id is
  not in it, and the GitHub copy cannot be read back. It is an argument. The
  file is deleted only with `--delete`, since deleting it is the owner's call.
- The take-down tool's local commands cannot become a workflow dispatch: `show`
  prints the private record, and Actions logs and dispatch inputs are public.
  They use D1 through the owner's wrangler login instead.
- `tools/secrets.sh list` reads Keychain names with `security dump-keychain`
  (attributes only, no values).

---

## 1. Inventory

Counted: **25 live credential items in four stores**, plus **26 names that
workflows or the Worker expect but that are not set**. "Remember?" asks
whether the owner must recall or type the value today.

### 1a. GitHub Actions secrets (set, 14) — `gh secret list`

| Name | Guards | Consumer | Remember? |
|---|---|---|---|
| `ASC_KEY_P8`, `ASC_KEY_ID`, `ASC_ISSUER_ID` | the App Store Connect API (builds, TestFlight, review, Pulse) | `appstore-build*.yml`, `appstore-submit.yml`, `pulse.yml` | no |
| `APPLE_DIST_P12`, `APPLE_INSTALLER_P12`, `APPLE_P12_PASSWORD`, `APPLE_DIST_CERT_ID` | the CI distribution and Mac installer signing identities | `appstore-build*.yml` | no |
| `APPLE_TEAM_ID` | not a secret (an identifier), kept here by template habit | `appstore-build*.yml` | no |
| `UPLOAD_KEYSTORE_B64`, `UPLOAD_KEYSTORE_PASSWORD`, `UPLOAD_KEY_PASSWORD`, `UPLOAD_KEY_ALIAS` | the Android **upload** key (Play App Signing holds the real key) | `play-release.yml` | no |
| `PLAY_SERVICE_ACCOUNT_JSON` | the Play Developer API (a long-lived service-account key, shared with Archive Watch) | `play-release.yml`, `android-build.yml`, `pulse.yml` | no |
| `TAKEDOWN_TOKEN` | the Worker's `/v1/takedown` route | `takedown-check.yml` | no |

Repository variables: `DMCA_AGENT_REGISTERED` (set); `APP_BUNDLE`,
`APP_STORE_PLATFORMS` (read, unset). None is secret.

### 1b. Expected GitHub secrets that are not set (24)

- `android-build.yml`: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`,
  `KEY_PASSWORD` (the template's names; the real upload key lives under the
  `UPLOAD_*` names above), `GOOGLE_WEB_CLIENT_ID` (public: it is already in
  `worker/wrangler.toml`; belongs in a variable, not a secret).
- `appstore-build*.yml`: `APPLE_ORG_NAME` (public).
- `pulse.yml` (18): `ASC_REPORTS_KEY_ID`, `ASC_REPORTS_KEY_P8`,
  `ASC_VENDOR_NUMBER`, `PLAY_REPORTS_BUCKET`, `AMAZON_CLIENT_ID`,
  `AMAZON_CLIENT_SECRET`, `AMAZON_APP_ID`, `PULSE_INGEST_TOKEN`,
  `BLUESKY_HANDLE`, `BLUESKY_APP_PASSWORD`, `MASTODON_BASE_URL`,
  `MASTODON_ACCESS_TOKEN`, `IG_USER_ID`, `IG_ACCESS_TOKEN`,
  `THREADS_ACCESS_TOKEN`, `YOUTUBE_CLIENT_ID`, `YOUTUBE_CLIENT_SECRET`,
  `YOUTUBE_REFRESH_TOKEN`. These are optional Pulse sources; each stays
  unset until its source is wanted.

### 1c. Cloudflare Worker secrets (`eardrama-api`) — `npx wrangler secret list`

| Name | Guards | Consumer | Remember? |
|---|---|---|---|
| `SESSION_SECRET` | signs every access token | Worker only | no; nobody ever needs its value |
| `IA_S3_ACCESS_KEY`, `IA_S3_SECRET_KEY` | the Ear Drama archive.org account (publishing plays) | Worker only | no; re-issuable at archive.org/account/s3.php |
| `TAKEDOWN_TOKEN` | `/v1/takedown` (the same value as the GitHub secret) | Worker | no, but it exists in **three** places (see 1d) |
| `APPLE_PRIVATE_KEY` *(unset)* | Sign in with Apple token revocation on account deletion | Worker | — |
| `OPERATOR_TOKEN` *(unset)* | `/v1/operator/*`, a school's deletion request; the route fails closed with `403` | Worker + whoever runs the request | would have to be kept somewhere and typed |

`worker/wrangler.toml [vars]` holds only public configuration
(`APPLE_AUDIENCES`, `GOOGLE_AUDIENCES` with the Google client ids,
`ALLOWED_ORIGINS`, empty `APPLE_TEAM_ID` / `APPLE_KEY_ID`) and the D1 id.
`worker/.gitignore` ignores `.dev.vars`; none exists.

### 1d. The owner's Mac

| Location | What | Cleartext? |
|---|---|---|
| `~/.appstoreconnect/private_keys/AuthKey_G5549XF8RV.p8` | an ASC API private key (probably the team key both apps use) | **yes**, an unencrypted private key |
| `~/.appstoreconnect/private_keys/aw-ci-distribution.p12`, `aw-ci-mac-installer.p12` | Archive Watch's CI signing identities (Ear Drama's GitHub secrets reuse them) | encrypted by a password … |
| `~/.appstoreconnect/private_keys/aw-ci-p12.password` | … which sits **next to them in a plain file** | **yes** |
| `~/.config/eardrama/takedown.env` | `TAKEDOWN_TOKEN`, read by `catalog/tools/takedown_cases.py` | **yes** |
| `~/.config/play/archivewatch-play.json` | the Play service-account key (`tools/setup_play_upload_key.sh` reads it) | **yes** |
| `~/Library/Preferences/.wrangler/config/default.toml` | wrangler's OAuth access and refresh tokens for the Cloudflare account (`wrangler whoami` reports this path) | **yes** |
| `~/keystores/eardrama-upload.jks` | the Android upload keystore | encrypted by its password |
| login Keychain, service `Ear Drama Android upload keystore`, account `eardrama-upload` | that password (`tools/setup_play_upload_key.sh`) | no (Keychain) |
| gh CLI token | GitHub access | no (`gh auth status`: "keyring") |

Not Ear Drama's, seen on the way: `~/.config/archivewatch/{pulse-ingest.env,
takedown.env}` and `~/keystores/roku-signing-key.txt` are cleartext too.

Expected by docs or tools but absent: `tools/asc-credentials.env`
(`tools/submit-appstore.sh`, `tools/asc_release.py`'s error message,
`docs/APPLE-SUBMISSION-CLI.md`), `~/.config/play/PLAY_SERVICE_ACCOUNT.json`
(`tools/play-publish.py`, `tools/submit-play.sh`, `tools/play_promote.py`).
Both are cleartext designs; the plan retires them rather than creating them.

### 1e. In git

- History: no `.p8`, `.p12`, `.jks`, `.keystore`, `.env`, `.dev.vars`, or
  service-account file was ever added (`git log --all --diff-filter=A`).
- Tracked PEM headers: `worker/test/account.test.js` builds a PEM from a key
  generated at test time (safe), and a skill reference file shows a public key.
- The repository is **public**. GitHub secret scanning and push protection
  are **on**; non-provider patterns and validity checks are **off**.
- `.gitignore` covers `.env`, `*.key`, `*.p12`, `AuthKey_*.p8`, `*.jks`,
  `*.keystore`, `asc-credentials.env`, `*_keys.env`. There is no pre-commit
  hook (`core.hooksPath` unset, no `.githooks/`) and no secret test in `tools/`.

### 1f. Why the agents were refused

Three findings explain both incidents, and they shape the design:

1. **The classifier ignores `autoMode` in project settings.** "The classifier
   doesn't read `autoMode` from project settings in `.claude/settings.json` or
   `.claude/settings.local.json`" ([auto mode config][cc-auto]). The three
   owner authorizations written into `.claude/settings.local.json` (wrangler,
   `gh secret set`, run approval) have never reached it. Only
   `~/.claude/settings.json` (or managed settings) does.
2. **Broad allow rules are dropped in auto mode.** Wildcarded interpreters and
   package-manager run commands are removed on entering auto mode; narrow
   rules "stay in effect" and resolve before the classifier
   ([permission modes][cc-modes]). `Bash(npx wrangler *)` is the kind that is
   dropped, so `wrangler secret put` went to the classifier.
3. **"Writing to a secret manager" and "printing a live credential" are
   default blocks** ([permission modes][cc-modes]). An agent that generates a
   token, holds it in its transcript, and writes it to two stores trips both.
   And one entry in the current local settings authorizes "writing secrets to
   gitignored files and `~/.config/eardrama`", which contradicts the hard rule.

---

## 2. What good practice says

**Remove the secret before protecting it.** The safest token is the one that
never exists. Three ways apply here:

- **Federated identity (OIDC) instead of a shared token.** Every GitHub
  Actions job with `id-token: write` can ask GitHub for a short-lived JWT
  signed by `https://token.actions.githubusercontent.com`, with a custom
  audience; the receiver checks the signature against GitHub's JWKS and the
  claims (`repository`, `ref`, `workflow_ref`, `event_name`, `actor`)
  ([GitHub OIDC reference][gh-oidc]). No stored secret on either side. The
  Worker already verifies Apple and Google JWTs against their JWKS
  (`worker/src/jwt.js`), so GitHub is a third issuer for the same code.
  Fork pull requests never get an `id-token`, which matters for a public repo.
- **Workload Identity Federation for Google.** `google-github-actions/auth`
  trades the GitHub OIDC token for short-lived Google credentials by
  impersonating a service account, which retires the JSON key
  ([Google Cloud blog][gcp-keyless], [GitHub docs][gh-gcp],
  [the action][gcp-auth]). The Play-specific guides are third-party
  ([example][play-wif]); verify with one dry-run edit before deleting the key.
- **A person's own sign-in instead of an operator key.** The Worker could
  instead accept the owner's Ear Drama session and check the user id against
  an allowlist var. It needs no secret, but it needs a UI or a session token
  in the agent's hands; OIDC fits better because agents, not screens, run
  these requests.

**What cannot be removed.** Apple has no OIDC federation for the App Store
Connect API or signing: the `.p8`, the `.p12`s and their password must exist.
Play upload signing needs a keystore. The Worker needs `SESSION_SECRET` and
the archive.org S3 pair.

**Where a secret must exist, give it one home: where it is consumed.**

- **GitHub Actions encrypted secrets** for everything CI uses; values are
  write-only and masked in logs ([GitHub secrets][gh-secrets]). CI does all
  store calls, so the ASC and Play keys never need to be local.
- **Cloudflare Worker secrets** for what only the Worker uses. Pushing them
  from GitHub with `cloudflare/wrangler-action`'s `secrets` input
  ([wrangler-action][cf-action], [Cloudflare CI docs][cf-ci]) needs a
  `CLOUDFLARE_API_TOKEN` in GitHub: one more secret, held in a second place,
  for values (`SESSION_SECRET`, the S3 pair) no workflow ever reads. For this
  repo the better rule is that each value is generated or pasted straight
  into its only consumer, through a pipe.
- **macOS Keychain for local use.** `security find-generic-password -s NAME
  -w` prints the value to a pipe at use time; nothing lands in a file
  ([`security` man page][mac-security]). `security add-generic-password -w`
  takes the value on argv; `security -i` reads the same command from stdin,
  which keeps it out of `ps`.
- **wrangler's login.** wrangler stores its OAuth tokens in a plaintext
  `default.toml` by default; `wrangler login --use-keyring` moves them into an
  encrypted file keyed from the OS keychain and deletes the plaintext one
  ([Cloudflare changelog][cf-keyring]). The installed wrangler (4.80.0) has
  the flag.

**Password managers.** 1Password's `op run` / `op inject` resolve
`op://` references into a child's environment or a template at run time
([1Password CLI][op-run]); Bitwarden Secrets Manager does the same with a
machine-account access token ([Bitwarden SM CLI][bws]). Both are good for a
team. For one owner they add a subscription, a vault to unlock, and (for
Bitwarden) an access token that is itself a secret on disk. The agent calling
`op` is also a "secret manager" read the classifier scrutinizes. Neither is
installed. Verdict: not needed; GitHub, Cloudflare and the Keychain already
cover every consumer.

**Rotation.** Short-lived credentials (OIDC, WIF) rotate themselves. For the
rest, rotate on suspicion or expiry, from a script, without a human copying a
value: the distribution certificate expires yearly
(`tools/ci_make_signing_p12.py` mints a replacement through the ASC API);
`SESSION_SECRET` rotation signs everyone out, so only on compromise; the S3
pair is re-issued at archive.org; ASC keys are revoked in App Store Connect
([Apple: creating API keys][asc-keys]).

**Scanning.** GitHub push protection blocks known provider tokens at push
([push protection][gh-push]); non-provider patterns add private keys and
generic high-entropy strings ([non-provider patterns][gh-nonprov]). A local
pre-commit check catches a secret before it is even a commit; gitleaks runs
as `gitleaks git --staged` in a hook ([gitleaks][gitleaks]). A
repository-specific check that also fails on forbidden file types and on
code that reads secrets from files is the stronger guarantee for this repo,
because it can follow the project's own rules and prove itself with a
negative control (`docs/ENGINEERING-PROCESS.md`: a test is not a test until
seen to fail).

**The agent's permissions.** A narrow, vetted script that generates and
stores a value without echoing it, allowed by an exact rule, lets an agent do
the job without ever holding the value. Narrow allow rules resolve before the
classifier; any remaining classifier exceptions go in `autoMode.allow` in
`~/.claude/settings.json` ([auto mode config][cc-auto]).

---

## 3. The recommended design

**Principle: a secret exists only if nothing else can do its job, lives only
where it is consumed, and moves only through a pipe.** The owner remembers
nothing and types no value; agents ship through CI and two vetted scripts.

### 3a. What disappears

| Today | After |
|---|---|
| `OPERATOR_TOKEN` (never set; would need keeping) | **Never created.** `/v1/operator/*` accepts a GitHub OIDC token instead. |
| `TAKEDOWN_TOKEN` ×3 (GitHub, Worker, `~/.config/eardrama/takedown.env`) | **Gone.** `/v1/takedown` accepts the same OIDC token; local runs of `takedown_cases.py` become a workflow dispatch. |
| The agent needing ASC ids locally for `asc_release.py status` | **Gone.** `appstore-submit.yml mode=status` already does it in CI; point the tool's error message and the docs there. |
| `tools/asc-credentials.env`, `~/.config/play/PLAY_SERVICE_ACCOUNT.json` designs | **Retired** from tools and docs. |
| `~/.appstoreconnect/private_keys/aw-ci-p12.password` | **Deleted** for Ear Drama (the password is in GitHub); Archive Watch's own copy is its call. |
| wrangler's plaintext OAuth file | **Encrypted** by `wrangler login --use-keyring`. |
| `PLAY_SERVICE_ACCOUNT_JSON` + the local JSON key (phase 2) | **Gone** via Workload Identity Federation, after one dry-run edit proves Play accepts it. |
| `GOOGLE_WEB_CLIENT_ID`, `APPLE_ORG_NAME`, `APPLE_TEAM_ID` as secrets | **Repository variables**: public identifiers. |
| `android-build.yml`'s `KEYSTORE_*` names | Point at `UPLOAD_*` or drop the step; one key, one set of names. |

### 3b. What stays, and where

| Home | Secrets | Who writes it |
|---|---|---|
| GitHub Actions | `ASC_KEY_P8/ID/ISSUER`, `APPLE_DIST_P12`, `APPLE_INSTALLER_P12`, `APPLE_P12_PASSWORD`, `APPLE_DIST_CERT_ID`, `UPLOAD_*` (and `PLAY_SERVICE_ACCOUNT_JSON` until phase 2) | already set; renewals by `tools/secrets.sh` recipes |
| Cloudflare Worker | `SESSION_SECRET`, `IA_S3_ACCESS_KEY`, `IA_S3_SECRET_KEY`; `APPLE_PRIVATE_KEY` if revocation is turned on | `tools/secrets.sh` (generate or pipe from a downloaded file, then delete the file) |
| login Keychain | the upload keystore password (exists); `eardrama:ASC_KEY_P8`, `eardrama:ASC_KEY_ID`, `eardrama:ASC_ISSUER_ID` for the yearly local certificate renewal, moved in from the `.p8` file, which is then deleted | `tools/secrets.sh` via `security -i` |
| encrypted on disk | `~/keystores/eardrama-upload.jks` (password in Keychain) | exists |

Nothing remains in a plaintext file, and no value has a second copy.

### 3c. What to build

1. **Worker: GitHub OIDC for owner routes** (`worker/src/github-oidc.js`,
   reusing `worker/src/jwt.js`). Accept `Authorization: Bearer <GitHub JWT>`
   on `/v1/operator/*` and `/v1/takedown` when: `iss` is
   `https://token.actions.githubusercontent.com`; `aud` is
   `eardrama-operator` (or `eardrama-takedown`); `repository` is
   `bhwilkoff/Ear-Drama` and `repository_id` matches; `ref` is
   `refs/heads/main`; `workflow_ref` names exactly
   `.github/workflows/operator.yml` (or `takedown-check.yml`); `exp` is in the
   future. Pin the expected values in `wrangler.toml [vars]` (public). Log
   `actor` and `run_id` with each deletion, which gives the school request an
   audit trail it did not have. Keep failing closed with `403`. Tests: a
   locally signed JWT through the existing `LOCAL_TEST_JWKS` seam, plus a
   negative control for each claim (wrong repo, wrong workflow, a pull
   request event, expired).
2. **`.github/workflows/operator.yml`** (`workflow_dispatch`, inputs `code`,
   `reference`, `delete_class_id`; `permissions: id-token: write`). Fetches
   the OIDC token with the custom audience and calls the Worker. Only people
   with write access can dispatch it. The agent runs
   `gh workflow run operator.yml -f code=K7QF2M9X`, then reads the log.
   Update `docs/WORKER.md` "A school asks" and Decision 084.
3. **`takedown-check.yml`**: swap `secrets.TAKEDOWN_TOKEN` for the OIDC
   token; teach `catalog/tools/takedown_cases.py` to dispatch the workflow
   (or run only in CI) and drop `ENV_FILE`. Then delete the Worker secret,
   the GitHub secret, and the local file.
4. **`tools/secrets.sh`**, a vetted script with **named recipes only** (no
   arbitrary command, no arbitrary name), that never echoes a value:
   - `list`: names only, from `gh secret list`, `wrangler secret list`, and
     Keychain services starting `eardrama:`.
   - `gen SESSION_SECRET` (and any future generated Worker secret on a fixed
     list): `openssl rand -base64 48 | npx wrangler secret put NAME`.
   - `put-file APPLE_PRIVATE_KEY <path>`: pipes a downloaded key into the
     Worker, then deletes the file.
   - `keychain-import-asc`: moves the `.p8` into the Keychain through
     `security -i` and deletes the file.
   - `renew-signing distribution|mac_installer`: reads the ASC trio from the
     Keychain into the child's environment only, runs
     `tools/ci_make_signing_p12.py` with a generated password into a
     `mktemp -d` directory, pipes the `.p12` (base64) and its password into
     `gh secret set`, and removes the directory. Needs
     `ci_make_signing_p12.py` to accept the key as content (`ASC_KEY_P8`) as
     well as a path.
   The script refuses names outside its list, which is what makes it safe to
   allow by an exact rule.
5. **Phase 2, `play-release.yml` / `pulse.yml` on WIF**: the agent creates the
   pool, provider (attribute condition
   `assertion.repository=='bhwilkoff/Ear-Drama'`) and the impersonation
   binding with `gcloud`; workflows switch to `google-github-actions/auth`;
   one internal-track dry-run edit proves Play accepts the token; then the
   key is deleted in Google Cloud, in GitHub, and on disk. Archive Watch
   shares the service account, so its key is deleted only when it moves too.

### 3d. Permission rules

In `.claude/settings.json` (project, checked in; narrow rules survive auto
mode):

```json
"Bash(tools/secrets.sh list)",
"Bash(tools/secrets.sh gen *)",
"Bash(tools/secrets.sh put-file *)",
"Bash(tools/secrets.sh keychain-import-asc *)",
"Bash(tools/secrets.sh renew-signing)",
"Bash(gh workflow run operator.yml *)",
"Bash(gh workflow run takedown-check.yml *)",
"Bash(gh workflow run appstore-submit.yml *)"
```

In `~/.claude/settings.json` `autoMode.allow` (the only place the classifier
reads it), replacing the ignored block in `.claude/settings.local.json`:

> "For Ear Drama (bhwilkoff/Ear-Drama), the owner authorized tools/secrets.sh
> to generate secrets and write them directly to Cloudflare Worker secrets,
> GitHub Actions secrets, and the macOS Keychain without printing them;
> running wrangler deploy and D1 migrations for eardrama-api; dispatching this
> repo's workflows, including operator.yml for a school's deletion request."

Delete the local block's line that allows "writing secrets to gitignored files
and `~/.config/eardrama`": it contradicts the hard rule. The owner's
`soft_deny` entry for `gh workflow run appstore-build.yml` was written for
Archive Watch; it will also slow Ear Drama ships unless narrowed to that repo.

### 3e. The check that keeps it true

- **`tools/test_no_secrets.py`** (stdlib only, runs everywhere):
  1. scans every tracked file (`git ls-files`, sorted) and, with `--staged`,
     the staged blobs, for: PEM private keys with an inline base64 body,
     `"private_key":` JSON, GitHub tokens (`ghp_`, `gho_`, `ghs_`,
     `github_pat_`), Slack and Google API key shapes, and
     `(SECRET|TOKEN|PASSWORD|_KEY)\s*[=:]\s*["']…{24,}` assignments;
  2. fails on any tracked `*.p8`, `*.p12`, `*.jks`, `*.keystore`, `.env*`,
     `.dev.vars*`, `*service-account*.json`, `takedown.env`,
     `asc-credentials.env`;
  3. fails when tracked code reads a secret from a plaintext path
     (`~/.config/eardrama/`, `asc-credentials.env`, `*.password`), which is
     the "never in cleartext on disk" half of the rule;
  4. carries its own negative control: each pattern injected into a sample
     must be caught, or the test fails;
  5. a small allowlist file for fixtures such as
     `worker/test/account.test.js` (which builds its PEM at run time and
     should not match anyway).
- **`.githooks/pre-commit`** runs `python3 tools/test_no_secrets.py --staged`;
  enable once with `git config core.hooksPath .githooks` (the agent can).
- **CI**: a step in an existing push workflow (or a small `secret-guard.yml`)
  runs the full scan, so a commit made with `--no-verify` still turns red.
- **GitHub**: turn on non-provider patterns and validity checks
  (`gh api -X PATCH repos/bhwilkoff/Ear-Drama` with `security_and_analysis`),
  alongside push protection, already on.
- **AGENTS.md**: give the hard rule its check mark: "Check:
  `tools/test_no_secrets.py` + push protection."

### 3f. The owner's one-time steps

Three, none of which types or reveals a value:

1. **Encrypt wrangler's login**: in a terminal,
   `cd worker && npx wrangler login --use-keyring`, and approve once in the
   browser.
2. **Approve the agent rules**: in Claude Code, `/permissions` → Auto mode
   tab → add the `autoMode.allow` entry in 3d (or tell an agent, in your own
   words, to add it to your user settings).
3. **Approve the clean-up**: one message naming the files to delete (the
   `.p8` after it moves to the Keychain, `aw-ci-p12.password`,
   `~/.config/eardrama/takedown.env`), because deleting the owner's files is
   the owner's call.

Phase 2 adds at most `gcloud auth login` if the gcloud session has lapsed.
Turning on Sign in with Apple revocation later needs one key download from
the Apple Developer site (the API cannot create that key); after that,
`tools/secrets.sh put-file APPLE_PRIVATE_KEY ~/Downloads/AuthKey_….p8` is the
agent's job ([Apple: revoke tokens][apple-revoke]).

### 3g. Order of work

1. `tools/test_no_secrets.py` + hook + CI step (prove it fails first).
2. Worker OIDC + `operator.yml` (unblocks Decision 084 with no secret).
3. Takedown on OIDC; delete the three `TAKEDOWN_TOKEN` copies.
4. `tools/secrets.sh` + the permission rules; move the `.p8` to the Keychain.
5. Retire `asc-credentials.env` and `~/.config/play/…` from tools and docs;
   move public ids to variables; reconcile `android-build.yml` names.
6. Phase 2: Play on WIF.

---

## Sources

[cc-auto]: https://code.claude.com/docs/en/auto-mode-config.md
[cc-modes]: https://code.claude.com/docs/en/permission-modes.md
[gh-oidc]: https://docs.github.com/en/actions/reference/security/oidc
[gh-gcp]: https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-google-cloud-platform
[gcp-keyless]: https://cloud.google.com/blog/products/identity-security/enabling-keyless-authentication-from-github-actions
[gcp-auth]: https://github.com/google-github-actions/auth
[play-wif]: https://dev.to/gcaguilar/how-to-automate-google-play-releases-without-losing-your-mind-139a
[gh-secrets]: https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions
[cf-action]: https://github.com/cloudflare/wrangler-action
[cf-ci]: https://developers.cloudflare.com/workers/ci-cd/external-cicd/github-actions/
[cf-keyring]: https://developers.cloudflare.com/changelog/post/2026-06-03-wrangler-keyring-credential-storage/
[mac-security]: https://ss64.com/mac/security.html
[op-run]: https://developer.1password.com/docs/cli/secrets-environment-variables/
[bws]: https://bitwarden.com/help/secrets-manager-cli/
[asc-keys]: https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api
[apple-revoke]: https://developer.apple.com/documentation/sign_in_with_apple/revoke_tokens
[gh-push]: https://docs.github.com/en/code-security/secret-scanning/introduction/about-push-protection
[gh-nonprov]: https://docs.github.com/en/code-security/secret-scanning/using-advanced-secret-scanning-and-push-protection-features/non-provider-patterns
[gitleaks]: https://github.com/gitleaks/gitleaks

- Claude Code, auto mode configuration: <https://code.claude.com/docs/en/auto-mode-config.md>
- Claude Code, permission modes: <https://code.claude.com/docs/en/permission-modes.md>
- GitHub, OpenID Connect reference: <https://docs.github.com/en/actions/reference/security/oidc>
- GitHub, OIDC in Google Cloud: <https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-google-cloud-platform>
- Google Cloud, keyless authentication from GitHub Actions: <https://cloud.google.com/blog/products/identity-security/enabling-keyless-authentication-from-github-actions>
- google-github-actions/auth: <https://github.com/google-github-actions/auth>
- Play releases with WIF (third-party guide): <https://dev.to/gcaguilar/how-to-automate-google-play-releases-without-losing-your-mind-139a>
- GitHub, using secrets in Actions: <https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions>
- cloudflare/wrangler-action: <https://github.com/cloudflare/wrangler-action>
- Cloudflare, Workers with GitHub Actions: <https://developers.cloudflare.com/workers/ci-cd/external-cicd/github-actions/>
- Cloudflare changelog, wrangler keyring storage: <https://developers.cloudflare.com/changelog/post/2026-06-03-wrangler-keyring-credential-storage/>
- macOS `security`: <https://ss64.com/mac/security.html>
- 1Password CLI, secrets in environment variables: <https://developer.1password.com/docs/cli/secrets-environment-variables/>
- Bitwarden Secrets Manager CLI: <https://bitwarden.com/help/secrets-manager-cli/>
- Apple, creating App Store Connect API keys: <https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api>
- Apple, revoke tokens (Sign in with Apple): <https://developer.apple.com/documentation/sign_in_with_apple/revoke_tokens>
- GitHub, push protection: <https://docs.github.com/en/code-security/secret-scanning/introduction/about-push-protection>
- GitHub, non-provider patterns: <https://docs.github.com/en/code-security/secret-scanning/using-advanced-secret-scanning-and-push-protection-features/non-provider-patterns>
- gitleaks: <https://github.com/gitleaks/gitleaks>

## Progress, 2026-11-22

- Ear Drama: wrangler login in the Keychain (no plaintext config). OIDC operator and take-down routes
  deployed (Worker b600ac47; 58/58 targeted mutants caught); operator.yml and takedown-check.yml ran
  green on the live Worker. TAKEDOWN_TOKEN deleted from the Worker and GitHub; takedown.env moved to
  the Trash. Worker secrets now: SESSION_SECRET, IA_S3_ACCESS_KEY, IA_S3_SECRET_KEY. Owner permission
  rules added (user autoMode entry; project rules; local block removed).
- Archive Watch: Worker deployed (b041ae6c); takedown-check green over OIDC; TAKEDOWN_TOKEN gone from
  GitHub and the Worker; 11 files imported into the Keychain (byte-for-byte), 3 deleted by the import;
  secrets.sh fixed (executable, pinned wrangler 4.152.0, failures reported) and the pre-commit hook
  made executable in git.
- GarageDoor: keystore + password in the Keychain; release.p12 deleted.
- ACR-Helper: no secrets; scan + hook in place.
- Duet-Connect: scan + hook in place; two tools still read the shared .p8 (being switched).
- Template: skill secrets-without-bookkeeping + tools upstreamed (8182a5c2).
- Remaining: binary Keychain reads for Archive Watch's keystore and Tizen certs; Archive Watch
  asc_certs/asc_profiles and Duet-Connect submit/pulse to the Keychain; then the shared AuthKey .p8,
  aw-ci-* files, roku-genkey.raw, upload .jks, Tizen certs and asc-credentials.env files to the Trash;
  Play workload identity federation (phase 2, both apps together).
