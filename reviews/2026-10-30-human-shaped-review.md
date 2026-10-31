# Human-shaped review, 2026-10-30

*Written by an AI agent (Claude Code, Claude Sonnet 5.5) at Ben Wilkoff's request, against the Human-Shaped Principles version 0.6. It reports evidence and questions, not a grade, and it could not use the app the way a person would. Teacher and classmate feedback is the other half.*

**How I looked.** I read the repository at commit 225dd4b and drove headless, muted Chrome through `tools/webdrive.py` against https://eardrama.org (home, Browse, Stations) and against a local copy. I never pressed Play. The live site did not show a Voices scope in Browse, so it is running an earlier build than main; what I describe of D3-9 comes from the code and PARITY.md. The iPhone, iPad, Mac, Apple TV, and Android apps are yours to play; I could not see or hear any of them.

**What I looked for and did not find.** Your answers in your own words in `HUMAN-SHAPED.md` (15 "In my words" lines are still blank; status is "working toward", which is accurate). Any record of someone other than you or an agent using the app. A device-played recording of an ear drama. These come up again below.

## 1. A human-shaped problem
I looked at `docs/research/RESEARCH.md`, `docs/PLAYS-DESIGN.md`, and the README. Your 2026-10-17 request is quoted at the top of the research file, and your relay idea is quoted in the plays design. The README describes the app by its features. I did not find a sentence in your words naming who has the problem and why a computer could not solve it alone. The app does treat the archive as stories to be heard on a particular night ("This day in radio", Stations rebuilding an evening), which leans toward the experienced side of your distinction.
*Question:* Who is the first person you picture, and what have they not been able to do with the archive as it is?

## 2. More possible, not more profit
The privacy page says no analytics, cookies, or advertising. No price or purchase code appears in `js/`, `apple/`, or `android/`. PARITY.md section 6 lists payments as not in 1.0. Library shows no streaks, counts, or nudges. I could not check how the apps behave over a long evening.
*Question:* When an episode ends at bedtime and nobody touches the device, what do you want to happen, and does each platform do that?

## 3. Values as guardrails
`AGENTS.md` carries the values, each standing rule says what holds it, and three say "no check yet". Decision 059 (CC0 with a warning) shows a value changing a decision. Since the 2026-10-23 review, the device-voice take now has `needsRetake` in `js/plays-core.js:229`, the privacy page covers the native apps and rooms, and credits name Claude Code, so a written value visibly turned into changes.
*Question:* Which "no check yet" rule would you most want a test to hold?

## 4. Iteration, never a first draft
648 commits. PARITY.md names rounds (D3-1 to D3-9, D3-fix2), a 2026-10-30 note that "no native player has the verbs on its own surface", and a Decision 068 that renamed sections after a first shape. I did not read the diffs of each round.
*Question:* Which feature went through the most rounds, and what changed your mind?

## 5. Grounded in research
`docs/research/` holds 20 files, from rights to palette to sync, and `catalog/DECISIONS.md` has its own log. Data sources are named in `credits/index.html`. Design direction D is recorded in `docs/research/design/`.
*Question:* What did you learn from the research that you would not have guessed?

## 6. Decisions with feedback
DECISIONS.md records reasons and owner rulings with dates (for example 2026-10-28 and 2026-10-29 rulings cited in PARITY.md). The feedback in them comes from you and from agents. I found no decision that cites a person outside the project.
*Question:* Whose reaction, other than yours or an agent's, has changed something?

## 7. Tested the way people use it
This is where I can say the least. PARITY.md ties ✅ cells to iPhone 12 UI tests with dates, and keeps most other cells at 🚧 "built, not seen". Many cells say "not heard on a device". On the web I saw the home page at phone width render the day chart, show tiles, and tab bar. I did not hear anything, run a screen reader, or watch anyone listen.
*Question:* Who has listened to a whole episode on the app in the car or at bedtime, and what did they do that surprised you?

## 8. Documentation as seriously as code
`SCRATCHPAD.md`, `DECISIONS.md`, `PARITY.md`, `WEB-DESIGN.md`, and platform design docs are current to 2026-10-30. A few documents disagree with the running system: `docs/WORKER.md` line 18 says "Nothing is deployed" while the Worker answers `/v1/health`, and the sign-in cells in PARITY.md still wait on a deploy. Much of the prose is agent-written.
*Question:* Which document could you explain to a classmate without opening it?

## 9. Shared openly
MIT license, public repository named in `HUMAN-SHAPED.md`, the method in `docs/path/`, and a catalog pipeline with its own tests. Plays are published CC0, with the consent step recorded in Decision 059.
*Question:* What is the one lesson from this project you would want another builder to find first?

## 10. Learning as success
The word "learned" appears in decision records and the session logs, but I did not find a place where you say in your own voice what building this taught you.
*Question:* What do you know now about radio drama, rights, or building this way that you did not know in October?

## 11. People own their data
History, queue, and follows are on the device; sync is optional (Decision 057). Account deletion is in the app and at `delete-account/`. The privacy page now describes the apps and rooms. I did not find a way to export history or follows. I could not check what the Worker's D1 actually holds.
*Question:* If someone leaves, what can they take with them besides a finished play's audio?

## 12. No new problems
Recording needs headphones, and a warned take no longer counts as complete. Rights wording says "no claim known; removed on request" rather than public domain, and `no_recommend` keeps harmful recordings findable but unsuggested. I did not find a written "strongest case against" for Ear Drama or for plays with strangers (reporting and blocking exist, per PARITY.md).
*Question:* Who could be harmed by hearing, or being recorded in, a play, and what have you written about it?

## 13. The builder's own voice
The standing rule "no AI-written lists or copy in the product" is written down, and the web shows data-derived text. Device voices are labeled "Device voice" and never stored. The "In my words" lines in `HUMAN-SHAPED.md` are blank, which is correct. The home page copy comes from the catalog and its editors; I could not tell whose words each label is.
*Question:* Which words on screen are yours, and which did an agent write that you kept?

## 14. Credit everything
`credits/index.html` names data sources, Claude Code, and tools. It still holds OWNER comments (lines 21 to 22 and 68) asking you to add an opening and review a section. Recorded performers' credits appear as faces and names in D3-9.
*Question:* Who beyond the data sources and agents should be named, such as people who tested it?

## 15. Joy for at least one person
The web home page opens on a day of the year with a stacked chart of surviving broadcasts and star portraits, which reads as made with some affection. I could not tell whether anyone is glad of it.
*Question:* Who has enjoyed Ear Drama as it is today, and what were they doing when they did?

## What stood out
1. **The values reach the code.** The 2026-10-23 review's fixes (the device-voice rule, the privacy page, credits for agents) landed, which is principle 3 working in the open.
2. **Most of the claims are unplayed.** Most PARITY cells say "not seen on a device", so principle 7 is the largest open question.
3. **Your own voice is missing from the declaration.** The agent notes are thorough; the fifteen answers are still yours to write.

## One round to try next
Play one real evening on the apps yourself and write what you hear. *A starting point to rewrite in your own words:* "Play Tonight on the iPhone in the car and on the Apple TV, write down what I hear and where I get stuck, and send those notes as the next round."

## What only people can tell you
Whether the problem is real for someone else (1), whether the apps work for people who are not you (7, 12), whether the plays are safe and welcome for strangers (12), and whether anyone is glad of it (15). A classmate or a listener can answer these; I cannot.
