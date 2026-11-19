# R3c: Table reads, classes, and reading a play together

> **Owner rulings, 2026-11-19 (ROUND3-LOOP.md):** storage is archive.org, never Cloudflare. Q1's R2
> recommendation is superseded: a take passes through the Worker to the teacher's device and is deleted on
> arrival, and the teacher uploads the full recording under their name. Q2, Q3, Q5 and Q7 adopted as recommended.

*Research and design, 2026-11-19. Research only: no code changed. Written for
the owner's request of 2026-11-19, quoted in full in §0. Decision-ready: §9
lists the owner questions that our rules do not already answer.*

## §0. The request, and the short answer

> "We theoretically have built the functionality for recording a play as a
> 'class' with a 'teacher' organizing the process, but that functionality
> really doesn't exist yet. We need to build out how a teacher actually would
> manage that process. We also need to build out how someone would do this
> with a bunch of different devices in the same room (whether a classroom of
> kids or a group of adults doing a table read). Ideally, all of this would
> work quite easily and would be fully tested on the many devices that you
> have access to for testing. Please research ways of doing 'table reads' or
> other methods for reading through plays together (either synchronously in
> the same room or across space and time). We need to fully build and test
> this process to make it more enticing for our users." (owner, 2026-11-19)

**The owner is right: classes do not exist yet.** Today a "class" is a name, a
code and a list of accounts (§1.1). It owns no play, assigns no part, shows
the teacher no roster on any client, and every student needs an Apple or
Google sign-in to join. Nothing in Ear Drama lets two devices in one room read
the same script together, and recording across devices cannot work in
production yet because take storage (R2) is still switched off (§1.2).

**The proposal** (§3 to §6) has four ways of reading together, all built on
one new piece, a **read room**: a shared cursor in the script that one leader
moves and every device follows.

1. **Table read.** The leader moves the cursor. Each phone lights its own
   lines. A shared screen (a TV, a projector, a laptop) shows the page.
   Nobody records, and no phone makes a sound.
2. **Rehearse.** The same room, plus "Hide my lines" and Again. The shared
   screen alone reads any part nobody holds.
3. **Record in the room.** When the cursor reaches a line, the phone that
   holds that part records it and nothing else. Every voice is heard live in
   the room, so no headphones are needed: no device plays audio during a take.
   Takes upload to the class's production.
4. **Relay across time.** The invite production that exists today, plus
   parts the teacher assigns, so a class can record at home in parallel and
   the teacher can see who is done.

The teacher keeps the judging and the deciding (§7): they cast, they lead,
they approve takes, and they choose whether anything leaves the class.

---

## §1. Audit: what exists today

### §1.1 Teacher classes

**Decisions.** Decision 059 (DECISIONS.md:455-485) says "A teacher account can
run a class and give consent for students under 13 (the school-authorization
route); without one, under-13s record on a device only", and "Teacher classes
need a privacy policy that covers school consent before they open"
(DECISIONS.md:477-478). PLAYS-DESIGN §11.6 keeps two owner items open: **P5**,
the privacy policy for school consent (docs/PLAYS-DESIGN.md:1214), and **P8**,
"Do classes own productions?", whose default is "No: classes are a roster
only; every production is invite-only" (docs/PLAYS-DESIGN.md:1218).

**The Worker** (`worker/src/plays.js:675-790`, routes at 818-825):

| Route | What it does |
|---|---|
| `POST /v1/plays/classes` | Makes a class: name (deny-list filtered), `under13` fixed at creation, an 8-character Crockford code (plays.js:684-705, `CLASS_CODE_LENGTH` at :87) |
| `POST /v1/plays/classes/join` | Joins by code, with an optional display name; refuses the class's own teacher; **refuses any under-13 class without school consent** (plays.js:707-729) |
| `POST /v1/plays/classes/:id/school-consent` | Teacher only. Answers `503 pending_owner_policy` while `SCHOOL_CONSENT_POLICY` is unset, which it is (plays.js:731-749) |
| `GET /v1/plays/classes/:id` | The teacher gets the members (user id, display name, joined time); a member gets the name only (plays.js:751-769) |
| `GET /v1/plays/classes` | `teaching` and `member_of` (plays.js:771-781) |
| `DELETE /v1/plays/classes/:id/members/:user` | The teacher removes a member, or a member leaves (plays.js:783-788) |

Every route is behind sign-in (plays.js:7, worker/src/index.js:52-53). The
tables are `play_classes`, `play_class_members` and `play_school_consents`
(worker/src/account.js:35-37, so account deletion removes them).

**What a class is not.** There is no `class_id` on `play_productions`
(plays.js:276-283 inserts none), so a class cannot own a play. There are no
part assignments; a part is claimed by a person (plays-relay.js:99-105). There
is no session, no progress view, no review, no seat for a student without an
account.

**The clients.**

| Platform | What the teacher sees | Source |
|---|---|---|
| Web | Library > Ear dramas > **Classes**: each class's name and code (in two groups of four), "Waits for the school's consent" on an under-13 class, **Make a class** (name, Under 13), **Join a class** (code, your name). No roster; `getClass`, `school-consent` and member removal are never called | `js/plays-ui.js:914-957`, `js/api.js:1518-1521` |
| iPhone, iPad | The same section; Join asks only for the code (the display name is sent as nil) | `apple/Shared/SharedPlaysViews.swift:507-576`, `apple/Core/Plays/SharedPlays.swift:242-258`, rendered at `apple/Shared/PlaysScreens.swift:137` |
| Mac | The same view in a sheet | same file, `#if os(macOS)` at :567 |
| Apple TV | Nothing (the file is `#if os(iOS) \|\| os(macOS)`, SharedPlaysViews.swift:1) | n/a |
| Android phone | `ClassesBlock`; `classDetail` is called only to read the consent flag, never to list members | `ui/screens/SharedPlaysScreens.kt:597-640`, `plays/SharedPlays.kt:247-260`, `plays/PlaysApi.kt:124-135` |
| Android TV | Nothing | n/a |

PARITY.md:204 reads "🚧 make, join; no roster view yet", which is accurate.

**So, today, a teacher on any platform can:** sign in, make a class, read its
code aloud, and see which classes they teach. **They cannot:** see who joined
(on any client), remove a student (on any client), record school consent (the
Worker refuses), let any under-13 student join, attach a play to the class,
assign a part, start a session, see who has recorded, hear or approve a take,
or keep a class's work private to the class. A student cannot join without
their own Apple or Google account.

### §1.2 Productions and invite links

`worker/src/plays.js` holds invite-only productions (Decision 066,
DECISIONS.md:701-740): the director makes one from a castable script whose
cast sheet hashes to the manifest (plays.js:265-290); invites are 256-bit
tokens stored as hashes, 1 to 30 days (plays.js:367-386); a member claims a
part (plays.js:419-443); takes are mono WAV or FLAC of at most 300 s, kept in
R2 (plays.js:466-540); the newest take is the line's chosen one; publishing
needs every performer's CC0 consent at `cc0-2026-10-29` and queues an
archive.org job (plays.js:640-672, Decision 073). Reports, blocks and a
name filter answer guideline 1.2. An open invite can be read signed out
(`worker/src/plays-open.js:1-22`). Limits: 64 members, 10 takes a line, 100
productions a person (plays.js:76-79).

Three facts decide what a class can do with this today:

1. **Only one part records at a time.** `claimRefusal` refuses a claim while
   any other part is `recording` (`worker/src/plays-relay.js:99-105`;
   PLAYS-DESIGN §11.2: "nothing is claimed while a part records"). A claim
   lasts 7 days (plays-relay.js:19). A class of 25 could record one student at
   a time, a week each, unless every part finishes quickly.
2. **Take storage is off.** The `TAKES` R2 binding is commented out
   (`worker/wrangler.toml`, last lines: "PLACEHOLDER, owner ... uploads answer
   503 storage_not_configured"), owner item P1. Every client says "Uploads are
   off." (PARITY.md:201). No take has ever been uploaded in production.
3. **It has never run against the deployed Worker.** PARITY.md:201 and :202:
   "never against a deployed Worker" on every platform. The Worker itself is
   deployed (`docs/WORKER.md:18`, `eardrama-api.benwilkoff.workers.dev`).

Clients: web `js/plays-share.js` (413 lines), Apple
`apple/Core/Plays/PlaysShare.swift` and `SharedPlaysViews.swift`, Android
`plays/PlaysShare.kt` and `SharedPlaysScreens.kt`. The TVs play back only
(PLAYS-DESIGN §11.7 rule 12, docs/PLAYS-DESIGN.md:1328).

### §1.3 Listen Together rooms: the real-time transport we have

**It is not Durable Objects.** Decision 065 (DECISIONS.md:676-698) chose D1
polling "because Durable Objects are not on the free plan (the zero-cost
rule)". The rules live in `worker/src/room-protocol.js` (258 lines, no imports,
a test fails if it gains one); the HTTP and D1 adapter is `worker/src/rooms.js`
(271 lines). What it does:

- A 6-character Crockford code (room-protocol.js:22-31), normalized the same
  on every stack (:48-66).
- No account: each member is a random id and a key, stored as a hash
  (rooms.js:12-20).
- **The host writes state; members poll** every 2 s while things change and
  every 10 s when still (`DRIFT.pollFastMs`/`pollSlowMs`, room-protocol.js:41-48,
  `pollInterval` :252-255). Every read is a clock sample, and the client
  estimates the server's clock with Cristian's algorithm, best-RTT sample
  (`clockOffset`, :214-229).
- The state is media state only: `episode_id`, `archive_id`, `file`,
  `position`, `playing`, `rate`, `generation` (`applyHostState`, :121-166).
  There is no notion of a script, a line or a part.
- Host handoff to the longest-present member (`nextHost`, :176-181); a member
  silent 2 minutes has left (:35); 20 members at most (:33); an idle room ends
  after 6 hours (:39).
- **Rate limits are per address** (`worker/wrangler.toml`): `ROOM_LIMITER` 300
  a minute, `ROOM_JOIN_LIMITER` 20 a minute, `EVERY_IP_LIMITER` 600 a minute;
  `ROOM_MEMBER_LIMITER` 60 a minute per member key.

Clients: web `js/together-core.js` (a golden-checked port), `js/together.js`,
`js/together-ui.js`; Android `ui/ListenTogether.kt` (and an Android TV joins
by code, PARITY.md:176). **Apple does not use the Worker rooms at all**: it uses
SharePlay (`apple/Core/ListenTogether/SharePlayRoom.swift`; the
`com.apple.developer.group-session` entitlement in
`apple/Resources/EarDrama.entitlements:13`), with `RoomProtocol.swift` ported
for the drift rules only. None of it has run on devices (PARITY.md:176).

**What changed since Decision 065.** Cloudflare's pricing page now says
Durable Objects are available on the Workers Free plan with the SQLite storage
backend: 100,000 requests a day, 13,000 GB-s, 5 million rows read and 100,000
rows written a day, 5 GB stored, and incoming WebSocket messages billed at
20:1 with hibernation
(<https://developers.cloudflare.com/durable-objects/platform/pricing/>, fetched
2026-11-19). Decision 065's reason no longer holds. §5.1 weighs both.

**Why the room as it stands cannot carry a classroom.** A school puts 25 to 30
devices behind one public address. Polling at 2 s is 30 reads a minute a
device, so 30 devices make 900 a minute from one address, three times
`ROOM_LIMITER` and over `EVERY_IP_LIMITER`. A class joining in the same minute
hits `ROOM_JOIN_LIMITER` (20) after the twentieth child, and `MAX_MEMBERS` is
20. D1's free plan allows 100,000 rows written a day
(<https://developers.cloudflare.com/d1/platform/pricing/>); a presence write
every 20 s (`SEEN_REFRESH_MS`, room-protocol.js:37) from 30 devices for 45
minutes is about 4,000 writes, so about 25 class periods a day would use the
whole free allowance for every user of the Worker.

### §1.4 The script reader and the studio

Decision 076 (DECISIONS.md:1126-1152) and PLAYS-DESIGN §2.7 to §2.11 give
every castable play a **Read** door (no account), pages by default, and
**"I'm playing ___"**: highlight my lines, jump to my next, **hide them to
rehearse** (`js/reader.js:339-420`, the Hide my lines button at :726). The
studio lives inside the reader: tap a line to record it, three modes (Run
through, Line by line, Step), every take kept (`js/studio-core.js`,
`js/plays-session.js`). Decision 080 keeps a take going through a Duo fold.
**Read along** (PARITY.md:136) already makes the reader follow a playing
production, and the TVs already have a **read-along panel** (the line heard,
one before and one after, speaker in the part's hue, 31 pt; `ReadAlongPanel_tvOS`
and Android's `ReadAlongPanel`, seen on Ben Bedroom and a Google TV
2026-11-15). These are the pieces a table read needs on each device; what is
missing is that the cursor comes from someone else's device.

### §1.5 Pass the phone, voices, and the stand-in rule

Pass the phone (PLAYS-DESIGN §2, PARITY.md:186) is the relay on one device:
take a part, record against live stand-ins, pass. Headphones are asked for
before every session because they "keep the stand-in out of the microphone"
(PLAYS-DESIGN §4.3, docs/PLAYS-DESIGN.md:914-921), and a take the bleed check
flags is refused by the Worker (plays.js:484). Voice casting (PARITY.md:133)
gives each part a device voice; Kokoro is the downloadable voice (Decision
078). A synthetic voice is a live stand-in only, never stored (Decision 055,
PLAYS-DESIGN §5). Each device keeps its own cast (Decision 076): in a room,
two phones would read the same unheld part in two different voices, which is
one more reason only one device should speak (§3.3).

### §1.6 Accounts and children

Signing in is optional (Decision 057); a first take needs no account, and
sharing, inviting, publishing or a second production asks for one (Decision
079, DECISIONS.md:1221-1249). Taking a part in someone else's production needs
an account (Decision 072). The privacy policy (`privacy/index.html`) says
nothing about children, schools, classes, or uploaded takes: it still says
"Recorded plays stay on the device" and "A finished play leaves it only when
you export it yourself". It has to change before shared productions open to
anyone, not only before classes. Research 08c §6.2 found that a child's voice
in an audio file is COPPA personal information and that the FTC's 2017
voice exemption cannot cover a kept recording
(docs/research/08c-collaboration-and-storage.md:760-790).

`docs/research/curriculum/` is the template's course for builders (Human
Shaped), not a classroom curriculum for Ear Drama; nothing in it bears on
classes in the app.

### §1.7 The audit in one table

| Capability | Web | iOS / iPadOS | macOS | tvOS | Android | Android TV | Worker |
|---|---|---|---|---|---|---|---|
| Make a class, see its code | yes | yes | yes | no | yes | no | yes |
| Join a class by code | yes (account) | yes (account) | yes (account) | no | yes (account) | no | yes, account required |
| Roster: see who joined | no | no | no | no | no | no | yes (`GET /classes/:id`) |
| Remove a student | no | no | no | no | no | no | yes |
| Record school consent | no | no | no | no | no | no | refuses (503, P5) |
| Students without an account | no | no | no | no | no | no | no |
| A class owns a play | no | no | no | no | no | no | no (P8) |
| Assign parts | no | no | no | no | no | no | no |
| Several parts record at once | no | no | no | no | no | no | refused (C7 rule) |
| Shared cursor in a script | no | no | no | no | no | no | no |
| Upload a take | blocked (R2 off) | blocked | blocked | n/a | blocked | n/a | 503 |
| Teacher reviews takes | no | no | no | no | no | no | no |
| A real-time room | Listen Together (media only) | SharePlay only | SharePlay only | SharePlay | Listen Together | joins by code | D1-polled rooms |

---

## §2. Research: how people read plays together

Sources were fetched or seen in search results on 2026-11-19. A claim marked
*(snippet)* comes from a search result's summary, not a full page read.
*Unconfirmed* means no source was found.

### §2.1 Professional table reads

- **The table read tests the story, and the length.** Ken Levine, a veteran
  sitcom writer, listens for whether the story tracks, whether steps are
  missing or repeated, and whether a character drops out. He doesn't trust
  big laughs at the table. On fast shows the team reads in the morning, puts
  the episode on its feet that afternoon, and rewrites overnight. His rule:
  "fix the story but give jokes a chance to work on stage." He also complains
  that pilot reads now face executives on a dais, so the actors can't play to
  each other (<https://kenlevine.blogspot.com/2021/01/table-readings.html>).
- **One person reads the directions and any part not yet cast.** In theater
  this is often the stage manager, whose read also gives a first running time
  that "will change quite a bit"
  (<https://www.theatrefolk.com/blog/effective-table-read-guide-school-directors>;
  <https://shootingpeople.org/qna/q/table-reads> *(snippet)*). Beats and
  reactions are cut from the directions reader's copy so actors can play them.
- Reads are often recorded for the team to review later
  (<https://www.backstage.com/magazine/article/table-reads-just-important-auditions-12588/>
  *(snippet)*). TV reads are shorter and often held over lunch. Whether a show
  holds them depends on the showrunner
  (<https://www.castingnetworks.com/?p=336957> *(snippet)*).
- **On Zoom**, actors renamed their tiles to their characters, and a doubling
  actor renamed theirs at each switch. The directions reader appeared once on
  camera, then read in voice-over. Hosts were told to use wired connections
  (<https://blog.playscripts.com/play/special/livescreendirectorsguide.pdf>;
  <https://community.zoom.com/t5/Zoom-Webinars/zoom-theatre-reading-on-webinar/m-p/41665>).

**For Ear Drama:** the shared screen should always show who is reading which
part. Directions should be a part a person holds, as PLAYS-DESIGN §2 already
makes them. Showing a read's elapsed time against the play's length is a fact
worth adding.

### §2.2 Radio drama practice

- **The BBC uses one microphone.** Actors step in for a line and back out for
  the next speaker, and distance from the mic gives a sense of space. Audible
  uses three cast mics and an effects mic. Big Finish puts each actor in a
  separate booth, still performing together. Binaural recordings are made as
  whole takes because they are hard to edit
  (<https://www.spotlight.com/news-and-advice/tips-and-advice/radio-and-voice-studio-setups-explained>).
- **The BBC studio crew** has three roles: panel (the mixing desk and mic
  layout), grams (recording, effects and music), and spot (live effects, and
  floor manager for the cast). As much as possible is recorded in the session
  itself. A one-hour play took two days to record and two to edit
  (<https://suttonelms.org.uk/articles3.html>).
- **The read-through is the first test of running time.** In one student
  production it ran two minutes over and was cut before recording
  (<https://blog.westminster.ac.uk/radio/joe-pilbrow-audio-drama-blog/>
  *(snippet)*).
- **Remote recording:**
  - Riverside's "double-ender": each person's device records locally and
    uploads during the session, one 48 kHz WAV track per person
    (<https://riverside.com/blog/double-ender-recording>).
  - Cleanfeed records each person on a separate track
    (<https://blog.cleanfeed.net/qa-and-then-the-lights-went-out> *(snippet)*).
  - Tape sync: a hired engineer records the guest's side, about $250 to $400
    a job
    (<https://www.bhphotovideo.com/explora/pro-audio/tips-and-solutions/how-to-record-a-tape-sync-with-the-right-gear>
    *(snippet)*).
- **A relay used in the pandemic.** Kansas City Actors Theatre recorded on
  Zoom first. Then each actor recorded alone while listening to that take,
  speaking on cue
  (<https://wnyc.org/story/theaters-return-to-an-old-art-form-the-radio-drama-with-a-twist/>
  *(snippet)*). This is the owner's relay, done by hand.
- **Live radio plays on stage.** Joe Landry's *It's a Wonderful Life: A Live
  Radio Play* has actors at microphones with scripts in hand, each playing
  many parts, and a Foley artist working in view
  (<https://www.wvia.org/news/local/2024-12-12/its-a-wonderful-sound-wonderful-life-radio-play-adds-foley-art-to-classic-christmas-tale>).
- How Audible and Realm handle remote sessions is *unconfirmed*.

**For Ear Drama:** our "one file per line, per person" is a double-ender.
"Record in the room" is a radio studio with one mic per actor. The BBC's
single mic suggests a variant: one device in the middle of the table
records every line (§3.4).

### §2.3 Readers Theater in K-12

- **Young & Rasinski (2009)**, *The Reading Teacher* 63(1), 4-13. A
  second-grade class did Readers Theater every week for a year. Students grew
  in word recognition, automaticity and prosody. Struggling readers took part
  as much as or more than strong ones
  (<https://irrc.education.uiowa.edu/node/686>). A secondary summary reports
  a prosody gain of about 20%, *unconfirmed* against the paper.
- **Martinez, Roser & Strecker (1998/99)**, *The Reading Teacher* 52. In two
  second-grade classes over 10 weeks, about 30 minutes a day, reading rate,
  accuracy and motivation rose. Effect sizes are *unconfirmed*
  (<https://www.iejee.com/index.php/IEJEE/article/view/63> *(snippet)*).
- **The weekly cycle:**
  - Day 1: the teacher models the script aloud.
  - Day 2: the class reads it chorally.
  - Days 3 and 4: students read in pairs, including at home.
  - End of the week: they perform.
  - Scripts have 6 to 8 roles, so a class splits into groups that give each
    other feedback (<https://irrc.education.uiowa.edu/node/686>).
- **ReadWriteThink** holds off assigning parts at first, which "eliminates
  the practice of assigning the stronger readers the larger roles." Groups of
  3 to 5 take roles with equal reading, and one reader may take several parts
  (<https://readwritethink.org/professional-development/strategy-guides/readers-theatre>).
- **Other teachers do match parts to readers** ("assign the proper reading
  parts to the proper readers") and perform a script at least twice
  (<https://www.educationworld.com/a_curr/profdev/profdev082.shtml>
  *(snippet)*).
- **With older readers**, five fifth-graders wrote and rehearsed a script from
  a novel. Each gained more than 20 words per minute on DIBELS, and the gains
  held on a new passage
  (<https://ascd.org/el/articles/using-readers-theater-to-reach-older-readers>).

**For Ear Drama:** the research credits repeated reading of the same text,
which is Rehearse. Casting practice differs between teachers, so the casting
board should show facts and leave the choice to the teacher. It should
offer **rotation** (parts change at each read) as well as fixed casting.

### §2.4 Drama education: Folger and the RSC

- **The Folger Method has nine practices:** Tone & Stress, Tossing Words and
  Lines, Two-line Scenes, 20-Minute Plays, Choral Reading, 3-D Shakespeare,
  Cutting a Text, Promptbooks, and Group Scenes. Its principles include
  "teacher as architect," and its self-check asks whether the words are in
  every student's mouth (<https://www.folger.edu/teach/the-folger-method/>).
  Folger calls choral reading perhaps "the most powerful and versatile tool"
  (<https://www.folger.edu/blogs/teaching-shakespeare/folger-method-essential-practices/>
  *(snippet)*).
- **RSC rehearsal-room approaches:** read one text several ways (whispering
  back to back, walking and stressing key words), build freeze frames in
  groups of 3 to 5, work about ten lines that trace a scene's arc, and hear
  the words before reading the footnotes
  (<https://rsc.org.uk/education/teacher-resources/introducing-rehearsal-room-approaches>).
  An EEF/NFER trial of Rehearsal Room Writing in about 200 Year 5 classes
  reports in 2027
  (<https://www.rsc.org.uk/research/current-research/rehearsal-room-writing>
  *(snippet)*).

**For Ear Drama:** an **Everyone** part (choral lines), **split by scene**,
and **rotate** put words in every student's mouth. Cutting a text is
editing the script, which we leave to people and never to a model. It is
out of scope here.

### §2.5 Table-read and rehearsal apps

- **Scriptation:** pick your character and the app reads the other parts,
  with auto-highlight, cue mode and loop. Its **Live Layers** pushes a
  writer's changes to every actor's script during a table read, on the
  Team or Enterprise plan
  (<https://help.scriptation.com/en/category/playback-mode-1wkg8it/>;
  <https://help.scriptation.com/en/article/uses-and-tips-for-live-layers-1345ub6/>).
- **Arc Studio's table read** lists unassigned characters and auto-assigns AI
  voices (<https://help.arcstudiopro.com/guides/table-read>). Tableread uses
  device voices for free and a chosen voice per character in Pro
  (<https://www.premiumbeat.com/blog/need-to-table-read-a-script-theres-an-app-for-that>
  *(snippet)*).
- **Line-learning apps:**
  - Rehearsal Pro: record your lines, scroll like a teleprompter, black out
    your lines (<https://apps.apple.com/app/id1116896197>).
  - Run-Through: show a line in full, as first letters only, or hidden
    (<https://apps.apple.com/app/id6451156913>).
  - Off Book! Pro: a ding just before your turn
    (<https://mwm.ai/apps/off-book-pro/1072004273>).
- **Final Draft 12 and 13** co-edit in real time
  (<https://kb.finaldraft.com/hc/en-us/articles/15575058271508-Does-Final-Draft-offer-real-time-collaboration>).
- Table-read features in StudioBinder, Celtx, LineLearner and ColdRead are
  *unconfirmed*.

**For Ear Drama:** every one of these is one person reading against
machines, or writers editing together. None puts several people's devices
on one live cursor in a room. Our reader already has the solo tools
(highlight, hide, next mine). A "first letters" hide is a cheap later
addition to Rehearse.

### §2.6 How classroom apps let people join

| Product | Join | Late joiners, drops, control | Names |
|---|---|---|---|
| Kahoot | Game PIN; optional 2-Step Join (tap a 4-tile pattern from the host's screen) | The PIN stays on screen, so latecomers and dropped players rejoin; the host removes players only in the lobby; school networks may need `wss://game.kahoot.it` allowlisted | A nickname generator; a word filter that Kahoot says misses names aimed at a classmate (<https://kahoot.com/blog/2019/03/08/tips-keep-kahoot-nicknames-appropriate/>; <https://support.kahoot.com/hc/en-us/articles/115003198708> *(snippet)*) |
| Jackbox | 4-letter code at jackbox.tv, on the big screen; QR sign-in in Party Pack 9 | A host disconnect pauses the game 5 minutes; moderators kick, and the VIP role passes on | Profanity filter None, Moderate or Strict (<https://www.jackboxgames.com/the-ability-to-kick-players-and-other-new-features-coming-to-party-pack-9/>; <https://support.jackboxgames.com/hc/en-us/articles/15794773430295-How-does-Moderation-work->) |
| Nearpod | Code at join.nearpod.com | Teacher-paced (the teacher moves the slides) or student-paced (<https://nearpod.com/blog/virtual-learning-faq/> *(snippet)*) | n/a |
| Pear Deck | 6-letter code at joinpd.com, or a link | Codes expire in a week, links don't; switch between instructor- and student-paced; **Lock Screens** with a countdown (<https://docs.goguardian.com/products/pear-deck/present-a-session>; <https://docs.goguardian.com/products/pear-deck/use-the-teacher-dashboard>) | n/a |
| Google Classroom | Class code | The teacher resets (the old code dies) or disables the code to stop joins (<https://support.google.com/edu/classroom/answer/6020282>) | School accounts |
| Seesaw | A class QR code for PreK-3 and shared devices, in class only; 16-digit home codes | | The student taps their name (<https://help.seesaw.me/hc/en-us/articles/4424230271501-Seesaw-Codes>) |
| Flip | A group join code or link; no student account | With moderation on, classmates see a video only after the teacher approves it (<https://learning.ptsem.edu/flip/> *(snippet)*) | |
| Plickers | Only the teacher has a device; students hold printed cards and the phone camera scans them | Works offline (<https://www.techlearning.com/how-to/plickers-how-to-use-it-to-teach> *(snippet)*) | Card numbers |
| Blooket, Gimkit | Game ID, QR or link | | Random names or a nickname generator (<https://help.blooket.com/hc/en-us/articles/16001464321559>; <https://help.gimkit.com/en/article/nickname-generator-1ng9lwx>) |

How these products handle duplicate names is *unconfirmed* for all of them.

**For Ear Drama:**
- A short code that stays on the shared screen.
- The student picks their name from the teacher's list (Seesaw), so we
  never filter typed names (Kahoot's own filter misses names aimed at a
  classmate).
- A dropped reader gets their seat back (Kahoot, Jackbox).
- If the leader drops, the read holds (Jackbox pauses).
- **Lock joining** (Classroom, Pear Deck).
- Teacher approval before classmates hear a take (Flip).
- Leader-paced or self-paced (Nearpod, Pear Deck): Table read is
  leader-paced, and Rehearse can let each device go at its own pace.
- Plickers shows a class can work with one device, which is pass the phone.

### §2.7 Sound in one room, clocks, and delay

- **Echo.** Zoom's classroom guidance is one connection with audio per room
  and "Leave Computer Audio" on the rest. Muting isn't enough, because the
  speaker still plays into the room
  (<https://moravian.teamdynamix.com/TDClient/288/Portal/KB/Article/6168/Zoom-in-the-Classroom-Joining-in-the-Same-Room>
  *(snippet)*). Each device cancels only its own playback, not the sound from
  the laptop beside it (<https://getstream.io/blog/what-is-echo-cancellation/>).
  Chrome reportedly cancels only audio that arrives over WebRTC
  (<https://www.github.com/webrtc/samples/issues/1243>), and Firefox uses one
  output device as its reference
  (<https://bugzilla.mozilla.org/show_bug.cgi?id=1879180>). Both reports may
  be dated. A 2025 paper groups devices by room and has devices in the same
  room mute one another
  (<https://webdev.apsipa.org/proceedings/2025/papers/APSIPA2025_P458.pdf>).
- **Clock sync.** The offset is server time minus client time minus half the
  round trip, taken from the best of about ten samples
  (<https://rapidtoolset.com/en/tool/server-clock-offset-calculator>). The
  error is bounded by half the round trip
  (<https://uhr.ptb.de/wst/paper>). One library targets under 100 ms within 5
  to 10 s (<https://www.pkgstats.com/pkg:javelin-timesync>). Background tabs
  throttle timers (<https://github.com/guigrpa/clocksy>). Our
  `room-protocol.js` `clockOffset` already takes the best-round-trip sample
  (§1.3).
- **How much delay people notice:**
  - The gap between turns in conversation averages about 200 ms across ten
    languages (Stivers et al. 2009, PNAS;
    <https://www.scientificamerican.com/article/universal-social-rules-underlie-languages/>).
  - Planning a turn takes at least 600 ms, so listeners start planning before
    the speaker finishes (<https://pmc.ncbi.nlm.nih.gov/articles/PMC4586330>).
  - ITU-T G.114 treats one-way delay under 150 ms as acceptable for most uses
    (<https://www.itu.int/rec/T-REC-G.114/index.html>).
  - Lip-sync error is noticed from about 45 ms with audio early to 125 ms with
    audio late (ITU-R BT.1359, via
    <https://en.wikipedia.org/wiki/Audio-to-video_synchronization>).

**For Ear Drama:** in a room, only one device plays sound. Phones show text
and stay silent. A highlight that lands within about 150 ms of the leader's
press reads as "now". Polling at 1 s cannot reach that, and a socket can
(§5.1, T4). A reader's own "you're next" mark has more room than that,
since they need it before their turn, not at it.

### §2.8 Collaboration across time

- **Exquisite corpse:** each player adds to the page, folds it to hide their
  part, and passes it on. It started in Paris around 1925
  (<https://www.tate.org.uk/art/art-terms/cadavre-exquis-exquisite-corpse>).
- **Soundtrap for Education** is a "walled garden": only teachers add
  students, groups co-edit in real time, and teachers see each student's part
  of a group piece. Rosters come from a link, Google Classroom or a CSV. It
  says it is designed for COPPA and FERPA, at about $399 a year for 50 users
  (<https://edu.soundtrap.com/what-is-soundtrap-for-education-2> *(snippet)*).
- **BandLab for Education** is free: a teacher-made class with a join code,
  and assignments that are set, tracked and graded. For US students 13 and
  under it asks for verifiable parental consent, through its own form or the
  school's
  (<https://help.edu.bandlab.com/hc/en-us/articles/900000403583-COPPA-Compliance-Parental-Consent>).

**For Ear Drama:** teacher-only rosters, visibility of each student's part,
and a free join code are what music-education tools expect, and our class
plan matches them. BandLab shows that a free product can still route
under-13 consent through the school.

### §2.9 What schools require

- **COPPA as amended.** The amendments were published April 22, 2025,
  effective June 23, 2025, with compliance due April 22, 2026
  (<https://www.govinfo.gov/content/pkg/FR-2025-04-22/html/2025-05904.htm>).
  They add:
  - a **written data-retention policy** (no indefinite keeping);
  - a written security program;
  - separate consent before sharing with third parties;
  - biometric identifiers, voiceprints among them, as personal information.

  (<https://www.loeb.com/en/insights/publications/2025/05/childrens-online-privacy-in-2025-the-amended-coppa-rule>)
- **The school-authorization exception was not written into the rule.** The
  FTC still enforces it through its COPPA FAQs, which it can revise (same
  source; <https://pipc.substack.com/p/webinar-on-new-coppa-rule-and-pipcs>).
  A school may consent only for the school's educational use, which is why
  publishing a child's voice to a public, permanent archive (Q4) falls outside
  it.
- **A child's recorded performance is personal information.** The FTC's 2017
  policy spares only audio used briefly in place of typed words and then
  deleted
  (<https://www.ftc.gov/news-events/news/press-releases/2017/10/ftc-provides-additional-guidance-coppa-voice-recordings>).
- **FERPA's "school official" exception** fits a vendor only if it does work
  the school would otherwise do, under the school's direct control over how
  records are used and kept. Schools must be able to direct how long data is
  kept and when it is deleted
  (<https://studentprivacy.ed.gov/faq/who-school-official-under-ferpa>;
  <https://fpf.org/2016/01/19/who-exactly-is-a-school-official-anyway/>).
- **The SDPC National Data Privacy Agreement** (v2, built with 28 state
  alliances, with a public registry of who signed) is what districts ask
  vendors to sign
  (<https://fpf.org/blog/the-first-national-model-student-data-privacy-agreement-launches/>;
  <https://privacy.a4l.org/>). **California's SOPIPA** binds K-12 operators
  even without a school contract: no targeted ads, no sale, no
  non-educational profiling
  (<https://fpf.org/wp-content/uploads/2016/03/SOPIPA-At-a-Glance.pdf>).
- **Student devices and accounts:**
  - Google Workspace for Education treats users as under 18 by default and
    blocks them from unconfigured third-party apps
    (<https://knowledge.workspace.google.com/admin/getting-started/editions/manage-access-to-unconfigured-third-party-apps-for-users-designated-as-under-18>).
    A school Google account may not be able to use our Sign in with Google
    unless the admin allows the app, one more reason for seats.
  - Apple's Managed Apple Accounts have no email. On Shared iPad, students
    tap their name and enter a passcode
    (<https://support.apple.com/guide/deployment-education/edu6d39b9909/web>).
- **Accessibility:**
  - WCAG 1.4.12: text survives line height 1.5×, paragraph spacing 2×,
    letter spacing 0.12× and word spacing 0.16×
    (<https://www.w3.org/WAI/WCAG22/Understanding/text-spacing>).
  - Dyslexia guidance: dark text on an off-white ground, sans-serif, 1.5
    spacing
    (<https://dyslexiascotland.org.uk/dyslexia-friendly-typed-formats>). The
    reader's 7 sizes and 3 spacings (PARITY.md:130) are most of this.
- **Teacher time.** Teachers get about 45 to 53 minutes of planning a day,
  and elementary teachers get less
  (<https://edsurge.com/news/2024-03-14-we-know-how-much-planning-time-teachers-get-on-average-is-it-enough>).
  Setup (make a class, paste names, pick a play, cast) has to fit in part of
  one planning period, and running a read has to take one tap.

---

## §3. The proposal: four ways of reading together

All four start from the same screen, a play's cast sheet, and from the same
two roles: a **leader** (the teacher, the director, whoever opened the read)
and **readers**. A **shared screen** is optional in every mode.

### §3.1 One new thing: the read room

A read room is a Listen Together room whose state is a place in a script
instead of a place in an audio file. It holds:

- the script id and revision (the castable manifest's, as productions do), and
  the production id when it records;
- **the cursor**: the line id now being read, and a generation number;
- **the mode**: `read`, `rehearse`, or `record`;
- **who holds what**: each member's part or parts (a seat, §4.2), and which
  member is the leader and which are screens;
- per line in `record` mode, whether a take has landed.

The leader moves the cursor (Next, Back, jump to a scene). In `record` mode the
reader whose line it is can also end their own line, which moves the cursor
(their take ends on one second of silence as it does today, PLAYS-DESIGN §2.4,
or on their tap). Nothing advances on a timer and nothing listens to the room
to guess where people are: a person always moves the play on.

**Why not reuse Listen Together's state as is?** Its arbiter only accepts
media state and a host copy (`applyHostState`, room-protocol.js:121-166). The
right move is the same pattern, not the same file: a new pure
`worker/src/read-protocol.js` with no imports (cursor arbiter, part rules,
leader rules, late-join snapshot), ported and golden-tested in
`js/read-core.js`, Swift and Kotlin exactly as `room-protocol.js` is today
(AGENTS.md "Multiplayer rides a transport seam"). Codes, member keys, the
clock and the presence rules are imported conceptually from room-protocol and
copied with their constants, so a code read aloud means the same thing in both.

### §3.2 Mode 1: Table read (live, nobody records)

What it is: the first read-through, the classroom cold read, the adults'
evening. Everyone has the script on their own device; the leader moves the
cursor; everyone reads their own lines aloud in the room.

- **Each reader's device** opens the reader (§1.4) in a new **following** state:
  the page turns to the cursor, the current line is lit, the reader's own lines
  carry the "I'm playing" tint, and the next line of theirs is marked
  "Next: you, in 3 lines" (a fact, so it passes the essential-words rule).
  A touch to scroll away stops following; **Back to the line** returns, as Read
  along does today (PARITY.md:136).
- **The leader's device** shows the same page with **Next** and **Back** as the
  primary controls (keyboard arrows, a page-turn pedal, the volume keys where
  that opt-in exists), the cast with who holds each part, and who is here.
- **The shared screen** shows the page large: the current line, the one before
  and two after, speaker names in part hues, and in a corner the room code and
  how many are here. This is the TVs' read-along panel (§1.4) driven by the
  cursor instead of a file.
- **Stage directions**: a part like any other (PLAYS-DESIGN §2 step 2). The
  film convention is that one person reads them (§2.1); the leader can hold
  Directions themselves, give them to a reader, or set the shared screen to
  show them without anyone reading (Decision 076: "stage directions not read
  by default").
- **No sound from any phone.** Parts nobody holds are read by the shared screen
  if the leader turns on **Read open parts** (one device, one cast, §1.5), or
  shown on every device for anyone to pick up.
- **Doubling and splitting**: one person may hold several small parts (the
  radio tradition, PLAYS-DESIGN §2 step 2); a large part may be split by scene
  between two readers (§4.3).

### §3.3 Mode 2: Rehearse

The table read plus the reader's existing rehearsal tools: **Hide my lines**
(peek on tap, js/reader.js:397-420), Again (the leader jumps the cursor back to
the scene's start), and marks (private, on the device, Decision 076). In a
room, only the shared screen speaks stand-ins. A reader alone, at home, keeps
today's solo rehearsal with the device voice reading the other parts.

### §3.4 Mode 3: Record in the room

The new thing a same-room group can do that pass the phone cannot: everybody
records their own lines, on their own device, in one sitting, in script order.

- The cursor reaches a line. **Only the device holding that line's part opens
  its microphone**, shows the record ring, and records. Every other device is
  silent and shows "Lucy is reading".
- The reader speaks; the take ends on one second of silence or on their tap
  (today's take ending), and the device marks the line done. The cursor moves
  on by itself to the next line, so the scene keeps its pace; the leader can
  stop, go back, or call **Again** on any line, which re-arms that reader's
  microphone for a new take (every take kept, PLAYS-DESIGN §2.9).
- **No headphones are needed in this mode, and that is the point of it.** The
  headphone rule exists so a device's stand-in voice does not reach its own
  microphone (§4.3). Here no device plays anything during a take: the cue is
  the previous reader's real voice, heard in the room, which is what a radio
  studio's actors do around one microphone (§2.2). A shared screen reading an
  open part does so between takes, never during one.
- **The other voices in the room** will bleed into each take a little (the
  previous speaker's tail, a cough). The existing bleed check measures the
  device's own stand-in, which is not playing, so it stays silent; the take
  meta records `capture: "room"` (a third value beside `direct` and `aec`,
  plays.js:458) so the mix and the review know. Each take is trimmed by the
  existing silence trim. A whisper rule on screen ("Quiet while others
  record") is a refusal-class instruction and passes the essential-words rule.
- **Takes upload as they finish**, to the production on the Worker, queued on
  the device when the network drops (never lost: the take is written locally
  first, as now).
- **Lines nobody holds** are skipped and stay open; the production is
  incomplete until someone records them (C6: a speaking part needs a human).

This needs the Worker to let several parts record at once in a room-run or
class production (§5.3), which changes the C7 rule as built (§9, Q3).

**Variant: one microphone (the BBC's way, §2.2).** One device in the middle
of the table, or the teacher's iPad, records every line. Its cursor tells it
whose line each take is, so each take is credited to the right part and seat,
while readers follow on their own devices or on the shared screen. It gives
the most even sound (one mic, one room), needs no microphone on any student
device, and keeps all the audio on the teacher's device. It is pass the
phone without passing the phone. The trade-off is that readers must come to
the mic, or the mic must be good enough to reach the whole table.
**Recommended as the default for a class under 13** and for any room with
one good device. Per-device recording is the choice when readers are spread
around a room, or when each person wants their own take list.

### §3.5 Mode 4: Relay across time

Today's invite production (§1.2) is already the across-time relay for adults:
one person records, the next hears their takes and records against them. Two
additions make it work for a class:

- **Assigned parts** (§4.3) instead of first-come claims, so 25 students can
  each record at home in the same week, in parallel, each against the takes
  already in and the stand-in for the rest.
- **The teacher's progress list** (§4.5): who has recorded how many of their
  lines, whose takes wait for review, which parts are open.

The "exquisite corpse" variant (each person hears only the line before theirs)
is a known writing game (§2.8) but it would hide the play from its performers,
which fails the first learning question (§7); it is not proposed.

### §3.6 Which mode for whom

| Group | Usual sequence |
|---|---|
| A class, one period | Table read (day 1) → Rehearse (days 2-4) → Record in the room (day 5), the Readers Theater week (§2.3) |
| A class across a week, at home | Table read in class → Relay across time as homework → the teacher reviews → the class listens through together (Listen Together on the shared screen) |
| Adults at a table | Table read, then Record in the room if they want to keep it |
| Adults apart | Relay across time (today's invite link), optionally a Table read over a video call with each person following on their own device |

---

## §4. The teacher's flow, end to end

### §4.1 Make a class

As today (name, Under 13). New: the class page itself (it has none today), with
the code large and a **Show code** that puts it full screen for a projector.
Following `learner-experience-design` §3, the class page is a list of what
needs the teacher, not a dashboard of charts: "4 takes to review", "2 parts
open", "Ms. Ortiz's class is reading now (Join)".

### §4.2 A roster without student emails: seats

A **seat** is a name the teacher types (a first name, a nickname, "Group 3"),
belonging to the class, with no account behind it. The teacher adds seats one
by one or pastes a list. A student joins by typing the class code on any
device and **picking their name from the teacher's list** (the Kahoot code
plus the Seesaw class list, §2.6), so a child never types a name, there are no
duplicates, and no nickname needs filtering beyond the teacher's own. The
device keeps a seat key (a random key stored as its hash, the room member
pattern, rooms.js:63-66). The teacher sees which seats are on a device and
can **Release** a seat (a lost phone, the wrong child), after which the next
device can take it.

For younger students, a printable **seat card** per name with a QR code that
carries the class code and the seat (Seesaw's sign-in sheets, §2.6) skips typing
entirely. On a shared iPad cart, picking your name on each session is the
whole sign-in; the seat key goes when the session ends (§6).

Older students and adults may still join as themselves with an account (as the
class join works today), and their seat links to their account.

**What a seat carries**: the teacher's label only. No email, no birth date, no
photo, no voice outside the class's production.

### §4.3 Pick a play and cast it

The teacher picks any castable play (PLAYS-DESIGN §3), which makes a **class
production** (a production with a `class_id`, §5.2), visible to every seat in
the class without an invite (owner question Q2, which reopens P8).

The **casting board** lists the parts largest first with facts from the
script (lines, words, scenes, the longest speech in words) beside the seats,
and the teacher drags or taps to assign. Many Readers Theater teachers match
part size to the reader on purpose, and others rotate parts first (§2.3), so
the choice is the teacher's: the app shows the facts and never a reading-level label or a suggestion of who should read
what (owner rule 2026-10-23: no invented age ratings; Decision 067). Helpers,
each one a proposal the teacher edits:

- **Totals per seat** (lines and words), so an imbalance is visible.
- **Fill evenly**: a deterministic proposal that spreads the remaining parts
  so each seat's word total is as close as possible, largest part first. The
  teacher accepts, edits, or ignores it.
- **Split by scene**: a large part (Romeo, Scrooge) divided between seats at
  scene boundaries, so a class of 28 can share a play with 12 parts (the
  Folger practice of many readers per part, §2.4).
- **Double**: one seat holds several small parts.
- **Everyone**: a crowd or chorus part every seat reads together (live only; a
  chorus line records on the leader's device). This is Folger's choral reading
  (§2.4).
- **Rotate**: parts move to the next seat at each read or each scene, so
  nobody is "the star" before the class knows the play (ReadWriteThink holds
  off on assigning parts at first, §2.3). Fixed casting is for the recording.

### §4.4 Run the read in the room

1. The teacher opens the production and presses **Read together**, choosing
   Table read, Rehearse or Record. A read room starts, tied to the class.
2. Every seat on a device sees **Your class is reading** with Join, on Home and
   on the class page; no code is typed a second time.
3. Once everyone is in, the teacher can **Lock joining** (Google Classroom,
   Pear Deck, §2.6); a released seat can still be taken.
   The shared screen: on an Apple TV or Google TV, **Show a reading** displays
   a short pairing code and the teacher types it on their own device (the TV
   never asks for typing, the Jackbox direction of entry, §2.6). On a projector,
   the teacher opens the web screen view on the classroom computer
   (`/read/CODE?screen`), or mirrors an iPad (AirPlay) or a Mac window.
4. The teacher leads with Next and Back, or hands the lead to a student seat
   (a student director), and takes it back at will. In a class room only the
   teacher or the seat they chose can lead; if the leader's device drops, the
   room holds still until they return, never passing the lead to a random
   student as Listen Together does (§6).

### §4.5 Monitor, review, approve

- **Who has recorded** (Record in the room and Relay): per seat, "12 of 15
  lines", the lines waiting, flagged takes. Counts and links, never a ranking
  or a leaderboard (`learner-experience-design` §5).
- **Review**: the teacher listens line by line in script order (the
  listen-through, with the read-along cursor), and on each line can **Approve**
  or ask for **Again** with an optional spoken or typed note to that seat
  (owner question Q6 on whether a teacher's spoken note is a stored voice of
  an adult, which our rules allow, or should be typed only). The student
  chooses which of their takes is offered (today's rule: the claimant
  chooses, plays.js:599-607); the teacher approves what is offered. The
  student keeps the performing choice; the teacher keeps the judging.
- **The class listens back** together: Listen Together on the shared screen
  playing the production, with the read-along panel.

### §4.6 Keep it in the class, or publish

A class production stays inside the class by default: the teacher and the
seats can hear it, nobody else. The teacher can export the mix to a file
(Export, PARITY "Pass the phone" path) to share with families the school's
own way. **Publishing to archive.org** follows Decision 059's consent, with one
open question for under-13 classes (Q4): the FTC's school-authorization route
covers collection for the school's educational use (§2.9), and a permanent,
public CC0 item on archive.org goes beyond that. The proposal is that an
under-13 class production can never be published, only kept in the class and
exported by the teacher; a 13-and-over class publishes as adults do, each
performer agreeing for their own recording.

### §4.7 Consent for under-13s

What our rules already decide: under-13 voices leave a device only under the
school-consent route (Decision 059), the privacy policy must cover it first
(P5), and the Worker refuses the record until `SCHOOL_CONSENT_POLICY` names
that policy (plays.js:735-737). The flow the proposal adds on top:

- Making an under-13 class asks the teacher to confirm, in the owner's words,
  that they act for their school, with an optional reference (the school's
  name or its agreement number; the field exists, plays.js:739-740).
- Until that is recorded, the class can still do Table read and Rehearse.
  Nothing is collected: no voice leaves a device, and a seat is a name the
  teacher typed. Record in the room keeps every take on the device that made
  it, which is phase 1 recording and not collection, and the class's
  production shows those lines as "on Lucy's device". Uploading waits for
  the consent. The one-microphone variant (§3.4) keeps every take on the
  teacher's own device, so a class can make a whole recording before consent
  exists, as pass the phone does today.
- With consent, takes upload to the class production, are visible only to
  the class, and are deleted when the teacher deletes the class or their
  account (account deletion already removes classes, account.js:35-37).

---

## §5. The adult and student flows, platforms, data

### §5.0 The student's flow

Open Ear Drama on any device (a phone, a school iPad, a Chromebook's browser),
**Join a class**, type the code (or scan the seat card), tap your name. No
account where the class allows seats. Home now shows the class: the play, your
part, "Next: you, in Act 1, Scene 2", Read, and **Join** when the class is
reading. In a read the device follows; in Record it records only your lines.
At home, the class production opens in the studio at your first unrecorded
line.

### §5.0a The adult table-read flow

One person opens any castable play and presses **Read together**: a room code
appears (six characters, as Listen Together). Friends open Ear Drama or
`eardrama.org/read/CODE` (no account to read; Decision 057 asks for one only to
record with others, and Decision 072 for takes in someone else's production),
pick a part from the cast sheet (first tap wins; a taken part shows who holds
it), and follow. The host can switch to Record in the room; recording asks
each reader to sign in at that moment with the reason, as Decision 079 does,
unless the owner allows signed-out room takes to go to the host's production
(Q5).

### §5.1 Which transport

| | D1 polling (Listen Together as built) | A Durable Object with WebSockets |
|---|---|---|
| Cost | Free; already bound | Free on the SQLite backend (§1.3), 100,000 requests a day; incoming messages count 20:1 |
| Cursor delay | Half the poll interval plus a round trip: about 0.5 to 1.2 s at a 1 s poll | One round trip, typically under 150 ms on a school network (measure, §8) |
| A class behind one address | Needs per-member limits instead of per-address, and 30 reads a minute a device | One connection a device; messages only when the cursor moves |
| D1 writes | Presence writes every 20 s a device count against the shared 100,000 a day | The object holds presence in memory; nothing written until the read ends |
| Code to build | The room adapter exists; a new protocol file | A new Worker binding and class; the protocol file is the same |
| Clients | `fetch` everywhere | `WebSocket` on the web, `URLSessionWebSocketTask` on Apple, OkHttp WebSocket on Android: all native, no packages |

**Recommendation: one pure `read-protocol.js`, carried by a Durable Object
per read room**, with D1 polling as the fallback adapter for any client that
cannot hold a socket (a TV browser, a network that blocks WebSockets). The
reasons are measured, not taste: a table read moves the cursor every few
seconds and a reader's own line should light before they need it; polling 30
devices at 1 s from one school address is exactly the load Listen Together's
limits were set to refuse; and the presence writes alone would spend the
Worker's whole free D1 allowance at about 25 class periods a day. This
reverses Decision 065's reason (not its rule for Listen Together, which can
stay as it is), so it is logged as a new decision before building (`research
before fixes`), with a bench measurement of cursor delay on both adapters as
its gate (§8, T4). Apple uses the same Worker read room, not SharePlay, because
a classroom mixes iPads, Chromebooks and Android phones and SharePlay needs a
FaceTime call or Apple devices side by side (Q7 asks whether an all-Apple
SharePlay path is wanted later).

### §5.2 Data model

New and changed tables (D1 for durable records; the read room's live state
lives in its Durable Object, written to D1 only when it ends):

| Table | Columns | Notes |
|---|---|---|
| `play_class_seats` | `class_id`, `seat_id`, `label`, `user_id` (nullable), `key_hash` (nullable), `claimed_at`, `created_at` | A seat is the teacher's label; `user_id` only when an account joins as itself |
| `play_productions` | + `class_id` (nullable) | A class production: every seat is a member without an invite (Q2) |
| `play_assignments` | `production_id`, `part`, `from_line` (nullable), `to_line` (nullable), `seat_id` | Replaces claims for class productions; a range is a split by scene |
| `play_takes` | + `seat_id` (nullable), `capture` may be `room` | A seat's take is owned by the class's teacher account; `user_id` is the teacher |
| `play_reviews` | `production_id`, `take_id`, `state` (`approved`, `again`), `note`, `by`, `at` | The teacher's review; a take never changes |
| `read_rooms` (in the Durable Object) | code, script id and revision, production id, class id, mode, cursor line, generation, leader member, screens | Ends after 6 idle hours, as rooms do |
| `read_room_members` (in the Durable Object) | id, key hash, role (`leader`, `reader`, `screen`), seat id or chosen part, joined, seen | Anonymous, as `room_members` (rooms.js:40) |

### §5.3 Worker changes

- `read-protocol.js` (pure): `applyCursor`, `canLead`, `partsOf(member)`,
  `whoReads(line)`, `nextMine(member, cursor)`, `joinSnapshot`, `leaderGone`
  (class: hold; adult: longest present, as `nextHost`), `claimInRoom` (adult:
  first claim wins; class: assignments only).
- `ReadRoom` Durable Object: create, join (code, or class session for seats),
  WebSocket messages `cursor`, `mode`, `line-done`, `again`, `presence`;
  polling fallback routes with the same messages.
- Seats: `POST /v1/plays/classes/:id/seats` (teacher adds), `DELETE` (removes),
  `POST /v1/plays/classes/seat` (code + seat id, no account, returns a seat
  key once), `POST .../seats/:seat/release`.
- Class productions: `POST /v1/plays/classes/:id/productions`; assignments
  `PUT /v1/plays/productions/:id/assignments`; seat-key auth on take upload
  (`x-seat-key`), checked against the assignment instead of a claim.
- **The relay rule**: a production with assignments lets every assigned part
  record at once; a production without them keeps today's one-at-a-time
  `claimRefusal` (Q3).
- Review: `POST /v1/plays/productions/:id/takes/:take/review`; progress
  `GET /v1/plays/classes/:id/progress` (counts only).
- Rate limits keyed by member, seat or account, never only by address, for
  every read-room and seat route (the comment at wrangler.toml's
  `USER_LIMITER`, "so a classroom behind one school address is not one
  person", applied everywhere a class goes). A per-address join floor stays,
  raised to a class's size (60 a minute) to keep code guessing slow.
- `MAX_MEMBERS` for a read room: 40 (a class plus a teacher, an aide and a
  screen); a class production's member limit stays 64.

### §5.4 Each platform, in its own idiom

| Piece | Web | iPhone / iPad / Duo | Mac | Apple TV | Android phone, tablet | Google TV / Android TV |
|---|---|---|---|---|---|---|
| Teacher: class page, seats, casting board | full; drag to cast | full; iPad drag and drop, iPhone a list with a part picker | full; a window per class, drag to cast, menu commands | no | full | no |
| Leader controls | arrows, Space, a pedal | big Next in the reader's dock; hardware keys on iPad | arrows, a Reading menu, a second window on the projector display | no | Next in the dock; volume keys opt-in | no |
| Reader following | the reader | the reader; the Duo's outer display shows the current line when folded (Decision 080's rule) | the reader window | no | the reader | no |
| Record in the room | yes (the browser's mic; Safari and Chrome tested) | yes | yes | no (records nothing, rule 12) | yes | no |
| Shared screen | `/read/CODE?screen`, full screen | AirPlay mirror or an iPad as the screen | a second window, full screen on the projector | the read-along panel, pairing code | an Android tablet as the screen | the read-along panel, pairing code |
| Reads open parts aloud | the screen only | the screen only | the screen only | yes, as the screen | the screen only | yes, as the screen |

The TVs' role is new but stays inside rule 12 (they record nothing): they show
and they speak stand-ins. tvOS-DESIGN §4.13 and ANDROID-DESIGN's TV panel
rule are amended to add the cursor-driven panel, the pairing code, and the
room's presence count (binding docs first, `binding-design-doc-discipline`).

---

## §6. Failure states

| What happens | What the room does |
|---|---|
| A reader's device drops mid-read | Its seat stays assigned. When the cursor reaches that reader's line, the leader sees "Lucy's phone is away" with **Skip**, **Read it from the screen** (a stand-in, never stored) and **Wait**. On reconnect the device rejoins with its key and jumps to the cursor |
| The leader's device drops | Class: the room holds still and every device says "Waiting for Ms. Ortiz"; the leader rejoins with the key, or a co-leader seat takes over. Adults: the longest-present member leads after 2 minutes (Decision 065's rule) |
| A late joiner | Gets a snapshot: the page at the cursor, their parts, their next line. In Record, their lines already passed show as open, recordable later |
| Two devices claim one seat | The second sees "Lucy is already in on another device" with **Move here**; the first device leaves the seat. The teacher can always Release |
| Two adults claim one part | First claim wins (the arbiter is the server); the other sees who holds it and can ask the host to split it |
| No headphones | Table read, Rehearse and Record in the room need none (no phone plays sound). Solo rehearsal and Relay at home keep today's headphone ask (§4.3) |
| Several phones playing aloud | Prevented by design: in a room only the screen speaks, and only between takes |
| The network drops during a take | The take finishes and is written on the device first, then uploads when the network returns; the room's cursor can still be moved by the leader on their device |
| A school blocks WebSockets | The polling adapter carries the same messages; the screen says nothing unless it is slower than 2 s, then "Slow connection" (a warning) |
| A student records something unkind | Report and Block as today; in a class the teacher sees the report first and can remove a take; nothing reported is published |
| A take sounds like a room | `capture: "room"` is recorded; the review shows it; the teacher may ask for Again |
| The class grows past 40 | The room refuses with "This reading is full" (a refusal); a second room for the second half of the class works |
| An under-13 class without recorded consent | Everything but uploading works; Record keeps takes on each device |

---

## §7. The learning test

### Three questions of the idea

**Should it exist?** Zoom table reads and Kahoot-style joins exist, and
Readers Theater runs on paper. What no one gives a class is a play nobody
owns, a part for every child sized by their teacher, the whole class's voices
in one recording, and nothing kept that a model made. The strongest case
against, for the people outside the screen: children's voices are personal
information, a school's IT staff must vet one more app, and a teacher's
attention is the scarcest thing in the room. The design answers the first
with seats that carry only a typed name and an under-13 path that never
publishes; the second with no student accounts or emails; the third with a
list of what needs the teacher and nothing else.

**Who does it touch?** Students (some under 13), teachers, families who will
hear the result, school administrators who approve apps, the playwrights and
estates behind the castable plays (unchanged: only castable plays), and
archive.org (only adult and 13-and-over work reaches it).

**What will people learn, and stop learning?** They will read closely enough to
perform, listen for their cue, hear their own voice back, and try again:
the repeated reading Readers Theater research credits with fluency gains (§2.3).
The risk is that the app does the listening for them: auto-advance by speech
recognition, a "fluency score", or a voice that reads a struggling child's
part. None is proposed. The cursor moves when a person moves it or finishes
their own line.

### The four questions

1. **Does it deepen understanding?** Yes. The casting board shows the play's
   structure (who speaks how much, in which scenes) to the teacher, and the
   following reader shows each student where their lines sit in the whole
   play, not just their lines. Stage directions stay a part a person reads.
2. **Does it invite participation?** Yes. Every mode needs every reader's live
   voice; Record in the room hears the actual scene partner, not a stand-in.
   Nothing ranks readers.
3. **Does it support human agency?** The teacher casts, leads, approves and
   decides on publishing; the app proposes (Fill evenly) and never assigns.
   The student picks their own take and can ask for Again. A student can be
   handed the lead.
4. **Clarity over cleverness?** One new object, a cursor in a room, used four
   ways. The cleverer options (speech recognition to follow the reading, clock
   alignment to stitch overlapping voices, each phone speaking stand-ins in
   sync) are rejected: each needs sub-100 ms timing between devices and makes
   the play move without a person.

**What would we lose by automating?** If the room advanced itself by
recognizing speech, the reader who stumbles would be the one the app waits
on, publicly. If the app picked parts by "reading level" it would label
children. Both stay out (add to SCRATCHPAD "Out of scope": speech-following
cursor; reading-level labels; leaderboards or fluency scores).

---

## §8. Test plan on the real bench

Real devices only; never a simulator or emulator (the owner's rule). The bench
(`tools/bench.json`): iPhone 12 (`iphone`), open iPhone Duo (`duo`), iPad Pro
12.9 (`ipad`), the Mac (`mac`, role owner-watches: only with `--owner-ok`), Apple
TV 4K Ben Bedroom (`atv`), Pixel 8a (`android`), Google TV Streamer (`gtv`),
the Android TV at 10.0.0.139 (`atv2`), real Safari and Chrome (`web`). Leases
through `tools/devlease.py`; runs through `tools/qa_suite.py` so a skipped
device is reported as SKIP.

### §8.1 What can be automated

| # | Test | How |
|---|---|---|
| T1 | `read-protocol.js` rules: cursor, leading, assignments, late join, leader gone, two claims | Vitest in `worker/test`, golden cases shared with JS, Swift and Kotlin ports; each rule's mutant seen to fail |
| T2 | The Durable Object and polling adapters carry the same messages | Miniflare (Wrangler's local runtime) in `worker/test`; the same script of messages through both, compared |
| T3 | Rate limits with 40 members behind one address | A load script against a staging Worker (`wrangler deploy --env staging`), 40 fake members from one machine; no 429 for members, 429 for a 61st join a minute |
| T4 | **Cursor delay**, the transport gate | Each device logs the local time it drew the line lit (with its clock offset from the protocol's `clockOffset`); the leader logs when it pressed Next; the difference on every device, both adapters, 100 presses. Target: 95th percentile under 300 ms on the socket; record the polling numbers |
| T5 | A scripted multi-device join | Launch doors on every platform: `APP_START_READ_ROOM=<code>` with `APP_START_SEAT=<name>` (Apple `LaunchDoors.swift`), `appname_start_read_room` (Android `LaunchDoors.kt`), `?read-room=CODE&seat=NAME` (web), `APP_START_SCREEN=<pairing>` on the TVs. One orchestrator makes a class and a room on a staging Worker, opens it on all eight devices, advances 30 lines, and OCRs each device's frame (`tools/devharness.py`) for the lit line's text |
| T6 | Following and Back to the line | `tools/ios_uitest.py` tap tier on the iPhone and iPad; adb input on the Pixel; Playwright-free headless Chrome via `tools/web_run.py` for the web; frames read |
| T7 | Record in the room without sound | Each recording device runs the studio's stub microphone door (`appname_studio_stub`, its Apple and web twins) so takes are synthetic tones, muted (`APP_MUTE`, `appname_mute`, `?mute=1`); checks that exactly one device's microphone opens per line and every take uploads to the staging bucket with the right line id |
| T8 | Drop and rejoin | The orchestrator kills the network on one device mid-read (airplane mode via `adb shell cmd connectivity airplane-mode enable` on the Pixel; the web's `appname_force_offline` twin) and checks the leader's prompt and the rejoin snapshot |
| T9 | Shared screen | The TVs open the pairing door; frames from `tools/atv_shot.sh` and adb screencap, read for the three-line panel and the presence count; the Duo folded (outer display) shows the current line |
| T10 | Teacher flows | UI tests: make a class, add 25 seats from a pasted list, cast with Fill evenly, approve and Again, release a seat; on web, iPad, Mac (owner-ok), Pixel |
| T11 | Seats on a shared device | The iPad joins as seat A, ends the session, joins as seat B; no data from A is visible |
| T12 | Under-13 class without consent | Uploads refused; takes stay on each device; the production shows "on Lucy's device" |

### §8.2 What needs people in the room

Automation cannot judge whether a read feels right or whether a room of
voices records cleanly. These need the owner (and ideally a teacher and a few
readers), all audible, so each is asked for first (the ask-before-audible
rule):

- **H1, a table read with four to six people** on mixed devices (iPhone, Pixel,
  iPad, a Chromebook or laptop browser) with Ben Bedroom as the screen: does
  the lit line arrive before people need it; do readers lose their place;
  does anyone need the leader to say where we are.
- **H2, Record in the room**: the same group records one short scene (Today's
  scene, a two-voice play, Decision 079) in one room, then listens back: is
  the bleed acceptable, are line ends cut, does auto-advance keep a natural
  pace or rush people.
- **H3, a classroom pilot** with a teacher: 20 or more devices on a school
  network, seats from a pasted list, one period. The only way to see the
  school address, a Chromebook's browser, and a teacher's time in one test.
- **H4, accessibility**: VoiceOver, TalkBack and the largest text sizes while
  following; a reader who uses a screen reader holding a part (the lit line
  must be announced without stealing their place).

---

## §9. Owner questions

Only those our rules do not already answer.

**Q1. Turn on R2 take storage (P1).** Nothing in Record in the room or the
relay can leave a device until it is on. R2 asks for a payment method on file
even at zero cost (research 08c Q8). Recommended: yes, before building §5.

**Q2. May a class own a production (P8)?** Recommended: yes. A class
production is visible to every seat of the class without an invite, and only
to them; productions outside classes stay invite-only.

**Q3. May several parts record at once?** Today one part records at a time
(C7 as built). Recommended: in a production with teacher assignments or in a
read room, every assigned part may record at once; everywhere else the
one-at-a-time relay stays.

**Q4. Under-13 class productions and archive.org.** Recommended: they are
never published; they stay in the class and the teacher may export a file.
Classes marked 13 and over publish with each performer's own CC0 consent,
as adults do. (The alternative is verifiable parental consent per child,
a separate project.)

**Q5. Seats without accounts.** Decisions 057 and 072 ask for an account to
record with others. Recommended: a seat in a class (a name the teacher typed,
vouched for by the teacher's account) may upload takes to that class's
production without its own account; the takes belong to the teacher's account
and are deleted with the class. For adult rooms, recording with others keeps
asking for an account at the moment of recording.

**Q6. The teacher's notes.** Recommended: typed notes only in v1 (no stored
adult voice notes), shown only to that seat.

**Q7. SharePlay for an all-Apple room.** Recommended: no for now; one
cross-platform read room on every device, Apple included. SharePlay can carry
the same protocol later if all-Apple groups ask for it.

**Q8. The privacy policy (P5) and its scope.** The policy has to describe
shared productions and uploaded takes for everyone (it still says recorded
plays never leave the device), plus seats, classes and school consent. The
words are the owner's; the research in §2 lists what a school's review will
look for (COPPA school authorization, FERPA's school-official terms, a
student data privacy agreement). The amended COPPA rule, in force since
April 22, 2026, requires a **written retention policy and a written security
program** (§2.9). Recommended retention: a class's takes are kept until the
teacher deletes the class, and a class with no activity for one school year
is deleted after notice to the teacher. That is a value and a number only the
owner can set. Does the owner want Ear Drama to sign the
SDPC's national data privacy agreement for districts that ask?

### Decisions to log before building (our rules answer these)

- A new decision replacing Decision 065's transport reason for read rooms
  (Durable Objects are free now, §1.3), with T4 as the gate; Listen Together
  stays on D1 until it has a reason to move.
- PLAYS-DESIGN gains §12 "Reading together", tvOS-DESIGN §4.13 and the
  Android TV panel rule gain the cursor-driven screen, and PARITY.md gains
  rows for each mode, seats, casting board, review, and the shared screen,
  each platform ⏳ until built.
- SCRATCHPAD "Out of scope": a speech-following cursor; reading-level labels or
  suggested casting by ability; leaderboards and fluency scores; each phone
  speaking stand-ins in sync; the exquisite-corpse relay.
