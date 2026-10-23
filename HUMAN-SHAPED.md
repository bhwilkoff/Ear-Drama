---
# Copied from docs/human-shaped/HUMAN-SHAPED-template.md. The humanshaped.org
# directory reads this header. Keep the keys as they are; change only the values.
app: "Ear Drama"
website: "https://eardrama.org"
repository: "https://github.com/bhwilkoff/Ear-Drama"
principles_version: "0.6"
status: "working toward"   # declared | working toward | withdrawn
declared_by: "Ben Wilkoff"
date: "2026-10-23"         # the date of the last change to this file
platforms: [web, ios, ipados, macos, tvos, android]
---

# Ear Drama is human-shaped

*Answering the Human-Shaped Principles, version 0.6
(https://github.com/bhwilkoff/UniversalAppTemplate/blob/main/docs/human-shaped/PRINCIPLES.md).*

> **Who wrote what in this file.** The template is Ben's to fill in. Every
> **Answer** and **In my words** line below is left blank on purpose, because
> those sentences have to be his (principle 13). The **Evidence** links and the
> **Agent's notes** under each principle, and the whole "Review" section at the
> end, were written by an AI agent (Claude Code, Claude Opus 5.5) on
> 2026-10-23, at Ben's request, as the `human-shaped-review` pass in LOOP-PLAN
> M10. The agent read the repository only. It could not use the apps on a
> device, hear them, or watch a person use them, and nothing on the live site
> was checked. It is evidence and questions, not a grade; teacher and
> classmate feedback is the other half. Ben can keep, rewrite, or delete any
> of it.

**What it is for, and who it is for.** *(Ben's words.)*

## How to fill this in

Each principle finishes the sentence "Human-shaped software...". For
each one, write one of three answers, then a sentence or two
in your own words, then at least one link to evidence someone else can
open.

- **Meets:** the evidence is linked, and a stranger could check it.
- **Not yet:** say what is missing and what you plan to do about it.
- **Does not apply:** say why it does not apply to this app.

Every principle is *meets* or *does not apply* before the status above
says `declared`. Until then, the status is `working toward`, and that is
an honest place to be.

---

## 1. A human-shaped problem

**Starts from a human-shaped problem, one that affects real people in the real world.**

*How someone can tell:* the builder has written down what the problem is, who has it, and why a computer cannot simply solve it for them.

**Answer:** meets / not yet / does not apply

**In my words:**

**Evidence (found by the agent):** [docs/research/RESEARCH.md](docs/research/RESEARCH.md) (Ben's request of 2026-10-17, quoted at the top); [docs/PLAYS-DESIGN.md §1](docs/PLAYS-DESIGN.md) (Ben's 2026-10-18 description of the relay); [README.md](README.md).

**Agent's notes.** The research file quotes Ben asking for "a public domain audio app that is specifically focused upon radio dramas", and the plays design quotes his relay idea in his own words. I did not find a sentence, in Ben's words, about whose problem this is: who he knows that wants to hear these programs, or to perform one together, and could not with the tools they had. The plays page names "a family at a kitchen table, or a class with one iPad", but those words are an agent's. *A question for you:* is Ear Drama's problem the listening (a hard-to-browse archive), the gathering (people making a play together), or both, and who is the first person you picture having it?

## 2. More possible, not more profit

**Increases what people are able to do, rather than how much profit can be made from them.**

*How someone can tell:* the heart of the software works without payment, any price is stated plainly, and nothing in it is designed to keep people longer than they want to stay.

**Answer:** meets / not yet / does not apply

**In my words:**

**Evidence (found by the agent):** [README.md](README.md) ("No ads, and no account needed to listen"); [privacy/index.html](privacy/index.html) ("No analytics, no cookies, and no advertising"); [DECISIONS.md 057](DECISIONS.md); the sleep timer in [DECISIONS.md 062](DECISIONS.md).

**Agent's notes.** There is no price, purchase, or advertising code in `js/`, `apple/`, or `android/`. The one place the apps decide to keep a person listening is what plays after an episode ends, and the three code bases do it three ways (see the Review, owner's call A). *A question for you:* when an episode ends at bedtime or in the car, what should happen without anyone touching the device?

## 3. Values as guardrails

**Has its values written down as guardrails for both the people and the AI agents who build it.**

*How someone can tell:* the values are written in the project itself, where both people and agents read them, and at least one of them has visibly changed a decision.

**Answer:** meets / not yet / does not apply

**In my words:**

**Evidence (found by the agent):** [AGENTS.md](AGENTS.md) "Why we build" and Standing instructions; [DECISIONS.md 055](DECISIONS.md) (the owner's catalog rules, each dated); [DECISIONS.md 059](DECISIONS.md) (CC0 chosen with a warning, in Ben's words); [catalog/tests/test_audio_rights.py](catalog/tests/test_audio_rights.py) and `tools/test_us_english.py` (two values with checks).

**Agent's notes.** Decision 059 shows a value changing a decision: Ben wanted to forbid AI training on contributed plays, learned CC0 cannot carry that, and chose CC0 with a plain warning. Three standing values say "no check yet" (essential words only, no AI copy, side doors). This review found places the first one is crossed (Review, fix now 4), which is the kind of drift a check would catch. *A question for you:* which of the "no check yet" values would you most like a test to hold?

## 4. Iteration, never a first draft

**Treats iteration as the path to innovation, so that no first draft of a feature, design, or piece of writing is ever shipped.**

*How someone can tell:* the history of the project shows rounds of feedback and revision before each feature, design, or piece of writing went out.

**Answer:** meets / not yet / does not apply

**In my words:**

**Evidence (found by the agent):** [DECISIONS.md 060 and 064](DECISIONS.md) (the palette: Ben asked for more research, then chose On Air); [docs/PLAYS-DESIGN.md "The learning test, as built"](docs/PLAYS-DESIGN.md) (the plays checked again after they were built); [DECISIONS.md 062](DECISIONS.md) (three platforms' player numbers reconciled); `git log` (268 commits since 2026-10-17).

**Agent's notes.** The rounds in the history are mostly agent rounds: research, build, audit, rebuild. Nothing has gone out to the public yet, and [SCRATCHPAD.md](SCRATCHPAD.md) items 3 and 11 say the listening apps and the plays are built but not yet played by Ben. LOOP-PLAN's "Owner feedback" section reads "(none yet)". *A question for you:* which feature will you play first, and where will you write down what you find?

## 5. Grounded in research

**Is grounded in research, so that its builder always knows whose work they are building on, from tools and services to authors and design patterns.**

*How someone can tell:* the research behind the major choices is recorded, and the tools, data sources, and borrowed ideas are named.

**Answer:** meets / not yet / does not apply

**In my words:**

**Evidence (found by the agent):** [docs/research/](docs/research/) (RESEARCH.md and twenty detail files, from content sources and rights to voices, scripts, palette, and evenings); [DECISIONS.md 058](DECISIONS.md) and [061](DECISIONS.md) (the transcript gate and loudness target, each measured before it was fixed).

**Agent's notes.** Decisions 058 and 061 name the sample, the command, and the numbers behind each threshold. The credits page names data sources but not the tools, libraries, or agents the app was built with (principle 14). *A question for you:* which piece of this research would you hand to another builder starting a radio or podcast app?

## 6. Decisions with feedback

**Makes every decision with feedback from another person, an AI agent, or a piece of documentation.**

*How someone can tell:* the major decisions are written down with their reasons, and the record shows where the feedback came from.

**Answer:** meets / not yet / does not apply

**In my words:**

**Evidence (found by the agent):** [DECISIONS.md 054 to 065](DECISIONS.md) (each with a dated owner quote, or marked as an agent's reading, as 064's "an agent's reading, kept on 2026-10-23; the owner may overrule"); [catalog/DECISIONS.md](catalog/DECISIONS.md); "Who was in the room" lines in 057 and 059.

**Agent's notes.** The record separates Ben's rulings from agents' readings. Open rulings are listed in [SCRATCHPAD.md](SCRATCHPAD.md) "Waiting on you" (items 2 to 13), and several of them (9, the next-episode rule; 4, the evening floor; 7, the plays questions) are already in the shipped code as interim behavior. No feedback from anyone other than Ben and agents appears yet. *A question for you:* who, besides you, should see Ear Drama before 1.0?

## 7. Tested the way people use it

**Is tested the way people will actually see, hear, and use it, not only the way a machine would check it.**

*How someone can tell:* every claim that something works points to evidence from a real device or a real person, and the software says plainly where it does not work yet.

**Answer:** meets / not yet / does not apply

**In my words:**

**Evidence (found by the agent):** [PARITY.md](PARITY.md) (audited 2026-10-22: no cell reads ✅, built-but-unplayed work reads 🚧); [SCRATCHPAD.md](SCRATCHPAD.md) items 3 and 11 ("None of it is verified until you play it"); in-app refusals such as "Not available yet" ([index.html:216](index.html)) and "Sign-in is not available in this build."

**Agent's notes.** I could not check this one: I did not use any app, and the project says plainly that nobody has played it on a device yet. The plays' bleed check carries "UNVERIFIED" on its threshold ([js/plays-core.js:24](js/plays-core.js)). *A question for you:* who other than you (a child, a teacher, someone using VoiceOver, someone on an older phone) will try the plays before they ship?

## 8. Documentation as seriously as code

**Treats documentation as seriously as code, so that it grows and changes with the software, in the builder's own language.**

*How someone can tell:* the project has current documentation of its decisions, its state, and its design, and the builder's own words are in it.

**Answer:** meets / not yet / does not apply

**In my words:**

**Evidence (found by the agent):** [DECISIONS.md](DECISIONS.md), [SCRATCHPAD.md](SCRATCHPAD.md), [PARITY.md](PARITY.md), the binding design docs ([docs/WEB-DESIGN.md](docs/WEB-DESIGN.md), [docs/iOS-DESIGN.md](docs/iOS-DESIGN.md), [docs/macOS-DESIGN.md](docs/macOS-DESIGN.md), [docs/tvOS-DESIGN.md](docs/tvOS-DESIGN.md), [docs/ANDROID-DESIGN.md](docs/ANDROID-DESIGN.md), [docs/PLAYS-DESIGN.md](docs/PLAYS-DESIGN.md)).

**Agent's notes.** Ben's words appear as quotes inside decisions; the surrounding prose is agents'. The privacy page describes the web app only (fix now 3), so one public document is behind the code. *A question for you:* which document would you want to read in your own voice first, the README or the privacy page?

## 9. Shared openly

**Shares its code, tools, and lessons as openly as the problem it solves allows.**

*How someone can tell:* the code, or at least the lessons, are public under terms that let others use them, and anything kept private has a stated reason.

**Answer:** meets / not yet / does not apply

**In my words:**

**Evidence (found by the agent):** [LICENSE](LICENSE) (MIT, "Ben Wilkoff and contributors"); [DECISIONS.md 054](DECISIONS.md) (a public repository, with the reason); the catalog pipeline in [catalog/](catalog/); contributed plays dedicated CC0 ([DECISIONS.md 059](DECISIONS.md)).

**Agent's notes.** Secrets are kept out by rule (AGENTS.md hard rules). *A question for you:* is there a lesson from Ear Drama (the rights audit, the evening builder) that belongs upstream in the template now?

## 10. Learning as success

**Counts learning as success, so that if at least one thing was learned in building it, the software has succeeded.**

*How someone can tell:* the builder can say what they learned, and the lesson is written down where the next builder can find it.

**Answer:** meets / not yet / does not apply

**In my words:**

**Evidence (found by the agent):** [docs/SESSION-LOG.md](docs/SESSION-LOG.md); [DECISIONS.md 061](DECISIONS.md) (what measuring loudness taught); [docs/PLAYS-DESIGN.md §3](docs/PLAYS-DESIGN.md) (what the rights test found castable, and why radio scripts are not yet).

**Agent's notes.** The lessons written down are mostly what the agents learned. I found no note of what Ben learned. *A question for you:* what do you know about old-time radio, or about making things with people, that you did not know on October 17?

## 11. People own their data

**Lets people own their data and make every decision about what happens to it.**

*How someone can tell:* the software collects only what it needs, says what it keeps, and offers a way to export and delete it.

**Answer:** meets / not yet / does not apply

**In my words:**

**Evidence (found by the agent):** [privacy/index.html](privacy/index.html); [delete-account/](delete-account/) and "Delete account" in [js/account.js](js/account.js); "Clear history" in [js/app.js:891](js/app.js); [DECISIONS.md 063](DECISIONS.md) (USER_TABLES and the deletion test); [docs/PLAYS-DESIGN.md §6](docs/PLAYS-DESIGN.md) (plays stay on the device).

**Agent's notes.** Listening needs no account, and the Worker keeps a provider account number, not a name or email. Deletion exists on every platform. I found no export of history, queue, or follows on any platform, and the privacy page does not mention the native apps, the microphone, or Listen Together rooms (Review, fix now 3 and owner's call G). *A question for you:* if someone leaves Ear Drama, what of theirs should they be able to take with them?

## 12. No new problems

**Creates no new human-shaped problems while solving the one it set out to solve.**

*How someone can tell:* the builder has asked, in writing, whom the software could harm, and has answered.

**Answer:** meets / not yet / does not apply

**In my words:**

**Evidence (found by the agent):** [docs/PLAYS-DESIGN.md §1](docs/PLAYS-DESIGN.md) ("The strongest case against it", on a child's recorded voice); "Who was in the room, who gains, who pays" in [DECISIONS.md 057 and 059](DECISIONS.md); the take-down model in [DECISIONS.md 055](DECISIONS.md); `no_recommend` (never recommended, always findable).

**Agent's notes.** Children are named, and phase 1 keeps every take on the device. What a child meets in Plays is a rights-filtered list of eleven stage plays with no information about their content (Review, owner's call B). *A question for you:* would you hand the Plays tab, as it is, to a ten-year-old or a fifth-grade teacher?

## 13. The builder's own voice

**Is written in the builder's own voice, so that every word is shaped by a human, and no machine pretends to be one.**

*How someone can tell:* the words people read were written or chosen by a person, and every automated part of the software says what it is.

**Answer:** meets / not yet / does not apply

**In my words:**

**Evidence (found by the agent):** "Automatic transcript" on the web ([js/api.js:237](js/api.js)), Apple ([apple/Core/Catalog/Transcript.swift:8](apple/Core/Catalog/Transcript.swift)), and Android ([Transcript.kt:10](android/app/src/main/java/com/example/appname/data/Transcript.kt)); "Device voice" labels while a stand-in reads ([js/plays-ui.js:480](js/plays-ui.js), [apple/Shared/RecordingScreen.swift:174](apple/Shared/RecordingScreen.swift)); [js/plays-voice.js](js/plays-voice.js) (no audio path, scanned by a test); [docs/PLAYS-DESIGN.md §8 rule 2](docs/PLAYS-DESIGN.md).

**Agent's notes.** I found no model-written list or blurb: the catalog tools contain no model calls, shelves are rules over data, and scripts are shown as printed. The interface strings were drafted by agents for Ben's approval; the store words wait on him ([SCRATCHPAD.md](SCRATCHPAD.md) item 13). One path lets a device voice reach a finished play (Review, fix now 1). *A question for you:* which words in the apps have you read yourself and would stand behind?

## 14. Credit everything

**Credits everyone and everything responsible for it, including people, communities, AI agents, tools, and processes.**

*How someone can tell:* the software and its project credit the people, communities, sources, agents, and tools behind it.

**Answer:** meets / not yet / does not apply

**In my words:**

**Evidence (found by the agent):** [credits/index.html](credits/index.html) (eleven sources, from the Internet Archive to Wikidata); the newspaper listing credited on every Radio evening ([js/app.js:496](js/app.js)); `Co-Authored-By: Claude` on 262 of 268 commits.

**Agent's notes.** The credits page names no AI agent, tool, or template, and it carries an open comment asking Ben whether to credit Jerry Haendiges' logs, Wikipedia episode lists, and the Copyright Office schedules, which the catalog reads (fix now 5). *A question for you:* how do you want Claude's part, and the template's, named where listeners can see it?

## 15. Joy for at least one person

**Brings joy to at least one person in the form it ships today, even if that person is the builder.**

*How someone can tell:* the builder can name someone who enjoys the software as it is today, even if that someone is the builder.

**Answer:** meets / not yet / does not apply

**In my words:**

**Evidence (found by the agent):** none yet; SCRATCHPAD item 3 asks Ben to play the listening apps for the first time.

**Agent's notes.** Only people can answer this one. *A question for you:* after the first evening you spend with Tonight in 19xx, who would you tell about it?

## One value, and the decision it changed

*(Ben's words. Decision 059, CC0 chosen over a license restricting AI use, is one the record already shows.)*

## Changes to this declaration

Add a line every time an answer or the status changes. Do not delete
old lines.

| Date | What changed | Why |
|---|---|---|
| 2026-10-23 | File created from the template, evidence links and an AI review added; every answer left for Ben | LOOP-PLAN M10, the human-shaped-review pass |

## Questions about this declaration

If you think something here is not true, open an issue on this
repository, name the principle by number (for example, "principle
6"), and say what you saw. I will answer it in the issue.

*Declared by [Ben Wilkoff], [date].*

---

## Review, 2026-10-23

*Written by an AI agent (Claude Code, Claude Opus 5.5) at Ben Wilkoff's
request, against the Human-Shaped Principles version 0.6. It reports
evidence and questions, not a grade, and it could not use the app the way a
person would. Teacher and classmate feedback is the other half.*

**What I looked for and did not find.** No answer in Ben's own words to any
principle yet, no play session by Ben or anyone else on a real device, and no
feedback from anyone outside Ben and the agents. The live site was not
opened. Everything below comes from reading the code at commit 0d7beac.

### Fix now (ranked)

Each one has a clear answer in a value already written down.

1. **A take with the device voice in it can still finish a play.** The web
   warns ("The microphone heard the device voice", [js/plays-ui.js:491](js/plays-ui.js))
   but still offers "Use this take" ([js/plays-ui.js:502](js/plays-ui.js)),
   and `isComplete` counts any chosen take ([js/plays-core.js:217](js/plays-core.js)).
   Apple ([apple/Shared/RecordingScreen.swift:196](apple/Shared/RecordingScreen.swift))
   and Android ([RecordingScreen.kt:400](android/app/src/main/java/com/example/appname/ui/screens/RecordingScreen.kt))
   carry the same warning. Crosses PLAYS-DESIGN §8 rule 3, Decision 055 (a
   synthetic voice is never stored), and principle 13. PLAYS-DESIGN's own
   learning test found this and "sent it for repair"; it has not landed here.
   Fix: a flagged take does not count toward completion, and the mix refuses
   it, on all three code bases, with a test that fails first.
2. **A rights line that will become false on January 1.** "Published before
   1926" is a literal in [catalog/tools/build_projection.py:40](catalog/tools/build_projection.py),
   [apple/Core/Catalog/CatalogModels.swift:177](apple/Core/Catalog/CatalogModels.swift),
   and [DisplayVocabulary.kt:20](android/app/src/main/java/com/example/appname/data/DisplayVocabulary.kt),
   while the rule it describes moves every year
   ([catalog/tools/audit_audio_rights.py:75](catalog/tools/audit_audio_rights.py),
   `year - 101`). Crosses Decision 055 ("public domain by age follows the
   calendar") and the essential-facts rule: the one fact on screen must be
   true. Fix: build the line from the same year function, publish it in the
   manifest, and have the native fallbacks compute it too.
3. **The privacy page describes only the web app.** [privacy/index.html](privacy/index.html)
   says nothing about the iPhone, Mac, Apple TV, or Android apps (downloads,
   history), the microphone and plays on those apps, or Listen Together rooms,
   where the Worker sees an address for rate limits and keeps room state and a
   hashed member key for up to six idle hours ([DECISIONS.md 065](DECISIONS.md),
   [worker/src/rooms.js:140](worker/src/rooms.js)). Crosses principle 11
   ("says what it keeps"). Fix: add those three sections, with Ben approving the
   words.
4. **Captions that explain.** [apple/Shared/ListScreens.swift:88](apple/Shared/ListScreens.swift)
   "Browse Series to start.", [ListScreens.swift:452](apple/Shared/ListScreens.swift)
   "Episodes you start are kept here.", and Android's
   [LibraryScreen.kt:67](android/app/src/main/java/com/example/appname/ui/screens/LibraryScreen.kt)
   "Episodes you play appear here." are instructions, not a refusal, a warning,
   or an undiscoverable fact (AGENTS.md standing instruction;
   `mobile-first-density-design` rule 7). Smaller: "Plug in headphones so the
   device voice stays out of your recording." (Apple
   [RecordingScreen.swift:66](apple/Shared/RecordingScreen.swift), Android
   [RecordingScreen.kt:241](android/app/src/main/java/com/example/appname/ui/screens/RecordingScreen.kt))
   carries an explaining clause the web leaves out ("Headphones only."). Fix:
   delete the descriptions and use the web's "Nothing played yet."; trim the
   headphones line to its warning.
5. **Credits leave out the tools and agents.** [credits/index.html](credits/index.html)
   names data sources only, and holds an unanswered OWNER comment about three
   more sources the catalog reads. Crosses principle 14. Fix: add a short,
   factual "Built with" section (the Universal App Template, Claude Code,
   the platforms' own frameworks); the wording and the three sources are Ben's
   to approve.
6. **Listen's shelves are three different rules.** The web shows "Most
   episodes" plus genre series ([js/app.js:321](js/app.js)); Apple shows "On this
   day" plus each genre's first episodes ([apple/Core/Catalog/CatalogStore.swift:133](apple/Core/Catalog/CatalogStore.swift));
   Android shows "This day in radio" plus genres
   ([ListenScreen.kt:60](android/app/src/main/java/com/example/appname/ui/screens/ListenScreen.kt)).
   Crosses Decision 058 (pipeline outputs every client reads) and parity. Fix:
   one shelf list in the data plane, read by all three; whether "Most
   episodes" belongs at all is in B below.

### Owner's call (ranked)

These need a judgment only Ben can make.

- **A. What plays after an episode ends** (SCRATCHPAD item 9). Apple plays on
  through up to 50 episodes of the series ([apple/Core/Player/AudioPlayer.swift:303](apple/Core/Player/AudioPlayer.swift)),
  Android through the rest of the season ([CatalogDatabase.kt:243](android/app/src/main/java/com/example/appname/data/CatalogDatabase.kt),
  whose comment says "autoplay chooses for the listener"), and the web only the
  queue's head when it is the same series ([js/player.js:122](js/player.js)).
  Three behaviors ship while the rule is open. A conservative interim is the
  web's: play only what the person queued.
- **B. What a child or a teacher meets in Plays.** The list is every
  rights-castable, cleanly parsed script: eleven stage plays,
  among them *The Custom of the Country* (Fletcher and Massinger, bawdy),
  *The Jazz Singer* (1925), and *Hamlet*, with nothing about content or age
  ([catalog/plays/castable-scripts.json](catalog/plays/castable-scripts.json)).
  Options that keep "no AI copy": a short note Ben writes per play, a list a
  person picks for families and classes, or the source's own subject headings.
  The same question covers "Most episodes" as a shelf.
- **C. Listen Together guests cannot pause their own sound.** A guest's play
  and seek controls are disabled ([js/app.js:956](js/app.js); Decision 065, "a
  code lets someone join and listen, never drive"). When a guest's phone
  rings, their only choice is to leave. Option: a local pause that stops
  following until they resume at the host's place.
- **D. Who picks the evening.** Tonight in 19xx is the pipeline's choice of
  year, and the floor is unset (SCRATCHPAD item 4); a listener cannot choose
  another surviving year for the same date. Option: list the other years under
  the evening.
- **E. The export gate in Plays.** Export opens only after one listen all the
  way through without skipping ahead ([js/plays-ui.js:337](js/plays-ui.js) and
  [:371](js/plays-ui.js)). It invites the cast to listen to what they made; it
  also decides for a teacher who already heard it on another speaker.
- **F. Sign-in merges without asking.** After sign-in, this device's history
  joins the account once ([DECISIONS.md 063](DECISIONS.md)); the sheet says so
  ([js/account.js:201](js/account.js)) but offers no choice. Sign-in itself is
  never pushed: it lives in a quiet Account row in Library on every platform.
- **G. Export of a person's data.** No platform offers one (principle 11). A
  JSON download from Library and from the Worker would answer it; it is a new
  feature, so its place in 1.0 is Ben's.

### What held

No side door (feed, MCP, IPTV) appears anywhere in the apps. No catalog tool
calls a model. Nothing plays on launch: `APP_AUTOPLAY` is a DEBUG-only door
([apple/Core/Store/LaunchDoors.swift:29](apple/Core/Store/LaunchDoors.swift)).
Listen live starts only on a press and stops on a pause, another episode, the
sleep timer, or the evening's end ([js/app.js:354](js/app.js)). Radio shows a
missing broadcast as a gap and credits the newspaper. The device voice cannot
be recorded on the web at all, and a test scans for any audio path.

### What stood out

The plays design asked "what will people stop learning?" before a line of code,
and answered it by refusing to keep the device voice; fix now 1 is the one
place the code has not caught up with that answer. And the project tells the
truth about itself: no ✅ in PARITY.md until Ben has played it.

### One round to try next

Play one evening of Tonight in 19xx and record one two-part scene with a
child or a student, then write what surprised you in LOOP-PLAN's "Owner
feedback". A starting point to rewrite in your own words: *"I played
[evening] and recorded [scene] with [person]. Here is what they did that I
did not expect, what they asked me, and what I want to change."*

### What only people can tell you

Whose problem Ear Drama is (1), whether it works for a child, a teacher, a
screen-reader user, and someone on an old phone (7), whom it could harm that
these files do not name (12), and whether anyone enjoys it yet (15).
