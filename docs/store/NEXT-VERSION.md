# Next store version: the paperwork, matched to the app (B23)

**Status: DRAFT for the next App Store and Play submission, written 2026-11-24 from main at 1eb78578 (1.0.170, build 171).**
Nothing here was set in App Store Connect or Play Console, nothing was submitted, and no build was made. The words
are drafts: the owner approves store words (Decision 060) and the privacy and policy wording is the owner's
(Decisions 084, 088). A line marked *not verified* is a thing this pass could not read or measure; it is named so
it is not mistaken for a finding.

**What was read live (2026-11-24, read-only GETs, no contact details copied):**

| Item | State |
|---|---|
| `tools/asc_release.py status` | repo 1.0.170 (171). tvOS 1.0.137 is READY_FOR_SALE (build 171 uploaded, VALID). iOS and macOS 1.0.137 are WAITING_FOR_REVIEW, submitted with build 138. |
| Age rating declaration | two exist: the live app info (READY_FOR_SALE) and the one on the submitted version (WAITING_FOR_REVIEW). Both quoted in section 3. |
| Review details | the 1.0.137 notes on iOS and macOS are `APP-REVIEW-NOTES.md` verbatim, on tvOS `APP-REVIEW-NOTES-TVOS.md` verbatim. Contact fields are filled (not copied here). No demo account (`demoAccountRequired` false). |
| Listing | en-US only; What's New is empty on all three (Connect takes none on an app's first version, `tools/asc_release.py:308-316`); the promotional text and keywords are `LISTING-DRAFT.md`'s. |
| App Privacy label | **not readable.** `GET v1/apps/{id}/appDataUsages` answers 404 "relationship does not exist"; the public API cannot read or set the label (`tools/asc_listing.py:2-3`). The "current" column in section 2 is therefore the last recorded intent (`LISTING-DRAFT.md`, "Privacy answers") plus what the privacy manifest declares, and the owner must compare it with the App Privacy page in the Connect web UI. |
| Play Data safety, target audience, content rating | **not readable** (the Play Developer API does not expose them). Section 4 gives what they must say; nothing says what they say now. |

Catalog facts used below, read from `https://eardrama.org/data/manifest.json` (generated 2026-11-24): 73,630
episodes, 4,841 series; the play library has 803 plays (DECISIONS 088).

---

## 1. What leaves the device, by feature added since 1.0.137

1.0.137 was cut 2026-11-16 (`8c9340a7`). The first row is the baseline that already shipped, because every later
row hangs on it and the label has to count it. Proof is `file:line` in this tree.

Legend: **who** A = signed-in adult or teen, T = teacher (signed in), S = student seat (no account), R = anonymous
reader in a room.

| Feature (who) | What leaves the device | Where it goes | How long it stays | Proof |
|---|---|---|---|---|
| **Sign in and sync** (A, T; shipped before 1.0.137, Decision 057) | Apple's or Google's opaque account number, never name or email; a device kind ("web", "iphone"); history, queue and follows while signed in | Cloudflare Worker, D1 database | Until the person deletes the account, or 3 idle years after a 30-day notice; a refresh session 60 days | `worker/src/auth.js:11-12` (never the email, name or tokens), `:32` (60-day session), `:148` (identity row); `worker/src/sync.js:93,103`; `worker/src/account.js:25-44` (every table deleted with the account) |
| **Classes and student seats** (T, S; Decisions 082, 084; web, iOS, iPadOS, macOS, Android; not tvOS) | The class name and join code, an under-13 flag, an end date; **names the teacher typed for students** (a first name, nickname or "Group 3", 40 characters, through the name filter); who reads which part; the teacher's Approve or Again mark and **an optional typed note (500 characters) shown to that one student**; for an under-13 class the school's authorization reference. Never a birth date, email or photo | Worker, D1 | Deleted by Delete class; the day after the end date (default the July 31 of the school year, at most 400 days ahead); 12 months idle after a 30-day notice in the teacher's list; or a school's request within 30 days. A submitted production is kept, with its takes' fields but no seat, review or note | `worker/src/plays.js:802-817` (class made), `:836`; `worker/src/plays-seats.js:33` (note limit), `:132` (label filter), `:165` (release), `:319` (seat claimed, key returned once), `:364` (under-13 refused without school consent); `worker/src/plays-retention.js:91-98` (delete, detaching a submitted production); DECISIONS 084 |
| **Read rooms** (anyone, no account; Decision 082; web, iOS, iPadOS, macOS, Android; Apple TV and Google TV as the shared screen) | The place in a script (line id, mode), the cast sheet, a random member id and the hash of a random key, a role and the part held; an adult reader's **typed name** (40 characters, name filter); a TV's pairing code | A Durable Object per room, or D1 polling when the object cannot store | `deleteAll()` when the room ends or 6 idle hours pass; an ended room keeps only the end time for 6 hours; 40 members at most; a TV pairing code lasts 10 minutes, once | `worker/src/read-rooms.js:126` (name filter), `:423,588,617` (`deleteAll`); `worker/src/read-protocol.js:33` (40 members), `:43` (6 hours); `docs/WORKER.md` "Read rooms"; PARITY rows "Table read", "Shared screen of a read room" |
| **Relay of takes** (record in the room, relay across time; S, R, A, T) | **The audio of a take** (a student's or reader's voice) from the device that recorded it to the leader's or teacher's device. A take with no receiver waits on the recording device and is sent when both are open. A seat key is kept in the Keychain or Keystore only when a student records at home | Through the Worker's memory only; the take's fields (line, part, byte count, rate; no audio) go to D1, credited to the seat's teacher or to the reader's typed name | The audio is never written: no R2, D1, KV or Durable Object storage; it is held in flight (at most a 64 KiB head and one chunk). The take's row follows the production or class. Seat key in a room: memory for the app run (a tab on the web) | `worker/src/take-relay.js:1-8` ("never calls `ctx.storage`"), `:16` (memory held); `worker/src/plays.js:484` (the row has no audio column), `:547-548` (upload pipes to the director); `apple/Core/Plays/ReadSession.swift:8`, `android/.../plays/ReadSession.kt:35`, `js/read-session.js:12` (room keys not at rest); `apple/Core/Plays/RelayAcrossTime.swift:194-207` (home key in the Keychain) |
| **Shared plays, now for every library play, and Publish** (A, T; Decisions 059, 072, 073, 082, 084; R4-0) | Invite: a hash of an invite token, a display name (may be empty), parts, the CC0 consent record. R4-0 adds one manifest row per production (title, source, rights evidence, cast-sheet digest; no person column). **Publish** sends the performers' lines to archive.org as one public item, under CC0, credited by the names people chose | Worker (D1); the audio streams from the director's pass-through to archive.org | Productions follow Decision 084. A published item stays on archive.org (lines are removable one by one; credits carry only the chosen name). Reports and blocks stay until an account goes. **13 and over only, never an under-13 class; a class needs the teacher's two confirmations** | `worker/migrations/0012_script_rows.sql:1-6`; `worker/src/plays.js:676-677` (`under_13_never_published`), `:684` (credit name filtered), `:746-768` (report row); `worker/src/plays-archive.js:89-95` (credits from chosen names), `:146-149` (streamed, never held whole) |
| **Student privacy controls and the age question** (T, A; Decision 084) | Export class: a file the Worker hands the teacher (labels, casting, progress, takes' fields, notes; no audio). The age question asks a birth year and keeps only "under 13 or not" **on the device**; it is never sent | The teacher's device; the answer stays in `localStorage` or `UserDefaults` | The export is the teacher's file. The answer stays until cleared | `js/age-gate.js:11-20`; `apple/Core/Plays/AgeGate.swift:15-19`; `docs/research/design/R3d-drafts/data-inventory.md` section 1.8 |
| **Add a script** (web only; Decision 088.3, R4-2) | Nothing. The pasted or opened text is kept in the browser's IndexedDB and in the person's own export | Stays on the device | Until the person deletes it | `js/own-store.js`; PARITY row "Add a script" ("no account, nothing sent"); the Apple and Android cores (`OwnScript.swift`, `OwnScript.kt`) have no screen yet |
| **Shared own scripts and publishing a script you wrote** (Decision 088.4, 088.5) | **Not built.** No route, table or screen holds a person's text (`grep play_scripts` finds nothing in `worker/`, `apple/`, `android/`, `js/`). 088.4 opens only after a planted report has produced an email, 088.5 only after the title-and-content search has been seen to catch a planted copy | none today | none | `DECISIONS.md` 088.4-088.6; `docs/research/design/R4-record-anything.md` 3.3 |
| **Cast by ear** (R4-3) | **Not built.** Only the line-splitting core exists (`js/own-core.js`, `OwnScript.swift`). No screen asks for an episode transcript. When built it reads the archive.org automatic transcript the person is already shown and keeps the result on the device | none today | none | `docs/research/design/R4-record-anything.md` 2.4; PARITY row "Add a script" note "Cast by ear is R4-3" |
| **Kokoro voices** (Decisions 078, 086; Apple since 1.0.159, Android, web) | A request for model files, on a person's tap in Library > Voices. Speech is made on the device. A stand-in's audio is never stored (Decision 055) | GitHub Releases (`kokoro-model`) serve the files; on Android the engine arrives as a Play Feature Delivery module | The model stays on the device until the person presses Delete | `apple/Core/Plays/KokoroModelStore.swift:26`; `android/.../kokoro/KokoroModelStore.kt:180`; `android/app/build.gradle.kts:253`; `js/kokoro-model.js:56` |
| **Android Auto** (Android; PARITY "Android Auto") | Nothing is sent by us. The browse tree (titles, art addresses, resume position) is handed on the phone to the car host; voice requests are handled by Google's own Assistant and the app answers `onSearch` | the car host on the device | not kept by the app | `android/app/src/main/AndroidManifest.xml:92-117`; `.../res/xml/automotive_app_desc.xml:3`; PARITY lines 262, 385 |
| **CarPlay stub** (iOS) | Nothing. The entitlement `com.apple.developer.carplay-audio` is not in `EarDrama.entitlements` (Apple has not granted it), so no car scene ever connects | none | none | `apple/iOS/CarPlay_iOS.swift:11-14`; `apple/Resources/EarDrama.entitlements` (no carplay key) |
| **Read along, Library Listening and Making, voice defaults, Export my data, the reader's marks** | Nothing. Preferences and marks are on the device; Export my data writes a file the person saves | device | until deleted | PARITY rows "Read along", "Library, direction B", "Export your data" |

What the Worker sees and does not keep: the requester's address (counted per minute by Cloudflare's rate limit,
`worker/wrangler.toml` ratelimits); `wrangler.toml` has no `[observability]` block, so logs are not persisted by
us (the Cloudflare dashboard setting itself was *not verified*, a standing owner item in the data inventory 1.7).
The apps' only other network contacts are archive.org (audio), GitHub (catalog files, model files),
eardrama.org, and Wikimedia, Library of Congress and Smithsonian for pictures (`data-inventory.md` section 3).
`allowBackup` is false on Android (`AndroidManifest.xml:24`), so device data is not copied by Auto Backup.

---

## 2. Apple App Privacy label

**Current answers: unreadable by API; the last recorded intent is `LISTING-DRAFT.md` "Privacy answers"
(2026-10-23):** no data collected without signing in; signed in, an account identifier and listening history,
linked, for sync only; "recording a play: audio stays on the device in phase 1; nothing is uploaded". The privacy
manifest still says "no account, no analytics, no ads: nothing is collected" with an empty
`NSPrivacyCollectedDataTypes` (`apple/Resources/PrivacyInfo.xcprivacy:4-5,23-24`), which has been untrue since
sign-in and sync shipped (Decision 057, before 1.0.137). **Open the App Privacy page in Connect, record what it
says, and compare with the second column.** One label covers iOS, iPadOS, macOS and tvOS, so each row takes the
widest platform.

Apple's definition used below: "collected" means the data is sent off the device and kept longer than needed to
serve the request in real time. Tracking is **No** everywhere: no third-party ads, no analytics SDK, no data broker
(`PrivacyInfo.xcprivacy:19-22`, `NSPrivacyTracking` false, no tracking domains).

| Data type (Apple's list) | Intent on record | What it must be | Linked to identity | Tracking | Purpose | Proof |
|---|---|---|---|---|---|---|
| Contact Info > **Name** | not collected | **Collected.** Display names people type for a production, an adult read-room name, a performer's credit name, and **a student's first name or label typed by a teacher** | Yes for a member or teacher (stored with their user id); a seat label is tied to the class, not to a person's identity | No | App Functionality | `plays.js:252,402,684,836`; `plays-seats.js:132`; `read-rooms.js:126`; `data-inventory.md` 1.4, 1.5 |
| Contact Info > Email, Phone, Address | not collected | **Not collected.** Sign in with Apple's "Hide My Email" address arrives in the token and is written nowhere | n/a | n/a | n/a | `auth.js:11-12` |
| Identifiers > **User ID** | collected, linked, sync | **Collected.** Our random account id and the provider's opaque account number | Yes | No | App Functionality | `auth.js:148`; `account.js:25-44` |
| Identifiers > Device ID | not collected | **Not collected.** The device kind ("iphone") is stored, never a device identifier | n/a | n/a | n/a | `data-inventory.md` 1.1 |
| User Content > **Audio Data** | "stays on the device" | **Collected, narrowly.** A take passes through our server in memory and is deleted on arrival, which Apple's real-time rule does not count; but a recording a person **publishes** goes to the Internet Archive and stays, with credits, and a class's takes pass through to the teacher. Declare it so the page cannot be read as "no recordings leave the device" | Yes (a take row carries the performer's or the teacher's user id) | No | App Functionality | `take-relay.js:1-8`; `plays-archive.js:89-95,146-149`; `plays.js:676-677` |
| User Content > **Other User Content** | not collected | **Collected.** Production cast sheets and part claims, **a teacher's typed note to one student**, Approve or Again marks, the class name. (Apple has no messages-between-users row outside Messages; notes and names fit here) | Yes | No | App Functionality | `plays-seats.js:33`; `data-inventory.md` 1.4, 1.5 |
| Usage Data > **Product Interaction** | collected, linked, sync | **Collected only when signed in:** history (where you stopped), queue, followed shows, which Apple's own examples name ("saved place in a song or video") | Yes | No | App Functionality | `sync.js:93,103,125` |
| Usage Data > Other Usage Data, Advertising Data | not collected | **Not collected** | n/a | n/a | n/a | no analytics in any client (`PrivacyInfo.xcprivacy`; `data-inventory.md` section 3) |
| Diagnostics (crash, performance) | not collected | **Not collected.** No crash or analytics SDK; Apple's own crash reports are Apple's | n/a | n/a | n/a | same |
| Location, Contacts, Photos, Health, Financial, Purchases, Search History, Browsing History, Sensitive Info | not collected | **Not collected.** The age question's birth year never leaves the device | n/a | n/a | n/a | `age-gate.js:11-20`; `AgeGate.swift:15-19` |

Judgement calls the owner should see, not hide: (a) the **address of a request** reaches archive.org, GitHub
and Cloudflare as it reaches any host a media app contacts; the label above does not list IP address because Apple
asks about data collected through the app's own service and these hosts are the content's origin (Cloudflare
runs our Worker and counts requests for a minute). Say so in the privacy page, which already names each company
(`privacy/index.html` lines 117-119); (b) the Kokoro model download is a request to GitHub, which the page
describes only as "requests for the website and catalog files" (line 117): one added phrase would make it exact
(owner's wording); (c) children: the label has no field for it, and Decision 084's school-authorization route is
the answer for under-13 classes (FTC FAQ N.3).

Also update: `NSPrivacyCollectedDataTypes` in `PrivacyInfo.xcprivacy` to the same list (header comment too), and
the microphone string, which is wrong today (section 8, item 2).

---

## 3. Apple age rating declaration

Two declarations exist. **Live app info** (READY_FOR_SALE, the shipped tvOS 1.0.137) and the **submitted version's**
(WAITING_FOR_REVIEW) differ only in the old scale (`INFREQUENT_OR_MILD`) against the new (`INFREQUENT`) and in
fields the old one left null. Both were written by `tools/asc_listing.py:57-75` (`AGE`), the source of truth.
Read 2026-11-24.

| Question (API field) | Current (submitted version) | Correct for the next version | Proof |
|---|---|---|---|
| **Messaging and chat** (`messagingAndChat`) | false | **true.** People exchange voice takes and typed text through the app: a teacher's typed note to a student, performers' takes sent to a director or teacher, and names typed into read rooms. It is not open chat, but Apple's wording asks whether users communicate by text or audio, and a no would be hard to defend | `plays-seats.js:33` (500-character note), `take-relay.js:1-8`, `read-rooms.js:126` |
| **User-generated content** (`userGeneratedContent`) | true | **true** (keep). Takes, display names, a teacher's notes, published recordings; own scripts shared later | `plays.js:746-768`; `plays-archive.js:89-95` |
| Social media (`socialMedia`) | false | **false.** No feeds, follows of people, or public profiles; a person is a name inside a production or room | `data-inventory.md` 1.4 |
| Age assurance (`ageAssurance`) | false | **false.** A neutral birth-year question exists but nothing verifies age; read Connect's help text for this field when answering (*not verified here*) | `age-gate.js:11-20` |
| Unrestricted web access (`unrestrictedWebAccess`) | false | **false.** The app opens fixed source pages in the system sheet, never a browser a person can point anywhere | `apple/Shared/SourcePages.swift:12-17` |
| Advertising (`advertising`) | false | **false.** No ads | `PrivacyInfo.xcprivacy:19-22` |
| Shared location (`sharedLocation`) | false (live: null) | **false.** No location use | no `NSLocation*` string in `project.yml` |
| Parental controls (`parentalControls`) | false | **false.** The app has none of its own | n/a |
| Guns or other weapons (`gunsOrOtherWeapons`) | NONE | **arguable: `INFREQUENT`.** The catalog's Western and crime series (Gunsmoke is a launch screenshot) have gunfights; this is audio only and the realistic-violence answer is already `INFREQUENT`. Owner's call; a `NONE` here sits oddly beside it | `LISTING-DRAFT.md` screenshots table; genre list in `manifest.json` (`western`, `mystery`) |
| Realistic violence (`violenceRealistic`) | INFREQUENT | **INFREQUENT** (keep) | same |
| Prolonged graphic or sadistic violence | NONE | **NONE** | n/a |
| Cartoon or fantasy violence | NONE | **NONE** | n/a |
| Horror or fear themes (`horrorOrFearThemes`) | INFREQUENT | **INFREQUENT** (keep). Mystery and science-fiction series exist; the manifest has no horror genre, so frequency could not be measured, not *verified* either way | `manifest.json` `genreNames` |
| Mature or suggestive themes | INFREQUENT | **INFREQUENT** (keep) | n/a |
| Alcohol, tobacco or drug references | INFREQUENT | **INFREQUENT** (keep) | n/a |
| Profanity or crude humor | NONE | **NONE** is true of what was read, but the catalog is third-party uploads from the Internet Archive that cannot be fully vetted; `INFREQUENT` is the conservative answer. Owner's call | `LISTING-DRAFT.md`; Decision 055 |
| Sexual content or nudity, and graphic | NONE, NONE | **NONE, NONE** | n/a |
| Medical or treatment information, health or wellness topics | NONE, false | **NONE, false** | n/a |
| Dating and relationships, contests, gambling, simulated gambling, loot boxes | false, NONE, false, NONE, false | **unchanged** | n/a |
| Age rating override, Korea override, kids age band | NONE, NONE, null | **unchanged.** The app is not in the Kids category | n/a |

After saving, read the rating Connect computes: a yes to messaging may raise it, and what it becomes was *not
verified* (Connect computes it on save). The categories (Entertainment, with Education secondary on the submitted
version) do not change the answers.

---

## 4. Google Play

*The Console forms below could not be read through the API, and Play's current Families text was not re-read, so
each answer is what the code supports and must be checked against the Console's own wording.*

### 4.1 Data safety

Android app id `app.eardrama`; permissions: `INTERNET`, `ACCESS_NETWORK_STATE`, `WAKE_LOCK`, `FOREGROUND_SERVICE`,
`FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `RECORD_AUDIO` (`AndroidManifest.xml:5-11`, the microphone only when a
performer presses record). No Firebase, Crashlytics, analytics or ad SDK in `android/app/build.gradle.kts`. Sign-in
uses Credential Manager with Google (and the web flow for Apple), Play Feature Delivery brings the Kokoro engine.

| Play data type | Collected? | Shared? | Optional? | Purpose | Notes and proof |
|---|---|---|---|---|---|
| Personal info > **Name** | Yes | No | Yes (a display name may be empty) | App functionality | production names, room names, a credit name, teacher-typed student labels: `plays.js:252,402,684,836`; `plays-seats.js:132` |
| Personal info > Email, address, phone, race, politics, religion | No | n/a | n/a | n/a | Google's account email arrives in the token and is not stored: `auth.js:11-12` |
| Personal info > **User IDs** | Yes | No | Yes (sign-in is optional) | App functionality | `auth.js:148` |
| **Audio > Voice or sound recordings** | Yes | See below | Yes | App functionality | takes pass through our server in memory only (`take-relay.js:1-8`); Play's own wording allows ephemeral processing to be left out, but a published recording is **kept on archive.org**, so declare it. Sharing: a person-initiated, consented upload to archive.org (the CC0 consent screen, 13 and over); mark **not shared** with third parties for the pass-through, and describe the archive.org upload in the policy |
| Messages > **Other in-app messages** | Yes | No | Yes | App functionality | a teacher's typed note to one student: `plays-seats.js:33` |
| App activity > **App interactions** | Yes (signed in only) | No | Yes | App functionality | history, queue, follows: `sync.js:93,103,125` |
| App activity > **Other user-generated content** | Yes | No | Yes | App functionality | cast sheets, part claims, class names, Approve or Again marks |
| App info and performance (crash logs, diagnostics) | No | n/a | n/a | n/a | no crash SDK |
| Device or other IDs, Location, Contacts, Photos and videos, Files, Calendar, Health, Financial | No | n/a | n/a | n/a | n/a |

Security practices: data encrypted in transit **Yes** (every route is HTTPS; the Worker's origin list is
`https://eardrama.org`, `wrangler.toml`). **Users can request deletion: Yes**, in the app (Library > Account >
Delete Account) and by the web page `https://eardrama.org/delete-account/`; classes and students' seats are
deleted by the teacher, the end date, idleness, or the school's request (Decision 084). Independent security
review: **No**. Data is not sold. The privacy policy URL is `https://eardrama.org/privacy/`.

### 4.2 Target audience and content, and Families

Recommended answers and the one conflict to resolve:

- **Target age groups: 13 and over (13-15, 16-17, 18+), not "appeals to children".** Ear Drama is a general-audience
  app. The under-13 path is a teacher-run class under a school's authorization (Decision 084; FTC COPPA FAQ N.3),
  the same model Apple's label cannot express either.
- **Conflict (decide before submitting):** Android has the class's "Under 13" switch too (PARITY "Teacher classes",
  Android cell). If the Console's wording makes under-13 use of the app count as a child-directed audience, the
  Families policy applies (its restrictions on sign-in, data and content), and the app does not satisfy a rule the
  school-authorization model rests on. *Not verified:* whether Play accepts the school-authorization route. Until
  that is read in the Console, either answer "13 and over" and say in the listing's "for schools" copy that an
  under-13 class is a teacher's use, or switch the under-13 class off on Android until the answer is known.
- **Content rating (IARC):** users can exchange content (voice takes and text names or notes) and the catalog has
  crime, western and mystery drama with violence. Answer "users interact: yes, share content: yes (audio and text),
  share location: no, digital purchases: no, ads: none". The rating Play assigns was *not verified*.
- **News app, health, government, financial features:** none. **Ads:** none.

### 4.3 CarPlay and Android Auto review notes

**CarPlay (Apple):** not needed for this submission. `EarDrama.entitlements` carries no `carplay-audio` key, so no
CarPlay scene connects (`CarPlay_iOS.swift:11-14`) and Apple's request is still unanswered (LOOP-PLAN, 2026-11-14).
When Apple grants it, add to the notes (under 700 characters): "CarPlay: Ear Drama is an audio app. In the car it
shows four tabs, Continue, Stations, Browse and Downloads. Continue and Downloads play. It uses the phone's player
and listening history; it records nothing, shows no video and takes no payment."

**Android Auto (Play):** the manifest declares a media browser service and `automotive_app_desc` of type media
(`AndroidManifest.xml:92-117`), and PARITY line 262 records that every release with car support waits on Google's
car review and goes to the internal or closed track only. *Not verified in a car or the Desktop Head Unit*; the
tree was browsed on the Pixel 8a by a media browser client (`CarBrowseProbeTest`). Text for the Console's car
instructions (about 600 characters):

> Ear Drama is a media app. In Android Auto it shows four tabs: Continue (resume where you stopped), Stations
> (live old-time radio evenings), Browse (shows you follow, popular, genres, by length) and Downloads. Search and
> spoken requests ("play Gunsmoke") are answered by the app. Playback uses the phone's own player; no video, no
> messaging, no sign-in is needed in the car. Every folder answers within 8 seconds or shows one text row. The
> microphone is never opened by the car interface.

---

## 5. Review notes for iOS, iPadOS and macOS (replaces `APP-REVIEW-NOTES.md`)

Written to be pasted into App Review Information (the limit is 4,000 characters; this text is measured below in
the section's last line). Facts checked against the code in section 1. The text held in brackets is true only after
must-fix item 1 in section 8, and **must not be sent before then**.

```
This update adds classes for teachers, reading a play together in a room, and sending a recorded part to a teacher or director. The attached screen recording (physical iPhone, latest iOS) shows launch, listening, Search, the reader and studio, sign-in, a shared production with Report and Block, a read room, and Delete Account.

1. PURPOSE AND AUDIENCE
Ear Drama is a free, ad-free place to listen to old-time radio and radio drama from the Internet Archive, and to read and record radio plays. It is for listeners, families, amateur actors, and teachers and students who perform a play together.

2. HOW TO REACH EACH PART
- No sign-in needed: Home, Browse, Search, Library, the Record tab, the script reader, recording on this device, and Read together.
- Sign in: Library, scroll to the bottom, Account, Sign in with Apple. Use your own Apple ID; there is no demo account. We keep a random account number, never your name or email.
- Delete account: Library, Account, Delete Account, confirm. This removes the account, history, queue, follows and classes from our server at once.
- Report and Block: Record tab, a shared production, People. Every other member has Report (with reasons) and Block. A director can remove any line.
- Read room on one device: open any play, choose Read together. A room opens with a code and you lead it; Next moves the line everyone sees. No account is needed; a room is deleted 6 hours after last use.
- Class on one device: signed in, Record tab, Make a class, paste first names, Start a reading. The student side runs in a second browser window at eardrama.org/read/CODE, where a student picks a name and needs no account. A class marked under 13 sends no student recording until the teacher records the school's approval.
- Mac: the same, with the Mac microphone.

3. USER CONTENT
People can invite others to a production by link. Display names, class names and student names a teacher types pass a server-side name filter. Students have no accounts; their names show only inside their class. A teacher's note is seen only by its student. Names typed into a read room are filtered too, and the leader can lock or end the room. [Each report is sent to the developer by email notification and answered by the developer.]

4. WHERE RECORDINGS GO
A take stays on the device that made it. In a shared production, room or class it is passed through our server to the director's or teacher's device and deleted from the server as it arrives; no audio is stored on our server. Only a director, or the teacher of a class marked 13 and over, can publish. Publishing shows a consent screen and uploads the recording to archive.org under CC0 with credits; a class also needs the teacher's two confirmations (every performer agreed; the school holds a media release for each performer under 18). A class marked under 13 can never publish. Students' names are never published.

5. EXTERNAL SERVICES
archive.org (audio, metadata); Project Gutenberg (play texts, pre-processed); eardrama.org on GitHub Pages (catalog, pages); our server (a Cloudflare Worker with a database) for optional accounts, sync, shared productions, classes and rooms; Sign in with Apple. Stand-in voices are Apple's on-device speech synthesis or an optional downloaded voice model that runs on the device. Nothing goes to an AI service.

6. THIRD-PARTY MATERIAL
Ear Drama does not host audio; it streams recordings the Internet Archive publishes, each linked to its source. Recordings are removed on request at eardrama.org/takedown (complete notices answered within 48 hours); Learning is Change, Inc. has a registered DMCA agent (DMCA-1083942). Play texts come from Project Gutenberg records that document US public-domain status.

7. BACKGROUND AUDIO (2.5.4)
Ear Drama is an audio player. Listening continues when the person leaves the app, with Ear Drama in Now Playing in Control Center; this is why the app declares the audio background mode. The app works the same in every region.
```

(Measured 2026-11-24 with the held sentence in: see section 9.)

### 5.1 Review notes for tvOS (replaces `APP-REVIEW-NOTES-TVOS.md`)

```
BACKGROUND AUDIO (2.5.4): Ear Drama is an audio player. It plays old-time radio episodes and live stations, and it plays ear dramas people record on iPhone, iPad and Mac. Listening continues when the person leaves the app: press the TV button during an episode and the audio keeps playing, with Ear Drama in Now Playing in Control Center, where it can be paused, resumed or skipped. This is why the app declares the audio background mode. A recording from a physical Apple TV 4K (tvOS 27.3) is attached in App Review Information (ear-drama-tvos-background-audio.mp4).
HOW TO SEE IT: open Ear Drama, choose Listen Live on Home (or any show, an episode, Play), then press the TV button. Open Control Center to see Ear Drama in Now Playing.

1. PURPOSE AND AUDIENCE
Ear Drama is a free, ad-free place to hear drama made for the ear: old-time radio and radio drama from the Internet Archive, and ear dramas people record on iPhone, iPad and Mac. On Apple TV it is for listening, and it can be the shared screen for a reading. The TV records nothing.

2. HOW TO USE THE MAIN FEATURES (no login needed)
- Home: On the air, Listen Live. Browse and Search: find a series or episode and Play.
- Library: what you have played and queued. Signing in (Sign in with Apple, optional) syncs listening and shows ear dramas shared with you. Library, Account is where to sign in or delete the account; Delete Account removes the account and its data from our server.
- Shared screen: a person leading a read room on another device or a browser (open any play at eardrama.org, choose Read together) can attach the TV: on the TV, Library, Show a Reading, and enter the room's code. The TV shows the current line in large type and the room code, holds no part and leads nothing. Share on an episode shows a QR code for a phone to scan.

3. EXTERNAL SERVICES
archive.org (audio and metadata); eardrama.org on GitHub Pages (catalog data); our server (a Cloudflare Worker) for optional accounts, sync and rooms; Sign in with Apple. No analytics, no ads, no payments, no AI services.

4. REGIONS
The app works the same in every region.

5. THIRD-PARTY MATERIAL
Ear Drama does not host audio; it streams recordings the Internet Archive publishes, each linked to its source. Recordings are removed on request at eardrama.org/takedown (answered within 48 hours); Learning is Change, Inc. has a registered DMCA agent (DMCA-1083942).
```

*The two tvOS lines about attaching the TV and the QR code are from PARITY (rows "Shared screen of a read room" and
the 1.0.167 QR change) and were not re-run on the Apple TV in this pass.*

### 5.2 Held paragraph for when apps get Add a script (R4-6, R4-7)

Add to section 3 of the iOS and Android notes only when the Apple and Android screens ship: "Add a script: Record tab,
Add a script, paste or open a text file. The text stays on the device. A script you add cannot be published, and
cannot be shared yet." Cut "cannot be shared yet" when R4-4 ships, and replace section 3's first line with the
report and removal route from R4-record-anything.md 3.4.

---

## 6. Demo recording shot list (an automated tour drives it)

Rules (owner): never ask the owner to record or to touch a device (`automate_store_demos_fully`); capture
headless, with `devicectl` screenshots and the tap tier's attached frames stitched with `ffmpeg`, never QuickTime
or Device Hub windows (`no_mac_apps_for_device_capture`, 2026-11-16, which supersedes the Device Hub method that
`APP-REVIEW-RECORDING.md` still describes); real devices only (the iPhone 12, lease "iphone"; the open Duo; Ben
Bedroom, lease "atv" for the TV); one simulator-free run at a time; no `APP_RESET_USER_STATE` on an owner device
without the snapshot the door now takes (`tap_tier_erases_owner_lists`). Where a step needs a fingerprint or Face
ID (Sign in with Apple, the delete confirmation) the tour stops at the system sheet and the notes say so.

The tour that exists: `apple/UITests/AppReviewTourUITests.swift` (`testTour`, marks `launch`, `home`, `listen-live`,
`browse`, `series`, `episode`, `play`, `pause`, `resume`, `search`, `record`, `play-page`, `reader`, `contents`,
`part`, `studio`, `apple-sheet`, `delete-production`, `library`, `account`, `delete-account`, `delete-confirm`,
`end`) and `AppReviewModerationUITests.swift` (`testJoin`, `testModeration`: `people`, `report`, `reasons`,
`block`). Both start with `launch`; both print `TOUR-MARK` lines the stitcher cuts on.

| # | Shot (about seconds) | Shows | Driver |
|---|---|---|---|
| 1 | Cold launch, Home (8) | the app opens, On the air | `testTour` marks `launch`, `home` |
| 2 | Listen Live, Browse, a series, an episode, Play, pause, resume (40) | listening, background-audio player | `testTour` unchanged |
| 3 | Search (8) | search | `testTour` mark `search` |
| 4 | Record, a play, Read, Contents, I'm playing, Record in the studio (40) | the reader and recording on this device | `testTour` marks `record` to `studio` |
| 5 | Sign in with Apple, to the system sheet (10) | where sign-in is | `testTour` mark `apple-sheet`; stops there |
| 6 | **Read together**, signed out (30) **new**: play page, Read together, the room opens with a code, Next three times, Table read, then End | a read room with no account and no second device; room is deleted on end | new test `AppReviewRoomUITests` over the doors `APP_START_PLAY` and a tap on `Read together` (the room is a real Worker room; the door `APP_START_READ_ROOM` joins an existing one) |
| 7 | **A class, teacher side** (40) **new**: Record, the class door, Make a class (13 and over), paste three first names, Start a reading, Casting, back to the class page | teacher side with no student data beyond typed first names | needs a signed-in teacher; production has no test accounts (`tools/class_bench.py` header), so the tour **stops at the Sign in with Apple sheet** and the class frames come from the web run (`tools/class_bench.py --keep-frames`, T10) in real Chrome on the Pixel 8a |
| 8 | **A class under 13** (10) **new**: Make a class with Under 13 on; the class page says "Waits for the school's consent" and a School approval box | no student recording is sent until the teacher records the school's approval | web `js/class-ui.js:108-112` frame; Apple and Android frames after sign-in is available; *blocked on the owner setting `SCHOOL_CONSENT_POLICY`* if a consent is to be shown recorded |
| 9 | **Student seat** (20) **new**: a second browser window at the room link, pick a name, the line lights, a take is recorded and sent | no account, no email, the take passes through | `tools/class_bench.py` T10 (web, two Chrome profiles on the Pixel's Chrome or the bench) |
| 10 | **Class privacy** (15) **new**: Class section: end date, Export class, Delete class (stop before the destructive confirm) | the retention controls from Decision 084 | frames from the web run; Apple and Android frames from `ClassPrivacyViews.swift` and `PrivacyUi.kt` once signed in |
| 11 | Shared production, People, Report with reasons, Block (30) | user-content safety | `AppReviewModerationUITests` `testModeration` (needs the second member from `testJoin`'s invite; the invite link is a Release-signed account the notes cannot bundle, so this clip uses the owner's two Apple IDs already signed in on the Duo and iPad, as before) |
| 12 | Publish's consent screen (10) **new**: a 13-and-over production, Publish, the consent text, Cancel | what publishing does and that it asks first | web frame, then native once a signed-in device is available |
| 13 | Library, Account, Delete Account, to the confirm (15) | account deletion | `testTour` marks `account`, `delete-account`, `delete-confirm` |
| 14 | **tvOS** (45): Home, Listen Live, Home Screen with audio still playing, Control Center's Now Playing; Library, Show a Reading (the code field) | background audio and the shared screen entry | the TV harness on Ben Bedroom (`docs/DEVICE-HARNESSES.md`), headless screenshots stitched; the 1.0.137 clip `ear-drama-tvos-background-audio.mp4` is the model |

Blocked, and said so rather than faked: shots 7, 9, 10, 12 on Apple and Android until a signed-in device is
available without a person at the sheet; the web is a real run, the apps are not. The recording attached to the
submission must be one file, one pass, and every frame read before it is attached (`read_audit_frames_myself`).

---

## 7. What's New drafts (the next version of each app)

There is no earlier What's New to match: Connect takes none on an app's first version and all three are empty today.
The voice is the listing's: plain, concrete, no superlatives, nothing a platform lacks (`LISTING-DRAFT.md` rules).
Each line is a fact checked in section 1 and PARITY; a line stays out if its platform cell is not built.

**iOS, iPadOS, macOS** (4,000 maximum):

> Classes. A teacher makes a class, types students' first names, chooses who reads which part, and starts a reading. Students pick their name with the class code. They need no account and no email.
>
> Read a play together. Everyone in a room sees the same line, on iPhone, iPad, Mac, Android and the web. Do a table read, rehearse with your lines hidden, or record, each person on their own device.
>
> Record your part at home and send it to your teacher or director when both apps are open. A take passes through our server and is deleted when it arrives.
>
> Any play in the library can be shared, cast by a class, and read together.
>
> For teachers: delete a class, change its end date, and export it. A class marked under 13 never publishes.
>
> Read along follows the word being spoken and turns the pages. Voices you download (Kokoro) read parts on your device. Library has two sides, Listening and Making. Export my data saves your lists as a file.

**tvOS:**

> The Apple TV can be the shared screen for a reading: the current line in large type and the room's code. Ear dramas shared with you appear in Library. Share on an episode shows a QR code. Library lists what you listen to and follow, with Account and Show a Reading.

**Google Play** (500 maximum):

> Classes for teachers: type first names, assign parts, start a reading. Students pick a name and need no account. Read a play together in a room, on any device. Record your part at home and send it to your teacher; it passes through our server and is deleted on arrival. Any library play can be shared and read together. Teachers can delete or export a class. Read along follows the spoken word. Download Kokoro voices. Library: Listening and Making.

Listing lines to add to the description's MAKE bullets (owner to approve, `LISTING-DRAFT.md` is the source
`tools/asc_listing.py` reads): "Teachers can make a class: students pick their name with a code and need no
account." and "Read a play together in a room, each person on their own device." The description's statement "No
account is needed; signing in is optional" stays true: a class's teacher signs in, a student does not.

Not in any of these, because it is not shipped on that platform: Add a script (web only), cast by ear (not built),
CarPlay (dormant), Android Auto (Android, internal track until the car review).

---

## 8. What the app, the build or the paperwork must change before submitting, ranked

1. **Reports must reach a person (Decision 088.6; not built).** Today a report writes a `play_reports` row with
   status open (`worker/src/plays.js:766-768`) and nothing notifies anyone (`docs/PLAYS-DESIGN.md:1324`, P4;
   no workflow in `.github/workflows/` reads reports). **Does this apply to classes today? Not on their own:**
   a student sees only the teacher's names and notes, the teacher hears the student, and no student sees another
   student's content outside a room. **It does apply today to the two stranger-facing surfaces: invite
   productions (Report and Block exist since 1.0.137, `js/plays-ui.js:1005-1010,1246`, but nobody is told) and
   adult read rooms (a typed name and a voice seen by whoever has the code).** Guideline 1.2 asks for a way to
   report and for timely action; a report that waits unread does not meet the second half. Build the hourly
   OIDC workflow that opens one GitHub issue to the owner stating only a count; then the bracketed sentence in
   section 5 becomes true. Without it, sentence-by-sentence the notes must not claim a response.
2. **The microphone string is wrong** (`project.yml:136`): "The recording stays on this device." It is false once
   a take is sent to a director, a teacher or a room, or published. Replace with: "Ear Drama records your part in
   a play. The recording stays on this device unless you send it to a teacher, a director or a room you joined."
   Needs a build, so it is a change to make before the build that carries the submission.
3. **Privacy manifest** (`PrivacyInfo.xcprivacy:4-5,23-24`): the header and an empty `NSPrivacyCollectedDataTypes`
   say nothing is collected. Update to the section 2 list in the same build.
4. **The App Privacy label** in Connect to the section 2 answers. No API reads or sets it, so it is a step in the
   Connect web page (`tools/asc_listing.py:2-3`). The Play Data safety form to section 4.1 in the Console. Both
   are one-time edits that ride the next submission.
5. **Age rating**: `messagingAndChat` to true in `tools/asc_listing.py` `AGE` (line 72) and in Connect, then read the
   computed rating; decide the two arguable fields (guns or weapons, profanity).
6. **Review notes and recording**: copy section 5 and 5.1 into `APP-REVIEW-NOTES.md` and `-TVOS.md` (the tool reads
   them verbatim and asserts under 4,000 characters, `asc_listing.py:42-44`) and re-record shots 6 to 13. The notes
   attached to 1.0.137 say "Recordings stay on the device", that signing in "only syncs listening", and name no
   class or room.
7. **Play's Families question and the Android Auto declaration** (4.2, 4.3): decide the under-13 class on Android
   against Play's own wording, and either pass the car review first or build the production bundle without the
   `automotive_app_desc` meta-data (the manifest line 117), because PARITY 262 says a car-capable release waits
   on that review.
8. **`SCHOOL_CONSENT_POLICY` is unset** (owner item, `BACKLOG-LOOP.md` "Waiting on the owner"; the policy wording was
   approved 2026-11-21): no school consent can be recorded, so an under-13 class takes no student recording and a
   reviewer who makes one sees "Waits for the school's consent" and nothing more. Set it at the deploy, or
   leave the notes' sentence as written, which is true either way.
9. **Report and Block for read-room readers**: a room has Lock and End for its leader but no per-member remove and no
   Report (`worker/src/read-protocol.js`, no kick message). Apple may ask; add Report on a member's typed name
   (the same endpoint, a room target) before wide release.
10. **Privacy page**: one phrase for the Kokoro download ("GitHub: requests for the website, catalog files and
    voice files", line 117), and, only when shared scripts ship, the R4 section 7.8 phrase. The wording is the
    owner's.
11. **Listing numbers** (73,000 episodes, 4,800 series, 800 plays): still true (73,630, 4,841, 803) and need no edit.

---

## 9. Measured lengths (2026-11-24)

Counted by a short script over the fenced blocks and quotes above: the iOS and macOS review notes 3,986 characters
with the held sentence in (limit 4,000; without it about 3,880); the tvOS review notes 2,403 (limit 4,000); the
iOS, iPadOS and macOS What's New 941 (limit 4,000); the Play What's New 449 (limit 500). `tools/test_us_english.py`
passes with the file in the tree. Re-count after any edit: the iOS notes have 14 characters of room.
