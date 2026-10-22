# 08c — Collaborative radio plays: precedents, archive.org as the store, the relay model, safety (2026-10-18)

> Track: COLLABORATION, ORGANIZATION AND ARCHIVE.ORG STORAGE, for the owner's
> request of 2026-10-18: *"allow users of this new app to record their own radio
> plays ... in a collaborative way ... have the other characters that haven't
> yet been recorded as simulated voices ... merged together as more and more of
> the characters are recorded ... We would want to continue to use archive.org
> as our storage system, but we would need ways to organize the recordings and
> connect them to the scripts."* The owner's clarification of the same day
> governs everything below: *"The simulated audio would not be recorded ...
> only your part would actually be recorded. Then the next person would take
> one of the simulated parts and record that ... until all of the parts are
> taken."* The model is a **relay**.
>
> Evidence rules: every external claim carries a URL in Sources. **MEASURED
> 2026-10-18** means a command was run this session and its output is quoted.
> **UNVERIFIED** means it was not confirmed from a primary source.

---

## Verdict

1. **Feasible at $0, and the closest precedent already exists and works.**
   LibriVox has run this exact workflow by hand for years: claim a character,
   record only that character's lines with 3-5 s gaps, upload, a proof-listener
   checks against the script, an editor pastes lines around the narrator file,
   and the result is dedicated to the public domain. Its cost is time: plays
   take **5-8 months**, dramatic readings **10-12** (LibriVox wiki). The owner's
   idea automates the editor and the waiting. The live stand-in voices are what
   LibriVox lacks: rehearsal apps (Run Lines, Acting Pal) already use TTS for
   scene partners, but none collects or assembles human takes.
2. **archive.org's ownership rule decides the storage design.** An item is
   writable only by the account that uploaded it ("ACLs are fake. permissions
   are: World readable, Item uploader writable"; the `uploader` field "determines
   which account has full access"). So many contributors can add files to ONE
   item only if the app uploads for them. **Recommendation: one archive.org
   item per production, uploaded by the app's own account through the existing
   Worker; one file per take, never overwritten; a sidecar JSON per take.**
   That is how LibriVox does it too: its finished items are uploaded by
   `info@librivox.org` into its own collection (MEASURED). It is also the only
   layout in which the app can REMOVE an abusive take, which App Store 1.2
   requires.
3. **The coordination index lives on the existing Worker and D1**, at about 6
   rows per take. That is far inside 100,000 writes and 5 million reads a day.
   archive.org is the durable record: every take's sidecar and a
   `production.json` snapshot are in the item, so D1 can be rebuilt from it. A
   rebuild that cannot read archive.org changes nothing. Absence is not
   evidence.
4. **No accounts for v1-v2.** Use anonymous device keys and a production
   director key, the same pattern as the Watch Together host key, and let the
   group chat do the inviting. Open casting (v3) needs blocking that sticks, so
   it needs Sign in with Apple + Google, and Apple then requires in-app account
   deletion.
5. **Policy is real but bounded.** User recordings are UGC: Apple 1.2 requires
   filtering, reporting, blocking and contact details; Play requires accepted
   terms plus in-app report and block. A child's voice in a published file is
   COPPA "personal information". The FTC's 2017 voice exemption does not apply
   because these files are kept and published. So **under-13s may record only
   locally (v1)**, and an age screen comes before any upload.

---

## 1. Precedents: how they actually work

### 1.1 LibriVox dramatic works (the closest precedent)

Read from LibriVox's own wiki (raw wikitext fetched 2026-10-18: "How to Become
a Dramatic Reading/Play Coordinator", "An Introduction to Dramatic Readings and
Plays for New Readers", "How to Edit a Dramatic Work", "An Introduction to
Proof-listening a Dramatic Work", "Information on coordinating dramatic
readings", "Copyright and Public Domain").

**Roles**
- **BC (book coordinator)** owns the project. Before launch they must have a
  committed **narrator** (for a dramatic reading), an **editor**, and ideally a
  **DPL (dedicated proof-listener)**. "MCs may refuse to set up your project
  until you have a committed narrator in place" (and the same for an editor).
- **MC (meta coordinator)** is an admin who sets the project up. "Please don't
  solicit for an MC ... one will show up when they have time."
- **Readers** claim characters. **Stage directions** is a claimable role "just
  like any other character".
- There is a cap: "a limit of **two** dramatic readings per BC", because a
  dramatic reading is "between 3 and 10 times the work" of a play, and "should
  something unexpected happen to the BC, picking up the pieces is potentially
  too much work for others."

**Casting**
- Casting happens in a public forum thread ("[OPEN] DR: Emily of New Moon ...").
  The **Magic Window (MW)** is a per-project table with "one line for each act
  and one line for each character who reads in that act." A reader claims a
  role with a post such as "Can I please claim 03-Jill?"
- The BC is told: "remind volunteers as the deadlines approach ... if someone
  cannot deliver, offer to find another volunteer." No automatic claim expiry
  was found in the pages read (**UNVERIFIED** whether one exists in the forum
  rules).

**Recording**
- "You only record the lines for that one character." The reader opens with
  "Silvius, read by Charlotte Duckett", records **one file per act or chapter**,
  and leaves "3 - 5 seconds of room silence between each of your lines (even if
  all that separates them is a single word of stage directions!) ... That
  silent space helps the editor."
- Files are named `titleofwork_nameofcharacter_act` and uploaded to the MC's
  folder on LibriVox's own uploader (not archive.org). The link is posted in
  the thread.

**Review**
- "A dramatic work requires both **parts-PL** (of all individual roles, reading
  along with the scripts) and **final PL** (of the edited chapters/acts,
  reading along with the source text)." The level is set per project: standard
  or word-perfect (Shakespeare is word-perfect by default).
- Speed is part of the job: "Because readers come and go from LibriVox
  frequently, any delay in PLing the roles could leave the coordinator with a
  role that will need to be scrapped."
- Tone is a rule: "Make only positive comments about the quality of the
  readings submitted."

**Assembly**
- The editor uses "the narrator/stage directions file as foundation" and pastes
  each line in "about half a second after the end of the narrator's last
  words." They normalize loudness across characters and use no music or sound
  effects ("Copyright issues can be tricky").
- A **Cast Coder** page builds the cast list linking each reader to
  `librivox.org/reader/<n>`. Credits come from data.

**Licence**
- "LibriVox takes a text that is already in the public domain, asks volunteers
  to make audio recordings of that text, and then releases the resulting audio
  back into the public domain ... You really have to let go!"

**On archive.org (MEASURED 2026-10-18)**
- `ahiveofbusybeesdrversion_2610_librivox`: `uploader = info@librivox.org`,
  `collection = ['librivoxaudio', 'audio_bookspoetry']`,
  `licenseurl = http://creativecommons.org/publicdomain/mark/1.0/`, 89 files,
  originals are one MP3 per chapter (`hivebusybees_01_williams_128kb.mp3`) plus
  an m4b. Only finished, assembled chapters reach archive.org. Per-role files
  never do. 145 items in `librivoxaudio` have "Dramatic Reading" in the title.

**What made it work:** a named owner per project, the script as the contract
that review checks against, files that are easy to edit (gaps), positive-only
feedback, credits from data, and a PD dedication that removes every later
negotiation.

**What makes it slow, and what the app can remove:**
- Coordinator burnout (hence the two-project cap).
- Manual bookkeeping in the MW.
- Readers who vanish before corrections.
- One editor hand-assembling every act.

The app can remove the bookkeeping, the hand assembly and the "is my line
missing" checks. It cannot remove the need for a responsible human per
production.

### 1.2 Mozilla Common Voice (crowdsourced recording plus peer validation)

- Contributors record prompted sentences. Other contributors listen and vote.
  "A maximum of three contributors will listen to any audio clip. If an
  <audio,transcript> pair first receives two up-votes, then the clip is marked
  as valid" (Ardila et al. 2019, arXiv 1912.06670, read from the PDF).
- "All of the speech data is released under a Creative Commons CC0 license"
  (same paper).
- Lessons:
  - Validation by peers scales. Two independent yes votes is a cheap, explicit
    rule.
  - Splitting "record" and "listen" into separate queues means newcomers can
    contribute by listening.
  - CC0 voice data is reused for things contributors may not expect, including
    model training. That is relevant to §6.4.

### 1.3 Smule (asynchronous duets) and BandLab (forks and collabs)

**Smule**
- One singer records an "open call" part and another joins later. Smule merges
  them (VentureBeat).
- Invitations reportedly expire after **7 days** (a user's account, **UNVERIFIED**
  as policy).
- Starting an open call is a paid VIP feature; joining is free (App Store
  listing).
- Lesson: an expiring open call keeps a feed fresh. It also produces abandoned
  halves at scale.

**BandLab**
- A creator must explicitly toggle a project **Forkable**. A fork lets another
  user "make edits ... and later republish your version", and Revision History
  lets you "view and access previous versions" (BandLab help).
- The separate "collab" mode is an invitation into one shared project
  (third-party guide).
- Lesson: forking is opt-in by the original creator. Two casts of one script
  are two projects, not one project with conflicts.

### 1.4 Rehearsal apps that already use synthetic scene partners

- **Run Lines** lets you "assign unique AI voices to different characters" to
  rehearse without a partner.
- **Acting Pal** is "an AI-powered app for actors to self-tape and memorise".
- **coldRead** keeps recordings on the device ("The lines you record aren't
  sent or synced to the cloud").
- **Off Book! Pro LineSync** is the nearest to the collaborative half: "Invite
  your actors by email; they sync everything to their own phone ... As
  castmates record their lines, the director hears them show up automatically."
  It is a paid per-show subscription paid by the director.
- All from App Store and listing pages via search, **not fetched directly**.
- None of them assembles human takes into a published production. That gap is
  where the owner's idea sits.

### 1.5 Riverside, Descript, Audacity (multitrack)

- **Riverside** records each participant locally and uploads the files, so
  network quality does not degrade the recording, and gives separate tracks
  (riverside.fm blog; RODE help).
  - Lesson: **record locally, upload the file**. Never stream a take through a
    live connection.
- **Audacity** is the LibriVox editors' tool: import every character as a
  track, then cut and paste into the narrator file.
- **Descript** (transcript-driven editing, voice cloning) was not researched in
  depth. Its cloned-voice feature is the impersonation risk named in §6.4
  (**UNVERIFIED** current feature name and terms).

### 1.6 What the precedents say, in one table

| Need | Proven by | Apply as |
|---|---|---|
| A human responsible per production | LibriVox BC; Off Book director | A required **director** role per production (the opener by default) |
| Claim a character, record only its lines | LibriVox | The core unit: a role, recorded per scene |
| Review against the script | LibriVox parts-PL; Common Voice votes | On-device script-match check plus a human listen (director or two peers) |
| Expiring claims | Smule 7-day calls (UNVERIFIED); LibriVox reminders | A claim expires after N days without a take |
| Forks are explicit | BandLab Forkable | "Recast" creates a new production; the original is untouched |
| Credits from data | LibriVox Cast Coder | Credits page generated from take metadata |
| Public-domain dedication | LibriVox; Common Voice CC0 | CC0 per take, consented at upload (§6.3) |
| Record locally, upload files | Riverside | Never stream a take |

---

## 2. archive.org as the store (measured from its docs and endpoints)

### 2.1 Upload API (IAS3)

From `archive.org/developers/ias3.html`, fetched 2026-10-18.

**Mechanics**
- Items map to S3 buckets. `PUT https://s3.us.archive.org/<identifier>/<file>`
  with `x-archive-auto-make-bucket:1` creates the item.
- Metadata goes in `x-archive-meta-<name>:<value>` headers (numbered
  `x-archive-meta01-...` for repeats). `--` in a header name becomes `_`.
  Non-ASCII values use `uri(...)`.
- Auth is `Authorization: LOW <access>:<secret>`. Keys come per account from
  `archive.org/account/s3.php` ("Select the checkbox and click Generate New
  Keys").
- Multipart is supported.
- `x-archive-queue-derive:0` skips derivation.
- `x-archive-keep-old-version:1` saves the old copy to
  `history/files/$key.~N~`. "Normally PUT and DELETE do not keep old versions."
- `x-archive-cascade-delete:1` removes derivatives with the original.
- `x-archive-interactive-priority:1` gives "an interactive user's upload"
  express-queue priority.
- **"ACLs are fake. permissions are: World readable, Item uploader writable."**
  Load-time ingest "can take some time"; derive time is unmeasured (§10).

**Rate limits (MEASURED 2026-10-18)**
- `curl "https://s3.us.archive.org/?check_limit=1&accesskey=probe&bucket=aw-probe"`
  returned `"accesskey_ration": 499, "bucket_ration": 149, "rationing_engaged": 1,
  "total_tasks_queued": 10833, "over_limit": 0`.
- So one key may have about 499 queued tasks and one item about 149. A burst of
  uploads into one production item must be paced. The doc says to expect
  `503 SlowDown` when over.

**Unauthenticated write (MEASURED)**
- A PUT without keys returns
  `HTTP 403 <Code>InvalidAccessKeyId</Code>`.

**Browser upload is possible (MEASURED)**
- `OPTIONS https://s3.us.archive.org/aw-probe/x.mp3` with
  `Access-Control-Request-Method: PUT` returned
  `access-control-allow-origin: *` and
  `access-control-allow-methods: GET,POST,PUT,DELETE`, and echoed the requested
  headers. A web client could PUT directly if it held keys, which it must not
  (§2.4).

**Download CORS (MEASURED)**
- `archive.org/download/<LibriVox item>/<mp3>` returned
  `302 ... access-control-allow-origin: *`.
- The storage node (`dn721803.ca.archive.org`) returned `200`, `ACAO *`, and
  allowed `Range` in `access-control-allow-headers`.
- So every client, including the web PWA, can fetch takes for the relay bed
  directly. This matches the coordinator's measurement of 2026-10-17.

**Python and CLI**
- `internetarchive` 5.12.0 on PyPI (MEASURED).
- Its `get_auth_config(email, password)` logs in at
  `https://archive.org/services/xauthn/?op=login` and returns the account's S3
  keys (read from `config.py`). That is how a tool gets keys from a password.
  There is no third-party OAuth, so an app cannot ask a user for "upload
  permission" (**UNVERIFIED** that no OAuth exists; none is documented on the
  developer portal).

**Automated access** (`archive.org/developers/bots.html`)
- The User-Agent must name the tool, its version, "and for AI agents: the model
  being used". Honor 429 and `Retry-After`.
- "For content you intend to keep on archive.org, contact info@archive.org to
  request a permanent collection. Otherwise, upload to the Community collection
  matched to the item's media type: ... opensource_audio."
- Archive Watch's `tools/archive_lib.py` already sends a descriptive UA
  (`ArchiveWatch-Lib/1.0 (...)`) and reads only metadata and downloads. It has
  never written to archive.org. This would be the project's first write path.

### 2.2 Items, collections, naming, metadata

**Items** (`developers/items.html`)
- "If the files in an item have separate metadata, the files should probably be
  in different items."
- Items "should not be over 100GB [and] not contain more than **10,000 files**."
- "All items must be part of a collection." An item may contain subdirectories.

**Collections**
- "Collections can only be created by archive.org staff."
- The help center sets a threshold: "**a minimum of 50 items** ... related and
  of the same subject. Until you have a collection, your items will remain in a
  public open source collection", and creation "may take up to two weeks".
- Until then the app uses `opensource_audio` plus a subject and custom-field
  convention (§4.3). That convention is also what a later collection request's
  "search query which will identify only your items" needs.

**Identifier**
- The upload guide says "5-80 characters ... only letters, numbers, dashes or
  underscores ... strongly prefer ... lower case."

**Metadata fields** (`developers/metadata-schema`)
- `creator` is "the individual(s) or organization that created the media
  content", here the playwright.
- `contributor` is "the person or organization that provided the ... media"
  (for born-digital, the distributing organization), here the app.
- `licenseurl` is the "URL of the selected license".
- `subject` is repeatable; the upload form says "do not exceed 10 tags".
- `source` is often "a URL where the media content originated", here the
  script's source text.
- `external-identifier` takes URNs (`urn:namespace:id`).
- The upload form allows "custom metadata pairs".
- `uploader` is internal: "The uploader field determines which account has full
  access to modify/edit/delete metadata and files from the item ... Any other
  account that wants to modify this item must have some level of
  administrative privilege granted by Internet Archive."

**Can other users add files to an item?**
- **No, by documentation.** Only the uploader account, or accounts staff grant
  privileges on a collection, can write.
- Not tested with a second account, because this session has no archive.org
  keys and creating test items is the owner's call (§10 lists the probe).

**Versions**
- Files are overwritten by a PUT with the same key unless
  `x-archive-keep-old-version:1` is sent.
- Item history is at `archive.org/history/<identifier>`.
- The model below **never overwrites a take** (new take, new filename), so
  versioning is by name, not by IA history.

### 2.3 Terms of Use

- `archive.org/about/terms.php` renders only with JavaScript. It could not be
  read this session (curl returned the app shell; WebFetch had no DNS; the
  Wayback fetch was reset).
- **UNVERIFIED:** the current upload licence grant, minimum age, and any clause
  on uploading for others or by automation. The 2014 IA blog paraphrase found by
  search covers only users' use of collections.
- **This must be read before v2** (§10). The Help Center says users "need to
  register for a free account ... before you can upload", which points to the
  Terms and Rights pages.

### 2.4 Who uploads: three options

| Option | How | Attribution | Moderation (can the app remove a take?) | Abuse blast radius | Friction |
|---|---|---|---|---|---|
| **A. Each contributor's own IA account** | User generates keys at s3.php and pastes them in, or the app collects their IA password for xauthn (no) | Native: `uploader` is them | **No.** Only the user or IA staff can delete their item. The app can only hide it from its own index. | Per user | High: an IA account plus key copying, per contributor |
| **B. The app's one account, keys in the client** | Ship the app's S3 secret in the binary or PWA | Metadata only | Yes | **Total**: extracted keys let anyone write or delete as the app | Low, and unacceptable |
| **C. The app's one account, behind the Worker** (recommended) | Client POSTs the take to the Worker. The Worker checks the production and contributor keys, rate limits, size and duration, then PUTs to IAS3 with the secret held as a Worker secret | Metadata plus credits page | **Yes**: the Worker can DELETE the file and mark the take removed | One account, so a pattern of abuse threatens every production. Mitigated by review before upload (§4.5) | Lowest: no account needed |

- **Option C fits Cloudflare's free limits.** "Request body size" is **100 MB**
  on the Free plan (Workers limits doc). A take is one role in one scene: 2-6
  minutes of mono speech at 64-96 kbps AAC, about 1-4 MB.
- **CPU time** is "10 ms" per request on Free. "Waiting on network requests ...
  does not count toward CPU time", so streaming the body through `fetch()` to
  IAS3 should fit (**UNVERIFIED** under load; §10).
- **This is LibriVox's own arrangement.** Readers upload to LibriVox's server,
  and LibriVox's account publishes to archive.org (§1.1).

---

## 3. The relay (owner's clarification) made precise

### 3.1 What one contributor does

1. Opens a production from a link, or (v3) from the casting board.
2. Picks an **open** role. The claim is written: `claimed`, expiring in N days.
3. The app downloads:
   - the **script** (JSON with stable line ids; §4.3),
   - for each scene the role appears in, the **currently selected takes** of
     every other role already recorded, plus their line-timing sidecars,
   - nothing else.

   Scenes the role is absent from are not fetched. For a 30-minute play that is
   roughly 5-20 MB (MEASURED order of size: a 128 kbps LibriVox chapter MP3 was
   9.7 MB; takes at 64-96 kbps mono are smaller).
4. **Rehearse / record in cue-response mode.** The app plays the scene line by
   line:
   - A line by a recorded role plays from that human's take, cut at its line
     markers.
   - A line by an unrecorded role is spoken live by the device voice
     (`AVSpeechSynthesizer`, Android `TextToSpeech`, web `speechSynthesis`),
     one voice per role chosen locally.
   - At the contributor's own line, playback **stops and the mic records only
     that line**, ending on a tap or voice-activity silence.

   So no stand-in audio is ever captured. That is the owner's rule enforced by
   the design rather than by filtering. Headphones are still recommended
   (§6.6). Re-take any line, then listen back with the bed.
5. The app writes **one audio file per role per scene** (LibriVox's grain),
   concatenating the recorded lines with silence, plus a sidecar giving each
   line's `line_id`, start and end offsets, and a script-match score (§6.5).
   Per-line files would hit the 10,000-file item limit quickly. Per-scene files
   mirror LibriVox and keep editing simple.
6. Submits. The take goes to review (§4.5). When it is accepted it becomes the
   role's **selected take** for that scene. The **next** contributor's bed now
   has a human voice where a stand-in was.

### 3.2 Assembly is line-sequenced, not a fixed timeline

- The mix is an **ordered list of lines** (the script order). Each line is a
  pointer to `take_id + [start, end]` and has a gap before it: default 0.5 s,
  LibriVox's editors' figure. A director may set an **overlap** (negative gap)
  for interruptions.
- Because nothing is pinned to absolute time, **replacing one take never breaks
  the sync of others**. Only the durations change.
- The final render is done on device (`AVAudioEngine` manual rendering, Media3
  Transformer, `OfflineAudioContext`), with loudness normalized per role as
  LibriVox's editors do.
- This is also what lets a contributor record against takes without anyone
  hand-editing. The EDL is computed from sidecars and is reproducible.

### 3.3 Concurrency: can two people record at the same time?

The owner described a strict sequence. The cost of strict sequence is time.

**Strict relay**
- If each handover takes a few days, a 10-role play takes 1-3 months. That is
  already faster than LibriVox's parallel 5-8 months, because no editor step
  waits at the end.

**Recommendation: one claim per role, any number of roles claimed at once, and
the relay as the default path rather than a lock.**
- Every take records a **`heard` manifest**: the take id that was in the bed
  for each other role, or `tts` for a stand-in.
- When two people record at once, each performs against a stand-in for the
  other. Their takes say so.
- The director sees "Mary acted opposite a stand-in for John; John is now
  recorded". They can ask Mary for a pickup (re-take) or accept as is.
- The casting view orders open roles by **line count, largest first**. The bed
  then fills with human voices fastest, and later, smaller roles act against
  the most people.
- A director who wants the purest relay can set `relay: strict`. The Worker
  then refuses a second concurrent claim and says why (Decision 128's pattern:
  a refusal is a stated state, not a dead button).

### 3.4 Replacing an earlier take changes what later people acted against

- **Takes are immutable.** A new recording is a new take id and a new file.
  Nothing is overwritten. So every `heard` reference stays resolvable, and
  "what was this person acting against?" always has an answer.
- **Selection is separate from existence.** Changing role A's selected take
  invalidates nothing automatically. Every later take whose `heard` names A's
  older take is marked **"recorded opposite an earlier take of A"** in the
  director's view. The director decides: keep, or invite pickups. This is the
  same information LibriVox editors carry in their heads.
- **Who may replace a selected take:**
  - the take's own contributor (re-record their role),
  - the director (pick among existing takes; recast an abandoned role).

  Never another contributor. Wanting a different cast is a **recast** (fork,
  §4.6), which leaves the original production exactly as its cast made it.

### 3.5 Claim and release

- A claim is `(production, role, contributor_key, expires_at)`.
- Default expiry: **7 days with no take submitted**, renewable once by the
  holder, releasable at any time (the Smule precedent as reported; owner
  question Q5).
- A submitted take ends the claim. If the director later asks for pickups, the
  contributor re-opens the role, but no one else can claim it while it has a
  selected take.
- An expired claim returns the role to `open`. The stand-in voice reappears in
  everyone's bed.

### 3.6 What "complete" means

A production is **complete** when:
- every `(role, scene)` pair that has lines has a selected, accepted human take;
- **and** the director has done a full listen-through of the assembled mix
  against the script. This is LibriVox's "final PL", and the only step that
  cannot be automated, because it is about the whole.

Stage directions and narration are roles like any other (LibriVox treats them
so). Whether a play may complete with directions omitted is LibriVox-allowed
for plays ("stage directions can optionally be left out of plays"). That is a
director's per-production switch (owner question Q6).

**A production can never complete with a synthetic voice in it.** Stand-ins
exist only in rehearsal. That is the owner's model, and it keeps the
published-audio rights clean (§6.4).

---

## 4. THE MODEL: what lives where

### 4.1 Storage layout compared

| Layout | Fits the ownership rule? | Files | Moderation | Verdict |
|---|---|---|---|---|
| One item per take | Only under option A or C | Thousands of tiny items per year, each with derive and indexing | Per item | Clutters archive.org search and wastes derive; rejected |
| One item per contributor per production | Natural under option A | Moderate | **The app cannot delete (A)** | The right layout only if contributors must own their uploads (owner Q3) |
| **One item per production (working), one item per published mix** | Requires option C | A 10-role, 8-scene play with re-takes: about 100-300 files, far under 10,000 | App can remove any file | **Recommended** |

**Two items per production:**
1. **Working item** `awr-prod-<script-slug>-<prod6>`, for example
   `awr-prod-trifles-glaspell-7k3m`:
   - `takes/<role_id>/<scene_id>/<take_id>.m4a` (or `.mp3`), uploaded with
     `x-archive-queue-derive:0` (the files are already playable and need no
     derivatives),
   - `takes/.../<take_id>.json` (sidecar),
   - `production.json` (manifest snapshot, uploaded with
     `x-archive-keep-old-version:1` so its history is the production's history),
   - `script.json` (a copy of the exact script version, so the production can
     outlive the app's script catalog).
2. **Published item** `awr-<script-slug>-<prod6>`:
   - the final mix as FLAC master per scene or act, with derive **on** so
     archive.org makes MP3/OGG and its player works,
   - `credits.json`, `edl.json`,
   - a description generated from data (§7),
   - `licenseurl` CC0.

   It is a separate item because its files have "separate metadata" from the
   working takes (IA's own rule) and because listeners should land on the play,
   not on 200 fragments.

### 4.2 Item metadata (both items)

| Field | Working item | Published item |
|---|---|---|
| `mediatype` | `audio` | `audio` |
| `collection` | `opensource_audio` until a staff collection exists (≥50 related items), then e.g. `archivewatchradio` | same |
| `title` | "Trifles (Susan Glaspell) — production 7k3m, takes" | "Trifles by Susan Glaspell — an Archive Watch Radio production" |
| `creator` | Playwright (from the script record) | Playwright |
| `contributor` | "Archive Watch Radio" (the distributing organization, per schema) | same |
| `subject` (≤10) | `archive watch radio; radio play takes; <title>; <playwright>` | `archive watch radio; radio play; audio drama; <title>; <playwright>; <genre>` |
| `licenseurl` | `https://creativecommons.org/publicdomain/zero/1.0/` (owner Q4) | same |
| `source` | Script source URL (e.g. the Gutenberg text) | same |
| `external-identifier` | `urn:awradio:script:<script_id>`, `urn:awradio:production:<prod_id>` | same, plus `urn:awradio:fork-of:<parent>` when recast |
| custom | `awradio_script_id`, `awradio_production_id`, `awradio_schema=1` | plus `awradio_working_item` |
| `description` | One generated sentence linking the published item | Cast list from data (role, then credit name) |

Header form: `x-archive-meta-awradio--script--id:<id>`. The double hyphen
becomes `_` (IAS3 doc).

### 4.3 Sidecar and manifest shapes (the durable record)

```
take.json
{ "schema": 1, "take_id": "t_9f3a...", "production_id": "7k3m", "script_id": "glaspell-trifles@2",
  "role_id": "mrs-hale", "scene_id": "s1", "credit_name": "Ruth P.", "recorded_at": "2026-10-18T19:02Z",
  "lines": [{"line_id":"s1-l014","start":0.00,"end":3.41,"match":0.97}, ...],
  "heard": {"county-attorney":"t_51c0...", "sheriff":"tts", "mrs-peters":"t_77ab..."},
  "dedication": "CC0-1.0", "consent_version": 1, "app": "awradio-ios/1.0" }
```
- The sidecar carries **no device key**. The key that proves ownership lives
  only in D1, hashed (§5).
- `production.json` holds the roles, the selected take per `(role, scene)`, the
  gaps and overlaps (the EDL inputs), director settings, status, and
  `fork_of`.
- Scripts are JSON with **stable line ids** (`scene-line`) and a version
  suffix. A typo fix makes a new script version, never a silent edit, because
  takes point at line ids.

### 4.4 The coordination layer: Worker + D1

This would sit on the same Worker as Watch Together, or a sibling Worker on the
same free account. It is a new set of routes beside `together.js`, with the
same CORS, rate-limit and anonymous-tally discipline.

```sql
CREATE TABLE productions (
  id TEXT PRIMARY KEY,            -- 6 Crockford chars, public (read aloud / in a link)
  script_id TEXT NOT NULL, fork_of TEXT,
  director_key_hash TEXT NOT NULL,-- like host_key: returned once, never read back
  relay_mode TEXT NOT NULL DEFAULT 'open',  -- 'open' | 'strict'
  status TEXT NOT NULL,           -- casting | complete | published | removed
  working_item TEXT, published_item TEXT,
  created_ms INTEGER NOT NULL, touched_ms INTEGER NOT NULL);
CREATE TABLE claims (
  production_id TEXT, role_id TEXT, contributor_key_hash TEXT, credit_name TEXT,
  expires_ms INTEGER, PRIMARY KEY (production_id, role_id));
CREATE TABLE takes (
  take_id TEXT PRIMARY KEY, production_id TEXT, role_id TEXT, scene_id TEXT,
  contributor_key_hash TEXT, file TEXT, state TEXT,  -- pending | accepted | rejected | removed
  created_ms INTEGER);
CREATE TABLE selections (production_id TEXT, role_id TEXT, scene_id TEXT, take_id TEXT,
  PRIMARY KEY (production_id, role_id, scene_id));
CREATE TABLE reports (id INTEGER PRIMARY KEY, take_id TEXT, production_id TEXT, reason TEXT, created_ms INTEGER);
CREATE TABLE blocks (contributor_key_hash TEXT PRIMARY KEY, created_ms INTEGER);  -- operator bans
```

**Budget against the free tier** (Cloudflare D1 pricing and limits, fetched
2026-10-18):
- D1 free: **5 million rows read and 100,000 rows written a day**, 500 MB per
  database, 5 GB per account, 10 databases, 50 queries per Worker invocation,
  7-day Time Travel.
- Workers free: **100,000 requests a day**, shared with Watch Together, the
  counter and the feeds.
- A take costs about 3-6 written rows (take, selection, claim close, touch) and
  one upload request. One contributor session is perhaps 20-40 requests.
- Even 500 takes a day would be under 3,000 writes and 20,000 requests.
- **The binding limit is Worker requests**, not D1. Watch it in Pulse if v3
  succeeds.

**Rebuild from archive.org (the Worker is a cache)**
- For each item in the convention search `awradio_production_id:*` (or the
  collection, once one exists), read `/metadata/<item>`, then
  `production.json` and every `takes/*.json`. That restores productions,
  takes, selections and state.
- **Claims and reports are not rebuilt.** Claims are ephemeral by design. A
  lost claim becomes an open role, which is safe. Reports should be mirrored to
  the operator's email at write time so they survive.
- **"Absence is not evidence":**
  - A rebuild or sync that gets an error, a 429, a timeout, or an empty answer
    from archive.org **changes no row**.
  - Only a positive read of `production.json` may update a production.
  - Only an explicit operator action may set `removed`.
  - The radio research found Archive Watch's own `scrape_query`/`adv_search`
    reading a throttled call as "nothing found" (SCRATCHPAD 2026-10-17). This
    path must not repeat it. The test should plant a 429 and assert zero
    writes.
- **D1 Time Travel (7 days free)** is the second backstop.

### 4.5 Review: the airlock before archive.org

archive.org is public the moment an item exists. To keep unreviewed audio off
it, there are two designs:

1. **Direct (simplest).** The Worker uploads on submit and the take is `pending`
   in D1. If it is rejected or reported, the Worker DELETEs the file. For a few
   hours or days an unreviewed take is publicly downloadable by anyone who
   guesses the path (it is not linked from anything).
2. **Airlock (recommended for v3, optional in v2).**
   - Submitted takes go to Cloudflare R2 (free: **10 GB-month, 1M Class A /
     10M Class B operations a month, free egress**; R2 pricing doc) with a
     30-day lifecycle.
   - The bed fetches pending takes from R2 for the director and reviewers only.
   - On acceptance the Worker copies the take to the archive.org working item
     and deletes it from R2.
   - Rejected or abandoned takes never touch archive.org.
   - **UNVERIFIED:** whether enabling R2 on a free account requires a payment
     method on file. That is a $0-constraint question for the owner (Q8).

**Who accepts:**
- **v2:** the director (LibriVox's parts-PL), with the on-device script-match
  score shown.
- **v3 open productions:** the director, **or** two peer accepts with no reject
  (Common Voice's 2-of-3), so a vanished director does not freeze a production.

The LibriVox norm "make only positive comments" becomes the design rule:
review choices are **Accept** / **Ask for a pickup (with the line)**, never a
star rating.

### 4.6 Forks ("recast")

- Anyone may start a new production of the same script. That is not a fork,
  just a second cast.
- **Recast from a production** creates a new production with `fork_of` set.
  Its initial selections point at the parent's takes **by reference** (they are
  CC0 and stay in the parent's item, so nothing is copied). The new director
  then opens chosen roles for new voices.
- The parent is never modified. BandLab's lesson: forking is explicit, and the
  original creator decides whether it is allowed. Here every take is CC0, so
  forking is always legally allowed. Whether a director can switch "allow
  recasts" off is owner question Q7.

### 4.7 Publishing

1. Status becomes `complete`. The director presses Publish.
2. The director's device renders the mix from the EDL. It uploads the
   per-scene FLACs through the Worker to the **published item**, with derive
   on.
3. The Worker writes `published_item` and sets `published`.
4. The app's listening side lists published productions from the convention
   search or the collection. They are a catalog source like LibriVox's
   (02-rights's clean pool).

---

## 5. Identity: does the app need accounts?

Decision 009 is "No user accounts; all state local". Watch Together kept it
with a public code plus a host key that "no human ever types". The same
pattern covers v1-v2:

| Need | Anonymous keys (recommended v1-v2) | Sign in with Apple + Google (v3) | archive.org accounts |
|---|---|---|---|
| Prove "this is my take / my claim" | Random contributor key per device per production, stored on device, hash in D1 | Account id | IA account |
| Director control | Director key, returned once (`host_key` pattern) | Account | n/a |
| Cross-device ("record on the Mac, finish on the phone") | Export or transfer the key by link (weak) | Native | Native |
| **Blocking that sticks** (Apple 1.2, Play) | Weak: a reinstall gives a new key | Strong | Strong, but the app cannot enforce it |
| Store obligations | None beyond UGC | **4.8**: offering Google requires an equivalent privacy-preserving login (SIWA satisfies it). **5.1.1(v)**: "If your app supports account creation, you must also offer account deletion within the app" | Asking for a user's IA password risks **5.1.1(vi)** ("surreptitiously discover passwords"); key pasting is clumsy |
| Fit with the project's privacy posture | Same as Watch Together | New: a person identifier on our server | Their identity lives at IA, not with us |

**Recommendation**
- **v1:** nothing; everything is local.
- **v2 (invite-only):** anonymous keys. The production link is shared in
  whatever chat the cast already uses, the same move SHAREPLAY §11.6 makes:
  "The app never learns who the guests are."
- **v3 (open casting to strangers):** add SIWA and Google sign-in **only for
  contributing to open productions**. Listening and invite-only productions
  stay account-free. Apple 5.1.1(v) allows this: "If your app doesn't include
  significant account-based features, let people use it without a login."
- archive.org accounts stay optional. A director could later be offered "also
  attach my archive.org username to the published item's credits".

---

## 6. Safety and policy

### 6.1 Store rules (quoted, fetched 2026-10-18)

**Apple 1.2 User-Generated Content**
- "Apps that enable users to create, generate, upload, share, or otherwise
  contribute content ... must include:
  - A method for filtering objectionable material from being posted to the app
  - A mechanism to report offensive content and timely responses to concerns
  - The ability to block abusive users from the service
  - Published contact information so users can easily reach you"
- Also: "It is your responsibility to remove content that violates this
  guideline, your terms of service, or your community standards."

**Google Play UGC policy (answer 9876937)**
- Apps "must implement robust, effective, and ongoing UGC moderation that:
  - Requires users accept the app's terms of use and/or user policy before
    users can create or upload UGC;
  - Defines objectionable content and behaviors ... and prohibits them ...;
  - Conducts UGC moderation ... This includes providing an in-app system for
    reporting and blocking objectionable UGC and users."
- And: "Apps that provide access to publicly accessible UGC ... must implement
  in-app functionality to report users and content, and to block users."

**How the model meets them**

| Requirement | Mechanism |
|---|---|
| Filter | On-device script match (§6.5), plus human acceptance before a take is selected or published (§4.5) |
| Report | A report control on every take and production → `reports` row plus an email to the operator; a "timely response" target written into the terms |
| Block | Per-viewer "hide this contributor" (local), plus operator `blocks` by key hash (v2) or account (v3) |
| Remove | The app's account owns every item (option C), so the Worker can DELETE any file. **This is why option A fails 1.2.** |
| Contact | The existing published contact on archivewatch.org's privacy page, carried into the new app |
| Terms acceptance (Play) | One screen before the first upload: terms, the CC0 dedication, the age screen |

### 6.2 Minors and COPPA

- 16 CFR 312.2 (Cornell LII, fetched): "Child means an individual under the age
  of 13". "Personal information" includes "(8) A photograph, video, or **audio
  file where such file contains a child's ... voice**" and "(10) A biometric
  identifier ... **voiceprints**".
- The rule was amended effective **June 23, 2025** (Federal Register
  2025-05904, MEASURED via its API). The compliance date of April 22, 2026 for
  most changes is from memory and **UNVERIFIED** here; federalregister.gov
  blocked the full-text fetch.
- The FTC's **2017 voice-recording enforcement policy** spares an operator who
  collects a child's voice "as a replacement for written words" and keeps it
  "only as long as necessary ... and then immediately delete[s]" it (FTC
  statement and Federal Register notice, via search). **A radio-play take is
  published and kept forever, so the exemption cannot apply.**

**Design consequences**
- **v1 local-only recording is not "collection"** (nothing leaves the device),
  so it is open to everyone, including families recording together on one
  device (§8).
- **Before the first upload: a neutral age screen** (birth year, no hint of the
  "right" answer). Under 13: uploading is refused with a sentence saying why;
  local recording stays.
- The app should not be placed in the Kids Category. Apple 1.3 forbids links
  out "unless ... behind a parental gate", and a UGC upload path would conflict.
- Verifiable parental consent for under-13 uploads is possible in law but is a
  separate project. Owner question Q9.
- Teenagers (13-17) are not COPPA children, but state laws and Play's Families
  policy may apply (**UNVERIFIED**, not researched).

### 6.3 Consent and licensing of contributions

**Recommended licence: CC0 per take**
- It matches LibriVox (the clean pool in 02-rights) and Common Voice.
- Published productions then join the app's own clean catalog with no later
  negotiation.
- Forks are always lawful.
- Note on Decision 153 ("A work made with Archive Watch claims Creative Commons
  or fair use, never public domain"): that rule is about clips of films whose
  status the app cannot vouch for. A CC0 **dedication** by the performer of
  their own performance of a vetted PD script is a Creative Commons instrument,
  not a claim about a source's status. It fits the rule's wording, but the
  owner should confirm (Q4).

**Alternative: CC BY 4.0**
- It obliges credit downstream, but complicates every reuse, including the
  app's own listening catalog's attribution display.

**What the consent screen must say plainly** (US English, owner's
essential-information rule: it is a WARNING the person would not otherwise
know):
- the recording is published permanently on archive.org;
- anyone may reuse it for any purpose, including training voice models;
- it cannot be withdrawn from copies others have made.

**The script must be public domain before a production can open.** The app
offers only scripts from its own vetted list, never an upload of arbitrary
text. That list comes from:
- PD plays (Project Gutenberg, pre-1931),
- LibriVox's DR scripts (made from PD texts),
- US-government scripts,
- Class D registrations not renewed (`work_script_lapsed`, 02-rights §3 and its
  table).

Most network-era radio scripts are protected (02-rights §3.1: *Lone Ranger*,
§303's 120-year term). "Recreate a 1947 Suspense episode" is therefore
generally **not** available, and the app should say so where people will look
for it.

### 6.4 Impersonation and voice cloning

- **Synthetic voices in takes.** Someone plays a cloned or TTS voice into the
  mic, or impersonates a real person. The owner's model is human-only. Terms
  must forbid synthetic or cloned voices and imitating real living people.
  Detection is unreliable (**UNVERIFIED**: no on-device detector was evaluated),
  so the controls are human review, reports and takedown.
- **Stand-ins are the device's own voices, never recorded.** Apple's Personal
  Voice (a user's own synthesized voice, behind its own authorization) should
  **not** be offered as a stand-in for another role. It would make one real
  person's voice speak lines in a production they did not join.
  (**UNVERIFIED**: that third-party apps can use Personal Voice only after
  `requestPersonalVoiceAuthorization`.)
- **CC0 takes can be cloned by others.** This is disclosed at consent (§6.3).
  It is the strongest argument for CC BY or a "no cloning" request, though
  neither binds a model trainer in practice.
- **The project's "no AI-written copy" rule.** The stand-in reads a human
  playwright's words aloud and authors nothing. The owner proposed it, so it is
  consistent. Credits and descriptions must still come from data (§7).

### 6.5 Automated filtering: does the take match its line?

- During recording the device already knows which `line_id` is active. An
  **on-device** transcription of each recorded line is compared with the script
  text, giving a word-match ratio stored in the sidecar as `match`.
- **Use:**
  - The app **flags** lines below a threshold to the contributor ("This line
    may not match the script — listen back?").
  - It **requires** a human look for takes with many low lines.
  - It does not silently reject, because accents, archaic diction and verse
    defeat ASR.
- **APIs:**
  - Apple: on-device `SFSpeechRecognizer` with `requiresOnDeviceRecognition`,
    and the iOS 26 SpeechAnalyzer family Archive Watch already uses for live
    captions (Decision 155 gates it to 26+).
  - Android: `SpeechRecognizer.createOnDeviceSpeechRecognizer` (API 31+).
  - Web: the Web Speech API in Chrome is server-based (**UNVERIFIED** current
    behavior), which breaks the "nothing leaves the device" posture. The web
    should skip the check and rely on human review.
  - None of these were fetched this session; treat them as **UNVERIFIED**
    pending the engineering track.
- The check also catches the wrong-content abuse case (someone reads something
  other than the script) at the cheapest point.

### 6.6 Other practical risks

- **Bleed.** In cue-response mode the bed is silent while recording, so a
  stand-in cannot leak into a take. Enabling voice processing (echo
  cancellation) and recommending headphones covers tails and room noise.
- **Takedown handling.**
  - A DMCA or abuse notice, or a report, leads to the operator removing it
    (Worker DELETE plus D1 `removed`).
  - Every published item needs re-rendering if a take in it is removed. The EDL
    makes that mechanical; the removed role reverts to `open`.
- **The app's archive.org account is a single point of failure.** If IA
  suspends it, every production's write path stops. Reads keep working because
  items stay. Mitigations:
  - review before upload (§4.5),
  - per-key and per-production rate limits on the Worker (the existing
    `ROOM_CREATE_LIMITER` pattern),
  - an early email to info@archive.org describing the project before v2
    launches. LibriVox's own relationship with IA is the model.
- **The privacy policy must change.** Today it says the apps "never send us
  information about you" except a room's playback position. A contributor's
  voice, chosen credit name and the take's time would become published data. A
  separate privacy page for the radio app is cleaner than amending Archive
  Watch's.
- **Erasure.** Under GDPR, voice is personal data. A request to delete a take
  can be honored on archive.org (DELETE, cascade) and in D1. CC0 copies made by
  others cannot be recalled. **UNVERIFIED** legal interaction of CC0 with
  erasure rights; owner and counsel question (Q10).

---

## 7. Learning orientation ("Why we build")

The four-question test applied (the `learning-orientation-design` skill was not
available in this session; the questions are paraphrased from CLAUDE.md):

1. **Does it make people more active?** Yes, and that is the whole point. The
   listener becomes a performer, reads a script closely, and makes choices
   about a character.
2. **Does it invite critical thought?** Yes, through director notes and
   pickups. The design keeps review as **specific human feedback on a line**,
   never a score.
3. **Does it connect people?**
   - The relay makes each contributor act **opposite** earlier people, a real
     scene partner across time.
   - Credits pages say who played opposite whom (from `heard`, i.e. from data).
   - Casting calls are shared in groups that already exist: classes, families,
     drama clubs, LibriVox-like communities.
4. **Does it avoid passivity and content farming?**
   - No feeds of trending takes, no likes, no follower counts.
   - Publishing requires a complete cast and a director's listen-through.
   - Rate limits: one open claim per contributor in open productions; a
     director cap like LibriVox's two dramatic readings per BC.
   - Productions, not clips, are the published unit.

**Community features that come from data, never from AI-written copy:**
- **Credits page:** role, then the contributor's own credit name; script source
  and playwright; "recorded between <first take> and <last take>"; "recast
  from <parent>".
- **Casting call:** the script's own dramatis personae plus line counts per
  role. The only words a human adds are the director's own note.
- **"Played opposite" graph** from `heard`.
- **Rehearsal mode:** the full relay bed with no recording. It is useful to
  student actors on its own, and it is what Run Lines and Acting Pal sell.
- **Classroom fit** (UNVERIFIED demand): a teacher as director, students as
  cast. Under-13 students must stay local (§6.2); a whole class can still
  relay on ONE device (v1).

---

## 8. Phased plan

### v1: solo and same-device relay, local only

- **What:**
  - Pick a vetted PD script. Record one role (or several) against live
    stand-ins.
  - **Pass the phone:** a family or class records role after role on one
    device. That is the owner's relay, with no server.
  - Assemble from the EDL; play back; export the mix to Files or the share
    sheet as a file the user owns.
- **Needs:**
  - the script JSON format with line ids,
  - a vetted script list (from radio-catalog and the 02-rights script rules),
  - TTS voice assignment per role,
  - cue-response recorder, line markers, local EDL renderer,
  - on-device script match (optional).
- **Not needed:**
  - **No UGC obligations**: nothing is shared in-app (an exported file is the
    user's own act).
  - No COPPA collection.
  - No accounts, no Worker, no archive.org writes.

### v2: shared productions by link (invite-only)

- **What:**
  - A director opens a production and gets a link plus a director key.
  - Contributors open the link, claim roles, and relay. Takes upload via the
    Worker to the production's working item.
  - The director accepts or asks for pickups, does the final listen, and
    publishes the published item.
  - Recast supported.
- **Needs:**
  - the Worker routes and D1 tables (§4.4),
  - the app's archive.org account and keys as Worker secrets, a descriptive UA,
    and SlowDown/429 handling,
  - the **UGC package**: terms acceptance, report, block, takedown, contact,
  - age screen, CC0 consent screen, new privacy page,
  - the rebuild job with "absence is not evidence" tests,
  - optionally the R2 airlock,
  - a read of archive.org's Terms (§2.3) and a courtesy email to IA.
- **Owner calls:** Q1-Q8.

### v3: open casting

- **What:**
  - A public casting board of open roles across productions, filtered by script
    and genre.
  - Peer acceptance (2 accepts, no reject) as a fallback for absent directors.
  - Auditions: several contributors submit a take for one role and the director
    picks.
  - A staff-created archive.org collection once ≥50 published items exist.
- **Needs:**
  - SIWA plus Google sign-in for open contributing, with in-app account
    deletion,
  - the review queue UI,
  - an operator moderation rota with a stated response time,
  - per-account rate limits,
  - Pulse panels for reports, takes per day and Worker requests per day
    (the 100k/day ceiling).
- **Content-farming guards** are mandatory before launch (§7).

---

## 9. Risks and open owner questions

**Risks (biggest first)**
1. The app's single archive.org account carries every contributor's behavior
   (§6.6).
2. Director abandonment freezes productions, LibriVox's top cost. Mitigations:
   a director handover (an accepted contributor may claim directorship after N
   days of silence) and v3 peer acceptance.
3. The script pool is narrow. Most famous radio drama scripts are protected
   (02-rights §3), so people's first wish (recreate *Suspense*) is mostly
   refused.
4. COPPA if age screening is weak. Voice is a biometric-class identifier.
5. Device TTS quality and voice availability vary widely. A web or Android
   stand-in may sound robotic, which affects rehearsal quality but never the
   product.
6. Unread archive.org Terms of Use (§2.3).

**Owner questions**
- **Q1.** Is the relay strict by default, or open-concurrent with `heard`
  manifests (recommended)?
- **Q2.** Is the app's own archive.org account acceptable as the uploader of
  everyone's takes (option C, recommended), or must contributors own their
  uploads (option A, which loses the ability to remove content)?
- **Q3.** Does the per-production item layout suit, given that contributors are
  credited in metadata rather than as IA uploaders?
- **Q4.** Licence: CC0 (recommended, LibriVox and Common Voice) or CC BY 4.0?
  Does Decision 153's wording need an amendment for original performances?
- **Q5.** Claim expiry: 7 days, renewable once?
- **Q6.** May a play complete with stage directions omitted (LibriVox allows
  it), or must every part be human?
- **Q7.** May a director forbid recasts of their production?
- **Q8.** Is R2 for the review airlock acceptable under the $0 rule if it needs
  a payment method on file?
- **Q9.** Under-13: local-only (recommended), or build verifiable parental
  consent?
- **Q10.** Who handles takedown and erasure requests, and what response time do
  the terms promise?
- **Q11.** Is this a section of the radio app, or does it also come to Archive
  Watch (teleplays, "plays in general")? Teleplays add picture and are out of
  scope here.

---

## 10. To measure (probes before v2)

1. **Second-account write test.** With two test archive.org accounts, create
   an item in `test_collection` with account 1 and attempt a PUT of a new file
   with account 2's keys. Expect 403. Confirms §2.2 by measurement.
2. **Ingest and derive timing.** PUT a 3 MB m4a with and without
   `x-archive-queue-derive:0` and with `x-archive-interactive-priority:1`, into
   `test_collection`. Measure the time until `archive.org/download/...` serves
   it with `ACAO *`. That determines how soon the next relay contributor can
   hear a just-accepted take, and whether the Worker or R2 must serve it in the
   meantime.
3. **Worker streaming upload.** Stream a 4 MB body from the Worker to IAS3.
   Read the invocation's CPU time in the dashboard against the 10 ms free
   limit.
4. **`check_limit` under a burst.** Upload 30 takes to one item in a minute and
   watch `bucket_ration` and `over_limit`.
5. **Archive.org Terms of Use.** Render `archive.org/about/terms.php` in a real
   browser. Record the clauses on uploads by an organization for its users,
   automated uploads, minimum age, and the licence granted to IA.
6. **On-device script match.** Score 50 recorded lines (verse, dialect, archaic
   diction) on iOS and Android on-device recognizers. Pick a flag threshold
   with a control set of deliberately wrong lines.
7. **Stand-in voice inventory.** Count the distinct installed voices per
   language on an iOS 18 device, a current Android phone, a Fire tablet and
   desktop Chrome/Safari. Decides how many roles can have distinct stand-ins.
8. **R2 activation** on a free Cloudflare account: is a payment method
   required?
9. **LibriVox claim-expiry rule** (forum rules thread). Is there a hard
   deadline that LibriVox itself found necessary?

---

## Sources

**LibriVox** (raw wikitext via `?action=raw`, fetched 2026-10-18)
- https://wiki.librivox.org/index.php?title=How_to_Become_a_Dramatic_Reading/Play_Coordinator
- https://wiki.librivox.org/index.php?title=An_Introduction_to_Dramatic_Readings_and_Plays_for_New_Readers
- https://wiki.librivox.org/index.php?title=How_to_Edit_a_Dramatic_Work
- https://wiki.librivox.org/index.php?title=An_Introduction_to_Proof-listening_a_Dramatic_Work
- https://wiki.librivox.org/index.php?title=Information_on_coordinating_dramatic_readings
- https://wiki.librivox.org/index.php?title=Copyright_and_Public_Domain
- https://wiki.librivox.org/index.php?title=How_To_Become_A_Book_Coordinator
- https://archive.org/metadata/ahiveofbusybeesdrversion_2610_librivox (MEASURED)

**Common Voice**
- Ardila et al., "Common Voice: A Massively-Multilingual Speech Corpus",
  https://arxiv.org/pdf/1912.06670v1 (validation rule, CC0)
- https://github.com/common-voice/common-voice (README)

**Smule / BandLab / rehearsal apps / Riverside** (search results; secondary
unless noted)
- https://venturebeat.com/technology/smule-adds-video-duets-to-its-sing-karaoke-mobile-app
- https://mollysoda.substack.com/p/thanks-for-joining
- https://apps.apple.com/app/id509993510
- https://help.bandlab.com/hc/en-us/articles/48041963115033-What-is-Forking (official)
- https://help.bandlab.com/hc/en-us/articles/4402292152857-Navigating-the-Project-Page (official)
- https://www.audeobox.com/learn/bandlab/bandlab-collaboration-features/
- https://mwm.ai/apps/off-book-pro/1072004273
- https://mwm.ai/apps/run-lines-script-rehearsal/6755323192
- https://apps.apple.com/om/app/acting-pal-learn-lines/id6736730265
- https://mwm.ai/apps/coldread/1264354117
- https://riverside.fm/blog/how-to-record-audio-and-video-separately
- https://help.rode.com/hc/en-us/articles/14562059377423

**archive.org** (fetched 2026-10-18 unless noted)
- https://archive.org/developers/ias3.html
- https://archive.org/developers/items.html
- https://archive.org/developers/metadata-schema/index.html
- https://archive.org/developers/bots.html
- https://archive.org/developers/tutorial-get-ia-credentials.html
- https://help.archive.org/help/uploading-a-basic-guide/
- https://help.archive.org/help/collections-a-basic-guide/
- https://archive.org/about/terms.php (could not be rendered; UNVERIFIED)
- https://raw.githubusercontent.com/jjjake/internetarchive/master/internetarchive/config.py
- https://pypi.org/pypi/internetarchive/json
- Measured: `s3.us.archive.org` unauthenticated PUT (403), `?check_limit=1`
  (rations), OPTIONS preflight (ACAO * with PUT), download redirect and storage
  node CORS.

**Cloudflare** (fetched 2026-10-18)
- https://developers.cloudflare.com/d1/platform/limits/
- https://developers.cloudflare.com/d1/platform/pricing/
- https://developers.cloudflare.com/workers/platform/limits/
- https://developers.cloudflare.com/r2/pricing/

**Stores and law**
- https://developer.apple.com/app-store/review/guidelines/ (1.2, 1.3, 4.8,
  5.1.1(v)-(vi), 5.1.4; fetched)
- https://support.google.com/googleplay/android-developer/answer/9876937 (UGC;
  fetched)
- https://www.law.cornell.edu/cfr/text/16/312.2 (COPPA definitions; fetched)
- https://www.federalregister.gov/documents/2025/04/22/2025-05904/childrens-online-privacy-protection-rule
  (effective date via API)
- https://ftc.gov/system/files/documents/public_statements/1266473/coppa_policy_statement_audiorecordings.pdf
  and
  https://www.ftc.gov/system/files/documents/federal_register_notices/2017/12/coppa_frn_12-8-2017.pdf
  (2017 voice policy; via search)

**This repo**
- `docs/SHAREPLAY.md` §11.5-11.6, `worker/schema-rooms.sql`,
  `worker/src/together.js`, `worker/wrangler.toml`
- `tools/archive_lib.py`
- `privacy.html`
- `docs/research/RADIO-DRAMA.md`, `docs/research/radio/02-rights.md` §3
