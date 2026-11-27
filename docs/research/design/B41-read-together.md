# B41: Read together, far better (research and design, 2026-11-27)

Design phase of BACKLOG-LOOP B41. No product code changed. Frames: `b41-frames/`, made by `b41-proto/shoot.mjs` from
`b41-proto/mock.html`. Every word of the play on them comes from the real library through `b41-proto/make_data.py`:
*Trifles* by Susan Glaspell (Project Gutenberg 59432, script `gut-59432-101`), lines L0026 to L0050, with its five
roles and their line counts. The readers' names (Ann, Lucy, Sam, Theo, Ms. Ortiz) stand for names people type when
they join. The QR code is `qrencode`'s for `https://eardrama.org/read/K7M4QX`.

> **Owner, 2026-11-27**: *"I'd like for you to make the "read together" experience far better. I'd like "read
> together" to allow multiple people with different devices to either be able to read/rehearse in a single synced
> experience in the same room and I'd like it to be possible to have a synced reading experience on a call
> (SharePlay, etc.). Please research and implement."*

Context: the owner taught language arts. One friend wanted to read a play with friends across the world, and
teachers will lead readings in their classrooms.

**Look at these frames first:**
1. `reader-375-light.png`: a reader at her cue (the line before hers is marked **Cue**, hers **You**, and the room bar
   says **Your cue**).
2. `invite-375-light.png`: the leader's Invite sheet, with a QR code, the code, **Share link** and **SharePlay**.
3. `tv-1920-dark.png`: the TV as the stage, with the line now, the cast strip with names, and the code and QR to join.
4. `call-390-light.png`: an iPhone on a FaceTime call, with the system's SharePlay pill, the call's tiles, and the
   reader under them.

Then:
- `join-375-light.png`: joining from the link. Your name, then a part chosen from a list that shows who holds what.
- `leader-375-dark.png`: the leader's Reading sheet, holding Invite, Jump to, Go around the room, Hold, Hand the lead.
- `ipad-1180-light.png`: the director's iPad, with the parts and who holds them, who is here, and the invite.
- `android-412-dark.png`: Android in Rehearse, lines hidden, with **Your line** and the haptic mark.
- `states-375-light.png`: joining by code, held, going around, waiting, away, offline, slow, SharePlay ended, full.

---

## 1. Should it exist, who it touches, what people learn

*Deepens understanding.* A play read aloud together is how a play is understood: timing, the cue, listening for the
line before yours. The design surfaces the **cue** itself, the theater's own word. Rehearsal tools (hide my lines,
cue marks, going around the room) are the ones drama teachers use, made visible rather than automated.

*Invites participation.* Every reader holds a part and moves the play on with their own line (**Readers turn the
page**, §5.2), instead of waiting while one leader presses Next 183 times. Going around the room gives every student
a turn, in an order the teacher can see.

*Supports agency.* People cast each other. The app never suggests who reads what (PLAYS-DESIGN §12.4 stands). A
stand-in voice reads only parts nobody holds, and only when the leader turns it on.

*Clarity.* One room, one code, one link, carried by whatever brought people together: the same room, a FaceTime call,
or a Meet or Zoom call. The rules live in one pure protocol.

*What it refuses*:
- a speech-following cursor that listens to the room (out of scope since Decision 082);
- fluency scores or rankings;
- casting by ability;
- in-app voice or video calls (people already have one; see `cross-platform-multiplayer`, "The call is not our
  problem");
- recording over SharePlay.

*Who it touches*:
- A teacher with 25 students on shared iPads and a projector.
- Four adults around a kitchen table, each on their own phone.
- Friends on three continents on a FaceTime call, one of them on Android who joined it from a link.
- A director rehearsing a cast.

*What people might stop learning*: when the leader paces every line, readers stop listening for their cue. That is
the reason for Readers turn the page and the cue mark.

## 2. What Read Together does today, and where it falls short (measured)

Today's system is large and sound:
- Decision 082 and PLAYS-DESIGN §12.
- `worker/src/read-protocol.js`, 662 lines, pure, held on every stack by `worker/test/read-golden.json`
  (115 cases).
- The `ReadRoom` Durable Object over WebSockets, with D1 long polling as the fallback.
- Four modes, class seats, a TV paired as the screen, takes passed through to the leader, and Remove.

The gaps below were measured from the code and the bench (file and line references are this worktree at
`fce1ff30`).

| Measure | Today | Evidence | Verdict |
|---|---|---|---|
| **Join flow** | A reader can join only from a link (`/read/CODE`, `eardrama://read/CODE`). No platform has a field to type a reading code: the only code fields are "Class code", "Code on the TV" and Listen Together's "Room code". No room offers Share or a QR code, so the leader reads six characters aloud and each reader types `eardrama.org/read/K7M4QX` into a browser. Adult join is then Join, then the Parts dialog, then Take: 3 taps after the URL. | grep for code `TextField`/`OutlinedTextField`/`placeholder` in `apple/Shared`, `android/.../ui`, `js/` finds no read-room code field; none of `navigator.share`, `ShareLink`, a QR code or the clipboard appears in `read-ui.js`, `ReadViews.swift`, `ReadRoomReader.swift`, `ReadScreens.kt` or `ReaderRoom.kt` | **The largest gap.** In a classroom, typing a URL is the step where readings stall |
| **Latency of a cursor move** | Socket p95 80 to 235 ms on every device; web polling p95 833 ms; 100/100 moves arrived | T7 bench, 2026-11-20, production Worker, 10 members (ROUND3-LOOP tick 25; `tools/read_bench.py`) | **Meets** Decision 082's 300 ms gate on the socket; polling is the fallback only |
| **Pacing** | Only the leader moves the cursor in Table read and Rehearse; readers can end a line only in Record (`line-done`). *Trifles* has 183 lines, so the leader presses Next about 180 times, and the next line lights a press late after every speech | `applyCursor`, `lineDone` (`read-protocol.js` 356 to 407) | **Falls short**: the leader becomes a page-turner, and readers wait instead of listening for their cue |
| **Late joiners** | The snapshot carries the cursor, parts, next line and who reads now | `joinSnapshot` (625 to 662) | **Good** |
| **Leader handoff** | The protocol has `lead`, but no client sends it: no "Hand the lead" control exists anywhere. An adult room passes the lead only when its leader has been gone 2 minutes; a class holds still | grep for a `lead` message in `read-session.js`, `ReadSession.swift`, `ReadSession.kt`: none | **Missing in every client** |
| **Roles and claims** | Readers claim their own parts (first claim wins); the web's Parts list reads "Taken" with no name, although names now travel in `members[].name`. In an adult room the leader cannot cast anyone. Classes cast through the teacher's board | WEB-DESIGN §4.17 item 2; `claimInRoom` | **Falls short** for the table read where the director says "Ann, you're Mrs. Hale" |
| **Cue and "your line"** | "Next: you, in 3 lines" and "Your line" are words in the room bar. There is no cue mark on the page, and no haptic on any platform | grep for haptic, vibrate, `sensoryFeedback` or `HapticFeedback` in the read views: none | **Falls short** of what rehearsal needs |
| **Rehearse tools** | Hide my lines on Apple and Android, and on the web through `reader.js` `hideAllowed`. Again goes to the start of the scene. No jump to an arbitrary scene, no hold, no going around the room | `ReadCore.sceneStart`; no `pause` or `hold` in any client | **Partial** |
| **Stand-ins for missing parts** | Only a screen speaks open parts, and only while `read_open` is on. With no screen (most kitchen tables, every call) open parts are silent | PLAYS-DESIGN §12.10 item 10 | **Falls short** on calls |
| **On a call** | Nothing. Decision 082 says "no SharePlay" for read rooms. Listen Together already runs on SharePlay (`apple/Core/ListenTogether/SharePlayRoom.swift`), and both entitlement files carry `com.apple.developer.group-session` | Decision 082; iOS-DESIGN §5.8 | **Missing**: the friend across the world has to paste a link into a chat by hand |
| **Offline** | "You are offline." The reader keeps the page but follows nothing. No room can open without the Worker | WEB-DESIGN §4.17 item 6 | **Acceptable** with one change (§8): keep reading by hand, then rejoin |

## 3. Research

### 3.1 Same room

| Option | Reach | Verdict |
|---|---|---|
| **The Worker room** (today) | Every platform, the web too; one code; works through a school's single address; polling when a school blocks sockets | **The same-room transport.** Measured at p95 under 235 ms. Free plan: Durable Objects are on Workers Free (SQLite-backed, since 2025-04-07), with 100,000 requests a day. A WebSocket's opening counts as one request; incoming messages bill at 20 to 1; outgoing messages are free; a hibernated socket accrues no duration ([changelog](https://developers.cloudflare.com/changelog/2025-04-07-durable-objects-free-tier), [pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/), [WebSockets](https://developers.cloudflare.com/durable-objects/best-practices/websockets/)). A class of 30 reading 180 lines sends about 30 opens plus 180 incoming moves; at 20 to 1 that is about 40 billed requests per reading |
| **Local network**: Bonjour (`NWBrowser`/`NWListener`) plus Android NSD, both DNS-SD/mDNS and interoperable ([Android NSD](https://developer.android.com/develop/connectivity/wifi/use-nsd)) | Apple and Android on the same Wi-Fi; **never the web** (no LAN discovery API) | **Not worth it now.** It leaves out the web (projectors, Chromebooks, shared carts). School and office Wi-Fi commonly isolate clients from each other, which blocks mDNS and peer TCP *(general knowledge, unverified here)*. It would also need app-layer encryption, keyed from the room code as in `cross-platform-multiplayer`. Its only gain is a room with no internet, which §8's follow-by-hand covers. The transport seam (§6) keeps it possible |
| **Google Nearby Connections** | Google's page claims Android and iOS interop ([nearby](https://developers.google.com/nearby)); the iOS side supports only Wi-Fi LAN, and the Swift package is `0.0.1-ios` (2021) | **No.** It is Android-only in practice and would add a third-party Swift package (AGENTS.md hard rule) |
| **The TV as the stage** (today: a pairing code; tvOS-DESIGN §4.13, ANDROID-DESIGN's TV panel, WEB-DESIGN §4.18) | Apple TV, Google TV, any browser on a projector | **Keep and deepen.** The TV becomes the room's lobby and stage: the line now, the cast strip with names, and the code with a QR code so phones join by camera (frame 3). It can open a reading itself (Library, **Show a Reading**), and it is the stand-in voice. It still records nothing, leads nothing and holds no part (Decision 082) |

### 3.2 What rehearsal needs (practice, and what the design does)

| Need | Design |
|---|---|
| My part highlighted | Kept: the I'm playing tint |
| The cue line, the line before mine | **New**: a **Cue** mark in the margin of the last spoken line before mine, and **You** on mine. The room bar says **Your cue** while the cursor is on it, then **Your line** |
| A "your line" nudge | **New**: one `medium` haptic (AGENTS.md taxonomy) when the cursor reaches *my* line, and none at the cue (one nudge, not two). Web: `navigator.vibrate(30)` where it exists (Android Chrome); Safari has none, and the bar's words carry it |
| Stand-ins for missing parts | **Extended**: the **voice device** (§5.2) speaks open parts while Read open parts is on: the screen when there is one, otherwise the leader's device. On a call, the call carries the leader's voice to everyone. Never stored, never mixed (PLAYS-DESIGN §5) |
| Pause and resume by the leader | **New**: **Hold**. Every device shows "Held by Sam". Turning the page, microphones and the voice stop until the leader lets go. Directors use it for notes |
| Jump to scene | **New**: **Jump to** opens the play's sections (`sectionsOf`) as a list. The leader picks one and the cursor moves to its first line. The protocol already accepts any line |
| Go around the room | **New**: a turn order of the readers present. Each spoken line, or each speech (owner question 2), goes to the next reader in turn, whatever its part. "Your turn" replaces "Your line". It is common in classrooms for prose and verse; in a play it gives every student lines whatever the casting |
| Hide my lines | Kept (Rehearse), with **Show my lines** to peek |
| Readers move on themselves | **New**: **Readers turn the page** (§5.2). The reader holding the line taps **Done**, or presses the space bar or a page-turn pedal, and the cursor moves to the next line. The leader can always move it too |

### 3.3 On a call

| Path | Facts (sources) | Verdict |
|---|---|---|
| **SharePlay** (GroupActivities) | `GroupSessionMessenger` on iOS 15, macOS 12, tvOS 15 and later; reliable delivery by default (`DeliveryMode`, iOS 16+); `GroupSessionJournal` for files (iOS 17+); end-to-end encrypted ([messenger](https://developer.apple.com/documentation/groupactivities/groupsessionmessenger), [framework](https://developer.apple.com/documentation/groupactivities)). Starts from a FaceTime call, a Messages conversation, or (iOS 17) bringing iPhones together over AirDrop with a `ShareLink` carrying a `Transferable` activity ([WWDC23 10239](https://developer.apple.com/videos/play/wwdc2023/10239/), [promoting SharePlay](https://developer.apple.com/documentation/groupactivities/promoting-shareplay-activities-from-your-apps-ui)). `GroupActivitySharingController` places a call when there is none (TN3128); it exists on UIKit and AppKit, **not on tvOS** (checked in the 27.0 SDK, `shareplay-activities`). FaceTime runs on Apple TV since tvOS 17. The entitlement is self-serve ([configuring](https://developer.apple.com/documentation/xcode/configuring-group-activities)) and is already in both entitlement files. Testing needs two or more physical devices (WWDC23) and, by practice, two Apple IDs. Unconfirmed: a message size limit (none documented; cursor messages are bytes), and whether a non-media activity runs on Apple TV | **Yes, for Apple devices in a call.** Phase 1 uses it as the *door* (§6.2), phase 2 optionally as a *transport* |
| **Google Meet Live Sharing** (Android co-doing) | Folded into the Android Meet add-ons SDK (`com.google.android.meet:meet-addons`); the newest Android release note (2025-01-30) is still "Early Access Preview", entered by application ([release notes](https://developers.google.com/workspace/meet/release-notes), [2022 launch](https://developers.googleblog.com/2022/05/Introducing-Google-Meet-Live-Sharing-SDK.html)); co-doing state limit 16 KB. Meet on Google TV is discontinued ([9to5Google, 2024-09-27](https://9to5google.com/2024/09/27/google-meet-android-tv-app-shutdown-soon/)) | **Not now.** It is a preview behind an application, with no public minSdk, and serves only people already in Meet on Android. Our room link in Meet's chat reaches the same people today |
| **Meet add-ons for the web** | Generally available since 2024-09-09; side panel and main stage; published through the Google Workspace Marketplace, which needs Google's review for public listing, and visibility cannot be changed later ([overview](https://developers.google.com/workspace/meet/add-ons/guides/overview), [publish](https://developers.google.com/workspace/meet/add-ons/guides/publish)) | **Possible later**: the web reader inside Meet's main stage, running the same room. It needs an outward listing under Learning is Change (owner question 1) |
| **Zoom Apps** | Run in the Zoom client on desktop and mobile; public apps pass Marketplace review; a free developer account must add a credit card ([Zoom Apps](https://developers.zoom.us/docs/zoom-apps/), [review](https://developers.zoom.us/docs/distribute/app-review-process/)) | **Out of scope**: review overhead and a card on file, for reach the room link already has in Zoom's chat |
| **Discord Activities** | A web app in an iframe in Discord; discovery needs identity and app verification ([overview](https://docs.discord.com/developers/activities/overview)) | **Out of scope**: a second web build tied to Discord's SDK and proxy, for an audience that is not our readers |
| **The room link beside any call** | Works today on every platform, in every call app's chat | **The universal path.** Phase 1 makes it one tap: **Share link**, and the QR code to scan |

## 4. The experience

**In a classroom.**
1. Ms. Ortiz opens *Trifles* on her iPad, taps **Read Together**, and the Apple TV shows the stage (it was waiting on
   **Show a Reading**, or she adds it by its code).
2. The TV shows the code and a QR code. Students scan it with the iPads' camera; the link opens their class's join
   (their name from the class list, as today).
3. Parts come from her casting board. She turns on **Go around the room** for the opening and **Readers turn the
   page**.
4. Each student taps **Done** at the end of their line, and the next student's iPad says **Your turn** with a nudge.
5. She **Holds** for a note, then **Jumps to** the next scene.

**Around a kitchen table.**
1. Sam taps **Read Together**, then **Invite**, and the others scan the QR from his phone (frame 2). Ann's phone opens
   the join page (frame 5): her name already typed, the parts with who holds them; she takes MRS. HALE and taps Join.
2. Nobody holds HALE, so Sam turns on **Read open parts** and his phone reads HALE's lines aloud.
3. Each reader taps **Done**, or nothing at all when Sam keeps the pace.

**Across the world.**
1. Lucy is on a FaceTime call with Ann (iPhone), Theo (Mac) and Priya (Android, who joined the call from a FaceTime
   link in her browser).
2. Lucy taps **Read Together**, then **SharePlay**. The iPhone and Mac get the system's SharePlay prompt and land in
   the same reading with one tap (frame 4).
3. Priya gets the link Lucy shares into the call's chat (**Share link**) and joins in the Android app or the browser.
   It is the same room, so all four see the same lit line.

**On a Meet or Zoom call.** The leader shares the link into the chat. Every device joins the same room; the call
carries the voices.

## 5. The protocol and the arbiter (one place, no networking)

### 5.1 Where it lives

`worker/src/read-protocol.js` stays the single source. It imports nothing, has no clock, and is enforced by the
existing test. `read-golden.json` holds every stack to it.

For the SharePlay transport (phase 2) the host device runs the arbiter, so Swift needs a port of `newRoom`,
`applyMessage`, `settle` and `joinSnapshot`. Kotlin needs the same only if Meet ever becomes a transport. The golden
file already has cases for all four; today's clients port only the client-side functions.

### 5.2 Version 2: what is added (additive; a v1 client ignores unknown fields)

| Message (sender) | Rule | Snapshot |
|---|---|---|
| `turn {line, base}` (a reader) | Allowed when `room.readers_turn` is on, the room is not held, the sender **holds** the line (claim, seat assignment, or round turn), `line` is the cursor and `base` is the current `cursor_gen`. The cursor moves to the next line that is held, or that the voice reads (Read open parts on and a voice device present); unheld direction lines are skipped. A repeat is a no-op; an old base is `stale`. The voice device may `turn` an open line when its stand-in ends: this is the one machine turn, after a person-started line, never on a timer | `readers_turn` |
| `readers-turn {on}` (leader) | Default **on** in an adult room, **off** in a class (owner question 3) | |
| `hold {on}` (leader or owner) | While held: `turn` and `line-done` are refused `held`; record microphones close; the voice stops. The leader's own cursor moves still apply (moving while held is how a director jumps for a note) | `held`, `held_by` (name) |
| `cast {part, to}` (leader, adult room) | Gives a part to a live reader (`to` a member id) or opens it (`to: null`). It overrides a claim: the leader decides, and the reader sees it at once. A class answers `class_assignments_only` (its casting board rules). A screen cannot be cast | |
| `round {on, order?}` (leader) | On: `order` is the live readers in join order (or the leader's order), saved with `round_from` = the cursor index. Each spoken line from `round_from` belongs to `order[k mod n]`, `k` counting spoken lines (or speeches, owner question 2). `holds()` answers by the round while it is on. A member who leaves drops out of the order at the next line | `round: {order, from}` |
| `lead {to}` | Unchanged. **Every client now sends it** (Hand the lead, frame `leader`) | |
| `voiceOf(room, members, now)` (a function, no message) | While `read_open` is on: the earliest-joined live screen, else the leader. One device only, never every phone (out of scope since Decision 082) | `voice` (member id or null) |

**Arbiter rules, unchanged and restated:**
- The server (or the SharePlay host) orders messages: one message at a time, and each changes the `generation`.
- A move made from an old generation is refused, never merged.
- First claim wins, except a leader's `cast`, which wins.
- A class room holds still for its teacher.
- An adult room hands the lead to the reader present longest after 2 minutes.
- At most 40 members.
- A screen never leads or holds a part.

### 5.3 What the clients compute from the snapshot (golden-checked)

- `cueOf(snapshot, cast, me)`: the last spoken line before my next one, when the cursor is at or before it.
- The bar's fact, from the cursor's distance: **Your cue**, **Your line**, **Your turn**, "Next: you, in N lines",
  or "{name} is reading".
- `hapticAt(prev, next, me)`: true only when the cursor *arrives* on my line, not on a resync of the same line.

These live beside `nextMine` in each `ReadCore`, so the web, Swift and Kotlin agree on when a phone buzzes.

## 6. Transports (one seam)

### 6.1 The seam

`ReadTransport` in each client's Core:
- `open(join) -> snapshot`
- `send(msg) -> reply | refusal`
- `snapshots: stream`
- `close(leave: Bool)`

`ReadSession` (web `read-session.js`, `ReadSession.swift`, `ReadSession.kt`) already does this for the socket and the
long poll. The batch names the seam and moves the polling and socket code behind it, without changing behavior.

### 6.2 SharePlay, phase 1: the door (build this)

A `GroupActivity` named **`ReadTogether`** (`app.eardrama.read-together`, type `.generic`) carries:
- `code`, the Worker room's code;
- `script_id` and `script_revision`;
- `title`, and a `fallbackURL` of `https://eardrama.org/read/{code}`.

How it runs:
- **Start.** In a call (`GroupStateObserver.isEligibleForGroupSession`), **SharePlay** in the Invite sheet calls
  `activate()`. Outside one it opens `GroupActivitySharingController`, which places the call. On iOS 17 and later the
  sheet's `ShareLink` with the activity also offers AirDrop (iPhones brought together) and Messages.
- **Join.** Every Apple device listens with `ReadTogether.sessions()` from launch (the cold-launch lesson in
  `shareplay-activities`; `SharePlayRoom` already does it for Listen Together). On a session it joins it, then joins
  the Worker room with the code: the join sheet with Your name, then Join. The system's SharePlay UI shows who is in
  the call.
- **One room for everyone.** The Android or web friend in the same call joins by the link. Takes in Record still pass
  through the Worker to the leader (§12.5), so Record works on a call unchanged.
- **Ending.** The session ending (`.invalidated`) does not end the reading: "SharePlay ended" with **Stay in the
  reading** (frame `states`). Leaving the reading leaves the session.
- **tvOS.** An Apple TV in the FaceTime call receives the session and joins as the **screen**, with no part and no
  lead (it has no `GroupActivitySharingController`, so it cannot start one). Whether a non-media activity reaches
  tvOS is unconfirmed: batch B41d checks it on a device, and the pairing code remains the TV's way in.
- **macOS.** The AppKit sharing controller (`presentAsSheet`, `await controller.result`).

**Why the door and not the messenger first:**
1. A call often mixes Apple and non-Apple people (FaceTime links let Android and Windows join a call from a browser).
   A messenger-only room would split them from the reading.
2. One arbiter (the Worker) means no host election and no split brain.
3. The latency is already measured under the gate.
4. Record mode's pass-through needs the Worker anyway.
5. It reuses everything built.

### 6.3 SharePlay, phase 2: the messenger transport (designed; build only on a measured need)

A `ReadTransport` over one reliable `GroupSessionMessenger`, for an Apple-only call when the Worker cannot be
reached, or to take load off the shared free account if the request count ever nears its ceiling.

How it would run:
- The host is the participant that started; two at once settle by the lower participant id
  (`RoomProtocol.claimWins`, as Listen Together does).
- The host runs the Swift arbiter port. Every message goes to the host, which broadcasts snapshots.
- After each change the host also sends the world (room and members, no keys exist here), so every peer holds a
  replica. When the host leaves, the lowest remaining id continues from its replica.
- Member id is the participant id; the session authenticates members, so there are no member keys.
- **No Record over the messenger** (no takes over SharePlay), and no class rooms (a class needs its seats on the
  Worker).
- Gate: the same 300 ms p95 bench as T4, run on two Apple IDs.

### 6.4 Not built, and why

- Local network (§3.1).
- Meet Live Sharing (§3.3, a preview behind an application).
- Zoom and Discord (§3.3).
- A Meet web add-on, unless the owner says yes (question 1). It would run the web reader against the same Worker
  room, and the protocol would not change.

## 7. Data and privacy

- **Nothing new is kept.** The room keeps a typed name and who holds what until it ends, then deletes both
  (PLAYS-DESIGN §12.13). `round`, `held`, `readers_turn` and `cast` live in the room object and go with it.
- **The SharePlay activity carries** the room code, script id, revision and title. No name and no audio. Apple's
  servers relay it end-to-end encrypted and do not learn the app's identity.
- **Names only as given.** GroupActivities gives no participant names, so the join sheet still asks "Your name" (the
  account's name, or the last one typed on the device). A seat's name is the teacher's.
- **No recordings over SharePlay or Meet.** Takes keep their one path: written on the device, passed through the
  Worker to the leader, deleted on arrival (Decision 082).
- **13+.** The age question gates Share, Invite, Take part and Publish of productions (Decision 084). An adult read
  room keeps nothing and never asked before. Starting SharePlay sends a code inside a call the person placed with
  people they know, so no new gate is added. A production's Record room keeps its existing rules (its takes go into a
  production that is already gated). An under-13 device's "sharing off" answer hides **SharePlay** and **Share link**
  in Invite and keeps the code (a classroom's seats never ask: the school decides).
- **Haptics and the cue** are computed on the device from the snapshot. Nothing is sent.

## 8. Failure states (essential words only; frame `states`)

| What happens | What shows |
|---|---|
| Typed code wrong | "That is not a reading code." / "No reading with that code." (today's refusals) |
| The leader holds | "Held by Sam" on every device; Done disabled |
| Going around, my turn | **Your turn**, with a nudge |
| A class's teacher drops | "Waiting for Ms. Ortiz" (today) |
| The line's reader is away | For the leader: "Lucy's phone is away" with **Skip**, **Read it from here** (the voice device's stand-in) and **Wait** (§12.6, extended to adult rooms) |
| Offline | "You are offline." and the reader keeps the page, the last cursor, and the reader's own page turns (**Following by hand**). On reconnect the snapshot puts them back on the line. A leader offline keeps moving locally; its stale moves are refused and it resyncs (today's rule) |
| Slow (over 2 s) | "Slow connection" (today) |
| SharePlay ends | "SharePlay ended" with **Stay in the reading** |
| SharePlay unavailable (no call, Screen Time, or a managed device) | `prepareForActivation` → `.activationDisabled`: the Invite sheet hides SharePlay and keeps Share link and the QR code. It never silently does nothing (the "three-case outcome" lesson) |
| 41st member | "This reading is full." (today) |
| A non-media activity does not reach tvOS | The TV keeps its pairing code; tvOS-DESIGN says so |

## 9. Platforms (same verbs, native idioms)

**Invite** (leader):
- Web: a `<dialog>` with the QR code, **Share link** (`navigator.share`, or Copy where there is none) and the code.
- iOS and iPadOS: a sheet with `ShareLink(item: ReadTogether)` (SharePlay, Messages, AirDrop), a plain `ShareLink`
  for the URL, and the QR from Core Image's `CIQRCodeGenerator`.
- macOS: the Reading menu's Invite, with the AppKit sharing controller.
- Android: the system share sheet (`Intent.ACTION_SEND`) and the QR code.
- tvOS and Google TV: the code and QR on the stage, always.

**Join a reading** (anyone): a six-character field on Record (and on the web's Record page) with **Join**, and
**Scan** on phones (Apple: the system camera already opens universal links; Android: the same, through App Links).

**The bar** (readers): **Done** (when Readers turn the page is on and it is my line), the fact, "{n} here". The space
bar or a pedal sends `turn` for a reader holding the line, and moves the cursor for the leader.

**Haptic:**
- iOS: `.sensoryFeedback(.impact(weight: .medium), trigger:)`.
- Android: `HapticFeedbackConstants.CONFIRM` through the app's one haptic map.
- Web: `navigator.vibrate`.
- macOS and TVs: none. AGENTS.md's taxonomy: `medium`, mapped in one place.

**QR on Android and the web:** neither platform has a native generator. Use one small public-domain-style encoder per
stack, Project Nayuki's QR Code generator (MIT; single files in JS and Java, [nayuki.io](https://www.nayuki.io/page/qr-code-generator-library)).
A golden test compares each stack's module matrix for the same URL with Core Image's output, through a fixture made
once. Swift stays native, with no package.

**Binding docs to change first (fix the doc, then the feature):**
- PLAYS-DESIGN §12: a new §12.14, and §12.7's "Apple uses the Worker's read room, not SharePlay" becomes "the
  Worker's read room; SharePlay is the door on a call".
- WEB-DESIGN §4.17 and §4.18.
- iOS-DESIGN: a new §5.9 beside §5.8.
- macOS-DESIGN.
- tvOS-DESIGN §4.13.
- ANDROID-DESIGN's read room and TV panel.
- PARITY.md rows: Table read, Rehearse, plus new rows for Invite and Join by code, Readers turn the page, Hold, Go
  around the room, Hand the lead, SharePlay door.
- A **DECISIONS entry** that supersedes Decision 082's "no SharePlay" sentence, with the owner's words above.

## 10. Build batches and acceptance checks

Each batch updates its binding doc first, then PARITY.md in the same change set, bumps the version, and keeps every
word on screen to a label, fact, warning or refusal. Briefs forbid simulators (real devices only).

| Batch | What | Acceptance |
|---|---|---|
| **B41a Protocol v2** (Worker, Opus) | `turn`, `readers-turn`, `hold`, `cast`, `round`, `voiceOf`, and the snapshot fields. `read-rooms.js` passes them on both transports. `node worker/tools/read-golden.mjs` regenerates the goldens. WORKER.md | Worker suite green. Every new rule has a test seen to fail first and a mutant in `test/mutations.mjs` (`b41:`). The no-import test still passes. A dry run on the deployed Worker (two web members, `turn` round trip) before the deploy. Free-plan check: requests per reading recorded |
| **B41b Web** (Sonnet) | The seam in `read-session.js`; Invite (Nayuki QR, `navigator.share`); Join a reading on Record; the join page with names and parts (frame `join`); the Cue and You marks and the bar facts; Done and the keys; Hold, Jump to, Go around the room, Cast, Hand the lead in the Reading sheet; the voice device; vibrate; follow-by-hand offline | `js/read.test.js` runs the v2 goldens, including `cueOf` and `hapticAt`. Frames at 375 and 1440, light and dark, read. Real Safari and Chrome on the bench: join by QR scan from the Pixel and the iPhone; 50 `turn`s across three devices with the bench's clock-corrected delay, p95 under 300 ms on the socket |
| **B41c Apple** (Sonnet port, Opus for SharePlay) | `ReadCore` v2 plus goldens; the seam; Invite with `ShareLink(ReadTogether)` and Core Image QR; Join a reading; Done, keys and pedal; `.sensoryFeedback`; Hold, Jump to, Round, Cast, Hand the lead; the voice device. The **SharePlay door**: `ReadTogether` activity, `sessions()` from launch in a long-lived object next to `SharePlayRoom`, the three-case start, "SharePlay ended" | `ReadCoreTests` on the v2 goldens. xcodegen first; macOS, iOS and tvOS Release builds with zero warnings. The iPhone 12 and the open Duo read frames (the Duo is a priority device). Tap tier: join by code, Done, Hold, on two devices. **SharePlay, two real devices, two Apple IDs** (§11) |
| **B41d TV stage** (Sonnet) | Apple TV, Google TV and the web screen: the cast strip with names, the code with QR, **Show a Reading** opening a room's stage, the voice device. Apple TV joining a FaceTime SharePlay as the screen (if the device check passes) | Real Apple TV (Ben Bedroom, lease `atv`) and both Google TVs (`adb connect 10.0.0.55:5555`, `10.0.0.139:5555`): frames read at ten feet. The stand-in speaks only open lines and stops on a move (an audible run: ask the owner first) |
| **B41e Android** (Sonnet) | `ReadCore.kt` v2 plus goldens; the seam; Invite (share intent, Nayuki QR); Join a reading; Done, the volume or pedal keys; `HapticFeedbackConstants.CONFIRM`; Hold, Jump to, Round, Cast, Hand the lead | `ReadCoreTest` on the v2 goldens; `lintRelease` clean; Pixel 8a frames read; the bench's 50-turn run with the Pixel in it. No Play build while one is in review (memory rule) |
| **B41f Bench** (Sonnet) | `tools/read_bench.py` gains a `turn` mode (each device turns its own lines in a scripted cast) and a `round` mode; per-device logs of the drawn lit line, corrected by `clockOffset` | Runs on the full bench (iPhone 12, Duo, iPad, Pixel, both Google TVs, Apple TV, 3 web), 100 turns, p95 under 300 ms on sockets; it names every device it could not reach |
| **B41g SharePlay messenger** (deferred, Opus) | §6.3: the Swift arbiter port (`newRoom`, `applyMessage`, `settle`, `joinSnapshot`) on the existing goldens; the host replica; a `ReadTransport` conformance | Built only if B41c/B41f measure a need (the Worker unreachable on a call, or requests near the free ceiling). Its own 300 ms p95 run on two Apple IDs |

## 11. Testing SharePlay without simulators

A simulator cannot place a FaceTime call; the memory rules forbid simulators anyway.

1. **Two real devices, two Apple IDs**: the iPhone 12 (lease `iphone`) and the iPad or the open Duo, one of them
   signed into FaceTime with a second Apple ID. "Two devices, one account" behaves differently and passes tests that
   the real case fails (`shareplay-activities`).
2. **Confirm the build on both** with `devicectl device info apps` before diagnosing anything.
3. **Placing and answering the call** needs a person, or iOS's Auto-Answer Calls accessibility setting on the
   answering device *(unconfirmed for FaceTime on iPad; check before relying on it)*. The SharePlay start prompt is a
   system alert that the tap tier (`tools/ios_uitest.py`) can press through SpringBoard. A DEBUG launch door
   (`APP_START_READ=CODE`, `APP_SHAREPLAY=1`, a no-op in production) brings the leader to the Invite sheet.
4. **Measure**: each device logs the drawn lit line with its clock offset to the Worker. The bench copies the logs
   off with `devicectl` and reports p95, the same method as T4.
5. **Apple TV in the call**: FaceTime on Apple TV needs an iPhone or iPad as its camera (tvOS 17+); this is the
   check of whether a non-media activity reaches tvOS.
6. **Mixed call**: a Pixel joins the FaceTime call from a FaceTime web link in Chrome, then joins the reading by the
   shared link. The test passes when all three show the same lit line within the gate.

**Needs the owner:**
- a second Apple ID signed into FaceTime on one test device (or a friend's device), once;
- answering the first calls, unless Auto-Answer works;
- the Apple TV FaceTime setup with an iPhone as its camera;
- an audible run of the voice device (memory rule: ask first).

## 12. Questions only the owner can answer (three)

1. **A Google Meet add-on?** The web reader could run inside Meet's main stage. It needs a public Google Workspace
   Marketplace listing under Learning is Change and Google's review, and the visibility can't be changed later.
   *Recommendation: not now.* The link in Meet's chat reaches the same people today, and Android's Live Sharing SDK
   is still a preview behind an application.
2. **Going around the room: who gets the next turn?** The next spoken line, the next speech whatever its length, or
   the next scene? *Recommendation: each speech* (one person's lines until the next speaker), the usual
   popcorn/round-robin unit for a script. The teacher can turn it off for cast parts.
3. **In a class, who turns the page by default: the teacher, or each student at the end of their line?**
   *Recommendation: the teacher by default in a class, and each reader by default among adults.* Either is one
   switch in the Reading sheet.

## 13. Out of scope (add to SCRATCHPAD "Out of scope")

- A speech-following cursor.
- Every phone speaking stand-ins at once (one voice device only).
- In-app calls or video.
- Recording over SharePlay or Meet.
- Local-network rooms.
- Nearby Connections.
- Zoom Apps and Discord Activities.
- Meet Live Sharing on Android while it is an application-only preview.
- Fluency scores, rankings, and casting by ability.

## 14. Files

- `docs/research/design/b41-proto/mock.html`, `make_data.py`, `data.js`, `qr.svg`, `shoot.mjs`: the mock, its real
  data, and the frame shooter (`nice -n 15 node shoot.mjs ../b41-frames 8995`).
- `docs/research/design/b41-frames/*.png`: ten frames, each read before this was written.
