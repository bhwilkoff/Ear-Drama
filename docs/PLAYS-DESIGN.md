# Ear Drama plays, phase 1: pass the phone (Feature Design, BINDING)

**Binding.** Quote this document before changing any recording, casting, or
play-mixing path on any platform. Where a platform design doc and this one
disagree about plays, this doc wins on what the feature does and the platform
doc wins on how it looks. Numbers marked *measured* were run on 2026-10-22
against the caches named; the rest is from research 08 and says so.

I want a family at a kitchen table, or a class with one iPad, to be able to
open a play nobody owns anymore, hand the device around until every part has
a human voice, and then listen to what they made together.

On 2026-10-18 the owner described the relay in their own words: *"you would
take one part and act it out. The other non-recorded roles would be simulated
audio when you are recording your parts (but only your part would actually be
recorded). Then the next person would take one of the simulated parts and
record that."* Decision 059 put phases 1 and 2 in 1.0, with radio scripts and
public-domain stage plays both castable when their own record carries the
rights evidence, and no approval queue. This page is phase 1, which is the
relay on one device, with no server and nothing uploaded; a first take needs
no account (Decision 079, owner 2026-11-15; it replaced "recording needs an
account", owner 2026-10-23).

The device voice is a scene partner, never a performer.

---

> **Owner, 2026-11-15** (Decision 079, from `docs/research/design/R2-design-review.md` Q1, Q2): a newcomer records without signing in; takes stay on the device; an account is asked for only to share, invite, publish, or start a second production, at that moment and with the reason. A production appears in Yours only after its first take, and one that stays empty is removed. *"I would like for people to get excited about recording new Ear Dramas."* This replaces the 2026-10-23 rule "Recording needs an account, always" everywhere below (§2.3, §2.9 rule 9, §6, §8 rule 4, §9); Decision 072's invite-only takes still need an account.

> **Owner, 2026-10-29** (DESIGN-LOOP): an invite link shows everything signed out (the play, parts, who is in, playable takes); claiming and recording need an account. Finished ear dramas are listed and credited on Ear Drama's own pages. Recording has three modes: Run through, Line by line, Step. These supersede any narrower rule below; §11.1, §11.5 and §11.7 rule 3 are rewritten for the first two (Worker side built 2026-10-29: docs/WORKER.md "Open reads"). The recording modes are written into §2.4 (D3-6, 2026-10-30).

## §1. Why it should exist, and who it touches

The `learning-orientation-design` skill asks three questions of the idea
before the four questions of the feature, so here are both, answered for
this feature rather than in general.

**Should it exist at all?** LibriVox has done this by hand for years: forum
casting, one reader per role, an editor stitching the takes together, and
five to twelve months a play (research 08c §1.1). Rehearsal apps such as Run
Lines and Acting Pal sell a synthetic scene partner, but nothing they make is
kept. What we can give people that neither does is a play finished in an
evening, by the people in one room, from a text whose rights a reader can
check, with the voice of every part belonging to someone who was there.

**Who does it touch?** The performers first, and some of them will be
children. Then the people outside the screen: the playwrights and the estates
and companies that may still hold a claim (which is why the rights test in §3
runs before a script is offered), the Generic Radio Workshop volunteers whose
transcriptions we read but may not reuse yet (research 08 C8), and Apple and
Google, whose voice licenses decide what a stand-in may be (§5).

**What will people learn, and what will they stop learning?** They will read
a script closely enough to perform it, make choices about a character, learn
to time a line against someone else's, and listen to one another. The risk is
the one the owner named: if the device voice were good enough to keep, people
would stop performing. So it is never kept (§5), and a play cannot be
finished with one in it.

**The strongest case against it,** made for the people outside the screen: a
child's voice is personal information (16 CFR 312.2 names an audio file of a
child's voice), and a recording made at a kitchen table can travel. Phase 1
answers it by keeping every take on the device it was made on; the only way a
recording leaves is an export the person makes themselves (§6). The cost of
that answer is real, because a family on two phones cannot share a production
until phase 2.

### The four questions

1. **Does it deepen understanding?** Yes. The cast sheet shows the play's own
   structure (who speaks, how much, in which scenes), and recording a part
   means reading it line by line against the lines around it. The stage
   directions stay visible as directions, so the people casting a stage play
   decide for themselves how it should sound on radio (Decision 059).
2. **Does it invite participation?** It is nothing but participation. Every
   part is a person's choice, every take is theirs to keep or redo, and the
   relay makes each performer act opposite the people who went before.
3. **Does it support human agency?** Yes, and the design protects it in two
   places: the app never judges a performance (a line check offers "Keep it
   anyway?" and never rejects), and "hear it read" is an optional rehearsal
   aid, never a default, because the performer's own reading is the point.
4. **Clarity over cleverness?** One device, one script model, line-by-line
   recording with "wait for me" pacing, and a timeline that is plain data.
   The fancier options (a neural voice, live multi-device sessions, automatic
   mixing choices) are left out of phase 1 on purpose.


### The learning test, as built (2026-10-23, M7)

The four answers above were written before the code. Checked against what
shipped on iPhone, iPad, Mac, Android, and the web:

1. **Understanding**: holds. The cast sheet is the play's own parts, largest
   first, with directions and sound as parts of their own; since the parser fix
   (df0db3b) no title page or publisher's list becomes a part, and Hamlet opens
   on Barnardo's line.
2. **Participation**: holds. The relay (C7) and "a part nobody takes leaves the
   play unfinished" (C6) are tested on every platform (`Relay.isComplete`,
   its Android and web ports).
3. **Agency**: holds in what the app does not do: no line is judged or
   rejected, and "hear it read" is a button, never a default. **One defect,
   against rule 3 of §8, fixed 2026-10-23:** a take the bleed check flagged was
   kept with a warning and could still be chosen and mixed, so some of the
   device voice could reach a finished play. Now a flagged take stays on disk
   and keeps its warning, but its line counts as missing (`Production.usableTake`,
   `Relay.missingSpeech`, `Relay.needsRetake`, `Relay.isComplete`), the timeline
   and the mix renderer refuse it, and the performer re-takes with headphones,
   as §5 rule 2 says. Same rule on Apple (`apple/Core/Plays/Relay.swift`,
   `MixTimeline.swift`, `MixRenderer.swift`), Android (`plays/Relay.kt`,
   `MixTimeline.kt`), and the web (`js/plays-core.js`); tested by
   `FlaggedTakeTests`, `FlaggedTakeTest.kt`, and `js/plays.test.js`.
4. **Clarity**: holds. One device, plain line-by-line takes, a timeline that is
   data; no neural voice, no automatic mixing choices.

The owner's play is the remaining check (SCRATCHPAD item 11).
---

## §2. The flow

Every platform does the same seven things, in its own idiom.

1. **Pick a play.** There is no Plays section (Decision 068, owner
   2026-10-24: *"You should be able to re-record anything that has a
   script. You search for something that has a script, and you should be
   able to start a new ear drama ... the content type doesn't matter"*).
   A play is found where anything is found: in Browse (with "Has a
   script" as a filter), in Search, and as a pick on Surprise. Its own
   page offers **Start an ear drama**, which opens this flow; later any
   episode whose record carries a usable script shows the same action.
   *Replaced, 2026-11-24 (Decision 088)*: every script the app can show is
   offered for recording, and a person may bring one (§13); rights decide
   only publishing. (It read "Only scripts whose rights state is `castable`
   (§3) and whose parse is clean are offered.") Each shows its title, author, source, its number of
   parts, and its rights line with a link to the evidence. Nothing on it
   is written by a model. A play is marked only by facts from its record:
   its year when the record has one, its author (with their years), and its
   length ("12 parts · 840 lines"); never an age rating or any label we
   invent (owner 2026-10-23, Decision 067). "Start an ear drama" takes any
   script the bundle carries, a radio episode's as well as a stage play's. The productions a person has recorded in or
   joined are **Ear dramas** in Library.
   - *Replaced*: "The Plays tab lists only scripts whose rights state is
     `castable` ..."
2. **Read the cast sheet.** Parts are listed largest first, with line counts
   and the scenes each appears in, using the script's own names. A part can be
   taken by anyone in the room, one person may double several small parts (a
   radio tradition), and "Stage directions" and "Sound effects" are parts
   like any other, so a person can read the directions aloud or knock on the
   table for the door.
3. **Take a part.** The performer types a name (or not) and picks any open
   part, in any order (C7, owner 2026-10-23). The largest open part is
   suggested first (its "Take part" is the prominent one), never forced; one
   part records at a time on one device, because there is one microphone.
   **A first take needs no account** (Decision 079, owner 2026-11-15): a
   signed-out person records, and the takes stay on the device (§6). The
   account is asked for at the moment it is needed, in place of the act, with
   the reason and the platform's sign-in: Share ("Sharing needs an
   account."), Invite and Publish (behind Share), taking a part in someone
   else's production ("Taking a part needs an account.", Decision 072), and
   **a second production**: signed out, beginning a production (Record this,
   Try a line, the cast sheet) while another production on this device
   already holds a take shows "A second production needs an account." and
   sign-in instead of opening the studio. A production with no take does not
   count; it is reused or removed (rule 3a). Signed in, nothing is asked.
   (*Replaced*, owner 2026-10-23: "Recording needs an account, always ... at
   Start recording a signed-out person sees "Recording needs an account."".)
   Then the app checks the
   audio route and asks for headphones (§4.3), records five seconds of room
   tone with a visible countdown, and opens the script at their first scene.
3a. **A production with no take stays out of sight** (Decision 079, F10 of
   the 2026-11-15 review: "After Taps · 0 of 594 lines recorded" listed
   twice). Yours lists a production only once it holds a take; a shared one
   is listed whatever it holds. A local, unshared production with no take is
   deleted when the person leaves the studio without recording, and every
   time the store loads (which also clears those made before this rule), so
   an abandoned try never becomes a row. Try a line and Record this reuse it
   while it lasts. Deleting one removes its folder, as Delete production does.
4. **Record, in one of three modes** (owner ruling 4, 2026-10-29: *"One
   option should let you record and have the other parts play (either human
   voices or generated voices for parts that haven't been taken yet) and it
   should play right through with your opportunity to record your part as
   it shows up naturally within the Ear Drama script. Another option should
   allow you to record each line individually or re-record any lines again
   by tapping them and re-recording. Another option could be a "wait for
   tap" to advance through the script as you are describing."*). The
   engine is one session; the mode changes only what follows a take
   (`runPlan`, `discardRun`, `partHue`, and the session's `mode`,
   `runThrough`, `pause`, `keepRun`, `discardRun`, `playCue`,
   `playWithCue`, the same names on every platform; golden-tested on each).
   In every mode a cue line plays from a usable human take where one exists
   and from a live device voice where not (never stored, §5), the speaking
   character's name and line on screen, then the device listens and voice
   detection ends the take; every take is a new take, chosen at once.
   - **Step**: each cue waits for a tap. Record plays the line's cue and
     listens; the take's review offers Again, With cue (the take after its
     cue), and Keep, which moves to the next line, ready (it does not play
     its cue). Run-up (two lines before) and Hear it read stay.
   - **Run through**: from the line on screen, the play plays straight
     through from that line's cue to the part's last line: other parts in
     their human takes or the live device voice, unrecorded directions and
     sound skipped, and the microphone opens on each of the performer's
     lines as it comes. Pause (or Stop while the microphone is open) ends
     the run; a line being recorded is kept as far as it went. The run's
     takes are written as they land, so nothing is lost if the app closes;
     the review then plays each with its cue, records any Again, and offers
     Keep N takes or Discard the run, which deletes the run's takes and
     files and puts each line back on the take it had (the person's own
     act, §8 rule 5).
   - **Line by line**: every line of the part with its state; tapping any
     line opens it under its cue to record it or record it again, and the
     take leaves the line ready to record again.
   Where it happens: inside the reader, the modes as three ways the reader
   moves (§2.9, Decision 076 S3).
   The mode control is the platform's native segmented control, disabled
   while a cue plays, the microphone is open, or a run is on screen. The
   recorder opens in Run through the first time, then in the person's last
   mode, kept on that device and never synced (web `localStorage`, Apple
   `UserDefaults`, Android `SharedPreferences`; D3-fix2, 2026-10-30). While
   a Step or Line by line cue plays, the one round control reads Cancel (Space
   on a keyboard): the cue stops and nothing is recorded. While the
   microphone is open the line's box carries a live level meter, bars in the
   record color on the surface, newest at the right.
   - *Replaced*: "**Record line by line.** The previous line plays ... and
     mark the take they like."
5. **Pass the phone.** "Done with this part" returns to the cast sheet, which
   now shows that part as recorded. The next person takes another part and
   hears the first performer's takes where the device voice used to be.
6. **Listen through, any time** (C5 and C6, owner 2026-10-23). Anyone can
   hear the whole play from the top: parts with a human take play that take,
   and speaking lines without one are read live by the listening device's own
   voice (or an openly licensed voice generated on that device), each labeled
   "Device voice" with its speaker on screen, so a listener hears the play and
   can choose to add their voice. Unrecorded directions and sound are skipped.
   The plan is plain data (`listenPlan`): a take, or the words a device voice
   reads, never audio. Nothing of a live listen-through is stored, mixed,
   exported, or uploaded (§5). Once every speaking line is human, the
   listen-through plays the rendered mix instead, and hearing it to the end
   marks the play finished.
   - *Replaced*: "Pending owner, the apps take the conservative reading: no
     preview of a half-voiced play outside the recording flow ..."
7. **Keep it and export it.** Export is offered whenever every speaking line
   has a human take and no chosen take is flagged, at any time then, not only
   after a full listen (owner 2026-10-23). The device renders the mix if it is
   missing or stale. They can play it back on this device, send it by AirPlay
   or Cast to a television, or export the file through the share sheet. An
   export is the person's own act, not the app publishing.

### §2.7 Reading a script (Decision 076, phase S1; binding on every platform)

The owner, 2026-11-14: *"You should be able to read a script and turn pages and mark them
up and do all of the things that a good book/script reading experience should contain."*
Research: `docs/research/design/R2-script-reader-and-studio.md` §4.1. The verbs, the same
everywhere; each platform's design doc says the idiom (WEB-DESIGN §4.16, iOS-DESIGN §4.15,
macOS-DESIGN §4.7, ANDROID-DESIGN §4.17; tvOS-DESIGN §4.13 is a read-along panel only).

1. **A Read door on every castable play** (its page, Record's play tiles, Today's play), no
   account, no part, no microphone. One seam opens the reader: `open(scriptID, at: lineID?)`.
2. **Pages by default** (owner ruling, over the research's scroll): a slide, never a curl;
   two facing pages when the reading area is wide (860 pt or px on every platform; Apple and Android at regular
   or expanded width with the reader holding the whole width); turns by keys (arrows, Page
   Up/Down, Space; pedals send these), by a tap on the outer fifth of either side, and by a
   swipe. **Scroll** is a setting, remembered per device.
3. **The reading position is a line id**, saved per script per device with the part chosen,
   and kept through every re-layout (text size, spacing, rotation, window size): the reader
   turns to the page holding the line that was first on the page. Pages are never stored.
4. **Contents** by act and scene, from `sectionsOf` / `contentsOf` in each stack's plays
   core: a printed heading the parser set aside (the script's `sections`, contract §4.1) or
   a stage direction that is a heading (`sectionLevel`, golden cases in
   `catalog/tests/golden/script_sections.json`); an act heading repeating the act in hand is
   its scene. Each entry is the first line of its printed heading, never a name we write.
5. **Search in the script**: case, accents, curly quotes and line breaks folded; results as
   the speaker and the words around the match; a tap goes to the line.
6. **Text settings**: size (seven steps, 87.5% to 175% of the reading body, on top of the
   system's own text size), line spacing (Tight, Normal, Loose), layout (Pages, Scroll).
7. **"I'm playing ___"**: one speaking part (sound and directions are never offered).
   It highlights that part's lines in its hue, gives **Next line** (and the previous, by key),
   and **Hide my lines**: the part's spoken words drawn as bars in its hue, names and
   printed directions left showing, the text keeping its place; a tap peeks a line until
   the next turn or tap.
8. **Built for what comes next**: each line is addressable by its id, and each printed run
   knows its offset into the line's printed words (`lineText`), so a mark is
   (script, revision, line id, start, end) (S5, §2.10); `go(line)` and `follow(line)` are the
   read-along's seam; the studio (S3) docks inside the reader.
9. **Nothing is written by the app**: every word on the page is the script's; the reader
   adds no summary, no character notes, no suggestions.
10. **The Ear Drama page** (owner 2026-11-14: *"You definietly need to work on the formatting of
   plays. Probably need to figure out the best way to show plays from research and then figure
   out an innovative way to do it within our app."*; research and frames
   `docs/research/design/R2-play-typography.md`). Six type levels only. The set-up is computed
   once per line by each stack's `layoutOf` (web `ReaderCore.layoutOf`), golden-tested.
   - **Speaker over speech** on a narrow page: the name in L3 (body strong) in the part's hue,
     uppercase as printed, on its own line, never left at a page's foot. **In a gutter** when a
     page holds 30 em or more: right-aligned, 8.5 em, the words hanging beside it.
   - **Verse keeps its lines**: a speech is verse when every row after a printed break starts
     with a capital and its rows are not mostly 60 characters or longer; one row per printed
     line with a turnover indent, a printed indent kept; prose breaks reflow as spaces. Never
     one verse row alone at a page's foot or head. An opening drawn outside the reader (Today's
     Scene, a play's window) uses this detection (`verseRows`) and keeps the same lines.
   - **A direction inside a speech**: italic, muted, in upright parentheses the page adds (never
     in the text). A short italic piece between said words that run on in lowercase is the
     speaker's emphasis and is drawn as said.
   - **A stage direction**: an indented, quieter italic paragraph, its enclosing brackets not
     drawn; a part it names in capitals drawn in that part's hue, upright.
   - **The sound lane**: a sound piece, or an aside beginning "sound of", "noise of" or "music",
     is its own row inside the speech: a speaker glyph and the cue in L5 capitals on a quiet
     block; the words continue after it without repeating the name.
   - **A speech run into another** (a printed `\nNAME` then `. ` the parser missed) is drawn as
     the second speaker's speech, its printed name as the name, the label's period not drawn.
   - **"NAME (cont'd)"** heads a page that opens inside a speech (L5, the name in its hue).
   - **The front**: title (L1), authors, and **Parts** with every speaking part in its hue,
     largest first. **An act opens a page** (L1); a scene is L2.
   - **I'm playing**: my speeches tinted with a rule in my hue, never clipped; **the cue I come in
     on** (the last sentence of the speech before mine) underlined in my hue; Hide my lines bars
     only said words.
   - Every drawn run keeps its offset into `lineText`; a character not drawn is skipped, never
     rewritten, so marks (S5) and the read-along anchor as before.

### §2.8 Casting the device voices (Decision 076, phase S2; binding on every platform)

The owner, 2026-11-14: *"The virtual voices who play the different parts should also be
intuitive."* Research: `docs/research/design/R2-script-reader-and-studio.md` §4.4 and Q7,
Q8, Q12 (answered (a) each). Each platform's design doc says the idiom (WEB-DESIGN §4.10
"The cast sheet" and §4.16 item 13, iOS-DESIGN §4.12c, macOS-DESIGN §4.5c, ANDROID-DESIGN
§4.9b; tvOS reads the cast only, tvOS-DESIGN §4.13).

1. **The unit is an engine and a voice id.** A part's casting is
   `{ engine, voice, name, rate, pitch }`: `engine` is `system` (the platform's own
   synthesizer), `kokoro` (the downloaded Kokoro-82M voices, phase S6; rule 10) or `none`
   (Not read); `voice` is the engine's stable identifier (web `voiceURI`, Apple
   `AVSpeechSynthesisVoice.identifier`, Android `Voice.getName()`), **never a language**
   (an iOS 26 report says a voice requested by language ignores the person's Settings
   choice); `name` is the voice's own display name, kept so a vanished voice can be named;
   `rate` 0.5 to 2 and `pitch` 0.5 to 1.5 multiply the platform's normal.
2. **One cast, everywhere on the device.** The recorder's cues, Hear it read, Run-up, Run
   through, the listen-through and the reader's Hear the cast all read the same
   assignment through one seam (`VoiceCast` on every stack), so a part sounds the same
   wherever it plays. A production's cast is keyed by the production; the reader's,
   with no production, by the play; a new production starts from its play's cast when
   the person cast it in the reader. *Replaced*: each player assigning voices in the order
   parts first spoke in that session (R2 §8 item 1).
3. **Each device keeps its own cast** (Q8): never synced, never uploaded, never part of a
   shared production. A shared production starts from auto-cast on each device.
4. **Auto-cast** is every part's **Default** (Decision 086): worked out at each read over the
   device's voice defaults (rule 11), never written in as a choice, so a download or a
   reorder in Settings reaches every part nobody cast. *Replaced* 2026-11-22: "fills every
   part once, when the cast is first made on a device with at least one voice". Speaking
   parts in cast order (largest first) take **distinct** voices,
   the best voice first (the platform's quality tier, then the person's own language,
   then the system default, then the name), so the largest part gets the best voice;
   where the platform reports a voice's own gender (Apple `gender`; the web and Android
   report none), each next part takes the best remaining voice of the other reported
   gender. The device **never reads a character's name, a cast list's words, or the script**.
   *Replaced* 2026-11-26, the owner: *"While I'm not interested in making it so that only men
   can play men's parts and women can play women's, but I think for the play along, the voices
   that are chosen for a given role should match the gender of the character (i.e, higher voices
   for the female roles and lower voices for the male roles)."* (Q7 (a) said auto-cast never
   guesses a character's gender.) The catalog publishes, per role, the register of its stand-in
   voice, `high` or `low`, only where the play's own print settles it (catalog DECISIONS 049;
   contract §4.1), and a part with one takes the least-used voice of that register (a reported
   gender, else a measured register, rule 12), else a voice of neither pitched its way (up for
   high, down for low), else any voice pitched its way; when a register's voices are all used,
   one is used again at its next pitch. A part without one is cast as before. A person's own
   choice always wins; a register is never written into a cast and never shown: people read any
   part. When voices run out the list starts again at the next pitch (1.0, 0.86, 1.14, 0.93,
   1.07), so two parts on one voice can be told apart. "Recast all" returns every part to its
   Default. Golden-tested on every stack (`catalog/tests/golden/voice_register_cast.json`): the
   same voice list and registers give the same cast, and renaming every part changes nothing.
5. **Every choice is overridable**: a part's voice, speed and pitch, at any time, from the
   cast sheet (and the reader's Voices sheet), each change kept at once. The picker's first
   row is **Default** (naming the voice it reads now); choosing it drops the choice, and a
   chip on its Default says "Default".
6. **The picker previews the part's own first line** in the voice tapped (the play's own
   words, never a sample sentence), live, never stored (§5). Only local voices are listed
   (§5 rule 5), grouped by engine ("Downloaded", rule 10, then "On this device"), best
   first, each by the name the platform gives it (which carries its tier: "Ava (Premium)",
   "Samantha (Enhanced)"). A way to add voices is offered where the platform has one
   (Apple: Settings > Accessibility > Spoken Content > Voices; Android: the engine's
   installer; the web: a line saying the system's speech settings add voices).
7. **Stage directions and Sound effects are Not read by default** (Q12 (a)) and offer a
   voice like any part; when they have one, the listen-through and Hear the cast read
   their unrecorded lines. The recorder's cues never read them (a cue is the line before
   yours).
8. **A voice that vanishes falls back visibly.** When a cast voice is not on this device
   (another browser, a removed download), the part is read by its auto-cast voice and its
   chip says so with the warning glyph; the picker names the missing voice ("Ava is not
   on this device."). The person's choice is kept, and returns when the voice does.
9. **A voice never passes as a person.** The chip sits beside the dashed ring, every line a
   device voice reads is labeled "Device voice", and nothing of a device voice is stored
   (§5).
10. **Downloaded voices (Kokoro, Decision 078; S6d Android first, S6e Apple).** The picker's
   "Downloaded" group, under "On this device", holds one button until the model is here:
   **Download voices (… MB)** (the size is everything the platform fetches: on Android the
   on-demand engine module, 19 MB, and the q8 model, 107 MB, so 126 MB, R2-kokoro-feasibility
   S6a; Apple reads our own Core ML conversion, `kokoro-v4-apple-manifest.json`, 185 MB, its
   size in the iOS and macOS design docs; Apple writes it title case, "Download Voices (… MB)"),
   never started for the person, on any network. While it downloads: one progress bar over
   everything fetched, "34 MB of 126 MB" and Cancel (Play's own confirmation first when Play
   asks for one); a stopped download resumes
   where it stopped (HTTP Range), each file is checked against the manifest's SHA-256 and
   a mismatch is deleted ("The download failed." and Try again). Once here: the 28 voices,
   best grade first, each named "Heart (Kokoro)" so it is never mistaken for a system voice
   of the same name, each with the same preview of the part's own first line; then
   **Delete downloaded voices (107 MB)**; then the attribution the licenses ask for
   ("Kokoro-82M by hexgrad, Apache-2.0. Trained in part on Koniwa (CC BY 3.0) and SIWIS
   (CC BY 4.0)."). Since Decision 086 the download lives in Library > Voices (rule 11) and
   the picker lists the voices once here; the picker's download button is gone. Kokoro voices
   lead the Default pool where the platform's gate passes. *Replaced* 2026-11-22: "Auto-cast
   never casts a Kokoro voice (downloading recasts nothing); a Kokoro voice is a person's
   choice." A line is read by Kokoro only from the play's
   published phonemes (contract §4.1); a play with none (held for review) says "Not
   available for this play." in place of the voices, and a Kokoro part's line Kokoro
   cannot read (no phonemes, no model, a render with any non-finite sample or only
   silence) is read by the part's auto-cast system voice, never skipped and never
   phonemized on the device. After Delete a part cast to a Kokoro voice falls back
   visibly (rule 8) and its choice returns with the download. A Kokoro render is held in
   memory, played once, and refused by every writer (§5).
11. **The voice defaults live in Library, in a Voices section** (Decision 086, amended 2026-11-22; owner, 2026-11-22: "I thought we started allowing for multiple different voices to be downloaded/used with the recordings. It seems like everything is still using super robotic voices that no realistic person would want to use to listen to a play (or having other characters reading the lines as you record your own). Can we make it easier to use the high-fidelity voices and how to implement them as a default from the settings tab vs from the individual play that you are casting?").
   Amendment, owner 2026-11-22: *"I was talking about the fact that the "library" page shows the "settings" of the app, even without calling it a settings page. I don't think we need a settings page, but we should continue to iterate upon the library page to make it serve all of the given purposes we need."* No platform gets a Settings page or scene for this; Library is the settings home and Voices is a section of it (web: WEB-DESIGN §4.11a; the apps: `docs/research/design/VOICES-PORT-BRIEF.md`, whose Settings row and scene are superseded by a Voices section in Library, and whose "no Settings" rules in the iOS, macOS and Android design docs therefore stand). Each platform's Library has a **Voices** section: the Kokoro download
   (rule 10's words: size, progress, Cancel, Delete, attribution; where the platform cannot
   run them, one refusal), a default **Speed**, and the voices in the **Default order**:
   downloaded (Kokoro, best grade first) before the device's own (best quality first), each
   with a Use tick, Move up and Move down within its group, its quality, and Hear (a line of
   today's scene, live). Kokoro's grades under C- (D+ to F+) start unticked. The Default
   pool is that order less the unticked voices (never empty: all unticked means all).
   Auto-cast (rule 4) runs over it at the default speed. A Kokoro part's line Kokoro cannot
   read is read by the part's Default among the device's own voices. Kept on the device
   only, never synced. Where the voices are not downloaded but could be, the cast sheet and
   the reader's Voices carry one quiet **Better voices** that opens Library at Voices.
12. **A device voice the platform does not name is named from what it sounds like**
   (owner, 2026-11-23, on Android 1.0.161: *"I was talking about the android voices being
   named United States #1, United States #2. How does that help people to differentiate
   them? (Even if they sound different, there is no way to choose a voice based upon a
   numer instead of a name or description)."*). Where the platform gives a voice a name a
   person can choose by (Apple's "Samantha", a browser's "Google UK English Female"), that
   name stays. Where it gives only a code or a locale (Android's `en-us-x-sfg-local`, a
   browser voice named only "English (United States)"), the label is composed from facts,
   never invented: no persona, no first name, never a bare number.
   - **The facts are measured from the voice itself**: each voice reads one fixed
     sentence once into memory (never a file kept, never played aloud), and only four
     numbers are kept on the device: its median pitch (f0), its pitch range (the 90th over
     the 10th percentile), its tone (spectral centroid) and its pace (the sentence's
     length). A table of numbers measured once for an engine's known voices may stand in
     for the measurement; any voice outside it is measured on the device. The audio is
     dropped as soon as it is measured (§5).
   - **The label** is the register, then the trait that tells it from its neighbors, then
     the accent: "Low, warm · US", "High, lively · UK". Register by median pitch: Deep
     (under 115 Hz), Low (115 to 150), Middle (150 to 180), High (180 to 220), Very high
     (220 and up). Where two voices of one accent share a register, the trait whose
     measured values are furthest apart among them (tone, range or pace) names them in its
     order: tone warm, clear, bright; range even, varied, lively; pace unhurried, steady,
     quick (two voices take the ends; four or more split into thirds and the next trait
     splits again). The accent is the voice's region ("US", "UK", "Australia", "India").
     Only when every measure ties (one speaker under two names) does the engine's own code
     follow in parentheses.
   - **An alias is not a voice.** A voice the platform marks as standing for its locale's
     default (Android's `en-US-language`, feature `legacySetLanguageVoice`) is left out
     where a named voice of that locale is here: on the Pixel 8a it renders the same
     bytes as `en-us-x-iog-local`, so auto-cast gave two parts one speaker.
   - **Register stands in for gender in auto-cast** (rule 4) where the platform reports no
     gender: each next part takes the best remaining voice of the other register (lower
     under 165 Hz, higher above), so neighbors in the cast are told apart by ear. It is a
     fact about the voice, never a guess about a character.


13. **Better voices are offered once at first launch and once more at first use; the store
   download stays small** (Decision 090; owner, 2026-11-26: *"Can we also ensure that the app
   download remains small, but that we start working on a onboarding for the app that allows for
   people to download the better quality voices for their chosen device?"*).
   - **No voice model ships in a store download.** The model is fetched only by the person's tap
     with rule 10's machinery (size first, resume, SHA-256, Delete). `tools/test_no_model_in_bundle.py`
     fails when a model file (`.onnx`, `.mlmodelc`, `.mlpackage`, or a `.bin` over 5 MB) is in an
     app's sources, its resources, or Android's base module, and `tools/bundle_report.py` prints the
     AAB's size per module in the Play workflow's summary. (The App Store workflows are never edited,
     so the IPA's size is not printed in CI: App Store Connect shows it per build.)
   - **What is offered is what this device can run.** The step appears only where rule 10's download
     is offered now: the voices could run here, are not here, and are not downloading (the same
     predicate as Better voices, rule 11). Apple TV never shows it (no Kokoro, §6e); a browser
     without a WebGPU adapter, or whose self-test refused the voices, never shows it. Nothing to
     offer means no step and no "unavailable" screen.
   - **One step, skippable, never forced.** A platform sheet over the app (never a page, a flow, or
     slides) headed **Better voices**, one fact line, "Downloaded voices read the parts nobody has
     cast.", then the very control Library > Voices draws for the download (Download with its size;
     progress, "34 MB of 185 MB" and Cancel; "The download failed." and Try again), and **Not now**.
     A finished download turns Not now into **Done**. The sheet never starts a download for the
     person, never stops what is playing, and closing it any way (Not now, a swipe, Escape) is a skip;
     a download it started keeps going after it closes, shown in Library > Voices.
   - **Low storage is said.** When the device's free space is under the download's size plus 20%,
     Download is disabled and one warning reads "Not enough space: 310 MB free." (web: the storage
     estimate's quota less its usage).
   - **System voices, where the platform can open their settings.** On Android and macOS, when no
     enhanced system voice is installed (Android: no installed English voice of quality 400 or more;
     macOS: no `.enhanced` or `.premium` voice), one line "Better system voices are added in
     Settings." with **Open Settings** (Android's `com.android.settings.TTS_SETTINGS`; macOS's
     Accessibility pane, macOS-DESIGN §4.5c). iOS opens only the app's own settings page and the web
     none, so neither draws the line (Library > Voices keeps its footer with the path).
   - **When.** (a) At first launch, once, over the first screen once it is drawn. (b) If it was skipped,
     or the app could not offer it at launch, once more the first time the person opens a script to
     read, a cast, or the recorder. (c) Never after that, and never once a download has begun (from the
     step or from Library). The record is one number on the device, never synced: 0 never offered,
     1 offered at launch, 2 done (offered at first use, or a download begun).
   - **Doors.** `APP_SKIP_ONBOARD=1` (web `?onboard=0`) keeps the step away for UI tests and harness
     frames; `APP_VOICES_STEP=1` (web `?voices_step=1`; Android extra `appname_voices_step`), DEBUG
     only, shows it at launch without reading or writing the record, and never erases anything.

### §2.9 The studio inside the reader (Decision 076, phase S3; binding on every platform that records)

The owner, 2026-11-14: *"The recording experience should allow you to read the script as you
would any book or script while you record your lines. It should be easy to go back and forth
within the script and rerecord any line that you'd like to do another take with. ...
Additionally, on an iPhone Duo with the screen open, you should be able to see the script on one
side and the recording featueres on the other."* Research: `R2-script-reader-and-studio.md`
§4.3 and §4.5; Q9 and Q11 answered (a). Each platform's design doc says the idiom (WEB-DESIGN
§4.16 item 14, iOS-DESIGN §4.15 "The studio", macOS-DESIGN §4.7, ANDROID-DESIGN §4.17; tvOS
records nothing). Port spec: `docs/research/design/R2-studio-port-brief.md`. Step 4 of §2 (the
three modes) is unchanged in what the engine does; this section is where it happens.

1. **Recording happens in the script.** The studio is the reader (§2.7) with "I'm playing" set
   to the part and the studio attached; every page of the play stays readable, turnable and
   searchable while recording, and the page keeps the Ear Drama page (§2.7 rule 10) unchanged.
   It opens two ways: from the cast sheet (Take part, Record, Open part), at the part's first
   line with no take, else the line asked for; and from the reader itself, where a chosen part
   offers **Record**. The reader's Record continues this device's newest unshared production of
   the play in which that part is recording, else takes the part in the newest one where it is
   open and no other part records, else makes a new production and takes the part. One seam on
   every platform: `open(scriptID, at: lineID?, studio: (production, part)?)`.
2. **The current line.** One of my lines is current: outlined in ink on the page. A tap on any of
   my lines makes it current; Next and Previous (`J` / `K` on a keyboard) move to my next and
   previous line and turn the page to it. Other parts' lines are read as before (and their pages
   turn as before).
3. **Each of my lines shows its take state inline**, beside the speaker's name: an empty ring
   (no take), the ring filled in the part's hue with the number of takes (a chosen take; every
   line with takes has one), or the warning glyph (the chosen take was flagged by the bleed
   check). It is a button: it makes the line current and opens its **take list**.
   3a. **Every other part's line says who reads it** (2026-11-15, `R2-studio-review.md` F3; the
   owner: *"The virtual voices who play the different parts should also be intuitive (before
   humans re-record them)"*). Beside the speaker's name, where my lines show their take state, a
   line that a device voice will read carries the dashed ring in the part's hue (§2.8 rule 9; a
   waveform inside, never a face) and the voice's short name (its own name without the tier in
   brackets: "Ava", "Zoe"). A tap opens that part's voice picker (§2.8 rule 6), which previews the
   part's first line. A line with a usable human take shows nothing (the take reads it). Studio
   only: the reader alone stays bare.
4. **The take list** (one per line): every take, oldest first, numbered, with its length; the
   chosen one marked. Each row: play it, play it after its cue (With cue), choose it, and delete
   it. **Only an unchosen take can be deleted** (choose another first): the chosen take is the
   one the play uses, and in a shared production the one uploaded. **Record again** records the
   line again as a new take, chosen at once; every older take stays (§8 rule 5). **Delete unused
   takes** removes every unchosen take of the part, after one confirmation that says how many:
   the person's own act, never automatic.
5. **The three modes are three ways the reader moves** (owner ruling 4, Q11 (a)), the same
   native segmented control as §2.4, disabled while a cue plays, the microphone is open, or a
   run is on screen; the last mode is kept per device, as before.
   - **Run through**: Record (labeled "From here") plays the play from the current line's cue,
     other parts in their human takes or their cast voices (§2.8), the microphone opening on each
     of my lines as it comes and the line-end detector closing it; the reader follows the line
     being heard or recorded, turning its own pages. Pause ends the run; its review is §2.4's
     (each take with its cue, Again, Keep N takes, Discard the run). **Again** (2026-11-15, F1): with
     no run on and the current line holding a take, the status row offers Again, which records that
     line alone (as `R` does); while that single take's cue plays the round control reads Cancel, and
     while the microphone is open it reads Stop, so going back to retake one line never starts a run.
   - **Line by line**: Record plays the current line's cue and records it; after the take the
     line stays current, ready to record again. Next and Previous move by my lines.
   - **Step**: Record plays the cue and records; the take's review offers Again, With cue and
     Keep, and Keep makes my next line current and waits for a tap.
6. **The dock.** On a phone (and any compact width) the studio is a dock under the page: the
   mode control; one status line (the current line's place, "Line 3 of 44", and its takes; while
   the cue plays, the speaker and "Device voice" when a device voice reads it; while the
   microphone is open, "Recording 0:03" and the live level meter); and the transport (Previous,
   the one round record control, Next, then **Listen from here**), with the take list, the cast
   and the rest in a sheet. The record control is always on screen (Q9 (a)). Listen from here
   (2026-11-15, F2) is the panel's Listen through from here, one tap from the page on every width:
   a play icon that becomes Stop while it plays, disabled while a cue, the microphone or a run is
   on; any record press stops it first.
7. **Wide: the script on one side, the studio on the other.** When the reader has 860 pt (px,
   dp) or more, the studio's panel stands beside the script: the current line's take list, the
   cast with each part's voice (§2.8's chips and picker), or, for a part another member holds in a shared production, that person's chosen name in place of the chip, **Listen through from
   here**, Delete unused takes, Done with this part, and the keys. The script keeps the rest of
   the width (two facing pages when it still holds 860). On the open iPhone Duo this is the
   reader's wide layout, later an `ArrangementView` (S4); on a Mac the window's inspector; on an
   Android tablet or open foldable a supporting pane.
8. **Keys** wherever there is a keyboard: Space records, stops, or cancels the cue (in a run,
   starts or pauses); `J` / `K` my next and previous line; `R` records the current line again
   (Again in a review); Return keeps (Step's review, a run's review); the arrows and Page keys
   keep turning pages.
9. **Before the first take** (§2.3, Decision 079): headphones (§4.3), the microphone asked for at
   Start recording, five seconds of room tone, each shown in the dock. No account is asked here,
   signed in or out, online or off: the dock says one thing, and the record control and an account
   line never share a screen (F11). A refused microphone, a missing one and a take that did not
   save each say so in the dock. (*Replaced* 2026-11-15: "the account (signed out: "Recording needs
   an account." and sign-in, nothing else) ... being offline while signed out each say so".)
10. **Nothing new is stored.** Takes, the chosen map, room tone and the production record are
    §6's; device voices stay live and unstored (§5); take upload and publish rules are Decisions
    072 and 073's, unchanged. The reader's position and marks stay the reader's.
11. **A fold or a resize never stops a take** (Decision 080; owner 2026-11-16, Q4: *"Keep
    recording"*). Closing an iPhone Duo, folding an Android foldable, or resizing a window during a
    take changes the layout only: the take, a run and a cue go on, the compact dock (the script and
    the round record control) takes over from the panel, nothing is lost, and widening again shows
    the panel on the same line. The session and the microphone belong to the studio's model, never
    to a view, and a hardware reconfiguration under a take resumes into the same take.

### §2.10 Marks (Decision 076, phase S5; binding on every platform that reads)

The owner, 2026-11-14: *"You should be able to read a script and turn pages and mark them up
and do all of the things that a good book/script reading experience should contain."* The
rulings (Decision 076, the research's recommendations taken): typed marks everywhere plus Apple
Pencil ink on iPad; anchored to lines, never pages; on the device first, synced later; private.
Research: `docs/research/design/R2-script-reader-and-studio.md` §2.3 (what actors mark) and §4.2.
Each platform's design doc says the idiom (WEB-DESIGN §4.16 item 15, iOS-DESIGN §4.15 "Marks",
macOS-DESIGN §4.7, ANDROID-DESIGN §4.17; tvOS-DESIGN §4.13 has none). Port spec:
`docs/research/design/R2-marks-port-brief.md`.

The learning test (`learning-orientation-design`, R2 §3): marking a line is how an actor thinks
about it (where to breathe, what to stress, where the thought turns). The reader keeps that work
and shows it back; it never proposes a mark, a reading or a note.

1. **Six typed marks**, each the person's own:

   | Mark | What it means | Drawn as |
   |---|---|---|
   | **Highlight** | "this matters" | a tint behind the words in one of four hues, yellow (the first), green, blue, pink (`color.mark` in the design tokens: the text and the muted text hold 4.5:1 on each, light and dark) |
   | **Underline** | stress | a 2 px ink rule under the words (the cue I come in on keeps its own rule in my part's hue) |
   | **Breath** | breathe here | a `/` between two words, in ink, raised a little |
   | **Pause** | a longer pause | `//` between two words |
   | **Beat** | a turn in the thought | `//` and its label (one to three words, at most 24 characters) in caption capitals |
   | **Note** | the person's own words about the line | the words under a dotted ink rule, a note glyph after them; the note in a sheet |

   Plus **ink** on iPad with Apple Pencil (iOS-DESIGN §4.15): free strokes anchored to a line
   block, the same anchor rules. Every other platform shows that ink read-only where it can, and
   draws nothing where it cannot (never a wrong place).
   Every mark is drawn by the page, outside the script's words: no mark ever adds a character to
   the text, so offsets, search and the read-along never see one.
2. **Making a mark**: select words on the page, and a small **mark bar** offers the six:
   Highlight (in the last hue used), Underline, Breath, Pause, Beat, Note. A span mark
   (highlight, underline, note) covers the selection, grown to whole words; a point mark (breath,
   pause, beat) goes at the end of the selection, moved on to the end of its word and any
   punctuation after it, so "morning, / and" never splits a word. A selection that crosses lines
   makes one mark per line, the highlights or underlines of one selection kept as a group (a hue
   change or a delete applies to the group); a note on such a selection anchors to its first line.
   A speaker's name, a page's added parentheses and the "(cont'd)" head are not text: a selection
   that starts on one starts at the next word. Keys with a selection: `H` highlight, `U`
   underline, `/` breath, `P` pause, `B` beat, `N` note, `Esc` lets go.
3. **The anchor is a line, never a page** (Decision 076): `(scriptID, revision, lineID, start,
   end)`, offsets into the line's printed words (`lineText`, the same string search and the
   read-along use; every drawn run keeps its offset into it, §2.7 rule 10), plus the words
   themselves (`text`) and up to 32 characters either side (`prefix`, `suffix`), as the W3C Web
   Annotation model's TextPositionSelector and TextQuoteSelector pair them. A point mark has
   `start == end` and empty `text`. A mark survives reflow, text size, Pages or Scroll, rotation,
   another window size and a split line id (`L0009a`, contract §4.1) by construction.
4. **A new revision re-anchors by text** (one algorithm per stack, golden cases in
   `catalog/tests/golden/marks_anchor.json`):
   1. The same revision and the slice still reads `text`: placed as stored.
   2. Else, in the same line id: every place the line holds `text` (a point mark: every place its
      context meets), scored by how much of `prefix` and `suffix` still match around it; the best
      wins, ties to the nearest the old offset.
   3. Else, every other line, nearest first by script order (where the old id sorts: `L0009a`
      after `L0009`, before `L0010`): the best score wins, ties to the nearest line, and only
      with evidence: the matched words plus matched context come to 16 characters or more (or
      all there was).
   4. Else the mark is **not placed**: kept as it was, untouched, and listed in the notebook under
      "Not placed" with its words and its note, never dropped silently. It is tried again on the
      next revision. A placed mark that moved is saved with the new anchor and revision.
5. **Overlap**: highlights never stack. A highlight that overlaps or touches others in the same
   line merges with them into one highlight over all their words, in the new hue (the group goes
   with it). Underlines merge the same way. A highlight and an underline may share words. Notes
   never merge: each is its own. One point mark a place: a breath, pause or beat where another
   point mark stands replaces it.
6. **Changing a mark**: a tap or click on a mark opens the mark bar for it: a highlight's four hues
   and Delete; Delete alone for an underline, breath or pause; the label and Delete for a beat;
   the note and Delete for a note (the note and the label open in a sheet with the marked words
   above the field). A delete is immediate and undoable from the bar ("Undo") until the next
   mark or page turn: a mark is the person's work, never lost to a mistap.
7. **Show marks**: one switch (in the notebook) hides or shows every mark on the page, remembered
   per device. Hidden marks are kept, listed, and still made by the bar (shown again when made).
8. **The notebook** (Kindle's My Notebook; the reader's **Marks** button): every mark of the play
   in script order (line, then offset): the mark's glyph and hue, the speaker, the marked words
   (a point mark's words around it, the mark drawn between them), a beat's label, a note's text.
   A tap goes to the line, turning the page, and outlines it a moment. "Not placed" follows, for
   marks a revision lost. Empty: "Select words on the page to mark them." (how to mark is not
   on the page).
9. **In the studio** (§2.9): marks show on every line exactly as in the reader, so a person
   performs from a marked script. A tap on a mark opens the mark; a tap elsewhere on my line makes
   it current, as before. The studio's keys (Space, `J`, `K`, `R`, Return) keep their meaning; the
   mark keys act only on a selection.
10. **Hide my lines** hides a hidden line's marks with its words; a peek shows both.
11. **On the device, private** (Decision 076): each platform keeps a play's marks under its
    script id (web `localStorage` `ed.marks.<script id>`, Apple a file per script in Application
    Support, Android Room). Never uploaded, never in a shared production, never synced until a
    later phase rides the per-ecosystem sync (`per-ecosystem-sync-islands`), and never shown to
    another person. They travel only in the person's own data export (`marks[]`, docs/EXPORT.md).
12. **Four states.** Loading: none of its own (marks come with the script, from the device).
    Empty: the notebook's line (rule 8). Error: a mark that could not be saved says so in the
    mark bar and the notebook, with the warning glyph ("Marks are not being saved on this
    device."); the mark still shows until the reader closes. Offline: nothing to say; marks never
    touch the network.
13. **Accessibility**: each mark button is labeled with its key; a point mark is announced
    ("Breath", "Pause", "Beat: turn"); the notebook is the full, readable list of every mark, so a
    highlight the screen reader cannot see on the page is still there.
14. **Nothing written by the app**: no suggested mark, no generated note, no "AI coach" (§2.7
    rule 9). Every word in a mark is the person's or the script's.

### §2.11 Read along (Decision 076, "TVs get a read-along panel only"; rewritten 2026-11-23; binding on every platform that listens through)

The owner, 2026-11-23, after TestFlight 1.0.159: *"when you press the read along button, it should highlight
the words or underline them as they are read. It should also advance the pages as the read along happens.
Overall we need to update the read along interface. You should be able to control speed and it should be a
first-rate play reading experience."* Research: `docs/research/design/R3e-read-along.md` (Apple Books Media
Overlays, Kindle Immersion Reading, Speechify, Voice Dream, time-synced lyrics).

The script follows the voice. Two clocks, both measured: the **line** comes from the listen plan (`listenPlan`:
take or device voice, each entry names its line id), a finished drama's file playing (rule 11), or a rendered
mix's timeline (`ReaderCore.alongLineAt`); the **word** comes from the voice's own timing (rule 3). The same line
id feeds `follow(lineID)` on every platform. Nothing is guessed.

1. **The doors.** **Read along** on a production's page (and Made here), beside Listen through; **Read along**
   on a finished ear drama's page when its files map onto the script (rule 11); and the reader's **Hear the
   cast**, which is the same read-along over the play's own cast (§2.8 rule 2: every line in its part's voice,
   directions and sound only when given one). Read along opens the reader on the production's own copy of the
   script (or the library's, for a drama) **and starts reading at once** from the reader's place; Hear the cast
   starts on its press. One transport (rule 6), one follow, one word mark for all three.
2. **Two levels lit.** The line heard keeps the soft ink tint across the whole line, whoever speaks. Inside it
   the **word heard** is marked: a fill in the speaker's part hue at about a quarter strength with a 2 pt rule
   under the word in the full hue (ink for a direction or a cue). The mark sits on the printed run through the
   line's `lineText` offsets (§2.7 rules 8 and 10), so a speaker's name, a parenthesis the page adds, a
   "(cont'd)" head or a hidden line is never marked. It moves without animation (a state, not a transition).
   Pages and Scroll draw the same mark.
3. **Word timing is measured, never estimated.** A device voice gives its own word callbacks: Apple
   `speechSynthesizer(_:willSpeakRangeOfSpeechString:utterance:)`, Android `UtteranceProgressListener.onRangeStart`,
   the web `SpeechSynthesisUtterance` `boundary` event. The range is in the exact string the voice was given
   (`said`: the line's said words, italic marks dropped, the ends trimmed) and maps back to `lineText` with
   `spoken(line)` / `word(spoken, location, length)`. A **Kokoro** line's words come from the duration model's
   frames per token, which the render already computes: each phoneme word starts at the frames of every token
   before its first sounding symbol (600 samples a frame at 24 kHz, played at the pitch's rate), and the
   phoneme words pair with the printed words (`textWords`: runs split at white space and dashes, trimmed to
   letters and digits) **only when the whole line's counts agree** (`kokoroWords`, `phonemeWordStarts`,
   `phonemeWordCount`); the playback clock is the audio node's own sample time. Golden cases every stack runs:
   `catalog/tests/golden/read_along_words.json`. **Human takes and finished dramas have no word timing**, and
   neither does a line whose counts disagree or a voice that sends no boundaries: the line stays lit and no
   word is marked. A word is never placed by character counts, durations or an aligner's guess.
4. **Pages turn themselves.** When the line heard, or within a long speech the word heard, reaches a page not
   in view (either page of a two-page spread counts as in view), the reader turns to it with the same slide a
   person's turn makes; Reduce Motion cuts instead. Scroll brings the line heard to the top. A turn the reader
   makes never counts as a touch.
5. **Turning away.** A swipe, tap, key or scroll on the text stops the turning (the voice goes on) and shows
   **Back to the line**, which returns to the line now heard and follows again. Nothing is offered while
   nothing plays. VoiceOver: the marks never take focus or announce words (the voice is already speaking);
   the line heard is the element VoiceOver lands on when the person moves into the page.
6. **The transport** takes the bottom bar while reading along: the **speaker** (the line's printed name in its
   part's hue), **Previous line**, **Play / Pause**, **Next line**, **Speed** (rule 7), **Stop**, and the page
   count where the bar has room (regular width, the Mac, the web from 860 px). Icons on a phone, each labeled
   for accessibility; Play / Pause carries its word from regular width. **Pause holds the line** (still lit);
   **Play starts that line again from its beginning** (no device voice resumes mid-word on every platform).
   Previous and Next go to the nearest line the read-along reads (a speech, or a part with a voice) and play
   from there; paused, they move the held line. Stop ends the reading and the light; Hear the cast's Stop gives
   the bar back to the reader's own controls. A line a device voice reads keeps the "Device voice · PART" strip
   above the transport (§5). Keys: Space plays and pauses where the reader holds the keyboard (Mac, web, iPad
   with a keyboard), Option-Left and Option-Right step a line on the Mac. No other words on screen.
7. **Speed**: one control, **0.5×, 0.75×, 1×, 1.25×, 1.5×, 1.75×, 2×**, shown as "1.25×". It multiplies each
   part's own speed, so 1× is the cast as set and a Default part starts from the Library's default Speed
   (Decision 086). Device voices and Kokoro take a change from their next line; takes and finished dramas take
   it at once, the pitch kept (Apple AVAudioPlayer `rate` and AVPlayer `defaultRate` with the time-domain pitch
   algorithm, Android `PlaybackParameters`, the web `playbackRate` with `preservesPitch`). Remembered per
   device (`ed.along.speed`), never synced; every read-along door and the TV panel's listen use it.
8. **Not on the lock screen.** The read-along is reading on a screen: closing the reader stops it, and it
   writes no Now Playing entry (the app's player owns Now Playing).
9. **Nothing is written**: no marks are made by the follow, no take, no position other than the reader's usual
   place, and no synthetic sound is kept (§5). Recording stays out (§2.9): Read along is listening.
10. **On a TV** (tvOS, Android TV, Fire TV; no reader): a **read-along panel** under the transport while a
   production's listen-through or a finished drama plays: the line heard with one before and one after
   (`ReaderCore.alongPanel`), the body at 29 pt or larger (the tvOS floor; Android TV `bodyLarge` at 28 sp is
   the same size), the speaker's name in the part's hue, "Device voice" beside a line the device reads, inside
   the title-safe area (5%). No word mark (ten feet away the line is the unit), no marks, no recording, no Read
   door, no pages, no speed control; it plays at the device's remembered speed (rule 7). The panel never takes
   focus; focus stays on the transport.
11. **A finished ear drama** (Decision 073: one archive.org item per production, one file per line, named so a
   retry can only overwrite): the file's name is `NNNN-PART.ext` and `NNNN` is the line's **1-based place in
   the script** (`fileName` in `worker/src/plays-archive.js`). The clients play the item's line files in order,
   and the file playing is the line heard, so the timing is exact at file boundaries and needs no durations or
   guess: web `ReaderCore.dramaPlan` / `dramaListen`, Apple `FinishedDramas.linePlan` + `ReadAlong.line(files:)`,
   Android `ReadAlong.dramaPlan` (`ArchivePick.lines`). A silent or removed line has no file, so the highlight
   skips it, never shifts. The numbering holds only for the script revision the lines were recorded against, so
   the Worker's finished record carries `script_revision` and a client offers Read along only when its own copy
   of the script has that revision; a Worker that sends none, another revision, a number past the script, one
   whole recording, or lines still waiting for their MP3 offers no Read along. The door is **Read along** beside
   Listen on the finished drama's page (web `?read={script id}&finished={production id}&along=1`; iOS, iPadOS
   and Mac as a reader over the library's script with the item's files as the transport; Android
   `Route.Reader(along, drama)`). On a TV the drama page's Listen shows the rule 10 panel under it.

The follow logic is tested on each platform against the same cases: the plan's line by index, a mix's line by
time, turning while following, holding still after a turn-away, and returning (`js/reader.test.js`,
`ReadAlongTests`, `ReadAlongTest`); the word heard against `catalog/tests/golden/read_along_words.json` (a voice
range onto the printed word, the printed words, Kokoro's word starts and the refusal when counts disagree) and the
speed steps; a finished drama's file-to-line mapping against the same fixtures (`reader.test.js`,
`FinishedDramasTests`, `OpenPlaysViewTest`) and the Worker's file-number contract (`worker/test/archive.test.js`).

### §2.12 Recording one scene (B31 §3.4, 2026-11-26; binding on every platform that records)

The owner, 2026-11-26: *"I'd love to see themes and collections for plays and different ways of finding plays to read
or record."* A scene for two voices is the newcomer's invitation, so a scene card leads to recording that scene, never
the whole play. A production may carry **`range: {from, to}`**, two line ids of its script: `from` is the scene's
first line (the catalog's `scenes[].line`), `to` the last line before the next section (`scenes[].to`, CATALOG-CONTRACT
§4.1). The production records, listens to and exports those lines and the ones between, and nothing else.

1. **The cast sheet is the range's.** A range production lists only the parts with a line inside the range (Sound
   when a cue row is there, Stage directions when a direction is); its voice count and minutes are the range's.
2. **Done is the range's.** A part is done when each of its lines in the range has a chosen take, and the play is
   complete when every speaking line in the range has one: never the whole play.
3. **Listen Through, the mix and export hold only the range**, and so do Read together and Share (the Worker keeps
   the range and the range's cast sheet, docs/WORKER.md). A sound cue placed on a line outside the range is out of
   the mix, never missing (Decision 091). A range production's title is the play's with the scene's heading as
   printed: **"Adelphi, Scene II"**.
4. **A revision that moves either bound drops the range and says so**: "The scene's lines changed. This production
   is the whole play now." Its takes stay; it is listened through again.

- **The door.** A scene card (B31 §3.4) opens this scene's production, making it on the first tap: the newest of
  this device's productions of the play with the same range and not shared, else a new one (a signed-out person's
  second production asks for an account, §2.3). A scene with no `to` (a library built before it) opens the reader at
  its line, as before. Read (the book icon on the card's corner) opens the reader at the scene's first line. Not on a
  TV.
- **The record.** `format: 2` on every production written from now on; a record with no `format` is format 1 and is
  read as it is (migrating adds `format` and nothing else, so no fingerprint moves); a record with a higher
  `format` is a newer app's: kept, never listed or rewritten. `range` is absent on a whole-play production, and an old
  production is unchanged. `fingerprint` never includes the range.
- **One seam.** `scoped(p, script)` is the script cut to the range (its lines, its sections there, and each role
  speaking there with its lines and words there); `castParts(script, range)`, `missingLines`, Done, Listen Through,
  the run plan and the timeline read it, and `rangeDrifted` / `dropRange` are rule 4. JS `PlaysCore`, Swift
  `PlayScript.scoped(to:)` and `Production.range`, Kotlin `PlayScript.scoped` and `Production.range`.
- **Shared proof**: `catalog/tests/golden/production_range.json` (a ten-line script, range L0003..L0006: the cast,
  Done before and after the last take, the Listen Through and export line ids, a cue outside the range, the drift
  cases, an old record and a newer one), run by `js/plays.test.js`, `apple/Tests/ProductionRangeTests.swift` and
  `android` `ProductionRangeTest`, each with mutants that must fail it.
- **Export my data** carries `range` on a production's row (docs/EXPORT.md).

### The platform idioms

Same verbs, native idioms (`cross-platform-parity-discipline`).

| Platform | Records? | The idiom |
|---|---|---|
| iPhone | Yes | The reader with the studio's dock under the page (§2.9 rule 6); the take list, cast and the rest in a sheet; the cast sheet is a list and the relay is a push |
| iPad, open iPhone Duo | Yes | The script and the studio side by side once the reader holds 860 pt (§2.9 rule 7), so the person waiting their turn can follow along on the same screen |
| Mac | Yes | A production is a window: the reader with the studio as the window's inspector, and the keyboard drives it (Space to record or stop, Return to keep a take, J and K to move by my lines); the best seat for listening through and fixing timing |
| Android phone, tablet, foldable | Yes | Material 3: the reader with a bottom dock on a phone, a supporting pane when expanded; recording quality varies by device (§4.2) |
| Web | Yes, with headphones only | The reader with a dock under the page, a studio column from 860 px; "wait for me" pacing only, no sample-accurate cues, and no bleed check beyond level, because a browser cannot capture synthesized speech (08a §3) |
| Apple TV, Google TV, Fire TV, Roku | No | Play back only (research 08 §5). In phase 1 a finished play reaches a TV by AirPlay or Cast from the device that made it |

---

## §3. Which plays can be cast today

### The rights test

`catalog/tools/script_rights.py` is the test, written like the audio audit:
ordered buckets, every hide before every rescue, the first match wins, and
evidence a reader can open on every row. The hides are a take-down, the text
source's own terms (the Generic Radio Workshop says "TLDR: Assume
Copyright"), a non-commercial license, and a live renewal of this script by
its registration number or by its title, author, and year. A renewal of new
material on an old play (an adaptation, a translation, an acting version) is
not a claim on the play. Then come three "not enough evidence" states: an
adaptation whose source is unchecked, a translation without its own evidence,
and a foreign play published after the line that the URAA may have restored.

The rescues are publication in 1930 or earlier (the line is computed from the
calendar and moves every 1 January), registration in 1930 or earlier, a
clearance by Project Gutenberg or Standard Ebooks, registration in 1931-1963
with a recorded renewal search, and government work when this script's own
author and employer are on record. A missing renewal row alone never opens a
script, because the printed renewal file loses a quarter to a third of its
entries to OCR (08b §1.3).

"Individual author died by 1955" (research 08 C9) is accepted (owner
2026-10-23, Decision 067): `script_author_died`, castable, when every author
is a named individual whose death year is on record at or before the line
(today's year less 71, so 1955 in 2026), the work is not for hire, and no
publication is on record (a published work's term runs from publication).
Everything else is `script_no_evidence`, which is not castable.
The tests are `catalog/tests/test_script_rights.py`: 22 cases, each with a
control, and eleven broken controls recorded in its docstring.

### What is castable, measured

| Source | Records | Castable | Why |
|---|---|---|---|
| Project Gutenberg, English drama shelf or Drama subject | 1,740 (of 3,033 in all languages; 78,383 texts in the catalog) | **1,722** (1,718 stage, 4 radio) | 1,716 on Gutenberg's own "Public domain in the USA." and 6 more on a copyright line of 1930 or earlier in the text; 15 are Gutenberg's "Copyrighted" translations (Frank J. Morlock's, mostly), 2 carry a live renewal (*Night Must Fall*, 1935, renewed 1962; *The Terrible Meek*), and 1 is not a play and carries no evidence |
| Generic Radio Workshop | 1,371 | **0** | GRW's terms hide all of them until we ask GRW (C8). With permission, 10 are *Uncle Sam's Forest Rangers* scripts that still need their own author and employer on record, 1 (*Fibber McGee*, "Good Grammar", D unp. 10032) still needs its renewal search, and 1,360 carry no evidence at all |

The four castable radio plays are Henry Fisk Carlton's NBC *Great Moments in
History* plays (*The Landing of the Pilgrims*, *Caesar Rodney's Ride*, *The
Tree That Saved Connecticut*, and *The Story of Nathan Hale*), published in a
book and cleared by Gutenberg, two of which GRW also lists. So the castable radio library today is four plays, and the
stage library is large. Research 08b's other free radio class, the USDA
typescripts on archive.org, waits on OCR repair and per-script authorship
(08b §2.3), and it is the next radio harvest to build.

### The file the apps read

Phase 1 bundles the castable scripts in the apps rather than publishing them
beside the catalog: casting then needs no network and no fetch, and the file
is small. `catalog/tools/build_castable_scripts.py` writes
`catalog/plays/castable-scripts.json` from the cached texts, keeping a script
only when `script_rights.judge` says `castable` and `script_parse` says clean
(§8 rule 1), with each line as the parser's exact slices, the rights evidence,
and a revision hash. Both the Apple and the Android apps bundle that one file.
Measured on 2026-10-23: 24 cached texts read, **11 plays written, all stage
plays**, 1,645,122 bytes (477,111 gzipped). The stage parser first finds where
the play begins and ends, so title pages, publishers' catalogs, prefaces, and
transcriber notes are set aside with their words and never become a part. A
text is refused, never split, when it holds several plays (cast lists or first
acts counted over the whole text) or sets aside over 40% of its words (the
plays measured set aside at most 28%).
The four Carlton radio plays ship
since 2026-10-23 (cast lists, labels with directions, multi-paragraph
speeches, and spoken italics read on the radio path; 0% unclassified each),
so the file holds 15 scripts; no Generic Radio Workshop text ships (C8). The file moves beside the catalog once the library outgrows a
bundle.

Rights is not the only gate. A rights-castable text also has to parse into
parts a person can perform, and some of Gutenberg's drama shelf is not a play
at all: the random sample below drew a playwriting manual, an issue of *The
Strand Magazine*, and a verse narrative.

### The harvest

`catalog/tools/harvest_gutenberg_plays.py` reads Gutenberg the way its robot
policy asks: "The Project Gutenberg website is intended for human users only,"
and its catalog data "are granted to the public domain." So the harvester
reads the weekly CSV and the daily RDF file from `/cache/epub/feeds/`, once
each, and plain texts from the aleph.pglaf.org mirror, one at a time with a
three-second pause, as "EarDrama/0.1 (+https://eardrama.org)". It records the
title, the authors and translators with their dates, Gutenberg's rights
statement and its link, the source URL, and the LibriVox cast size where a
LibriVox project read the same text. It keeps no summary.

Gutenberg's metadata "does not include the original print source publication
date(s)," so a year is recorded only from evidence a reader can open: a
copyright line in the text itself or the source year LibriVox recorded. That
gave a year for 145 of 1,740 records, measured. Of the authors whose death
year Gutenberg records (1,420 records), 250 died in 1950 or later, and 241
English records name a translator, which is why the translation rule exists.
LibriVox read 146 of these exact texts; where its description prints a cast
list (66), the median cast is 16 parts (quartiles 11 and 20, the largest 62).

### Parsing into parts and lines

`catalog/tools/script_parse.py` turns a radio script or a play into roles and
lines. Every line keeps the block exactly as printed beside its parts
(speech, direction, mic position, sound), and a part is a slice of that block,
so no word is rewritten (08b §4). Directions are kept apart from speech so the
people casting decide how to read them. A commercial is its own part (C10): from
a printed commercial marker ("COMMERCIAL", "MIDDLE COMMERCIAL") to an "END
COMMERCIAL" marker, the next commercial, or the first music cue after its first
speech, each speech's part is its printed role with "(COMMERCIAL n)" after it,
so the announcer of the play and the reader of each commercial can be different
people. Its tests, with four broken controls,
are `catalog/tests/test_script_parse.py`.

A **stub** is not a script: under 500 words, or a page of links with no
dialogue. Measured over all 1,028 cached GRW texts, 39 are too short ("Information
Coming Soon...") and 25 are link pages ("PDF files on Old Time Radio Researchers
Group website"). A long text with no dialogue found is a parse **failure**,
not a stub (7 of them, such as a Campbell Playhouse *Rebecca* whose line
breaks were lost). Of the 957 that parse, 827 parse clean.

Measured on seeded samples (`python3 tools/script_parse.py measure`):

| | GRW, 50 scripts | Gutenberg, 20 texts |
|---|---|---|
| Stubs or failures | 2 stubs (too short) | 1 failure (a verse narrative) |
| Parsed clean | **42 of 50** | **9 of 20** |
| Parts per script, median | 11 (8 with five lines or more; 2-13) | 23 (11 with five lines or more) |
| Speeches, median | 272 | 488 |
| Unclassified blocks, median | 1.4% | 4.6% |
| Failure kinds | more than 5% unclassified (6): cast lists in prose, commercials, untagged cues | more than 5% unclassified (8), several plays in one volume (3), not a play (3), Folio texts with rare abbreviated speakers and textual notes (2), a long prose introduction or verse preface (2) |
| Possible aliases flagged | 12 (FIB and FIBBER, DOC and DOCTOR) | 6 |

"Clean" means 5% or less unclassified, at least two parts with five lines or
more, and one play in the text. A hand check of 25 random speeches from the
clean GRW scripts found all 25 attributed to the right speaker. The same check
on the clean plays found 24 of 25 right, the Folio *Hamlet*'s abbreviated
speakers (HAM, OPHE, GUILD) among them, stored as printed for an alias table
to expand later; the miss was a song heading read as a speaker ("SHAMROCK AND
ROSE"), and one direction ("Going towards the door") was typed as a sound. A script that parses clean opens for casting; one that does not
waits for a person to fix its parts, which is editing, not a rights review.

---

## §4. Recording and mixing on each platform

The APIs are the ones research 08a read in Apple's, Google's, and the W3C's
documentation. The deployment floors are iOS 18, macOS 26, and Android 10
(`minSdk = 29`); an API newer than the floor is adopted behind a runtime and a
compile-time gate (Decision 048).

### §4.1 The pipeline

| Step | iPhone, iPad, Mac | Android | Web |
|---|---|---|---|
| Stand-in voice | `AVSpeechSynthesizer.write(_:toBufferCallback:)` into `AVAudioPCMBuffer`s one to three lines ahead, released after playing; `usesApplicationAudioSession = true` on iOS | `TextToSpeech.synthesizeToFile` to a pipe (`ParcelFileDescriptor`, API 30) collecting `onAudioAvailable` chunks; on API 29 a cache file deleted the moment it is read | `speechSynthesis.speak`, whose audio the page cannot see |
| One clock | One `AVAudioEngine`: a player node for human takes, one for stand-in buffers, an input tap for the microphone, every event stamped in sample time | `AudioTrack` and `AudioRecord` (or Oboe/AAudio) with `getTimestamp()` on both | One `AudioContext`; stand-in timing from `speechSynthesis` events, which is coarse |
| Capture | `.playAndRecord` with `.allowBluetoothA2DP`, never `.allowBluetoothHFP`; 5-10 ms I/O buffer | `VOICE_PERFORMANCE` (API 29), `UNPROCESSED` where offered | `getUserMedia` into an `AudioWorklet` writing PCM |
| Route check | `currentRoute.outputs` includes `.headphones`, `.bluetoothA2DP`, or `.usbAudio`; AirPlay is refused for recording | `AudioManager.getDevices(GET_DEVICES_OUTPUTS)` for a wired, A2DP, or USB headset | Asks for headphones and cannot verify |
| Without headphones | Voice processing (`setVoiceProcessingEnabled`), or `setPrefersEchoCancelledInput` on 2024 and later iPhones (iOS 18.2); the take is marked `capture: "aec"` | `VOICE_COMMUNICATION` with `AcousticEchoCanceler`, device by device | Refused |
| End of a line | `SpeechDetector` (26, gated); an energy and zero-crossing detector on iOS 18-25 | An energy detector, or WebRTC's (BSD) | The same detector in the worklet |
| "Did they say the line?" (optional, never a rejection) | `SpeechTranscriber` (26, gated), `SFSpeechRecognizer` with `requiresOnDeviceRecognition` below it | `SpeechRecognizer` on device where offered (UNVERIFIED by API level) | `SpeechRecognition` where `available()` says so |
| Bleed check before a take is kept | Correlate the microphone against the exact stand-in buffer played, delayed by the route latency | The same, against the `onAudioAvailable` PCM | Level only, in the stand-in windows |
| Mix a finished play | `AVAudioEngine` manual rendering (`enableManualRenderingMode`) | Media3 Transformer `Composition` (`@UnstableApi`) | `OfflineAudioContext.startRendering()` |

### §4.2 The takes and the timeline

A take is the performer's line only: from voice onset less 250 ms to its end
plus 250 ms, mono, 48 kHz, 24-bit, so the stand-in windows are never kept.
Each take records what its performer heard (the take id for each other part,
or `standin`), which is how the credits can say who played opposite whom.

The mix is a timeline that is plain data: lines in script order, each pointing
to a take with its in and out points, a gap before it (0.35-0.5 s by default),
an overlap where someone interrupts, and a gain measured by ITU-R BS.1770 and
stored, never written into the take. Because placement is relative, a re-take
that runs half a second longer ripples correctly. The renderer is a pure
function of the timeline, written once per language and proven by one golden
timeline on every platform (`cross-platform-determinism`), and the finished
mix is normalized to -16 LUFS integrated and -1 dBTP. Sound and music cues
show as text and are silent until someone records them or picks a sound with
evidence (08a §8); phase 1 ships no effects library.

**Sound lanes and the duck (B32 K2, Decision 091; binding on every stack).** A production's optional `sound` block places
cues on lines (`docs/research/design/B32-sound-board.md` §3.3, §5.1). Before and After cues sit in the gap and move later
lines; Under and Bed cues move nothing. Each sound's gain is its level (effects to −19 LUFS, music and beds to −20 LUFS)
times a duck computed from the voice takes' places (merged across gaps under 1 s; attack 120 ms before, release 600 ms
after; −6 dB effects, −12 dB music, a cue's own value or Off) times its fades; a mix with sound is scaled once so its
peak sits at −1 dBFS. A play with no sound keeps its timeline byte for byte. One function per language, golden
`catalog/tests/golden/mix_sound.json`.

### §4.4 As built on Apple (2026-10-22)

- One `AVAudioEngine` per recording session (`Core/Plays/LiveAudio.swift`): one
  player node for takes and stand-in buffers, a tap on the input converted to
  mono 48 kHz in memory. The microphone permission is asked when the performer
  presses Start Recording, never at launch.
- Takes are FLAC from a 24-bit source, which writes on macOS 27 (measured); the
  iOS 18 floor is still to measure on a device.
- The end of a line is an energy detector on 20 ms frames with its floor from
  the session's room tone, ending after one second of silence; the one record
  control also stops it. `SpeechDetector` and the line check are not built yet.
- The bleed check correlates each kept take against the stand-ins that cued it
  and flags a match (`BleedCheck.threshold` is 0.5, to measure on devices).
- The finished mix is rendered offline by `Core/Plays/MixRenderer.swift` into
  `mix.m4a` (AAC, 96 kbps mono). Each take's gain targets -16 LUFS and is held
  so its sample peak stays at or below -1 dBFS; sample peak stands in for true
  peak until a true-peak meter is written. The listen-through plays that
  rendered mix, which holds only human takes, and reaching its end without
  skipping ahead finishes the play.
- Gaps are 0.4 s; overlaps, room-tone fill, and per-role pan are not built.

### §4.5 As built on Android (2026-10-23)

- `AudioRecord` at 48 kHz mono float from `VOICE_PERFORMANCE` with
  headphones; without them `VOICE_COMMUNICATION` with
  `AcousticEchoCanceler`, the cue played as voice-call audio, and the takes
  marked `capture: "aec"`. The built-in or wired microphone is preferred
  over a Bluetooth one. The cue plays through an `AudioTrack`.
- The stand-in is collected from `onAudioAvailable` into memory. On API 30
  and later `synthesizeToFile` writes to a pipe, which is drained and
  dropped; on API 29, which has no pipe overload, the engine speaks at zero
  volume while the same callback hands over the samples (UNVERIFIED on a
  device). No cache file is ever made, stricter than §5 rule 1 allows.
- Takes are 24-bit PCM WAV, not FLAC: MediaMuxer has no FLAC container, so
  FLAC would mean hand-writing the stream around MediaCodec's frames on a
  path no JVM test can read back. The file names and `production.json`
  keys are Apple's.
- The timeline, gain, detector, and bleed check are Apple's, line for line
  (`plays/`). The mix is rendered a chunk at a time and encoded by
  `MediaCodec` (AAC-LC, 96 kbps mono) into `MediaMuxer` as `mix.m4a`, not
  Media3 Transformer. The listen-through plays it with `MediaPlayer`.
- Export is the share sheet through a `FileProvider` scoped to `Plays/`.

### §4.6 As built on the web (2026-10-23)

- `js/plays-*.js` (WEB-DESIGN §4.10). The microphone is asked for when the
  performer presses Start recording (`getUserMedia`, `echoCancellation: true`,
  `autoGainControl` and `noiseSuppression` off); a take records `capture: "aec"`
  when the browser reports its echo canceller on.
- Headphones: the page cannot see the output route (Safari enumerates no
  outputs; Chrome's device labels do not say which route is in use), so it
  states the refusal and Start recording stays disabled until the person
  checks "My headphones are on", every session.
- Capture is an `AudioWorklet` tap posting PCM to the page, so the same
  line-end detector as Apple's reads 20 ms frames live; takes are resampled
  to 48 kHz in an `OfflineAudioContext` and stored as 24-bit WAV.
- The device voice is `speechSynthesis` with local English voices only; its
  sound never reaches the page. The bleed check is level only: the share of
  20 ms microphone frames above the room's floor while the device voice reads
  (0.3 flags the take; UNVERIFIED, to measure on devices).
- The mix is rendered in 30 s `OfflineAudioContext` chunks into a 16-bit WAV at
  48 kHz (no AAC or Opus file encoder short of real-time MediaRecorder),
  played in its own `<audio controls>`, and exported as a download. Gains
  follow §4.4.
- Measured in headless Chrome on 2026-10-23 with a fake microphone: room tone
  and a take written to IndexedDB, a second `add()` of a take path refused
  (`ConstraintError`), a three-take timeline rendered in 0.5 s chunks to its
  exact length with each take where placed and silent gaps, and a finished
  fixture play heard to the end and offered for export. Not yet run with a
  real microphone, real headphones, or on iOS Safari.

Recording quality varies on Android by manufacturer (echo cancellation,
`UNPROCESSED` support, and engine voices all differ), so the bench needs the
Pixel 8a and one Samsung before Android is called done.

### §4.3 Headphones

Headphones are asked for before every recording session, and the request is a
refusal with its reason, which the essential-words rule allows. They do two
jobs: they keep the stand-in out of the microphone, and they let the
performer hear the scene without the room hearing it. Bluetooth microphones
are refused for takes (HFP is narrowband), so the route is headphone output
with the built-in or a wired microphone.

---

## §5. The live stand-in rule

A synthetic voice is a live stand-in only and is never stored (Decisions 055
and 059). Apple's macOS license allows the system voices "while running the
Apple Software" and forbids "recording, publishing or redistribution ... in a
profit, non-profit, public sharing or commercial context" (08a §1.4); Google's
engine has no output license we could find, and the safe reading is the same.
So, on every platform:

1. Stand-in audio lives in memory buffers (or, on Android 10, a cache file
   that lives for milliseconds) and is released after it plays.
2. The stored take is the performer's line window only, and the bleed check
   flags any kept window whose microphone signal matches the stand-in it
   overlapped. A flagged line is re-taken with headphones.
3. A partial play is never mixed into a file. A listen-through plays the human
   takes and voices the open parts live, on this device, and the screen labels
   each such line as a device voice, so a stand-in never passes as a person
   (`learning-orientation-design`, the honesty checklist). Every platform has a
   guard test that fails if a synthetic buffer reaches a take write, the mix,
   an export, or an upload, and each was seen to fail once.
4. A play cannot be finished or exported with a stand-in in it; Export
   appears only when every speaking line is human.
5. Only local voices are offered: `localService` on the web and
   `!isNetworkConnectionRequired()` on Android, so a script line is never sent
   to a speech server.
6. Personal Voice (Apple) is offered as a live listen-through voice only
   (owner 2026-10-23): spoken with `speak`, never written to a buffer, a file,
   a cue, or a mix, so Apple's public-sharing limit is never reached.

Voices are cast per part by §2.8: one assignment on the device, auto-cast from
the voices' own quality and (where the platform reports it) the voices' own
gender, never a character's, and every choice the person's to change. A fresh
iPhone may have only a few English voices, so the character's name on screen
does the identifying, and the picker points to Settings for more.
- *Replaced* (2026-11-14, R2 §8 item 2, it was never built): "Voices are
  assigned per part from what the device has, by `gender` on Apple where the
  script states one and by a small hand map on Android".

---

## §6. What is stored where on the device

Phase 1 keeps everything on the device that made it. Nothing is uploaded, and
no record leaves the device unless the person exports the finished play.
Recording needs no account (§8 rule 4); an account, when there is one, holds
no take.

| What | Apple (iPhone, iPad, Mac) | Android | Web |
|---|---|---|---|
| The script as cast (the parsed model, with its line ids and revision) | Application Support, `Plays/<production>/script.json` | `filesDir/Plays/<production>/script.json` | IndexedDB `ed-plays`, key `<production>/script.json` |
| Takes, one file per kept take, never overwritten | `Plays/<production>/takes/` as FLAC (if the floor OS cannot write FLAC, ALAC in CAF; to measure) | `filesDir/Plays/<production>/takes/` as 24-bit WAV (§4.5) | IndexedDB, `<production>/takes/`, 24-bit WAV, written with `add()` |
| Room tone, per session | `Plays/<production>/roomtone/` | the same | IndexedDB, `<production>/roomtone/` |
| The production record (parts, who took which part by the name they typed, what each take heard, the timeline) | `Plays/<production>/production.json` | the same | IndexedDB, `<production>/production.json`, the same fields |
| A script the person added (§13): its castable shape, the working copy it is corrected in (cast by ear: its lines' times, the parts, the place), and the text as pasted | `Scripts/<id>/script.json`, `doc.json`, `row.json`, swapped in together; `Scripts/draft.json` (never on the TV) | ⏳ (R4-7) `filesDir/Scripts/<id>/` | IndexedDB `ed-plays`, object store `scripts`, keys `scripts/<id>/script.json`, `doc.json` and `row.json`; the text being added, `scripts/draft.json` |
| The rendered mix of a finished play | `Plays/<production>/mix.m4a`, rebuilt from the takes whenever they change | the same | IndexedDB, `<production>/mix.wav`; `navigator.storage.persist()` is asked when a play is cast |
| Stand-in audio, transcripts of takes, analytics | Never stored | Never stored | Never stored |
| Apple TV | Nothing: it records nothing and stores no plays in phase 1 (tvOS writes only to Caches) | | |

The web keeps IndexedDB rather than OPFS (decided 2026-10-23): writing a file
into OPFS from the page needs `createWritable`, which older Safari lacks (it
offers only a worker's synchronous handle), while IndexedDB holds an
ArrayBuffer in every browser the web app serves, and its `add()` refuses an
existing key, which is the never-overwritten rule in one call.

Takes are in Application Support rather than Caches because they are the
person's own work and the system may purge Caches; they go into the device
backup like any other document. A line check keeps only its score, not the
words it heard. Deleting a production deletes its folder, and "discard
unused takes" removes every take that is not a part's chosen one. Because
nothing leaves the device, phase 1 collects nothing under COPPA, which is
why it is open to everyone, children included (08c §6.2).

---

## §7. Accessibility

- **Screen readers.** VoiceOver and TalkBack speak through the same speaker
  the microphone hears, so the app announces "your line" before it starts
  listening and makes no announcement while it listens. The line itself is
  on screen and on a braille display before the take begins.
- **Type.** The teleprompter follows Dynamic Type and the platform's font
  scale with no truncation; a long line wraps rather than shrinks.
- **One action.** Recording starts and stops with one control, reachable by
  Switch Control, Voice Control ("Record"), a keyboard (Space on the Mac and
  the web), and a hardware key on Android, and "wait for me" pacing never
  rushes anyone.
- **Cues you can see and feel.** Every stand-in line shows its speaker and
  text as it plays, and "your line" comes with the `selection` haptic and a
  visible countdown, so a performer who is hard of hearing can follow the
  scene.
- **Pace.** Stand-in rate is adjustable, and Reduce Motion turns off the
  scrolling teleprompter in favor of a page per line.
- **The honest cost.** A person who cannot speak cannot record a part in
  phase 1: Personal Voice may read the open parts in a listen-through on their
  own Apple device, but it is never stored, so it cannot be a part (§5). They
  can still direct, take the sound-effects part, and listen.

---

## §8. Rules (binding)

1. A script is offered **for publishing** only when `script_rights.judge`
   returns `castable` and its parse is clean (*Replaced, 2026-11-24, Decision
   088*: it said "for casting"; every script the app can show is offered for
   recording, §2.1). A new kind of evidence is a new bucket
   with a paired test and a broken control, never a list of ids.
2. No model writes, rewrites, summarizes, or fills in a word of a script, a
   cast list, or a description. Stage directions are shown as printed.
3. A synthetic voice is never written to a stored file, never part of a mix,
   and always labeled as a device voice where it plays (§5).
4. Phase 1 uploads nothing. A first take needs no account (Decision 079,
   owner 2026-11-15); sharing, inviting, publishing, joining someone else's
   production and a second production do (§2.3). Listening and reading
   along never do.
5. A take is immutable; choosing a different take never deletes the old one
   until the person discards it. A take is deleted only by the person's own act
   (its Delete, Delete unused takes, Discard the run), and never the chosen one
   alone (§2.9 rule 4).
6. The app never scores or rejects a performance.
7. Every platform that records ships the same seven verbs (§2) in the same
   change set, or carries a ⏳ cell in PARITY.md with its reason.

---

## §9. Questions only the owner can answer

Answered by the owner on 2026-10-23 (Decision 067), and built in batch 0b:

| # | Question | The owner's answer, as built |
|---|---|---|
| C5 | May anyone hear a half-recorded play with live stand-ins? | Yes: anyone can listen through any time, open parts read live by the device (§2.6) |
| C6 | A part nobody takes? | The play stays unexportable; its lines are read live in a listen-through, never stored |
| C7 | Relay order? | Any order; the largest open part is suggested first, never forced (§2.3) |
| C9 | "Individual author died by 1955" as evidence? | Accepted: `script_author_died`, castable (§3) |
| C10 | Commercials? Personal Voice? | Commercials stay, each its own part (a speech inside commercial *n* is the part "ROLE (COMMERCIAL n)"); Personal Voice offered live only (§5 rule 6) |
| New | Does a local, never-shared recording need an account? | Yes, always (§2.3, §8 rule 4). *Replaced* 2026-11-15 (Decision 079): no for the first production; an account for a second, and to share |

Still open:

| # | Question | What phase 1 does until it is answered |
|---|---|---|
| New | A text that is rights-castable but parses unclean (11 of the 20 sampled plays): who fixes its parts, and is that an editing role phase 1 needs? | Not offered until someone fixes it |
| New | GRW (C8): ask before reusing its transcriptions? The owner sends the request (Decision 067) | All 1,371 hidden on GRW's own terms |

---

## §10. Out of scope for phase 1

Uploading, invite links, accounts, the Worker, and archive.org (phase 2);
open casting and peer review (phase 3); a stored synthetic voice of any kind;
an effects library; teleplays; any model-written text in a play; any score,
like, or ranking of a performance.


---

## §11. Phase 2 as built: the Worker (2026-10-23)

Phase 2 makes one production recordable across several devices, by people a
director invites (LOOP-PLAN M8, Decisions 057 and 059). This section is the
server side; §11.7 is the apps' side. Every rule
below is proven by `worker/test/plays.test.js` and `account.test.js`, with a
deliberate break for each in `worker/test/mutations.mjs`. The endpoints, the
record's fields, and the schema are in `docs/WORKER.md`, "Shared plays".

### §11.1 What a production is on the Worker

- **An account is required** for every call that contributes (Decision 057):
  claiming, recording, uploading, reporting, blocking. Two reads need none (owner,
  2026-10-29): an open invite, and the finished listing (§11.5).
- **Castable only** (§8 rule 1). A production names a script id, its
  revision, and its cast sheet: every line id with its part, in script order,
  exactly as `linePart` gives it. The Worker holds a manifest of each castable
  script's revision, title, and the SHA-256 of its cast sheet: the bundle's, and one row a play
  published beside the library and built with it (R4-0; `docs/WORKER.md` "Castable only"), so every
  play of the library can be shared, cast by a class, and read together. So a client cannot invent a castable
  script, and the Worker never holds the text of one.
- **The record is production.json**, merged line by line from every member's
  takes, with the field names the apps already decode (§6). Room tone and
  listening through stay on the device.
- **Invite only.** The director makes invite links: 256 random bits, shown
  once, stored as a hash, revocable, expiring after 1 to 30 days (7 by
  default). Whoever holds one sees everything without an account (the play, its
  parts and their states, who is in by chosen name, and the chosen takes,
  playable; owner 2026-10-29: "they just can't contribute until they sign in").
  Signed in, they also claim one part. A revoked or expired invite says so (410).
  At most 64 members.

### §11.2 The relay across devices

The owner's answers in §9 hold on the server, word for word:

- **C7.** Any open part may be claimed, in any order; the largest speaking part
  is the suggestion (`next`), then sound, then directions; nothing is claimed
  while a part records; a finished
  part reopens only while nothing records, for its performer or the director.
  A claim lapses after **7 days** (the figure §9 names), the part is open
  again, and its takes stay.
- **C6.** A speaking part is done only when every line has a take; only
  sound and directions may be left silent.
- A take is uploaded only by the part's claimant, only for a line of that
  part, and is immutable (§8 rule 5). The newest take becomes the line's
  chosen one; the claimant can choose an older one back.

### §11.3 Takes on the server

- **Where.** *Superseded 2026-11-19 by Decision 082 (§12.5, §12.8).* A take
  passes through the Worker to the director's device and is kept nowhere on
  Cloudflare; its fields are a row in D1. (Until then each take was to be an
  object in an R2 bucket that was never turned on.)
- **Limits, read from the file's own header**: mono WAV or FLAC only; at most
  300 seconds (the longest castable speech, 644 words, is about 258 seconds at
  150 words a minute, measured over the 7,345 speeches in the castable file on
  2026-10-23) and 45 MB; a declared length more than 50 ms off, or a header
  claiming more audio than was sent, is refused; at most 10 takes a line.
- **The stand-in rule (§5) holds on the server.** A take whose bleed check
  fired is refused, so the device voice is never stored there either.

### §11.4 Safety (App Store guideline 1.2)

- **Report** a take or a member, from inside the production, with a reason
  and an optional note. A reported take is hidden from its reporter at once,
  and a production with a reported chosen take cannot be published.
- **Block** a person: their takes are hidden from the blocker, and an invite
  made by either of the two does not work for the other.
- **Filter** display names and class names through a deny list, folded for
  accents, case, and look-alike characters, with links and the service's own
  name refused. Whole-word terms let "Cassandra" through.

### §11.5 Consent, publishing, and classes

- **CC0 consent** (Decision 059) is recorded per person per production with
  the consent text's version id, before the play is published. A take
  uploaded to the Worker reaches only the production's members, so it needs
  no consent (Decision 072, 2026-10-28). The words are the owner's, approved
  2026-10-29 (Decision 059), version `cc0-2026-10-29`; a consent recorded at a
  version whose text begins "OWNER:" never counts. New words take a
  new version id, and everyone consents again before the play is published.
- **Publishing** queues a job; the request itself calls nothing. It needs a
  complete production, no open report on a chosen take, and every performer's
  consent at the current version, and it opens only when both archive.org
  keys are set (Decision 073).
- **The uploader** (2026-10-29, Decision 073) is the Worker's cron, every
  five minutes: one archive.org item per production, `eardrama-<production
  id>`, in Community Audio (`opensource_audio`), one file per line in script
  order (`0042-HAMLET.wav`), and no mixed file: the mix is the device's
  (§2.7) and would hold every voice in one file nobody could take back alone.
  Metadata is data only: the script's title, source, and rights evidence, the
  performers' chosen names as `creator` and `credits`, CC0 1.0 as
  `licenseurl`, `mediatype` audio. A job is `queued`, then `uploading`, then
  `published` (with the item's URL) or `failed` (with the reason); the record's
  `archive` carries `status`, `url`, and `reason`.
- **Replace or remove a published take** (P12, owner 2026-10-29). A performer
  uploads a new take for a line of theirs on the item, at the current
  consent, and the Worker overwrites that line's file; or removes it, and the
  file is deleted with who removed it and why. The director removes any line,
  with a report's reason. A line the director removed stays removed. A
  replacement is a take like any other: reports and blocks apply, and a
  reported one is held back from the item. When a performer's last line
  leaves, their name leaves the credits. Copies others made before cannot be
  called back (the consent says so).
- **Finished ear dramas are listed and credited** (owner, 2026-10-29: "Why else
  would we record them?"). A public, paginated listing of published productions:
  title, the script's source, credits (part: chosen name), the archive.org item,
  and the publish date, newest published first (a stated rule, never engagement),
  plus one production by id. A removed line (P12) drops its credit; a deleted
  account's lines stay on the item and are credited to no one. The site reads
  the Worker directly (docs/WORKER.md "Open reads").
- **Classes.** A teacher makes a class and students join by an eight-character
  code. A class marked under 13 (fixed when made) takes no student until its
  teacher records the school's consent, and that record is refused until the
  owner names the privacy policy's version that covers school consent. The
  school or district decides (FTC COPPA FAQ N.3): the teacher names which
  authorization (`reference`, required since Decision 084).
- **Retention** (Decision 084, owner 2026-11-21: "I don't mind deleting the
  info about who recorded what, but we need to be able to keep the recorded Ear
  Dramas in our database"). A class ends the day after its end date (by
  default the July 31 that closes its school year; the teacher changes it), goes
  after 12 idle months and a 30-day notice, or when its teacher deletes it or
  its school asks (the owner's operator route, within 30 days). Its seats and
  names, take-to-seat links, notes, casting, membership, school record and every
  unsubmitted production are deleted; a submitted production stays, detached and
  without its seats. A director deletes an unsubmitted production. An account
  idle 3 years is deleted after a 30-day notice any sign-in cancels. The
  teacher exports the class as one file (no audio: none is stored). Client rules: §12.12.
- **Deletion** (Decision 063) removes every row, the person's take audio in
  the bucket (none since Decision 082), and their classes. A **submitted production** (its publish is
  queued or done) survives any member's deletion (owner, 2026-10-29: "Account
  deletion should definitely not remove their recordings from already submitted
  works"): its listing, takes, audio and archive.org item stay, the deleted
  person's part goes uncredited (the item's credits are rewritten), and
  directorship passes to no one, so nobody new gains director rights; the
  remaining performers keep control of their own lines. An unsubmitted
  production with others in it passes to the member who joined first, with
  their takes, and one nobody else is in goes with its last member.

### §11.6 Open owner items

| # | Question | What the Worker does until it is answered |
|---|---|---|
| P1 | R2 needs a payment method on file. Turn it on, or keep phase 2 waiting? | Answered 2026-11-19: "We are using archive.org for storage, not cloudflare." No R2; takes pass through (Decision 082, §12.5) |
| P2 | The CC0 consent words (Decision 059) | Answered 2026-10-29: the owner's words at version `cc0-2026-10-29` |
| P3 | A vetted deny list for names | A short seed list in `worker/src/plays-names.js` |
| P4 | Who reads reports, how they arrive, and how fast they are answered (guideline 1.2 asks for timely action and a published contact) | Answered 2026-11-24 (Decision 088.6): an hourly workflow tells the owner by GitHub email how many wait, and `tools/reports.py` reads and answers them (`docs/runbooks/reports.md`); nothing auto-hides a take for everyone |
| P5 | The privacy policy that covers school consent for students under 13 | Words approved 2026-11-21 ("The policy wording looks good to me."); `SCHOOL_CONSENT_POLICY` is set to the published policy's version at deploy. Until it is set, no school consent can be recorded, so no under-13 class takes a student |
| P6 | The Ear Drama archive.org account and its keys | Answered 2026-10-29: keys given; the uploader runs once both are Worker secrets (Decision 073) |
| P14 | Does deleting an account remove that person's lines from the item? An Ear Drama collection on archive.org? | Answered by the owner 2026-10-29: "Account deletion should definitely not remove their recordings from already submitted works" (lines stay, uncredited); "community audio is just fine, as long as we are doing a good job of labeling the ear dramas within archive.org" |
| P7 | The 7-day claim lapse (C6 and C7 are answered, §9) | Applied as the default |
| P8 | Do classes own productions (a class member joins without an invite)? | Answered 2026-11-19 (ruling 3): yes, a class owns a production, seen only by its seats (Decision 082, §12.4) |

### §11.7 Phase 2 in the apps (2026-10-24, binding)

The same verbs on the web, iPhone, iPad, Mac, and Android (§8 rule 7); Apple
TV and the other TVs play back only (rule 12) and offer none of the rest. Recording stays
phase 1's, on the device, line by line; phase 2 adds only the link to the
Worker. Every call goes through the platform's one API client, refreshed
first (AGENTS.md hard rules). Words on screen are these, on every platform.

1. **Share.** A production's cast sheet offers **Share** to a signed-in
   person (signed out: "Sharing needs an account." and the platform's
   sign-in). It sends the script id, revision, and cast sheet
   (`POST /productions`, an optional display name) and keeps the Worker's id
   beside the record: `share.json` (`{ pid, consented }`) in the production's
   folder (web: IndexedDB `{id}/share.json`). The caller directs. A shared
   production's parts, claims, and chosen takes are the Worker's from then on.
2. **Invite.** The director's **Invite** makes a link,
   `https://eardrama.org/invite#{token}` (twin `eardrama://invite#{token}`,
   DEEP_LINKS.md), handed to the share sheet; the caption under it is the
   fact "Works for N days." The token rides the fragment, so no server log
   holds it. Shown once; the Worker keeps only its hash.
3. **Join.** Opening a link holds the token (for this session) and opens
   Library's Ear dramas, which shows **Invitation**: the play's title, its
   parts with their states, who is in by chosen name, and the takes, which play
   (`GET /open/invite`; owner, 2026-10-29: signed out, everything is visible).
   Signed out, "Sign in to join" stands where **Take part** would; claiming and
   recording need an account. A revoked or expired invite reads "This invite does not work."
   (the Worker's 410). Signed in,
   every open part offers **Take part** with an optional name field while no
   part records, the suggested one (`next`) as the accent (C7: any order);
   a member already in it sees **Open**. Joining makes the production on this
   device from the bundle's script at the same revision; a revision the
   bundle no longer has is "This play has changed since it was cast." and
   offers nothing. "Not now" drops the token.
4. **The shared cast sheet.** Each part with the Worker's state and the
   performer's chosen name. Mine and recording: **Record** (phase 1's
   recorder, §2.4). Open while none records: **Take part**; sound and
   directions also **Leave silent**. Finished, mine or I direct: **Open part**
   while none records. Mine: **Release** gives it back.
5. **Upload.** After recording, **Upload N takes** sends the chosen take of
   each line of a part this person holds that the Worker lacks, never a
   flagged one (§5; the Worker refuses one anyway). **The owner's switch**
   (P1): the record and `GET /consent` carry `uploads`; while it is false
   the button is disabled and the warning "Uploads are off." stands in its
   place, before anyone records, so nobody learns it after an evening's work.
   Takes stay on the device either way. **Done with this part** finishes it
   on the Worker once every line's take is up. Uploading asks for no
   consent: the take reaches only the members (rule 6).
6. **Consent before anything leaves the members** (Decisions 059 and 072).
   Invite-only takes on the Worker need an account and nothing more. The
   CC0 consent screen, with its warning that a published recording is
   public and reusable by anyone, including for AI training, comes before
   anything is published beyond the members (Decision 059, words approved
   2026-10-29). Tapping **Publish** opens the platform's own sheet or dialog
   with the Worker's text exactly as `GET /consent` serves it (never
   hard-coded), **I agree to publish my recording under CC0.** and **Not
   now**; agreeing sends its version id, kept in `share.json`, then queues the
   job. **Publish** is offered only while `GET /consent` says `publishes`;
   otherwise the one line "Publishing opens when the Ear Drama archive
   account is connected." stands in its place. The old gates
   (`TODO(M8-consent-screen)`) are gone.
   - **Every performer agrees for their own recording** (Decision 059:
     consent is per person; owner, 2026-10-29). The Worker's record marks
     each member `performer` (holds a chosen take) and `consented` (agreed
     at the current version). Once the production is complete and
     `GET /consent` says `publishes`, each performer who is not the
     director and has not agreed sees one prompt in that production: the
     Worker's text exactly as served, **I agree to publish my recording
     under CC0.**, and **Not now** (it returns next time the production
     opens; nothing is sent). The director sees the performers as a list
     of names, each with a mark for agreed or not yet, and nothing else
     written. **Publish** is disabled until every performer other than the
     director has agreed; tapping it then opens the director's own sheet as
     above. Apple TV shows neither the prompt nor the list.
   - *Replaced*: "Consent before the first upload (Decision 059). The
     Worker's text, exactly as it arrives, with I agree and Not now ..."
7. **Listen through.** Coming back to a shared production (opening it, the
   app returning to the foreground, the browser tab shown again) reads the
   record again, so a part recorded on another device shows as recorded
   without a reload; nothing polls while the screen is away. The other
   members' chosen takes are fetched into the
   production on this device (an imported take is a file like any other,
   never overwritten), then phase 1's listen-through plays: human takes,
   and the device voice live for the rest (§5). Export once every speaking
   line is human, as in §2.7. A take hidden from this person (blocked or
   reported) never arrives; "N takes are hidden from you." says so.
8. **People: report and block** (guideline 1.2). The members by display
   name, "You" and "Director" as tags. Everyone else has **Report** (a reason:
   Offensive, Harassment, Personal information, Not a performance, Other;
   and an optional note) and **Block** (asks first: "You will no longer hear
   their takes."). Another member's line in read-along has **Report** on its
   take. A report hides that take from the reporter at once.
9. **Publish** (the director, once complete): queues only. Its refusals are
   one line each. Asks rule 6's consent first. Once the record carries a job
   it says only what the job is (P15, 2026-10-29), from `archive.status`:
   `queued` "Queued for archive.org" and `uploading` "Uploading to
   archive.org", both a quiet line; `published` **On archive.org**, a link to
   `archive.url` that the platform opens with its own link handling; `failed`
   the Worker's `reason` in the error color, and for the director **Publish
   again** (no new consent: the agreement stands; the Worker queues the job
   again). The record is re-read whenever the production is opened (rule 7).
   Apple TV shows the line only, without the link or the action.
10. **Classes.** Library's Ear dramas, signed in: **Classes**, each with its
    code for its teacher (in two groups of four), **Make a class** (a name,
    and "Under 13", fixed when made; such a class shows "Waits for the
    school's consent"), and **Join a class** by its code. A roster only (P8).
11. **Library's Ear dramas** lists this device's productions and, signed in,
    the shared ones this person is in that the device has not opened
    (`GET /productions`); opening one makes it here as in rule 3.
12. **Apple TV plays back** (§2's table: TVs record nothing). Signed in,
    Library's **Ear dramas** lists the shared productions this person is in
    (`GET /productions`), newest first. Opening one shows the title, each
    part with its state and performer's chosen name, and **Listen
    Through**: the chosen takes the Worker shows this person are fetched
    into Caches (the only place tvOS lets an app write besides the App
    Group; nothing is kept as the person's work) and play in script order,
    with each speaking line that has no take read live by the device voice,
    labeled "Device voice" with its speaker (§5; never stored). **People**
    offers **Report** and **Block** for every other member, because a TV
    that plays other people's takes owes the same guideline 1.2 controls.
    Nothing is claimed, recorded, uploaded, invited, or published there;
    invites stay off the TV (DEEP_LINKS.md). Signed out, the section is
    absent, since Library already offers Account. The other TVs: none yet.
13. **Replace or remove a published line** (P12, P15; Decision 073). Once the
    job is `published`, the cast sheet lists, under Listen, **Your lines**
    (the director: **Lines**): each spoken line with a chosen take that this
    person may change, shown as printed. A performer has **Replace** and
    **Remove** on each line of a part they finished. The director has
    **Remove** on every line, and **Replace** on their own. **Replace**
    opens phase 1's recorder on that one line, with the existing flow (its
    takes, "Use this take"); the new take is a pending take of a finished
    part, so **Upload N takes** appears as in rule 5, and the upload
    overwrites the line on the item. **Remove** asks first with the
    platform's own destructive confirmation ("Remove this line from
    archive.org?" and **Remove**), then `POST
    /productions/:pid/archive/lines/:lineId/remove` with `withdrawn` for
    one's own line; the director chooses the reason from the report reasons
    before the confirmation, and a director's own line needs none. The
    action takes the error color, never red (Decision 064: red is for
    recording). Done, the line reads "Removed" for the rest of the visit: the
    record carries no per-line state yet, so a reopened production offers the
    action again, and the Worker accepts it twice. Refusals: `not_your_take`
    "This line is not yours to change.", `removed_by_director` "The director
    removed this line.". Apple TV offers none of it.

Each refusal the Worker can give maps to one line (web
`PlaysShare.line`, the same strings on Apple and Android): `storage_not_configured`
"Uploads are off.", `not_open` "This part is taken.", `another_part_is_recording`
"{Part} is still recording.", `lines_missing` "N lines still need a take.",
`invite_not_found` "This invite does not work.", `not_found` "This production is
not shared with you.", `consent_version_mismatch` "The consent changed. Read
it again.", and the rest as written there.

### §11.8 The learning test for phase 2 (2026-10-28, M8a)

Asked of the invite-only client before its second pass:

1. **Understanding**: the shared cast sheet is the play's own parts in the
   Worker's order, each with who holds it, so a group spread over several
   homes sees the same structure the table did. Facts only, from the record.
2. **Participation**: every part is still a person's choice (C7, any open
   part), and the takes of the people who went before now arrive from their
   own devices, so each performer acts opposite real voices, not only the
   device's.
3. **Agency**: the Worker suggests a part and never assigns one. Consent to
   publish is a person's own decision, which is why the screen waits for
   words the owner has approved instead of a placeholder anyone could tap
   through (rule 6). Report and Block are in every member's hands,
   including on the TV.
4. **Clarity**: a re-read of the record when the person comes back, not a
   live socket; the TV plays and reports and does nothing else.

What would we lose by automating? Fetching every take the moment it lands
would spend a family's data without asking; takes are fetched only while a
person has the production open (the web waits for Listen through), never in
the background.

Not built yet: the apps' screens for
replacing or removing a published take (the Worker's side is built, P12), a moderator's view of reports, and a test that the
Worker's part order matches `js/plays-core.js` and Apple's on every castable
script (each is checked here against its own suite, not against the others).

---

## §12. Reading together (Decision 082, owner 2026-11-19; binding)

> **Owner, 2026-11-19** (ROUND3-LOOP.md part 2): *"We need to build out how a teacher
> actually would manage that process. We also need to build out how someone would do this
> with a bunch of different devices in the same room (whether a classroom of kids or a group
> of adults doing a table read)."* Rulings: a class owns a production, assigned parts record
> at once, seats need no account, one cross-platform read room, no SharePlay; *"We are using
> archive.org for storage, not cloudflare. We already decided that teachers could upload the
> full recording under their name."* Research: `docs/research/design/R3c-table-reads-and-classes.md`
> §3 to §6 (its R2 storage is superseded).

### §12.1 The read room

One new object: a **cursor in a room**. A read room holds a castable script (id and
revision, its cast sheet checked against the manifest as productions are), the production
when it records, the class when a class reads, the **mode**, the **cursor** (the line now
being read and a generation number), who leads, and who holds which part. A person always
moves the play on: nothing advances on a timer, and nothing listens to the room to guess
where people are. No audio passes through the room.

Rules (the protocol's, `worker/src/read-protocol.js`, held on every stack by
`worker/test/read-golden.json`):

1. **Only the leader moves the cursor** (Next, Back, a jump to a scene). A move carries the
   cursor generation it was made from: a repeat changes nothing, a move from an old
   generation is refused and the device resyncs. Keys: arrows and Space, a page-turn pedal,
   the volume keys where that opt-in exists.
2. **Joining**: a six-character code (Listen Together's alphabet, read aloud the same way),
   or, for a seat, the class's own "Your class is reading" with Join. No account to read.
   At most 40 members; the 41st sees **This reading is full** (a refusal). The leader may
   **Lock joining**.
3. **A late joiner** gets the snapshot: the page at the cursor, their parts, their next line.
4. **The clock**: every device keeps Listen Together's server-clock estimate (Cristian's
   algorithm, best round trip), so the cursor's delay can be measured (Decision 082's T4
   gate: under 300 ms at the 95th percentile on the socket).

### §12.2 Roles

| Role | Who | Does |
|---|---|---|
| **Leader** | the teacher, the director, whoever opened the read; or a seat the teacher hands it to | moves the cursor, sets the mode, calls **Again**, locks joining, ends the read, hands the lead on and takes it back |
| **Reader** | everyone else on their own device | follows the lit line, reads their own lines; in Record, records only their own |
| **Screen** | an Apple TV, a Google TV, a projector's browser (`/read/CODE?screen`), a Mac window, an Android tablet | shows the page large: the current line, one before and two after, speaker names in part hues, the room code and how many are here; reads open parts aloud only when the leader turns on **Read open parts**, and only between takes. Never leads, holds no part, records nothing |

In a class, only the teacher or the seat the teacher chose leads, and if the leader's device
drops the room **holds still** ("Waiting for Ms. Ortiz") rather than passing the lead to a
student. Among adults the reader present longest takes the lead after 2 minutes (Decision
065's rule).

### §12.3 The four modes

1. **Table read** (live, nobody records). Each reader's device follows: the page turns to
   the cursor, the current line is lit, the reader's own lines carry the I'm playing tint,
   and their next line is marked "Next: you, in 3 lines" (a fact). A touch to scroll away
   stops following; **Back to the line** returns (as Read along). No sound from any phone.
   Stage directions are a part like any other: the leader holds them, gives them to a
   reader, or lets the screen show them unread (Decision 076).
2. **Rehearse**: the table read plus **Hide my lines** (peek on tap), **Again** (the leader
   jumps back to the scene's start) and private marks (§2.10). Only the screen speaks
   stand-ins in a room; a reader alone keeps today's solo rehearsal.
3. **Record in the room**: the cursor reaches a line and **only the device holding that
   line records**; every other device is silent and shows who is reading. The take ends on
   one second of silence or a tap (§2.9), the line is marked done, and the cursor moves to
   the next line someone holds (lines nobody holds are skipped and stay open). The leader
   may stop, go back, or call **Again** on any line. No headphones: no device plays during a
   take. Each take records `capture: "room"`. *Quiet while others record* is a refusal-class
   instruction and passes the essential-words rule. Variant, **one microphone**: the
   leader's device records every line and the cursor credits each take to its part and
   seat (the default for a class under 13 and any room with one good device).
4. **Relay across time**: assigned parts recorded at home, in parallel, each against the
   takes already in and the device voice for the rest; the teacher's progress list shows
   who has recorded how many of their lines.

### §12.4 Seats and the class production

A **seat** is a name the teacher typed (a first name, a nickname, "Group 3"), belonging to
the class, with no account, email, birth date, photo, or voice outside the class's
production behind it. The teacher adds seats one by one or pastes a list; a student joins
with the class code and **picks their name**; a printable seat card carries a QR code. The
device keeps a seat key (stored only as its hash); the teacher can **Release** a seat. A
seat's takes belong to the teacher's account and go with the class.

A **class production** is visible to the class's seats without an invite and to nobody
else. The **casting board** lists parts largest first with facts from the script (lines,
words, scenes, the longest speech) and totals per seat; **Fill evenly** is a deterministic
proposal the teacher accepts, edits or ignores; a large part can be **split by scene**, a
seat can **double** small parts. The app never suggests who should read what and never
labels a reader's level. Parts the teacher assigns may record at once; elsewhere the
one-part relay (C7) stays.

**Review**: the teacher listens line by line and marks **Approve** or **Again**, with an
optional typed note to that seat. The student chooses which of their takes is offered; the
teacher approves what is offered. Counts and links, never a ranking.

### §12.5 Where takes go (pass-through, nothing at rest)

Each device records its own lines and writes each take on the device first, as every take
is. During the session the take **passes through the Worker to the leader's device** and is
deleted from the Worker the moment it arrives; with no leader's device present it is
refused and waits on the recording device, sending when both are present. Relay at home
works the same way: the take waits until the teacher's app is open. No take audio is stored
on Cloudflare (no R2, no Durable Object, KV or D1 audio). The full recording is the
leader's: the teacher uploads it to archive.org **under their own name** through the
existing uploader (Decision 073), for classes marked **13 and over** only, after each
performer's CC0 consent: the teacher's own, with the teacher's confirmation that every
performer agreed and that the school holds a media release for each performer under 18
(Decision 084, §12.12 item 6); an **under-13 class never publishes** and the teacher exports a
file.

### §12.6 Failure states

| What happens | What the room does |
|---|---|
| A reader's device drops mid-read | Its seat stays assigned. At that reader's line the leader sees "Lucy's phone is away" with **Skip**, **Read it from the screen** (a stand-in, never stored) and **Wait**. On reconnect the device rejoins with its key and jumps to the cursor |
| The leader's device drops | Class: the room holds still, every device says "Waiting for Ms. Ortiz"; the leader rejoins with the key or hands the lead from another of their devices. Adults: the reader present longest leads after 2 minutes |
| A late joiner | The snapshot: the page at the cursor, their parts, their next line. In Record, lines already passed show open, recordable later |
| Two devices claim one seat | The second sees "Lucy is already in on another device" with **Move here**; the first device leaves the seat. The teacher can always Release |
| Two adults claim one part | The first claim wins (the server decides); the other sees who holds it |
| The leader's device is not there to receive a take | The take stays on the recording device, marked "on Lucy's device", and sends when the leader's device is present; nothing waits on the Worker |
| The network drops during a take | The take finishes and is written on the device, then passes through when the network returns; the leader can still move the cursor |
| A school blocks WebSockets | The polling transport carries the same messages; the screen says nothing unless the cursor is slower than 2 s, then "Slow connection" (a warning) |
| A student records something unkind | Report and Block as today; in a class the teacher sees the report first and can remove a take; nothing reported is published |
| The class grows past 40 | **This reading is full**; a second room for the other half works |
| An under-13 class | Everything but publishing works; the teacher exports a file |
| Several phones playing aloud | Prevented: in a room only the screen speaks, and only between takes |

### §12.7 Each platform

Same verbs, native idioms (R3c §5.4): the web (`/read/CODE`, `?screen`), iPhone and iPad
(iPad drag to cast; the open Duo's outer display shows the current line when folded,
Decision 080), Mac (a window per class, a Reading menu, a second window on the projector),
Android phone and tablet. Apple TV and Google TV are the shared screen with a pairing code
and record nothing (tvOS-DESIGN §4.13, ANDROID-DESIGN's TV panel rule). Apple uses the
Worker's read room, not SharePlay.

### §12.8 As built on the Worker (T2, 2026-11-19)

The contract is `docs/WORKER.md` ("Shared plays", "Seats"); each rule below has its test
in `worker/test/seats.test.js`, `plays.test.js` or `archive.test.js` and a deliberate
break in `worker/test/mutations.mjs`.

1. **Seats.** The teacher pastes a list (one name a line; duplicates once; the name
   filter applies; at most 64). A student lists the seats by class code and claims one,
   with no account, and gets a seat key once (stored as its hash). A held seat is refused
   to a second device until it asks to **Move here**; the first device's key then stops
   working. **Release** frees a seat for the next device; removing a seat drops its
   casting and keeps its takes (the teacher's).
2. **Class production.** Made by the class's teacher; every seat of the class sees it
   without an invite. A class read room takes its roster and casting from the class and
   the production, never from the request, and a seat joins it (or takes a seat in it)
   only with its key.
3. **Assignments.** The teacher replaces the whole casting at once: a part, or a scene
   range of it, to a seat, no line twice. A seat records only its assigned lines; every
   assigned part records at once. A production without assignments has nothing for a
   seat to record, and accounts keep the one-part relay (C7) there.
4. **Pass-through.** The teacher's (director's) device holds a pickup open; a take is
   checked from its head against its declared length and piped to the pickup one chunk
   at a time; it is refused at once when no pickup is waiting and the teacher's device
   was not there in the last 10 seconds; a cut body never arrives as a take. The
   Worker holds at most the take's 64 KiB head and the chunk in the pipe, one take in
   flight per sender and four per production, so never a whole take (the Durable Object
   isolate has 128 MB). The teacher's own device records any line (one microphone) and
   may credit it to a seat.
5. **Under 13.** No seat's voice passes through until the school's consent is
   recorded (Decision 059, waiting on P5); until then a class under 13 records on one
   microphone, the teacher's device, and never publishes.
6. **Review and progress.** The student chooses which take is offered; the teacher marks
   it **Approve** or **Again** with an optional typed note that only that seat sees.
   Progress is counts per seat and part (lines assigned, recorded, approved, again),
   never a ranking.
7. **Publish.** A class marked 13 and over, every speaking line chosen, the teacher's own
   CC0 consent, and a name to credit: the item carries that name on every line and no
   seat's label. The cron lays the item out; the teacher's device sends each line's file
   through the Worker, streamed to archive.org and never kept. The same path carries
   every production's files now that no take is stored (an invite production's director
   sends them; a performer sends their own replacement, P12).


### §12.9 As built on the web (T3, 2026-11-19)

WEB-DESIGN §4.17 to §4.19 hold the web's idiom; what the other ports need to know:

1. **One client port of the protocol**, `js/read-core.js`, runs the shared goldens
   (`worker/test/read-golden.json`): every client-side function the golden file covers, and from
   each `joinSnapshot` case the client's own next line and lit lines rebuilt from the snapshot
   alone. Swift and Kotlin ports run the same file (T4).
2. **The transport**: the socket first (the key in a first `hello`), a long poll of the same room
   when the socket will not open or closes, and the socket tried again (2, 5, 15, 30, 60 s, then
   every 5 minutes) while the poll goes on. Each poll carries the generation in hand (`?gen=`);
   the room answers at once when it is behind, else when the room changes or after 20 s, never
   sooner than 1 s after the last poll began. No HTTP ping while polling: every answer is a clock
   sample, its `held_ms` (the wait in the room) taken out. A quiet room costs a polling member
   three requests a minute, not sixty-six (2026-11-23: every app shares one free Worker account,
   and a class of 30 polling every second used it up in under an hour). A snapshot older than the
   one in hand is dropped, so a slow poll never rewinds the cursor.
3. **A class room's join** needs the seat key, and a room code does not say which class it is: a
   device without a key for this room asks for the class code and the name. Seat keys live in the
   tab (the shared-cart rule, R3c §4.2).
4. **Gaps the protocol leaves** (T4 asks before porting): the snapshot carries no names, so a
   class room waiting for its teacher says "Waiting for the teacher", not the teacher's name; and
   there is no message for **Read open parts**, so the screen's own switch turns it on.
5. **Takes on the web**: nothing fetches take audio any more (the routes went with Decision 082).
   A director's cast sheet holds the pickup while it is open and imports what passes through; the
   class page holds it for review, keeping arrived takes in the tab only.
6. **Deleting a class keeps its published production**: the account deletion detaches a submitted
   class production from its class before the class goes (worker test and mutant, owner ruling
   2026-10-29 that published works stay).

### §12.10 Record in the room, pairing a TV, names (T5, 2026-11-19; binding on every client)

> **Owner, 2026-11-19**: *"We also need to build out how someone would do this with a bunch of
> different devices in the same room (whether a classroom of kids or a group of adults doing a
> table read). Ideally, all of this would work quite easily..."* Rulings: storage is archive.org,
> never Cloudflare; *"teachers could upload the full recording under their name"*; takes pass
> through the Worker to the leader's device and are deleted on arrival. The Worker's side is
> `docs/WORKER.md` "Read rooms"; each rule has its test in `worker/test/read-record.test.js` and a
> break in `worker/test/mutations.mjs` (`t5:`). The protocol's new rules (`recordRefusal`,
> `receiverOf`, `cleanName`, the paired screen) are in `worker/test/read-golden.json`, which every
> stack runs.

1. **Who records.** In Record mode only the device of the reader who holds the line at the cursor
   opens its microphone. The engine is the studio's (`RecordingSession`) with no cue played: the
   microphone opens when the cursor reaches the line, the take ends on one second of silence (the
   line-end detector) or the reader's **Stop**, is trimmed, and is written on the device first with
   `capture: "room"`. The reader taps **Start recording** once per room (the microphone permission
   and five seconds of room tone); there is no headphones gate, because no device plays during a
   take (§12.3). The take ended, the device sends `line-done` and the cursor moves to the next held
   line. It sends it whatever the cursor is by then: when the leader moved the cursor during the
   take, the line is still marked done and the cursor stays where the leader put it, so the line
   does not open a microphone again when the cursor comes back; only the leader's **Again** reopens
   a done line (T7c, 2026-11-20: a press racing a take had reopened lines, two takes of one line).
   Every other device shows who is reading ("Ann is reading", "Lucy is reading") and, while
   a take records, **Quiet while others record** (a refusal-class instruction).
2. **Where a take goes.** Each take joins the device's **outbox**, kept with its local room
   production (one per room code), and is sent with `PUT /v1/read/{code}/takes/{id}`. `201`
   empties it. `409 nobody_receiving`, offline, a timeout or a 5xx keeps it and it is sent again
   every 5 seconds while the room is open and on every new snapshot; any other refusal keeps the
   take on the device and takes it out of the outbox. While any wait the reader sees
   "{n} takes on this device" (a fact). A network drop during a take changes nothing: the take
   finishes, is written, and waits; the leader can still move the cursor.
3. **The receiver** is the snapshot's `you.receives` (a class's teacher whoever leads; an adult
   room's leader). While the room records, its device holds the room's pickup (`GET
   /v1/read/{code}/takes/inbox`) and imports each take into its own local room production, the
   newest take of a line becoming its chosen one (as on the Worker). The receiver never sends a
   take: its own device records only in One microphone (item 6).
4. **Takes** (the receiver's sheet, from the room bar): a head line of counts per reader ("Lucy
   3 of 5"; counts, never a ranking), then each speaking line in script order with its state:
   **Recorded** (Play, Again), **On {name}'s device** (the reader ended it, the take has not
   arrived), **Waiting** (held, not yet read), or **Open** (nobody holds it; it stays open and the
   play is unfinished until someone records it). **Again** sends the room's `again`: the cursor
   returns to that line and its reader's microphone re-arms. In a class room with a production,
   each arrived take also offers **Approve** and **Again** with a typed note (the class's review
   route, 500 characters, shown to that seat only), and the room's Again re-arms the reader when
   their device is there.
5. **Listen through and the file.** The receiver's **Listen through** plays its room production
   (the takes on this device; open lines read live by the device voice, never stored or mixed).
   **Export** when every speaking line has a take. **Publish under my name** only in a class
   marked 13 and over, with a production: the credit name (the account's chosen name to start),
   the CC0 consent, `POST /v1/plays/productions/:pid/publish { credit_name }`, then the device
   sends each line's chosen take to `archive/files` one at a time (`409 not_ready` waits for the
   cron and tries again; `409 already_sent` is skipped). An under-13 class shows **Export** and the
   refusal "An under-13 class never publishes."; an adult room without a production exports.
6. **One microphone** (the leader's **Record every line here**, in the Reading menu; on by default
   in an under-13 class): the leader's device records the line at the cursor whoever holds it,
   credits it to that line's part (and seat), keeps it in its room production, and moves the
   cursor on when the take ends. In a room with a production the take's row is written as the
   director's own take (recorded, never relayed).
7. **Names.** An adult room's join takes an optional name (40 characters at most, the name
   filter: `422 bad_name` reads "That name is not allowed."); signed in, the field starts with the
   account's chosen name. The name travels in `members[].name` and names the leader ("Waiting for
   Ann") and the reader ("Ann is reading"). A class room takes no name: its names are its seats.
8. **A reading that ended or never was.** `410 room_ended` reads "This reading has ended." and
   `404 no_such_room` reads "No reading with that code.", on the join page and in the room, on
   every platform, never "could not be reached". An ended room's code says so for 6 hours.
9. **Pairing a TV** (tvOS-DESIGN §4.13, ANDROID-DESIGN's TV panel rule, WEB-DESIGN §4.18). The TV
   asks `POST /v1/read/pair` and shows the pairing code large, split 3 + 3, with one line, "On the
   leader's device: Reading, then Add a screen." (a fact the viewer cannot discover by looking).
   It asks `GET /v1/read/pair/{code}` every 2 seconds; when a leader attaches it, the answer is the
   room's snapshot with the TV's member key, and the TV becomes that room's screen (past a lock:
   the leader let it in). A code lasts 10 minutes and is used once; an expired one is replaced by a
   new one without a word. The leader's **Add a screen** (Reading menu) takes the code (any case,
   spaces allowed) and sends `POST /v1/read/{code}/pair { code }`; refusals: "No screen shows that
   code." (`no_such_pair`), "That code has expired." (`pair_expired`). No audio passes, and the
   screen records nothing.
10. **The screen's voice.** On the Apple and Android screens (and the web's), a line nobody holds
    is read aloud by the live stand-in voice only while the room's `read_open` is on (the leader's
    message); it stops the moment the cursor moves, so it never sounds during a take; never stored.

### §12.11 Relay across time and the consent rule (T6, 2026-11-19; binding on every client)

> **Owner, 2026-11-19**: *"Please research ways of doing 'table reads' or other methods for
> reading through plays together (either synchronously in the same room or across space and
> time)."* Rulings: storage is archive.org, never Cloudflare; takes pass through the Worker to the
> receiving (teacher's or leader's) device and are deleted on arrival; nothing at rest. The
> Worker's side is `docs/WORKER.md` ("Is the receiver here?", "Credit and consent"); each rule has
> its test in `worker/test/relay.test.js` and a break in `worker/test/mutations.mjs` (`t6:`).

**Relay across time** is mode 4 of §12.3 made concrete. A class seat (no account) or an adult
production's member who holds a part records their lines at home, whenever they like, in the
studio inside the reader (§2.9), each against the device voice (another performer's take passed
through the Worker to the receiver and is never fetched again, so it is not here to hear). Parts
that are assigned record at once.

1. **On the device first.** Each take is written on the performer's device, as every take is, and
   stays there until it has passed through. Nothing waits on the Worker: a take the receiver is
   not there for is refused (`409 nobody_receiving`) and stays where it is made.
2. **One state per take, on the sender**, in essential words: **On this device · sends when
   {name} is in Ear Drama** (waiting), **Sending**, **Sent**. `{name}` is the receiver's chosen
   name from the receiver route; without one, "your teacher" (a seat) or "the director" (a member).
   Sent is known from the Worker's record (the take is in `takes`) or the `201` itself, and kept
   on the device so it reads the same offline. A take the Worker refuses for good (`not_assigned`,
   a bleed-flagged take, a lapsed seat key) leaves the queue, stays on the device, and shows the
   Worker's own words.
3. **Sending.** While the app is open the sender asks `GET .../receiver` (`{ receiving, name }`);
   only when it is `true` and the device is online does it send, one take at a time, in script
   order. Otherwise it asks again after 5, 10, 20, 40 s, then every 60 s, and at once when the
   network returns, the app comes to the front, or a take is saved. `409 nobody_receiving`,
   `409 one_take_at_a_time`, `429`, a timeout, offline and `5xx` keep the take and back off; any
   other refusal is final for that take. The ask reads the relay's memory and writes nothing.
4. **The receiver** (the teacher's class page, an adult director's cast sheet) holds the pickup
   while it is open and shown, as §12.10 item 3 does for a room: a hidden page holds none, and
   after 30 minutes with no take it stops and shows **Keep receiving takes** (a held pickup keeps
   the relay awake on the shared free account; a sender keeps its takes and waits). Each arrival
   is kept in that tab or device only, and the **progress list** (counts per seat and part: lines assigned, recorded, approved,
   again) refreshes on every arrival. Counts and links, never a ranking, and the Worker cannot
   say what is still waiting on a device: it has no record of a take it never received.
5. **At home with no one else there** the same screen works: a seat opens **Your parts** (its
   class code and name, remembered on the device), sees each assigned part and its lines, records,
   and sees each take's state and the teacher's review (Approve, or Again with the typed note).

**The consent rule** (decided from §12.5 and Decision 059, 2026-11-19). The maker is credited, never
the leader.

6. In an adult room, a reader who has no account is credited by the name they gave on joining
   (`credit` on the take, the name filter applied at join; a reader who gave none is "A reader").
   The take is a row of the director's production, so the row names the director as owner and the
   credit names the maker; the director is the performer of none of it. A class seat's take stays
   the teacher's, credited to the seat (Decision 082); the teacher consents for their own credit and
   confirms that every performer agreed and that the school holds a media release for each performer
   under 18 (Decision 084, §12.12 item 6).
7. Publish needs every performer's own CC0 consent at the current version. A maker who has only a
   name has none to give, so **a production with any line by such a maker cannot publish**: the
   Worker answers `409 consent_missing` with `credits` (the names), and Publish shows who still
   must consent (their names, in the same list as the performers who have not agreed). The names
   leave the list when the maker holds the part under their own account (an invite) and agrees, or
   the director records or chooses another take for the line. The consent words and version are
   `GET /consent`'s, never written into a client.
8. Only the director opens a room on an adult production (a stranger's room cannot write takes
   into it); a class's room still takes its class's production.

### §12.12 Student privacy: delete, end, export, confirm, ask (Decision 084, owner 2026-11-21; binding on every client)

> **Owner, 2026-11-21**: *"We want this to work for the vast majority of school districts, schools, teachers and
> students. The only way to do this is to build upon the work of the teachers and other advocacy groups that have
> already shown how to allow schools to create such great works of art (ear dramas) without compromising student
> privacy."* On retention: *"I don't mind deleting the info about who recorded what, but we need to be able to keep
> the recorded Ear Dramas in our database."* The Worker's side is `docs/WORKER.md` ("Retention and deletion"); each
> rule has a test in `worker/test/retention.test.js` and a break (`084:`) in `worker/test/mutations.mjs`.

Same verbs on every platform that has the class page (web, iOS, iPadOS, macOS, Android phone; a TV records nothing
and has no class page). Words are exactly these; a refusal is `ReadCore.refusal(code)`'s line.

1. **The Class section** closes the teacher's class page: one line **Ends {date}** (the class's `ends_on`, a day,
   shown in the person's date style and never shifted by a time zone), then **Change date** (the platform's date
   picker, today to 400 days ahead; `PATCH /classes/:id`), **Export class**, and **Delete class**.
2. **Delete class** asks first, in the platform's destructive confirmation: **"Delete {class}? Its names, casting
   and notes are deleted. Published plays stay."** with **Delete class** (destructive) and Cancel; then
   `DELETE /classes/:id` and back to the list. The received takes on the teacher's device are the teacher's and
   stay until they delete them.
3. **Export class** saves `GET /classes/:id/export` as `{class name} export.json` through the platform's own save
   (web: a download; Apple: the share sheet or a file exporter; Android: the system's create-document picker). No
   audio is in it.
4. **The teacher's class list** shows **Deleted {date} unless opened** under a class whose `deletes_on` is set (a
   12-month idle notice); opening the class ends the notice.
5. **School approval** (an under-13 class without `school_consent`) heads the class page: a checkbox **My school or
   district approved Ear Drama for this class.**, a field **Approved by** (placeholder "School or district, and the
   approval", up to 120 characters, required), and **Record** (`POST /classes/:id/school-consent { reference }`).
   Until the owner sets `SCHOOL_CONSENT_POLICY` the Worker answers `503 pending_owner_policy`, shown as its refusal.
6. **Publishing a 13-and-over class** adds two checkboxes before the teacher's own CC0 consent: **Every performer
   agreed to publish.** and **The school has a media release for each performer under 18.** Publish sends
   `performers_agreed: true, media_release: true`; with either unchecked it is refused on the device with
   **Check both boxes first.** This replaces §12.11 item 6's "the teacher consents" for a class: the teacher's
   CC0 consent covers their own credit and the item, the two confirmations cover the students.
7. **Delete production** is offered to a shared production's director, and only while it has no archive job:
   **"Delete {title} for everyone in it? Its takes leave the server."** and the button **Delete for everyone**,
   then `DELETE /productions/:id`, and the local copy goes too. A submitted production is not offered it (its
   lines are removed one by one, P12).
8. **The age question** comes before a person's first **Share** (making a production shared), **Invite**, **Take
   part** from an invite, **Publish**, or **I agree to publish**, outside a class: **"What year were you born?"**,
   a year picker with no default (this year back 120 years), **Continue** and **Cancel**. Only "under 13 or not" is
   kept, on the device (web `localStorage` `ed.over13`; Apple `UserDefaults` `ed.over13`; Android preferences
   `ed.over13`), never sent. The year a 12-year-old shares with a 13-year-old counts as under 13 (`year - birth
   year <= 13`); an under-13 answer shows **"Sharing is for 13 and over. Your teacher can add you to a class."** and
   that device keeps sharing off. Seats and classes never ask: the school decides there.
9. **Refusal words**, added to every `ReadCore` table: `confirmations_required` "Check both boxes first.",
   `reference_required` "Name the school or district.", `pending_owner_policy` "Not open yet.", `bad_end_date`
   "That is not a date.", `end_date_past` "Pick a later date.", `end_date_too_far` "Pick an earlier date.",
   `submitted` "A published play stays."
10. **Never**: speaker identification, voice matching, or any analysis of a student's take (R3d T5); a birth year
    stored or sent; a notice by email (none is held).

### §12.13 Removing a reader, and leaving (App Store guideline 1.2, 2026-11-24; binding on every client)

1. **Remove.** An adult room's leader, or whoever opened it, removes any other member; in a class only the teacher
   does, never a student who leads. The opener is never removed. The member's key stops working at once on every
   transport, their parts open, and **joining locks** in the same message: the code is still on their screen, so a
   removal that left the door open would keep nobody out. The leader may unlock. The control is behind the presence
   count ("3 here"), which is a control only for someone who may remove: a list of who is here, each with
   **Remove**, confirmed by "Remove Ann and lock joining?" (a consequence the person cannot discover by looking).
2. **The removed device** reads "You are no longer in this reading." (`not_a_member`) and asks nothing more.
3. **Leave.** Closing the reading is leaving: the room is told, the person's parts open, an adult room's lead passes
   on at once, and the last reader to leave ends the room. A class's teacher keeps their place (the room holds still
   for them, §12.2). `leave` is sent only by a person's act, never by a rotation, a background, or a lost network:
   those keep the key and come back.
4. **Names.** Every name a room shows passes the name filter: a joiner's, a seat's, and the opener's (`422 bad_name`).
5. **No Report in a room, and why.** Guideline 1.2 asks for a filter, a way to report, a way to block, and a published
   contact where people's content is kept and shown to others. A room keeps none: the Worker holds a typed name and who
   holds what until it ends and then deletes both; no words are typed, and a take passes to the leader's device and is
   kept nowhere on the way. A report filed after the fact would name nothing anyone could look at, so the answer is the
   leader's, on the spot: Remove, Lock joining, End. A room that records into a production leaves takes there, and
   that production has Report and Block. If a room ever keeps something, it gets a Report first.

---

## §13. Record anything (Decision 088.3; binding on every platform that records)

The owner, 2026-11-24: *"You should be able to record your own version of
anything you want with your own casting."* Research and frames:
`docs/research/design/R4-record-anything.md`. Core: `js/own-core.js`
(`R4-core-port-brief.md`). Built on the web: adding (R4-2), casting by ear (R4-3),
sharing, classes and reading together (R4-5, over R4-4's Worker routes); on iPhone, iPad,
the Duo and the Mac (R4-6's on-device half) and on Android (R4-7's), adding and casting by
ear. Until sharing is built on one of them, an own script and its productions there offer
no Share, no Read together, no Invite and no Publish: the buttons are absent, never dead.

1. **An own script** is a script a person brought or cast by ear. It has the castable shape, an
   id `own-<uuid>`, line ids given once and never reused, and the catalog's
   revision formula. It is kept on the device (§6) and needs no account: adding,
   reading, editing and the first production ask for none (Decision 079).
2. **Add a script** (Record): a title and the text, pasted or opened from a plain
   text file. The light grammar (R4 §2.2, golden cases in
   `catalog/tests/golden/own_script_parse.json`) proposes parts; a paragraph it
   cannot place is shown as **No part**. Every piece is a slice of the person's
   text. The app never writes, completes, or corrects a word. The text being added
   is kept as it is typed, so a closed page loses nothing. A text too long to keep is refused
   here, judged on what Done would keep (every line with its id), not on its own bytes. A Project Gutenberg text
   is read between its own marker rows (`*** START OF THE` or `THIS PROJECT
   GUTENBERG EBOOK ...` and its END, with or without a space after the stars, a
   title that runs on to the next row included; the last row `End of [the] Project
   Gutenberg ...`; and the older small print, before the play or after it): of the
   pipeline's 1,721 cached texts, 1,683 carry START and END, 1,097 the last row and
   24 the small print, and 1,689 are read without their wrapping (the 32 of one 1990s
   Complete Shakespeare have none of these rows). Nothing else is cut, and the text
   kept is the text as pasted.
3. **The parts page** draws the script as the reader does. A line: give it to a
   part, Direction, or Sound; Split here; Join to line above; Edit words; Leave
   out. A part: rename; Join to; Not a part (its words go back, with no part). A
   strip counts the lines with no part, and Next goes to the next one. Undo takes
   back any step since the page opened. A line's **More** leaves out everything above
   it or everything below it, as one step, refused when a line there has a take ("A
   line there has a take."). Done turns a line with no part into a
   direction. Every step is kept as it is made; a script not yet Done is in Your
   scripts and opens here.
4. **After a take** on a line (a take in any production of the script, chosen or
   not), its part and its boundaries are fixed: the line says **"This line has a
   take."** and offers only Edit words. Its words may change, and a take recorded
   before they did (more than punctuation) reads **Words changed** in the take
   list. A part that holds such a line keeps its name.
5. **A change to a script reaches its productions on this device** (they are one
   text): each takes the new lines and revision, keeps its takes, and gains or
   loses parts with them. Sharing ends that (item 12).
6. **It never publishes.** "This script can't be published." stands on its page.
   Export stays: a finished recording, the script as text (Save as text, readable
   as Fountain), and `scripts[]` in Export my data.
7. **Delete** asks: "Delete {title}?", and with productions "Delete {title}? Its
   productions keep their copy." Its marks and voice choices go with it unless a
   production is left to read them in. A script not yet Done has Delete in the sheet its
   title opens, on the parts page and the casting page.
8. Kokoro voices are not offered for a script with no published phonemes; the
   device's own voices are.
9. Its kicker is **Your script** (`kind: "own"`), never Radio play or Stage play:
   either would be a claim.
10. **Cast by ear.** On an episode with a shown transcript and no castable script,
   **Record this** opens the transcript in lines (R4 §2.4, golden
   `ear_cast_lines.json`) with the episode playing and the line being said lit. A
   tap on a part gives it that line and those after, until the next tap; only lines
   the episode was heard through carry, so a seek hands nothing to anyone. **+ Part**
   names a voice, and the lit line is theirs; a part can be renamed while it is cast (its
   name on every line of theirs, refused when one has a take). Leave out works the same way. Undo takes
   back any step since the page opened. The app proposes no speaker and analyzes no
   voice. "Automatic transcript" stays on the page. The broadcast's sound is never a
   cue, a take, or in a mix, and no time is in the script.
   - **Kept on the device** from the first step (never by looking), one for an
     episode: the lines as they were then, the parts, and the place. Coming back goes
     on from there. When archive.org has since remade the transcript, the kept lines
     stay ("The transcript has changed. Your lines are kept."); when the episode's
     first copy is another file, "The recording has changed. The times may be off."
   - **Done** at any time: what is cast is its script, the rest are directions, and
     Your scripts and its page say "37 of 149 lines cast" with **Cast by ear** to go
     on. The parts page (Edit) finishes it as any script; opening it makes the marks
     the lines' own parts, and left-out lines are gone.
   - **Its source** is "Automatic transcript", linked to the episode. It never
     publishes, as no own script does.
   - **The door** stands only when it is sure to open: the transcript's times were
     read (R4 §1.3), or a casting was begun here. An episode the catalog no longer
     serves (a take-down, §8) has no page, no door and no casting ("Not in the
     catalog."); a script already made from it stays on its device and is refused
     wherever an own script is shared. Nothing here recommends an episode, so
     `no_recommend` is kept by having nothing to break it: no next, no suggestion,
     and the end of the episode starts nothing.
   - **Times**, measured 2026-11-24 against the decoded audio: a cue's words are
     said within a second of its start, late in an episode as early (nine episodes,
     median -0.6 to +0.9 s). Chrome's clock stays within 0.02 s of the decoded audio
     after a seek on seven of the nine, a VBR file whose length reads 41 s long among
     them. On a damaged file it runs 2.4 s behind after 27 minutes. On one whose header
     is a Xing table (100 places, each to 1/256 of the file) it plays 0.6 to 4.7 s
     early after a seek, and is right when played from its start. Nothing corrects for
     either: the page only lights a line.
11. **Sharing** (Decisions 079 and 088.4; docs/WORKER.md "Own scripts"; R4-5). **Share** on a production asks
   for an account, then makes the production on the Worker (`own: true`) and sends the script's lines once, as
   canonical JSON. One line says who can read it, where it is pressed and after: **"Only people you invite can
   read this script."** (a class: **"Only this class can read this script."**). Nothing lists, searches, links
   or recommends a shared script, on any platform.
   - **Refusals**: "The title is not allowed."; "The part name {part} is not allowed."; "This script is too long
     to share."; "You have shared 20 scripts. Delete a production of one first."; "Sharing scripts is full.";
     "This script was removed."; "This script has been reported."
   - **The text's state** is the record's `own_script.state`. `owed`, when its sending failed for now (no network,
     "Sharing scripts is full."): "The script was not sent." with **Try again**, and no Invite; `409 already_there`
     is success. A refusal that can never pass (`script_too_long`, `revision_mismatch`, `script_removed`) undoes the
     share. `kept`: Invite. `removed`: "This script was removed."; by the owner (`by` is set) no part is taken,
     sent or read together; with the account that brought it (`by` is null) members go on and nobody new comes in.
     What a member has stays on their device either way.
   - **A share whose creation answer was lost** (web 2026-11-25; Apple and Android follow): the Worker holds a
     production of the person's with the text `owed` and this device holds no link to it, and it counts toward 20.
     Once a page, over the list the screen already read (no polling), each such production is looked at once: exactly
     one unshared production of that script at that revision here adopts it (linked, the text sent). Any other is left
     as it is: the text may be owed by another device that is offline and still trying, so nothing but a person deletes
     it. Nothing is said on screen.
   - **One resolver** answers "the script of this production or room" for a member, an invite, a class, a seat and
     a room (web `PlaysShare.scriptOf`). A catalog play is the library's, at the recorded revision. An own script is
     this device's copy in the production, then this device's script at that revision, then the Worker's. What the
     Worker sends is drawn only when its SHA-256 is the revision, it is canonical, it passes the core's own check,
     and it matches the cast sheet (an invite's parts and line counts, a record's parts, a room's cursor and
     parts, a seat's lines); else "This script did not arrive whole." with Try again. A removed script has no Try again.
   - The fetched script is kept in its production's folder, and recording, relay, listen through, read along and
     export read that copy.
12. **A shared script is frozen**: its page and its production offer **Edit a copy** (a new script with a new id, no
   takes, and the same source) where Edit was, and its parts and casting pages open its page instead. Read together
   and a class freeze it as Share does.
13. **Read together shares first.** On an own script's page it asks once ("Share {title}? People who join the
   reading can read it."), shares a production of it (or uses the one already shared), and opens a room that
   carries that production; signed out, "Sharing needs an account." A shared production's page has it too, for its director.
14. **A class**: the teacher's own scripts stand after the plays in Pick a play. A seat fetches the text with its
   seat key and never sends text. The class export adds each own script's lines from the teacher's device.
15. **Report script** (in the production, for a member who did not bring it): the reasons of every report, and
   Copyright. The production is hidden from its reporter at once ("Reported. This production is hidden from
   you."), with Delete production for this device's copy.
16. **Publish is absent** where the record says `publishable: false`, and the reason stands there: "This script can't
   be published." (an own script), "This play cannot be published." (any other).
