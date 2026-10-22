# How Ben builds

Source material for rewriting the teaching path (`docs/path/00` to `08`).
This is not a lesson. It is the record the lessons should be built from:
what Ben Wilkoff actually typed to Claude Code, what the agent did in
response, what Ben looked at to judge it, and where it went wrong.

Written 2026-09-30.

## Where this comes from, and how far to trust it

- **Ben's own prompts.** 612 prompts typed into Claude Code between
  2026-08-23 and 2026-09-30: 528 in Archive Watch and 84 in Tidbits
  Trivia. These are verbatim. Where this document cites a date and an
  app with no other note, the quote comes from this log. Typographic
  apostrophes are normalized; spelling and typos are kept.
- **Commit messages that quote him.** The template's standing rule is
  that a commit quotes the request that caused it, so the git histories
  carry Ben's words back to April. These are marked "(commit quote)".
  They are close to verbatim but the agent sometimes trimmed them with
  "..." and a few are paraphrases (an early one reads "User: build
  native iOS/Android/web versions..."). Treat them as his words, lightly
  edited.
- **The four git histories.** Archive Watch (4,298 commits, 2026-04-17
  to 2026-09-30), Tidbits Trivia (1,594 commits, 2026-06-16 to
  2026-09-10), BOBA Playbook (1,986 commits, 2026-04-03 to 2026-06-30),
  Bsky Dreams (170 commits, 2026-02-20 to 2026-06-30).
- **The memory folders** for Archive Watch and Tidbits Trivia, where the
  agent saved each correction with a "Why" line.
- **The full prompt history (added for section F).** Every prompt Ben
  typed into the Claude Code CLI on his Mac, verbatim and timestamped,
  from each app's first CLI day: Bsky Dreams from 2026-03-03, BOBA
  Playbook from 2026-04-03, Archive Watch from 2026-04-18, Tidbits
  Trivia from 2026-06-16. 3,218 of those prompts come from before
  2026-08-23, which is the period sections A to E could only see
  through commit quotes. Section F is built from them, and sections A
  to E have been corrected where they disagreed.
- **Ben's working notes (added for section G).** Apple Notes exports:
  one running note per app (Tidbits Trivia, Archive Watch, BOBA
  Playbook) and three single-prompt notes, where most of his long
  prompts were drafted before he pasted them. Section G matches them to
  the prompt history where it can. The notes also held credentials;
  none are reproduced.

One honest caveat before anything else. Ben's practice changed a great
deal between February and September. In the first weeks (Bsky Dreams,
early BOBA, the first weeks of Archive Watch) he committed by hand in
GitHub Desktop ("So much wow", "iOS updates", "Major fun times" are
real Bsky Dreams commit subjects), created Xcode projects and targets
himself, ran the simulator himself, built to his own iPhone from Xcode,
pasted Xcode compiler errors and console logs back into the chat one
message at a time, ran setup commands in the terminal himself, and
installed skill packs himself. Some of the very first sessions happened
on his phone or in Claude Code on the web, not at the Mac. By June he
had stopped doing most of that and was telling the agent to stop
asking him to. The "what Ben never did" section below describes his
mature practice, from roughly June onward, and says so where the early
record differs. Section F tells the early story in his own words.

---

## A. The loop Ben actually runs

Stated in one breath: Ben says what he wants, names where the truth
comes from, lets the agent build all of it, then lives with the app on
his own devices and tells the agent what he sees. When the agent gets
something wrong twice, he makes it write the lesson down. When a job is
big, he puts it on a timed loop and checks in on it. When it works, he
tells it to ship, and he expects shipping to need nothing from him.

The pieces, in detail.

### A1. How a project starts

Every project began with a wish, a real data source, and a template.
None began with a spec, a schema or a wireframe that Ben wrote by hand.
Two honest qualifications from the early record: BOBA began from
transition files and data he had built in a separate Claude Cowork
session, and Tidbits began from a 22-line brief he pasted in (its text
is lost; only the commit quote below survives). So "no spec" means no
spec he typed himself, not no preparation.

**Archive Watch, 2026-04-17.** The first session ran in Claude Code on
the web (the branch was named `claude/archive-org-apple-tv-5bKXB`), and
by his own account at least part of it on his phone. The next morning
at 07:11 he moved to the Mac: "I need to finish this up inside of claude
code CLI because you can do things that the desktop app cannot." The
first real commit was research, not code: "Add research docs for
metadata sources and design reference," documenting how to layer TMDb,
Wikidata, Commons and the Library of Congress on top of archive.org, and
synthesizing design patterns from the Apple TV app, UHF and Channels.
The next commit named the project, logged Decisions 006 to 010
(tvOS-only, TMDb non-commercial, no accounts, free release), and
scaffolded the networking. The day after that brought the data pipeline
and an editorial dashboard seeded with Ben's seven personal favorite
films. The Apple TV app only started to look like something on the third
day, when the catalog held 799 films.

**Tidbits Trivia, 2026-06-16.** Ben made the repository from the
template at 6:12 PM ("Initial commit" by bhwilkoff, with the
template's whole `.claude/` folder of skills and commands in it). By 8:01 PM the iOS app existed. The
kickoff prompt, as the first commit quotes it:

> "A fully realized multi-player trivia game based entirely upon facts
> pulled from the open Wikipedia API ... The final outcome of this
> session should be a working iOS version with all v1 versions of the
> features fully implemented." (Tidbits, 2026-06-16, commit quote)

Then, the same evening, three more prompts (the prompt log shows them
at 20:00, 20:41 and 22:57; two commits quote the last one):

> "Go ahead and commit and change my standing instruction to commit and
> the communicate rather than ask and then commit. Also, keep pushing
> forward with the next round of work to fully build out this game/app"
> (Tidbits, 2026-06-16 20:00)

> "Let's tackle the quality moat next" (Tidbits, 2026-06-16 20:41)

> "I thought I told you to commmit and push and then communicate about
> it. Please keeep pushing forward with the next set of work to build
> this app!" (Tidbits, 2026-06-16 22:57)

Those four prompts produced, in about five and a half hours: the iOS
app, a web mirror of it, a 10,006-question corpus built from Wikidata,
an Apple TV app, and an Android app. "ALL FOUR PLATFORMS PLAY," the last
commit of the night says.

**BOBA Playbook, 2026-04-03.** The first commits are "Cowork files" and
"Checklists and Game Rules." The card catalog (17,793 cards) arrived
from a separate Claude Cowork session, not from Ben typing. Ben did do
the setup by hand that first afternoon: he placed the data files, ran
`!brew install rclone` and a string of `! rclone` commands himself to
upload the card images, pasted service keys, and ran `! git push`. The
web app's Search Mode shipped the same day. Later BOBA work ran across
two AI surfaces with written handoffs (`COWORK_RETURN.md`, "Cowork
handoff for the gap").

**Bsky Dreams, 2026-02-20.** The very first commit is "Add learning
philosophy note and initial project scaffold." The values paragraph came
before any feature. The first eleven days ran in Claude Code on the web
(the commits are on `claude/` branches and Ben merged them as pull
requests); his CLI record starts 2026-03-03 with a working web app
already in hand. Work ran as numbered milestones (M1 to M65) written
into `SCRATCHPAD.md` by the agent from planning sessions, and Ben fed
them back one or two at a time ("Please complete the next two
milestones in terms of priority within the scratchpad document,"
2026-03-11).

**What he hands the agent at the start:**
1. A wish in plain language ("a fully realized multi-player trivia game").
2. A real source of truth (archive.org, the Wikipedia API, a card
   catalog, the Bluesky API).
3. The template, with its "Why we build" paragraph already in `CLAUDE.md`.
4. What "done for this session" means ("a working iOS version").

**What he does not hand it:** data rows, a file layout, a list of
screens, or code.

### A2. How data gets into the app

The agent builds a pipeline from the real source, and the pipeline runs
in GitHub Actions, not on Ben's Mac. Ben steers the data entirely by
judgment, in product words, and he steers it constantly.

Representative steering, in order:

> "add missing episodes to the queue of videos we are searching for."
> (Archive Watch, 2026-05-31, commit quote)

> "use our multiple APIs that we've been using to pull metadata ... to
> instead go the other direction and identify all of the titles that we
> should be searching archive.org for that are public domain or have
> otherwise lost their copyright." (Archive Watch, 2026-06-11, commit quote)

> "There should be thousands of documentaries. Why are you saying there
> are only 6?" (Archive Watch, 2026-07-19, commit quote)

> "The goal is not the most questions, but rather the best trivia
> questions anywhere. Are you auditing all of these and rewriting for
> interest and delight?" (Tidbits, recorded in memory `quality-over-volume-steer`)

> "Why would I want you to use a fallback number. We have a way to
> identify the power number from our ocr pipeline. ALL CARDS SHOULD BE
> correct based upon the image that they show in the app or the best
> data we have." (BOBA, 2026-05-15, commit quote)

> "I want all titles in the database to be accurate and to represent
> only the title." (Archive Watch, 2026-08-29)

> "I continue to find descriptions and other metadata that are not
> appropriate for the films and titles that they are attached to. [...]
> I want every piece of information within our app to be both accurate
> and unbiased." (Archive Watch, 2026-09-16, a /loop prompt)

And on where the pipeline runs:

> "I want to make sure that we are transitioning to the cloudflare
> workers entirely for the future. I'm okay to run more locally now, but
> the whole point is to make it so that the estimator and the data is
> getting better over time without being dependent upon my mac running."
> (BOBA, 2026-05-30, commit quote)

Ben finds data problems by using the app and by clicking one real item:

> "Why does https://archivewatch.org/item/shakedown-1950 have actors
> names in the title?" (Archive Watch, 2026-08-29)

> "Why is the name of this movie and the description different?
> https://archivewatch.org/item/the_last_three" (Archive Watch, 2026-09-02)

> "It is playing correctly now, but I do notice that 2 Stupid Dogs is a
> show from the 1990s, so how is it public domain? Are the rights
> clearing gates not working correctly?" (Archive Watch, 2026-09-06)

The pattern: one concrete item, then the demand to generalize. "Can you
look for this issue anywhere else in the app?" (2026-09-06). "Can you
audit for those types of errors within our process so these kinds of
errors don't occur?" (2026-06-10, commit quote).

### A3. How he reviews

Ben is the app's heaviest user. He reviews by using the real apps on
his own devices, from TestFlight, the stores, sideloads the agent put on
the device, and the live websites. He watches films on his TVs every
evening. He reports what he sees in plain words, often mid-use.

> "I actually watch on every device. I am constantly using and testing
> with each device, but it is now time to start working on problems that
> real users are seeing." (Archive Watch, 2026-09-11)

> "I'm doing some spot checks on both iPhone and Apple TV. I'm watching
> 'The Maggie'. On the Apple TV, neither the subtitle file nor the
> generated captions show at the correct times (both significantly
> delayed)." (Archive Watch, 2026-08-27)

> "I've been leaving the 'Party Play' going on my TVs to enjoy ambient
> videos as I work and I realized that I wanted three different features
> to be built into the view that don't currently exist" (Archive Watch, 2026-09-14)

> "I'm looking at the latest version of the iphone app and I don't see
> any way to share playlists" (Archive Watch, 2026-09-14)

> "Did you forget about the join button on the web platform? I still
> don't see it resolved from github pages." (Tidbits, 2026-09-07)

On 2026-09-06 he narrated a bug in real time from the couch, while the
agent instrumented the Apple TV: "The audio just went out on the video
that is playing now." (20:24), "The movie playing now just lost audio"
(20:35), "Audio went out." (20:46), "Audio just went out again."
(20:49), and a dozen more over the next two hours, ending "The full movie played
without audio lost" (22:24) and then, when the fix was a workaround,
"That is not a solution" (22:30).

He also routes other people's eyes into the loop:

- Testers: "some of my testers have noticed significant issues within
  the Tidbits Trivia tvOS app" (Tidbits, 2026-08-24).
- Real users in public: "I posted about the app with links to all of the
  platforms on Reddit yesterday [...] I'd like you to use the
  comments/feedback from the users on this post to identify issues that
  need to be solved across all platforms." (Archive Watch, 2026-09-11)
- A user's message: "I just got this feedback for the fire tv version:
  'I tried to install on a firestick but it said all 3 of my devices
  were incompatible.'" (Archive Watch, 2026-09-10)
- Community exports: BOBA's loop mined Discord exports for
  user-requested features (BOBA, 2026-05-20).

What changed over time is who does the checking between his spot
checks. By August he refused to be the tester:

> "You should be able to see stuttering and swallowed audio. You should
> be able to see the captions and measure their timing and their
> accuracy... I should not be the one testing your work." (Archive
> Watch, 2026-08-14, commit quote)

> "you're guessing, build a simulator so you can iterate locally instead
> of making me test every tweak." (BOBA, 2026-05-16, commit quote)

So the review loop has two layers: the agent proves its work on real
devices with its own instruments, and Ben lives with the result and
reports what the instruments missed.

In the early months the first layer did not exist, and Ben was the
instrument. He reviewed in the tvOS simulator ("I still cannot go
"back" to the home view of the app once I'm looking at an individual
title. Pressing the "back button" (escape on the simulator)...", AW,
2026-04-19), on his own iPhone built from Xcode ("I'm using my iPhone 15
Pro for testing," BOBA, 2026-04-03), in mobile Safari and as a
home-screen web app ("when I add the web app to my homescreen on my
iphone and then launch it, I get a github 404 page," BOBA, 2026-04-03),
and on the live web app ("I'm testing on the web, which is the easiest
way for me to see the progress," Tidbits, 2026-06-17). He ran the tests
the agent wrote and pasted back the results and console logs ("Here are
the test results: [Pasted text #1 +27 lines]", Bsky, 2026-03-18). The
demand that the agent test its own work comes from these weeks: see F2,
stage 04.

### A4. How feedback rounds work

Two shapes.

**The numbered batch.** After a stretch of use, Ben sends a long
numbered list. The agent works through it, usually on a loop, and the
commits cite the item numbers. Examples:

- Roku, 2026-09-05: twenty numbered items, beginning "1. There are more
  animated movies/videos in the hero row than I would like. At most,
  there should only be one animated feature. 2. There are multiple
  shelves that only have 4 or 5 items. No shelf should display as less
  than a full row. 3. The same shelves should show up across all
  platforms."
- Roku, 2026-09-06: ten more ("More feedback for the Roku app:").
- Android TV, 2026-09-03: six items, ending "Please make use of the full
  suite of devices you have access to in order to build out and test all
  of these features."
- Mac Watch Together Studio, 2026-09-22: six items, beginning "Alright,
  the Watch Together Studio doesn't seem to work as it should."
- Archive Watch v1, 2026-06-03: "the 20 requested items," which the
  agent turned into a phased plan before building (commit "App Store v1
  roadmap (phased backlog of the 20 requested items)").

**The one-liner during use.** Short corrections while he is looking at
the screen: "The pills for the TV page start off by saying 'All films'
instead of 'All TV'." (2026-09-06). "It seems like ephemeral films
carries a single title" (2026-09-27). "Dollar store / dollar store
killers made it through to the Xtreme feed." (2026-09-27).

The April record shows the same rhythm from the first week: Archive
Watch commit subjects on 2026-04-19 run "UI feedback pass", "UI feedback
round 2", "round 3", "round 4", "UI round 5", "UI round 6", all in one
day, each a batch of what Ben saw in the tvOS simulator. The prompt log
has the batches themselves: ten numbered items at 07:37, ten at 08:17,
seven at 09:00. In Bsky Dreams and BOBA most early batches were written
somewhere else and pasted in, so the log shows only "Please update the
iOS app for the following pieces of feedback: [Pasted text #1 +10
lines]"; the items themselves are lost.

A third shape appears early and then fades: **answering the agent's
questions at a milestone boundary.** "Great. Let's begin on M2. Do you
have any question at the beginning of this milestone that are
unanswered by the current documentation?" (BOBA, 2026-04-03), followed
eight minutes later by four numbered answers. By September the same move
had become "Can you ask me the owner items as a series of questions
where I can see the options and choose from among them?"

### A5. How he corrects

Directly, with the reason, and usually by pointing at something that
already works: a native API, another app, a documented path, or a
previous success.

> "NO CUSTOM OVERLAYS... You can do this if every other video app on the
> market can do subtitles with the ability to skip. This is native
> functionality. Search better through the APIs." (Archive Watch,
> 2026-06-22, recorded in memory)

> "The automatic captions should NOT run 1-2 seconds behind speech. The
> whole point of the automatic captions API is that there is no delay.
> [...] you are claiming that it is structural transcription lag, but
> that isn't true. Do more research to see the right way to ensure this
> delay doesn't happen." (Archive Watch, 2026-08-27)

> "I just confirmed. The audio went out on the TV speakers as well. It
> ISN'T Airplay. Please stop guessing and figure out the issue."
> (Archive Watch, 2026-09-06)

> "You keep on saying (for many different sessions) that AirPlay doesn't
> work, but it does work. And it is documented." (Archive Watch, 2026-08-31)

> "You are absolutely wrong about not being able to submit a new version
> to the Google play console. That is a proven path and all versions are
> submitted by api" (Archive Watch, 2026-09-03)

> "You need to re-read the repository if you think we don't have a
> privacy policy. We have one and have had one for months." (Archive
> Watch, 2026-09-08)

> "Apple, Google, and Microsoft have NO WAY TO KNOW what has been
> submitted to each other's stores. The IAPs are all different for each
> different store, so there is literally no reason to publish them one
> after the other. Where is that idea coming from, as it is severely
> wrong." (Tidbits, 2026-08-31)

He also corrects the agent's claims, not just its code:

> "I am so so frustrated with you telling me things are fixed and
> working and what you can and cannot do on each platform." (Archive
> Watch, 2026-08-27)

> "This version is a huge step backward and you keep claiming things are
> fixed and you have fully tested them, but I see no evidence of
> either." (Archive Watch, 2026-08-14, commit quote)

And the agent's process:

> "I feel like we had solved all of this so so long ago as we were
> building the last resilient player for apple's platforms. Are we
> redoing work that has already been done and is documented already?"
> (Archive Watch, 2026-09-07)

> "This is insane. You have direct connections to each apple tv. You
> have documentation for how to do and it the connections are right
> there. There is no reason you can't connect." (Archive Watch, 2026-09-24)

### A6. How rules get written down

A correction that could recur becomes a written rule, and Ben asks for
that explicitly when the agent does not do it on its own.

> "Can you make a memory so that after every tick when you re-arm the
> loop, you give a time when the next tick should occur?" (Archive
> Watch, 2026-08-29)

> "If you are low on context, compact. Can't you simply add that as a
> rule?" (Tidbits, 2026-08-01, commit quote)

> "You have found significant issues in every tick and have still not
> developed rules to stop from seeing poorly written questions,
> distractors, or poor examples of gameplay." (Tidbits, 2026-08-01, commit quote)

> "I thought we had a standing rule to use US-specific english spelling
> and language." (Archive Watch, 2026-09-22, recorded in memory; there
> was no such rule, so the agent wrote one and a test for it)

Where the rules land, from the records:

- **Memories** (the auto-memory folder). Archive Watch has about 180
  files; the "Standing rules (owner directives)" section of its index
  lists rules like "Real devices only, never emulators," "Ship Apple
  releases WITHOUT asking," "Report times in Mountain time, never UTC,"
  "Audits fix everything found, don't ask." Each carries Ben's quote and
  the date.
- **`CLAUDE.md` standing instructions.** The no-AI-copy rule and the
  side-doors rule went here on 2026-09-26.
- **Decisions.** Product calls he makes become numbered decisions (the
  six he answered on 2026-09-25 became Decisions 139 onward; "hidden from
  recommendations, but available via search" became Decision 149).
- **Binding design docs.** "Everything in a menu" became macOS-DESIGN
  §B2; "Join must be obvious" became R-JOIN-1 in iOS-DESIGN.
- **Skills and the template.** Recurring lessons go upstream (A13).

### A7. When he asks for research first

Whenever the thing is new to the project, whenever a fix has failed
twice, or whenever the agent says something is impossible.

New capability:

> "Can you investigate the ability for the Apple versions of the app to
> take advantage of SharePlay and synchronous viewing of movies together
> using Apple's API's and version 27 platform features?" (Archive
> Watch, 2026-08-31)

> "Can you research the feasibility of creating a version of Tidbits
> Trivia as an iMessage game that you could play in a direct iMessage
> conversation or even in a group conversation?" (Tidbits, 2026-09-01)

> "I'd like you to start researching (and then implementing) offline
> viewing/downloading movies" (Archive Watch, 2026-09-01)

> "Is there anything we can learn from the site or features that would
> complement Archive Watch? Can you fully research the site and its
> features and write up a list of features to further build out our
> functionality" (Archive Watch, 2026-09-26, about orphanedfilms.com)

Stuck fixes:

> "There have to be better ways of doing this audio routing and syncing.
> Can you do some more research before we continue to burn cycles on
> this?" (Archive Watch, 2026-09-18, commit quote)

> "You are doing fixes and reversions without researching the right way
> to solve for these in lasting and sustainable ways... Do the full
> research. Learn what the best practices are. [...] We are not on the
> prototyping stage. We are building large-scale working software that
> needs to be best in class." (Archive Watch, 2026-08-17, recorded in memory)

Refused limits:

> "That cannot be the way in which you have to get API access enabled.
> Amazon is a huge company and there is no way that they require every
> developer to ask for API access. You need to keep looking for ways to
> do this" (Archive Watch, 2026-08-31)

> "You keep on saying that Google's export is broken, but it doesn't
> make any sense. The data exists. [...] You cannot stop at 'the old way
> doesn't work, so I will just wait until it does again'." (Archive
> Watch, 2026-09-14)

The research-first request almost always converts to "fully implement"
in the next message once the answer is yes: SharePlay went from
"investigate" (2026-08-31 20:38) to "I'd like you to fully implement
SharePlay for all Apple platforms" (20:45); iMessage went from
"research the feasibility" (2026-09-01 00:22) to "Please fully build out
and enable a tidbits trivia iMessages app and prepare the App Store
Connect settings to submit for review" (00:32).

### A8. Loops, and at what cadence

Ben uses `/loop` for any scope too big for one sitting: a device test
campaign, a platform buildout, a data audit, a design polish pass, a
parity sweep. The loop prompt states the goal and the stopping
condition, and he expects it to run for hours or days.

> "Please utilize an autonomous loop to continue working hard on this
> problem over multiple hours and across many different sessions. Each
> individual session should do significant work and not simply run for 5
> minutes and report a single bug being fixed." (Tidbits, 2026-08-24)

> "/loop let's start with some robust testing on the iPhone 12 to ensure
> that everything is working as it should. [...] Please make a
> systematic list and then run through it to check everything. Don't
> stop until you have completed the full list." (Archive Watch, 2026-08-28)

> "I want you to keep fixing things until everything is green on this
> chart. That is why I set it up as a loop rather than a single task."
> (Tidbits, 2026-08-31)

> "/loop implement all documented enhancements from Orphaned Films that
> fit within our Archive Watch approach." (Archive Watch, 2026-09-26)

**Cadence.** Five minutes is the default, set as a rule on 2026-09-17
("The loop should be 5 minutes, as that should be the default for all
loops"). He moves it deliberately: "Let's set the wakeup at 10 minutes
for this loop." (2026-09-03); "You can move the loop cadence to 30
minutes instead of 5" (2026-09-07); "We aren't getting enough done.
Please make the tick wakeups 5 minutes instead of 30." (2026-09-11).

**What he demands of each tick.**
- Real work: "I keep on seeing these completely inconsequential ticks. I
  need large scopes of work to be completed during each loop."
  (Tidbits, 2026-08-25) and "It is so frustrating to see that all you
  are doing for a single tick is letting a movie run on its own while
  you are doing nothing and measuring nothing and fixing nothing."
  (Archive Watch, 2026-08-26)
- New work, not the same check again: "Are we actually doing something
  new in each of these laps? Or, are we just checking the same things
  over and over?" (Tidbits, 2026-08-25)
- A visible report: "Please keep going and keep telling me what you are
  doing as you are doing it so that I can keep track." (Archive Watch,
  2026-08-26) and "I need you to always write down when the next tick
  should begin so I can determine if you are actually doing it"
  (Archive Watch, 2026-09-04)
- Focus on the loop's stated platform: "Please stop working on the Apple
  TV. The ga is full capabilities on Roku." (Archive Watch, 2026-09-05)

**Stopping.** He stops loops that have run out of real work, and asks
for a summary: "Stop the loop until you can tell me what you are
actually doing with it." (Tidbits, 2026-08-26). "Seems like you are just
waiting on App Store review. Do we need to keep the loop armed just for
that?" (Archive Watch, 2026-09-14). "Stop the loop and summarize all
work completed during the full loop as well as outstanding things that
need my input." (Archive Watch, 2026-09-24). "Go ahead and do that,
finish up any documented work from the loop, and then close the loop."
(Archive Watch, 2026-09-12).

**Checking the loop is alive.** A large share of his short prompts are
about the loop's health: "The loop doesn't seem to be firing"
(Tidbits, 2026-09-02), "It seems like the loop stopped last night for
some reason." (Archive Watch, 2026-09-04), "You didn't wake up"
(2026-09-06), "Is the loop still armed?" (2026-09-25).

### A9. How a new platform gets started

Every new platform followed the same arc: Ben decides it is time (often
because he bought or plugged in a device), asks for research and a test
rig, has the agent build to parity against the best existing platform on
a loop, reviews it on the glass, sends a design critique, and then says
ship.

> "build native iOS/Android/web versions of every tvOS feature using the
> TriAppTemplate as the basis" (Archive Watch, 2026-06-09, commit
> paraphrase; the commit adds that each should be fully native per
> platform, with a full parity matrix)

> "a lot of the instructions in the readme ... seem like things that you
> can do programatically rather than having me do them in Xcode"
> (Archive Watch, 2026-06-23, commit quote, starting the Mac app)

> "research the best ways to develop for each platform, keeping our
> rules about native-app design and making sure that every platform is
> treated as a first-class experience ... write a thorough backlog of
> every implementation ... outlining any place where I have to complete
> steps in order to publish" (Archive Watch, 2026-08-03, commit quote, TV platforms)

> "I have purchased a Fire TV 4k and a Google TV streamer that are
> connected on my network right now. Can you research the ability to do
> the same kind of autonomous development that you have been able to do
> with the Apple TV on these kinds of devices? I would like to strive
> for parity to the Apple TV app and right now the Google TV
> implementation is not even close to as robust." (Archive Watch, 2026-08-27)

> "it is finally time to start the next major platform for Archive
> Watch: Roku ... make Roku as a first-class platform." (Archive Watch,
> 2026-09-03, commit quote)

> "I have access to Samsung TVs, so let's start building for that
> platform. We will need full parity ... for all features available on
> Roku, Apple TV, and Google TV." (Archive Watch, 2026-09-09, commit quote)

> "I have a windows 10 machine that is connected to the network that I
> would like to start using for development. Can you start building the
> tooling and harnesses necessary to install and interate upon the
> windows app as you have done for the other device types" (Tidbits, 2026-08-31)

The dates, from the git histories:

- Archive Watch: Apple TV 2026-04-17 alone for seven weeks (tvOS v1 went
  to App Store review in early June); iPhone/iPad, web and Android plan
  and start 2026-06-09; Mac 2026-06-23; TV-platform research 2026-08-03;
  Google TV parity push 2026-08-27; Fire TV 2026-08-28 to 2026-08-31;
  Roku 2026-09-03; Samsung 2026-09-09.
- Tidbits: iOS, web, Apple TV and Android all 2026-06-16; TestFlight
  2026-06-19; Google Play 2026-06-30; Mac 2026-07-03; Windows research
  and scaffold 2026-07-05; Android TV 2026-08-29; iMessage 2026-09-01.
- BOBA: web and iOS in the first week of April; Android 2026-05-19.

### A10. How shipping is asked for

Short, and increasingly without any expectation of doing a step
himself.

> "You can ship the new versions now." (Archive Watch, 2026-08-29)

> "Ship every platform" (Tidbits, 2026-09-03)

> "Fix everything and submit a build with the Google TV included.
> There's no reason to wait for me on any of this." (Tidbits, 2026-08-30)

> "I want it all fixed, fully tested, and a new version pushed to the
> App Store." (Archive Watch, 2026-09-06)

> "I want everything pushed to the production tracks and not just
> submitted, fyi" (Archive Watch, 2026-09-25, from a session summary)

He also polices what counts as a release:

> "Let's hold off on submitting new apple versions because of such a
> small change." (Archive Watch, 2026-09-16)

> "The what's new text should be different by platform because the
> features are different." (Archive Watch, 2026-09-29)

> "Are you introducing the strange line breaks in the markdown file
> rather than having it flow as fully rendered text? I really don't want
> to have to remove strange formatting every time I want to submit to
> the app store that shows that it was AI generated." (Archive Watch, 2026-09-01)

Store rejections and console alerts get pasted in whole, and the agent
is expected to diagnose and resubmit: the Google Play "Broken
Functionality" rejection (2026-08-29), the Play Billing 8 deadline
(2026-08-27), Roku deep-link failures from email ("read through my
email, diagnose the problem, fix it, and then re-submit for approval
using chrome", 2026-09-17).

### A11. How he handles CI and alerts

Failure emails are the signal. He forwards them and expects the class
of failure to end, not just the run.

> "Can you both clean up the decisions document to make it more context
> friendly [...] AND look into all of the failures happening on github
> actions from this repository?" (Archive Watch, 2026-08-23)

> "I want to stop getting alerts for failed GitHub actions. Can you fix
> it so that if it isn't broken, it doesn't fail?" (Archive Watch, 2026-08-23)

> "Fix everything. I don't want you to ask me. Just fix it." (Archive
> Watch, 2026-08-23)

> "Another workflow failed this morning and sent an issue email:
> https://github.com/bhwilkoff/Archive-Watch/actions/runs/32704327235/job/97362127993"
> (Archive Watch, 2026-08-24)

> "Can you confidently say that I will not receive another error from
> GitHub for any of the workflows we have for Archive Watch?" (Archive
> Watch, 2026-08-24)

> "We've been over this before. I shouldn't receive a failure alert for a
> non-failure status. Please fix all workflows/actions so that they don't
> fail if there is no failure state." (Archive Watch, 2026-09-09)

> "Can you make sure that you are checking on GitHub failures for these
> ticks? I keep getting error emails as you 'fix and build'" (Tidbits, 2026-09-01)

> "shouldnt warnings be fixed instead of ignored?" (Archive Watch, 2026-09-29)

The reverse matters to him as much: a pipeline that fails silently is
worse than a loud one. "Yes. I want these to work every time and fail
loudly if they don't so we can fix it." (Archive Watch, 2026-09-12,
about the social posting pipelines). And: "without a loop, you aren't
waking up to check anything about whether or not the workflows are
actually functioning." (Archive Watch, 2026-08-12, commit quote), which
produced the workflow health auditor.

### A12. How he uses Pulse

Pulse exists because Ben wanted one page instead of nine consoles.

> "a single place for me to go in order to understand what our users are
> enjoying or requesting of the app AND to understand the performance of
> the various platform's apps." (Archive Watch, 2026-09-09, commit quote)

He uses it the way he uses the apps: he reads it, spots what is wrong,
and asks for fixes and more depth.

> "Can you use this page to identify all of the crashes and other issues
> that need to be addressed. Additionally, all reviews that have been
> responded to should not show up under the 'needs you' section."
> (Archive Watch, 2026-09-09)

> "Did you fix the 'Needs You' item yet? If you have, then you should
> remove it from the pulse site." (Archive Watch, 2026-09-09)

> "Keep going until Pulse is fully developed for all audiences and has
> the full granularity of their individual dashboards within their
> individual systems. The whole point of Pulse is that I never have to go
> into the individual dashboards to find out information about how the
> app is doing or being used." (Archive Watch, 2026-09-14)

> "I don't see the data represented on the different areas of Pulse (No
> macOS or Roku items on Reach)." (Archive Watch, 2026-09-14)

> "Take a look at 'Needs Attention' section of the Archive Watch Pulse and
> see what you can directly address and solve for?" (Archive Watch, 2026-09-25)

He also keeps Pulse inside his values: "We are building a $0 platform.
Pennies a month still does not fit" (2026-09-14, commit quote), and asks
whether per-title viewing can be counted "since it is all anonymous"
(2026-09-14).

### A13. How he upstreams to the template

Lessons are expected to leave the app they were learned in, in both
directions: across sibling apps, and up into the template.

> "I'd like you to create a new repository for Universal App
> Development, where we continue to add new learning from the app
> development on our discreet apps (Archive Watch, Tidbits Trivia, Bsky
> Dreams, BOBA Playbook, etc.). [...] I would like to start iterating on
> a Universal App Template that will continue to incorporate all new
> findings, harnesses, and lessons learned for how I like to develop
> software." (Archive Watch, 2026-08-24)

> "Please add all of the lessons we have learned since the beginning of
> app development on Tidbits Trivia and you should further document and
> build out the Universal App Template so that it can be used by anyone
> who would like to develop software with the same values-based approach
> that I do." (Tidbits, 2026-08-24)

> "Can you learn all you can from the harnesses we've built to do
> autonomous loops of testing on real hardware for the Bedroom Apple TV,
> iPad 12.9, iPhone 12, Android TV/Fire TV, and Android Pixel 8a for the
> Archive Watch repository?" (Tidbits, 2026-08-29)

> "Can you learn from the Tidbits Trivia repository for how to submit to
> the Apple App Store fully via api instead of me having to create a new
> release manually as I have been doing for Archive Watch." (Archive
> Watch, 2026-09-03)

> "I'd like you to solve for any of these problems you have already
> identified then I'd like you to document our process and the recent
> development full within this repository and then make sure you are
> contributing all of the necessary skills, harnesses, and tooling back
> to the Universal App Template" (Archive Watch, 2026-09-09)

The template itself is the sixth generation: Tri, Quad, Quint, then
Universal (memory `universal_app_template`). Each earlier generation was
a fork that added one more platform.

### A14. How he keeps the agent's memory usable

He manages context as an operational concern, in plain words.

> "Document everything for compacting" (Tidbits, 2026-08-25)

> "Document anything you might need for a future session. I'm going to
> restart my computer." (Archive Watch, 2026-08-31)

> "We are close to needing to compact, please document everything we
> might need before I do that." (Archive Watch, 2026-09-17)

> "Let's get our context and documentation in order so that it isn't
> costing us on tokens every time we try to do something." (Archive
> Watch, 2026-09-14)

> "Document anything we will need to resume the loop after I update
> Claude and move to the new opus model for this work." (Archive Watch,
> 2026-09-23, commit quote)

---

## B. Phase by phase

Each stage of the course, mapped to what Ben actually did.

### 00. Values and why

**What Ben did, in order.**
1. Put the values paragraph in the repository before any feature
   (Bsky Dreams' first commit, 2026-02-20: "Add learning philosophy
   note"). Every template since carries it at the top of `CLAUDE.md`.
2. Did not write further rules in advance. He stated values as product
   rules at the moment the agent made a choice that crossed one, and
   then had them written down.

**Verbatim.**

> "I don't want AI making lists and writing copy. Any time we can use
> metadata or user copy/categorization from archive.org." (Archive
> Watch, 2026-09-26)

> "It is absolutely not acceptable. The goal of this app (and all of my
> apps) is for them to cost $0 to run." (Archive Watch, 2026-09-20)

> "We cannot have copy written work on the app, so you need to audit and
> get rid of anything that we know is still under copyright." (Archive
> Watch, 2026-09-06)

> "the whole point of Tidbits Trivia is that we are the world's best
> trivia app with the least amount behind a paywall." (Tidbits,
> 2026-07-29, recorded in memory `club-one-door-rule`)

> "It seems like a very good platform to build out for Tidnits,
> especially as we seek to create a positive habit for learning via
> trivia." (Tidbits, 2026-09-01)

> "Streaming a movie on your own serves no purpose, as the movie on its
> own is already available via archive.org and streaming it without a
> camera or microphone only puts another copy online with no additional
> value being added." (Archive Watch, 2026-09-24)

> "It must also be designed well and create genuine opportunities for
> connection for all involved." (Archive Watch, 2026-09-23, loop prompt)

**What the agent did.** Turned each into a standing instruction, a
memory, a decision, and where possible a test (US English got
`tools/test_us_english.py`).

**What Ben looked at.** The product: an AI-sounding blurb, a copyrighted
title on a shelf, a proposed paid relay, a caption that explained too
much ("You and I are having a conversation, but not everything I say or
what you discover needs to be listed in the interface," 2026-09-22).

**What went wrong.** Values were enforced after the fact, because they
were not written where the agent reads them at the moment of choice. The
paid relay for Watch Together voice got designed before the "$0" rule
stopped it. The fix was his reframing: "I mean, calling services like
Google Meet, Zoom, Phone Calling or other services that every device has
if we wanted to separate out the calling part from the movie playing,
syncing, and streaming to youtube." (2026-09-20).

### 01. First prototype

**What Ben did, in order.**
1. Stated the wish and the source (A1).
2. Let the agent do research and set up the pipeline first (Archive
   Watch) or build the whole first platform in one session (Tidbits).
3. Ran the first build on a real device or the simulator and sent
   rounds of feedback the same day.
4. Pushed immediately to "the next round" rather than polishing.

**Verbatim.**

> "A fully realized multi-player trivia game based entirely upon facts
> pulled from the open Wikipedia API ... The final outcome of this
> session should be a working iOS version with all v1 versions of the
> features fully implemented." (Tidbits, 2026-06-16, commit quote)

> "keep pushing forward with the next round of work to fully build out
> this game/app" (Tidbits, 2026-06-16, commit quote)

> "a much more diverse way to ask questions ... 'is best described'
> should only show up sparingly when we have dozens of different ways
> ... a default way to write the distractors/right answers (you can
> figure out the right answer)." (Tidbits, 2026-06-17, commit quote)

> "I still see mostly the same kinds of questions ... and the exact same
> questions showing up multiple times across different categories."
> (Tidbits, 2026-06-17, commit quote)

> "arrow keys let you escape the movie view" (Archive Watch, 2026-04-19,
> commit quote)

> "old style sidebar is still there + entire app unusable" (Archive
> Watch, 2026-04-19, commit quote)

**What the agent did.** Archive Watch: metadata research, a Node catalog
builder, an editorial dashboard that doubled as a pipeline validator,
799 real films by day three, then six UI feedback rounds in one day.
Tidbits: an iOS app with a question engine and a real 8,889-question
corpus in two hours, then web, Wikidata, Apple TV, Android.

**What Ben looked at.** The running app with real content in it. The
first Tidbits corrections are about the content itself (question
variety, guessable distractors), which only real data could expose.

**What went wrong.** Archive Watch's first week fought the tvOS focus
engine with a custom sidebar; commits on 2026-04-19 flip between
"restore forced initial focus," "stop fighting the tvOS focus engine,"
and finally "Switch to native tvOS 26 sidebar." The lesson became
`tvos-platform-patterns` and the project `tvos-playbook.md`. Also, the
early scratchpad gave Ben manual steps ("Create Xcode tvOS project at
repo root"), which he did then and objected to later (see D).

### 02. Shape: data plane and parity

**What Ben did, in order.**
1. Asked for parity as the default, across every platform, with a
   matrix.
2. Picked a reference platform whose choices win ("I prefer the order
   and titles of the Apple TV app").
3. Asked for parity audits when he suspected drift.
4. Made the web domain the canonical link target for every share.

**Verbatim.**

> "continue working on our parity matrix across all platforms to make
> sure we can launch on all platforms with the same features across the
> board" (Archive Watch, 2026-06-10, commit quote)

> "continue with your parity work and audit all features to ensure we
> have identified all of the items that should go in the parity
> matrix." (Archive Watch, 2026-06-10, commit quote)

> "Go ahead and do all of them autonomously." (Archive Watch,
> 2026-06-10, commit quote)

> "I would like the share functions inside each one of the apps (apple
> tv qr codes, iOS sharing links, etc.) to share the archivewatch.org
> links rather than the archive.org links. I also think that the web app
> should redirect to the native apps if you click on them on your
> phone/iPad/android." (Archive Watch, 2026-06-10, commit quote)

> "the shelves across platforms should have the same titles + order... I
> prefer the order and titles of the Apple TV app (replicate
> everywhere)." (Archive Watch, 2026-06-29, commit quote)

> "As much as possible, please always ensure web parity." (BOBA,
> 2026-05-18, commit quote)

> "Ensure that all platforms can join one another's game nights."
> (Tidbits, 2026-08-30, commit quote)

> "Make sure you are documenting full parity as well and making sure
> anything we can have cross-platform, that we do have it." (Archive
> Watch, 2026-09-26, from a session summary)

**What the agent did.** Wrote `PARITY.md`, the data contract, and the
multi-platform plan; moved shelf membership, rights, and "hero-safe"
flags into the pipeline so every client reads the same answer; wrote
parity tests that read the Swift, Kotlin and web sources and compare.

**What Ben looked at.** The same screen on two devices: "The same
shelves should show up across all platforms. Let's make sure that they
are syncing up correctly." (Roku feedback, 2026-09-05).

**What went wrong.** Parity cells lied. BOBA's loop found "Saved
Searches falsely claimed ✅✅ on iOS+web" with zero references in any
client (2026-05-20). Tidbits ran a parity audit on 2026-06-30 whose
commit subject says it corrected false cells between Android and Apple. A shared type is not a shared code
path (Archive Watch Decision 133). Ben's own catch: "Is the 'Join a
Room' feature on the library section available in the currently live
1.42.699 version on Google Play?" (2026-09-30). The correction in every
case was an audit that reads the code, not the matrix.

### 03. Native platforms and floors

**What Ben did, in order.**
1. Insisted each platform feel native to its own people, and called out
   stretched or borrowed designs.
2. Pointed at the platform's own conventions (menus on Mac, touch on
   iPad, the remote on TV).
3. Bought or dug out older hardware to set floors, and asked for a split
   between legacy and modern rather than holding the modern back.
4. Anchored on the newest OS for everything the newest devices can do.

**Verbatim.**

> "We are on iOS 26/27. Let's anchor on that, not iOS 18." (Archive
> Watch, 2026-06-15, commit quote)

> "The iPad should not just be a blown up version of the phone, but
> rather a distinct and first class experience." (Archive Watch,
> 2026-08-28, commit quote)

> "Yes. Each platform should feel like a first class native experience."
> (Tidbits, 2026-08-30)

> "within the MacOS native app, nearly everything in the app should be
> accessible via menus and hardly anything is. That is the design for
> desktop-class apps and it should be so for ours as well." (Tidbits,
> 2026-09-08)

> "Most iPad users do not use a keyboard at all, so the up-and-down
> arrows control for the channels will be entirely lost on them."
> (Archive Watch, 2026-09-28)

> "I have an iPhone 12 that I'd like to use for testing on older
> devices." (Archive Watch, 2026-08-28)

> "I was able to get developer mode to work on the box. It is
> restarting. I think there are ways of making it thinner for older
> hardware, right? If the videos can run on a web browser, surely they
> can run on old hardware." (Archive Watch, 2026-09-12, Roku 2 XD)

> "I do want to make sure that we are able to split the code for the
> legacy devices and modern devices. There is no reason to do a bunch of
> work pushing the platform on for modern Roku users if it is going to
> be hamstrung by the older devices that are mostly stuck in 2014."
> (Archive Watch, 2026-09-11, commit quote)

**What the agent did.** Built each shell in its native toolkit, wrote a
binding design doc per platform, measured floors by test-building at
candidate deployment targets, and split Roku into a legacy and a modern
tier.

**What Ben looked at.** The app on the actual device class. The Samsung
critique is the clearest record of what he checks:

> "I'm testing it on the glass, and there are a ton of things broken.
> [...] You have been trying to use the web app as the basis for this
> version of the app, but you are not designing for this platform at
> all. You are designing for a web browser that you have full control
> over. A tv interface has none of the nuance of a full-fledged web
> browser. The buttons should be tv sized. [...] We are far from
> releasing anything on this platform." (Archive Watch, 2026-09-10)

**What went wrong.** Platforms reused another platform's design (Samsung
from the web, the iPad from the phone, Tidbits' Mac Live screens from
"stock controls"); the Roku looked "incredibly boxy and rudimentary and
not as if a professional designer actually put it together"
(2026-09-04). The correction was an adversarial design pass per surface,
research into the platform's own patterns, and a design-doc rule written
first. One rule inverted by mistake had to be reversed by Ben: "We were
trying to ban the plain looking text controls and not the chunky good
looking design elements." (Tidbits, 2026-09-08, recorded in memory).

### 04. Seeing it work on devices

**What Ben did, in order.**
1. Bought and connected devices (Apple TVs in three rooms plus an Apple
   TV HD, a Fire TV, a Google TV streamer, a Pixel 8a, an iPhone 12, an
   iPad Pro, two Rokus including a 2011 Roku 2 XD, a Samsung TV, a
   Windows 10 PC).
2. Did the physical steps only a person can: developer mode, pairing
   codes, unlocking, plugging in.
3. Told the agent to test on those devices itself, never simulators.
4. Corrected the agent's manners on devices people in his house use.
5. Kept doing his own spot checks.

**Verbatim, device setup.**

> "I have enabled that for the iPad, but because the iPad is on iPadOS
> 27, you can use the Device Hub to control the screen as well"
> (Archive Watch, 2026-08-28)

> "I don't want to have to unlock the phone every time you need to check
> something. Figure out how to make it work with you unlocking the
> phone." (Archive Watch, 2026-08-28)

> "My device pairing code for the Google tv is [six digits]" (Archive Watch, 2026-08-27)

> "I've got a Pixel 8a with wireless debugging enabled. Can you connect
> to it now or do you need me to do the pairing code? The code is
> [six digits]" (Archive Watch, 2026-08-28)

**Verbatim, the standard.**

> "Do not use emulators. You have access to real devices." (Archive
> Watch, 2026-09-03, recorded in memory)

> "You should not be using simulators. You have access to real devices."
> (Tidbits, 2026-09-09, recorded in memory)

> "I really need captions to work on every device the the best of what
> is possible on that device. And more than that, I need when you tell
> me that things are working on a device, that they are actually
> working." (Archive Watch, 2026-08-27)

> "I don't understand why you can't push up and down keys on devices
> that you control. That shouldn't be an issue. If you can't press them,
> then it doesn't work." (Archive Watch, 2026-09-29)

> "You shouldn't have intermittent failures for the same harness. You
> should be able to investigate from end to end and find the expected
> results to be the same every time." (Archive Watch, 2026-09-24, commit quote)

**Verbatim, manners.**

> "Is there a reason why there is a movie playing in the background on
> my mac?" (Archive Watch, 2026-08-27)

> "How about you check the the Fireplace TV is actually on before you
> send a command to it?" (Archive Watch, 2026-09-28)

> "please make sure that you are using the shared devices with the
> check-in/check-out because they are shared with the Tidbits Trivia
> claude code session" (Archive Watch, 2026-08-31)

**What the agent did.** Built the observation rigs: screenshots of the
real screen read with on-device OCR, pyatv remote presses, adb, env-var
"doors" that open any screen, a device lease so two sessions do not
fight, teardown that asks the device what is still running.

**What Ben looked at.** The same screens, from the couch, plus the
agent's evidence when it offered some.

**What went wrong.** Almost everything a rig can do wrong, it did once:
tested the same film over and over ("Why are you continuing to test 'his
girlfriend Friday'?", 2026-08-26), tested captions on a foreign-language
film and audio on a silent one ("I wish you would stop doing that. It
makes it look like an error every time you do.", 2026-09-22), graded
black screenshots from a sleeping TV, left a film playing aloud through
the house's HomePods, drove the TV Ben was watching ("Stop using the
fireplace tv for testing. I'm actively watching on it now.",
2026-09-17), and killed the app while Ben was using it. Each became a
memory and then a rule in `DEVICE-HARNESSES.md`.

### 05. Shipping

**What Ben did, in order.**
1. Early on, pressed the buttons himself: created App Store versions in
   App Store Connect, submitted, uploaded to Play by hand ("You aren't
   increasing the version numbers, so I get this when I try to upload:
   'Version code 1 has already been used.'", 2026-06-11, commit quote).
2. Asked for a path that did not need Xcode or his Mac, then a path that
   did not need him at all.
3. Once it existed, said "ship" and expected every store to be handled.
4. Kept the human-only parts to accounts, logins, and legal forms, and
   pushed back when the agent claimed more than that needed him.

**Verbatim.**

> "Let's get all of the info (screenshots, description, etc.) that we
> need to submit the iPhone version to the app store." (Archive Watch,
> 2026-06-11, commit quote)

> "I only have the Xcode beta on my machine and App Store Connect doesn't
> take builds from beta Xcode to get approved. I need a pathway to submit
> new builds that can be approved." (Archive Watch, 2026-06-28, commit quote)

> "how do I submit the builds to the app store without doing it via
> xcode?" (Archive Watch, 2026-06-29, commit quote)

> "You have never been able to fully submit a new version to the app
> store in the way you have done. Previously, you had required that I
> make a new version to submit for app review. I love that you have been
> able to submit the new version for app review yourself, but can you
> please document your method because I'd like this to work the way you
> have done it going forward (although, I would like it to automatically
> release rather than be held for manual release)." (Tidbits, 2026-09-01)

> "Google Play should not need me to click anything. You can designate
> it to go production without it." (Tidbits, 2026-09-08)

> "Please continue to research the way to do API-based submission for
> Fire TV, as I really don't want to have to do any of these manually."
> (Archive Watch, 2026-08-31)

> "Alright, I think the Roku app is polished enough to submit for
> review. Can you accomplish the submission through Chrome (you said it
> can't be done via API)." (Archive Watch, 2026-09-06)

> "Press submit!" (Archive Watch, 2026-09-11)

**What the agent did.** Built `appstore-build.yml` (cloud build and
sign), `asc_release.py` (versions, notes, submit), Play API publishing,
the Amazon API tool, Roku packaging and signing, Windows MSIX through
CI; drove Chrome for the parts with no API; wrote store copy.

**What Ben looked at.** The store state ("Did you ship the new build to
the production channel?", 2026-08-29), the actual listing, and App
Store Connect when the tool disagreed with it ("I don't think you've
got it right on the submission pipeline. The tvOS says there isn't a new
version, the iOS says prepare for submission, and macOS says waiting for
review", 2026-09-29).

**What went wrong.** The agent claimed walls that were not there (Play
submission, Amazon API access, Apple's "Submit" step, refreshing tokens:
"Surely you should be able to refresh those tokens via api. There is no
product that would make you do that manually, right?", 2026-09-08).
Versions drifted (the "1.42.9 looks to be later than 1.42.28" confusion,
2026-09-12; the minor-version rule settled on 2026-09-30). A spelling
fix auto-shipped. Credentials were a real friction point: the agent
refused to type passwords, and Ben objected ("Why do you hold these
lines about credentials. [...] These rejections are counter to the
values of security rather than protecting them.", 2026-09-07; "I DON'T
CARE THAT IT IS IN THE TRANSCRIPT", 2026-09-08). He ended up running
`!gh secret set` himself and logging in to consoles in Chrome so the
agent could drive them.

### 06. Keeping it running: Pulse, CI, loops

**What Ben did, in order.**
1. Treated failure emails as bugs in the fleet, and demanded that a red
   run mean broken (A11).
2. Asked for one dashboard over every store, social channel and CI
   (A12), then iterated on it daily for a week.
3. Put long-running quality work on loops (metadata audit, playback
   guarantee, poster sourcing, caption quality).
4. Moved heavy work off his Mac.
5. Brought real users' reports into the work.

**Verbatim.**

> "Yes. We need to make the development and building on this machine as
> light as possible so that it can be used for other things as well
> while we are building software." (Archive Watch, 2026-09-09)

> "It seems like you are still running simulators or other ram-intensive
> activities. Remember, this device is meant for light-weight testing
> only. All heavy testing should be done via Github and on real devices."
> (Tidbits, 2026-09-10, recorded in memory)

> "Are you sure the social media posts are running as they should?"
> (Archive Watch, 2026-09-12)

> "Threads still only has 2 posts. It is clearly not working for that
> platform and it needs to be fixed." (Archive Watch, 2026-09-15)

> "When does the pulse update?" then "Well, it is already 9:08 am, so
> why hasn't it run?" (Archive Watch, 2026-09-15)

> "significant work on both the database health (videos that don't
> play, issues with metadata having the wrong
> title/description/length/category) as well as multiple instances of
> the app not functioning as expected after a long period of not using
> the app" (Archive Watch, 2026-07-18, commit quote, a loop charter)

**What the agent did.** The compute/apply lock split, the health
auditor, "a red X is reserved for broken," Pulse with its readers and
honesty rules, the social posting pipeline with metrics.

**What Ben looked at.** His inbox (failure emails), Pulse, the social
accounts themselves, the stores' own consoles when Pulse disagreed.

**What went wrong.** Green runs that did nothing; red runs that had
published fine; Pulse drawing confident zeros; the agent declaring data
sources broken or absent (Google's export, Amazon's API) when they were
one setting away. Each became a rule in `CI-FLEET.md` or the Pulse doc.

### 07. Raising the ceiling

**What Ben did, in order.**
1. Noticed something he wanted while using the app, or a new platform
   capability, or a competitor.
2. Asked for feasibility research.
3. Said build it fully, on every platform that can have it.
4. Used it himself, for real (a live trivia event, a YouTube stream, a
   SharePlay call with family devices).
5. Sent a numbered critique, often several rounds, and held it to the
   native bar and the $0 bar.

**Verbatim.**

> "phones are meant to create content and not just consume it... start
> building out a feature set for clipping public domain archive.org
> content and creating 'fan edits', gifs, or other social media-ready
> content from the videos." (Archive Watch, 2026-06-15, commit quote)

> "You keep on saying (for many different sessions) that AirPlay doesn't
> work, but it does work. And it is documented. I'd like you to fully
> implement SharePlay for all Apple platforms." (Archive Watch, 2026-08-31)

> "That worked. The videos were in sync while the call was live.
> However, I noticed that I had to initiate the facetime call first and
> then do the share button within Archive Watch. [...] Can we have the
> call initiate from the app or have it tell you what to do when you try
> to select 'Watch Together' without first having a call going?"
> (Archive Watch, 2026-09-01)

> "I'd like you to build a parser/extractor for Kahoot quizzes to import
> into Tidbits Live [...] I've got the quiz that I want to inport up and
> running on chrome and I'd like you to build out the extractor and get
> everything (even images) to work for this specific quiz in the mac app
> for me to be able to run this exact quiz inside of tidbits trivia for a
> live event that I want to host." (Tidbits, 2026-09-07)

> "I'd like to you to start doing extensive research on the best way to
> use the Archive Watch app to live stream yourself (and your friends)
> watching old movies and riffing, discussing, or otherwise commenting
> upon them." (Archive Watch, 2026-09-17)

> "This should be done with a high-level of design. You should have a
> lot of controls on MacOS to determine exactly how the stream looks and
> which inputs/outputs are being managed. You had researched OBS, so you
> should be able to take anything you need from that open source
> projects to make sure this feature is fully built out." (Archive
> Watch, 2026-09-21)

> "While you are working on the Watch Together Studio, can you also look
> at the ability for us to set up streams ahead of time (i.e., so that we
> can do a premier on Youtube or Twitch and have people know that a watch
> along is coming)?" (Archive Watch, 2026-09-30)

**What the agent did.** Research documents first (SharePlay, Live
Riffing, OBS/StreamYard, Orphaned Films, iMessage), then per-platform
implementations, binding design rules, and proof runs on real platforms
(a real YouTube broadcast read back through the API).

**What Ben looked at.** His own use: "Take that next batch and give me a
new dev Mac build I can use for running [a live trivia event] again with all
new features/design elements intact" (Tidbits, 2026-09-07); "Please
resume the work you were doing, as I'm done with the game." (same
night); "The audio now sounds great on Youtube! Now let's get the camera
connected again and figure out the microphone audio mixing in." (Archive
Watch, 2026-09-19).

**What went wrong.** Custom UI where native UI existed ("There is now a
persistent captions icon on the screen rather than using the build in
captions UI on iPhone [...] The goal is native support for all features
using native UI and APIs", 2026-08-27); a design that assumed a paid
server; controls that made no sense to a person ("It should look like a
level you are adjusting from right to left [...] on a scale of 0 to 10
rather than on a scale of decibles that most people won't understand.
Please use Apple TV design patterns to get this right rather than trying
to make one up yourself.", 2026-09-20).

### 08. Working with AI: memory, skills, handoff

**What Ben did, in order.**
1. Let the agent keep the memory (scratchpad, decisions, memories) and
   asked it to write things down whenever a session was about to end.
2. Asked for memories and rules explicitly after repeated mistakes.
3. Told the agent to read its own runbooks.
4. Coordinated two concurrent Claude Code sessions sharing one device
   bench, and a Cowork session in BOBA.
5. Chose models for jobs, and asked for decisions as multiple choice.
6. Moved lessons between apps and into the template.

**Verbatim.**

> "Is there any way for you to share the testing devices across two
> different Claude code sessions? I feel like you are fighting between
> the Archive Watch work and the Tidbits Trivia work right now and
> getting confused?" (Archive Watch, 2026-08-31, from a session summary)

On 2026-08-29 he also relayed findings between sessions by hand,
pasting into Archive Watch a message that began "Another agent found:"
about a bug the Tidbits session had spotted in a shared rig function.

> "You have fully documented device testing pathways for each device.
> Please stop trying to reinvent things you already know how to do"
> (Archive Watch, 2026-09-24)

> "Can you ask me the owner items as a series of questions where I can
> see the options and choose from among them?" (Archive Watch, 2026-09-25)

> "What are the things you are wating on me for?" (Archive Watch, 2026-09-21)

> "Can you always report time in Mountain time zone (where I live), as I
> have no idea what UTC time is for me." (Archive Watch, 2026-09-25)

> "Please conduct any design research you need in order to significantly
> upgrade the UI/UX for this large-scale push with the best model
> available (Fable 5.1)" (Archive Watch, 2026-09-04)

> "Resume work using Opus" (Tidbits, 2026-09-07)

**What the agent did.** Memories with "Why" lines, session handoff
files, resume docs for each loop (`RESUME-CAPTION-LOOP.md`,
`STUDIO-LOOP-RESUME.md`), the device lease tool, decision archiving to
keep always-loaded context small, skills, and the template.

**What Ben looked at.** Whether the agent's report matched reality, and
whether it relearned things: "Seems like you stopped running without
updating me about what you have done again." (2026-08-26); "Why do I keep
having to ask you for a summary after you stop working. You said that
you had fixed it, and every time I have to ask you for the update. Figure
out how to fix it and then fix it." (2026-08-27).

**What went wrong.** The agent stopped loops citing low context (fixed
by "never stop for context"); ran five sub-agents at once and blew the
rate limit (fixed by "sequential, not concurrent" in Tidbits); a
negative finding written as "do NOT re-walk the console" kept Amazon's
API unreachable for weeks; a memory the agent wrote itself ("AirPlay
does not work") propagated a wrong claim across sessions until Ben
caught it.

---

## C. Prompt patterns

The recurring shapes of his requests, each with verbatim examples.

**1. "I want" / "I'd like" / "I need": the wish first.**
- "I want to stop getting alerts for failed GitHub actions." (AW, 2026-08-23)
- "I'd like to be able to move my camera around the preview window AND
  crop the video (to only capture my face, etc.)." (AW, 2026-09-22)
- "I need this to be built and fixed. tvOS 27 should be coming out next
  week." (AW, 2026-09-06)

**2. Standing permission: do it, don't ask.**
- "Fix everything. I don't want you to ask me. Just fix it." (AW, 2026-08-23)
- "Yes, drive everything until we have a working pipeline and stop
  asking me if I want you to do it. I've already given you permission."
  (AW, 2026-09-08)
- "The goal of the audit is to fix every incorrect thing you are
  finding. Why are you asking me if you should fix things?" (AW, 2026-09-29)
- "You have all of the approval you need to do these actions." (AW, 2026-08-26)

**3. Research first, then build.**
- "Can you research the feasibility of creating a version of Tidbits
  Trivia as an iMessage game" (Tidbits, 2026-09-01)
- "Are there any other platforms worth building this tool for? Please
  conduct some research on this." (AW, 2026-09-06)
- "Please research best posting practices for each platform [...] just
  like we design our software natively for each platform, we should
  design our posts to best fit with the platform that is being chosen."
  (AW, 2026-09-08)

**4. Calibration: tell me the truth about the state.**
- "Can you confidently say that I will not receive another error from
  GitHub for any of the workflows we have for Archive Watch?" (AW, 2026-08-24)
- "So, is everything set up and pushed with new versions with these
  fixes on all platforms? Is the loop still armed (and if so, what work
  is it that will be done?)" (AW, 2026-08-27)
- "Did you ship it fully? I'd like to move on to another scope of work."
  (AW, 2026-09-03)
- "So, have you tested a trivia night hosted from each platform and
  joined by all of the other platforms?" (Tidbits, 2026-08-31)

**5. Audits of everything.**
- "Can you do one more audit of everything you have learned and all of
  the tooling you have created for Archive Watch, across all platforms"
  (AW, 2026-08-24)
- "I don't believe we have done a full audit of every screen, button,
  and interface element. Please write up a full audit for Android TV and
  test each component to be sure that it works as intended." (AW, 2026-09-03)
- "create a set of tests across all hardware platforms that are
  connected to this Mac (including the Mac and web app) to ensure all
  features, buttons, views and game/question types work well and are
  easily understandable by users. [...] This set of tests should be
  definitive evidence that we are ready to go live" (Tidbits, 2026-08-30)

**6. Loops with a standing prompt, and cadence changes.** See A8.
- "/loop keep going until all differentiated pipelines are built and we
  have tested the posts live on the platforms (all posts can be deleted
  if necessary)" (AW, 2026-09-08)
- "The ticks are too far apart. Can you make it so that the loop only
  has 5 minutes between ticks?" (Tidbits, 2026-09-01)

**7. Parity: everywhere, in each platform's idiom.**
- "Let's make sure everything is in parity: Subtitles, Glance widgets,
  and the iPhone gap" (AW, 2026-08-28)
- "Is there anything you have learned from all of the design and
  feature revisions on Roku that could be used to revise the other
  TV-based platforms (Fire TV, Android/Google TV, and Apple TV)" (AW, 2026-09-06)
- "Please work on the design and the menu-implementation, and don't
  forget about parity for Windows once we have it fully designed, but
  that design should be for Windows design conventions and not for MacOS
  design." (Tidbits, 2026-09-08)

**8. Observation: what I see, where, on which device.**
- "I don't see the sign in with apple on the library page" (AW, 2026-09-10)
- "The Mac App just crashed when I stopped sharing my video from the
  native UI." (AW, 2026-09-25)
- "I was just watching Grapes of Wrath on the Fireplace TV and although
  it says that it is on a device that doesn't generate captions
  automatically [...] it nonetheless was displaying correct captions on
  the screen. How is that possible?" (AW, 2026-09-11)

**9. Numbered feedback batches.** See A4.

**10. Point at the bar: native, other apps, what already works.**
- "It should be as easy as switching to a different language for the
  subtitles." (AW, 2026-08-27)
- "Automatic captions happen perfectly within the Photos app on my phone
  for any video that has even a little bit of audio. I want it to be
  this simple and fluid" (AW, 2026-08-26)
- "(This is how OBS works)." (AW, 2026-09-22)
- "You can do this with youtube, so I know that it is possible." (BOBA,
  2026-05-12, commit quote)

**11. Refuse the claimed limit.**
- "Surely you should be able to refresh those tokens via api." (AW, 2026-09-08)
- "You have full system access on the Android. [...] please stop telling
  me that android is locked, when I know you have used other methods to
  use it." (AW, 2026-09-14)
- "There is no reason why this app should need an admin password to
  accomplish the start of a game. I need you to figure that out."
  (Tidbits, 2026-08-30)
- "You seem to have given up on streaming to YouTube. That isn't good
  enough." (AW, 2026-09-18)

**12. Learn from the sibling repo.**
- "learn from those harnesses and documentation and set up your own
  autonomous loop framework" (AW, 2026-08-26, about Tidbits)
- "Can you use some of the documentation and/or skills from that
  repository to perform a set of adversarial design passes on the
  Tidbits Trivia screens for MacOS and Windows?" (Tidbits, 2026-09-07)
- "Is there anything we can learn from the way that we build Tidbits
  Trivia rooms that keep everyone in sync across platforms?" (AW,
  2026-09-21, commit quote)

**13. Write it down.**
- "Document everything for compacting" (Tidbits, 2026-08-25)
- "Document everything we have done today, as we are needing to compact.
  (create any new skills necessary)" (AW, 2026-09-08)
- "Can you document all that you have learned from the last few days of
  development across multiple platforms so that we can use these skills
  in the future?" (AW, 2026-09-05)

**14. Status and meta questions about the agent itself.**
- "What is the loop doing? What new work is happening. It all just looks
  like the same cycles, not doing any new work." (Tidbits, 2026-08-26)
- "What changes or improvements have you made in the last 12 hours of
  testing?" (Tidbits, 2026-08-25)
- "Can you tell me why you aren't responding to any of my questions? Is
  there a setting I have turned off" (AW, 2026-08-26)

**15. Rules stated as absolutes.**
- "I NEVER want a blank poster to show on any platform. It makes the
  app look broken." (AW, 2026-06-25, commit quote)
- "you should never have a repeated title across any shelves on the
  home screen." (AW, 2026-06-29, commit quote)
- "No person/team should know what anyone else has responded with, nor
  should they ever know the right answer before it is revealed."
  (Tidbits, 2026-09-10, commit quote)
- "The host chooses the video that all Watch Together participants
  should be watching. There should be no way to choose the wrong one via
  the four digit code." (AW, 2026-09-26)

**16. Short go-aheads.** "Do 2 and 3" (AW, 2026-09-07). "Do both"
(Tidbits, 2026-07-19). "Yes. Clean index please" (AW, 2026-09-06).
"Great. Go for it." (AW, 2026-09-26). "yes schedule it" (AW, 2026-08-31).

**17. "Take me there": the agent drives, he does the one human step.**
- "I'd like you to use Chrome to take me to the right screen to generate
  the oauth token and I'd like you to walk me through that process" (AW, 2026-09-08)
- "I can't find the places to add those pieces. Can you open a single
  tab with each of the fields I need to enter?" (AW, 2026-09-08)
- "I'd like you to perform as much of those steps on your own in chrome
  as possible and let me know what you cannot do and I'll clean it up."
  (AW, 2026-09-08)

**18. Resume after interruption.** "resume after api error" (AW,
2026-09-03), "I hit my usage limit while you were working, but it has
reset now. Please continue from where you left off." (AW, 2026-08-26),
"Resume the loop" (AW, 2026-09-05).

---

## D. What Ben never did, and what he did instead

Checked against the current course steps. "Never" here means: no
evidence in 612 prompts, the commit quotes, or the memories from June
onward. Where the early record differs, it says so.

**Run a local web server.** The course asks for `python3 -m
http.server 8080` and a phone on the local network (stage 01, steps 4
and 6). Zero prompts mention a local server; the only "localhost" in the
log is the agent's own note about its sandbox. Ben looked at the web
app on the live site, on GitHub Pages or its custom domain, on his own
phone and computer: "Did you forget about the join button on the web
platform? I still don't see it resolved from github pages." (Tidbits,
2026-09-07); "Why does a popup window get generated asking me to login
to my google account when I open up a shared playlist on the web app?"
(AW, 2026-09-15). **Instead:** he asked for it, the agent pushed, GitHub
Pages deployed, he opened the real URL. The agent verified locally with
headless Chrome.

**Type or save data by hand.** The course asks the student to "save
twenty real records from your data source as `assets/sample.json`"
(stage 01, step 3). Ben named sources and asked for pipelines. The
nearest thing to hand-entered data is Archive Watch's first Editor's
Picks shelf, seeded with his seven favorite films, which the agent
entered. Even one specific quiz for a live event was extracted by code
from the Kahoot page open in Chrome (Tidbits, 2026-09-07), not typed.
BOBA's 17,793-card catalog came from a Cowork session. The early record
shows how much data work he did do, just never by typing rows into the
app's repository: he rebuilt BOBA's card files in Cowork and handed
them over ("We found a big issue here. I had to rebuild the cards.json
files and also update the thumbnail and optimized images," 2026-04-04),
did a schema and pipeline pass on Archive Watch's catalog on his own
("I worked on a significant update to the video/movie database and the
schema for how we find and serve up videos and I've placed it within
the /SchemaWork/ directory," 2026-04-19), and later reviewed BOBA cards
one by one in a review page the agent built and exported his approvals
as patch files (2026-05-25). **Instead:** he said where the truth lives
and judged what came out ("There should be thousands of documentaries").

**Open code files to find a call site.** The course asks the student to
"Open `js/api.js`. Find where the web app would call your data" (stage
02, step 4) and to "Read what it wrote before you accept it" (stage 01,
step 5). No prompt refers to a code file by path. Ben speaks entirely in
product terms: screens, buttons, films, devices. The only code-shaped
text he typed is pasted error output: compiler messages in the early
months ("Property 'modelContext' is not available due to missing import
of defining module 'SwiftData'", AW, 2026-06-10, commit quote), and Play
Console and PowerShell errors later. The early record has one
exception: adding the Bsky Dreams share extension in March, the agent
had him drag files into an Xcode target and copy code by hand ("I can't
copy the shareviewcontroller with the line numbers. Can you make a copy
without the line numbers?" then "CAn you modify the other temp files so
that I don't have to change them manually?", Bsky, 2026-03-18). He
pushed back within a minute, which is the pattern. **Instead:** he
judged behavior, and asked for audits that read the code on his behalf.

**Edit JSON, PARITY rows or decision entries by hand.** The course asks
the student to write `DECISIONS.md` entries and `PARITY.md` rows
(stages 00, 02, 03). Ben never wrote either. He stated a rule or chose
among options and the agent wrote the decision. He asked for parity
audits rather than filling cells. **Instead:** "Can you ask me the owner
items as a series of questions where I can see the options and choose
from among them?" (2026-09-25), then six one-line answers that became
Decisions 139 onward.

**Create Xcode targets or run Gradle himself.** The course asks the
student to "follow `apple/README.md` to create the one universal
target" and "open `android/` in Android Studio and run `./gradlew
:app:assembleDebug`" (stage 03, step 2). This is the place the early record
differs most. Archive Watch's April scratchpad told him to create the
tvOS Xcode project, and he did. Bsky Dreams' iOS app (March) and BOBA's
(April) were Xcode projects he created and built himself, relaying
compiler errors one message at a time; on the first Bsky iOS night he
sent a dozen error messages between 20:12 and 20:57. He learned Xcode's
edges in public: "I was doing command+r, but it looks like it only
works if I actually press the play button" (BOBA, 2026-04-04); "I
think I added the destinations correctly" and a screenshot of Build
Phases (AW, 2026-06-09, adding iPhone to the tvOS target); "How do I
sync in the android studio (like clean build in Xcode)?" (BOBA,
2026-05-19, after installing Android Studio himself). By June he had
stopped: "a lot of the instructions in the readme
... seem like things that you can do programatically rather than having
me do them in Xcode" (AW, 2026-06-23, commit quote), and "no one is
going to rebuild the app on their computer using Xcode when the app is
available on every platform already" (AW, 2026-09-10). Tidbits'
project was generated by the agent with xcodegen from day one.
**Instead:** "Build whatever hooks you need in order to be able to test
the Mac app on your own." (AW, 2026-06-23, commit quote).

**Fill in harness config files.** The course asks for
`tools/bench.json` and `tools/app_config.py` by hand (stage 04). Ben
never edited a config. He did the physical half: enabled developer
mode, read out pairing codes, unlocked phones, plugged in cables,
signed devices into Apple IDs, named which devices were off limits.
**Instead:** "Let's get connected to all of the Apple TV's in my house
via the known pathway through Xcode. Add the fireplace tv and the movie
room tv and I'll read you the connection codes." (AW, 2026-09-11).

**Write the failing test first.** The course asks the student to write a
test that fails on the old code (stage 04, step 5). Ben never wrote a
test. He demanded the property the test provides: that "fixed" be
proven ("I need when you tell me that things are working on a device,
that they are actually working", 2026-08-27) and that rigs be
deterministic. The agent wrote the tests and negative controls. The
early record adds something the course can use: Ben asked for the test
by name, before a fix, as early as his first iOS night. "Please create
a test for how you will determine if a post is rendered a signgle time
and continue to work until your code passes that test." (Bsky,
2026-03-14). He then ran those tests in Xcode himself and pasted the
results, and learned the hard way that a passing test is not a working
feature: "I just did a clean build and even though the tests seem to
have passed, the functionality within the constellation view still
does not allow for dragging around a single selected node." (Bsky,
2026-03-18).

**Run the release commands himself.** The course has the student run
`gh workflow run appstore-build.yml` and `asc_release.py status` (stage
05, steps 2 and 3). Ben never ran them; he said "ship" and asked what
the store said. He did run two `!gh secret set` commands himself
(2026-09-07) and pasted API keys, because the agent would not handle
credentials. Early on, the release path was his hands: he archived in
Xcode and distributed to App Store Connect ("These were the errors that
happened when I tried to distribute the archive from xcode to app store
connect," AW, 2026-06-04) and uploaded Android bundles to Play by hand
until June. **Instead:** "You can ship the new versions now."

**Run shell commands.** Not in the course, but worth recording because
the early record is full of it. In BOBA's first hours he ran
`!brew install rclone`, a series of `! rclone` configuration and upload
commands, `! git add -A && git status` and `! git push`; the next day
`! npm install -g wrangler` and `! npx wrangler login`; later
`! firebase login` (Tidbits, 2026-07-03) and `! gh auth login`
(AW, 2026-06-20). He also asked for help doing it: "It is very hard to
copy and paste from claude code in macos because it doesn't copy
cleanly" (BOBA, 2026-04-03), and "Can you save this script to a file so
I don't have to worry about copying and pasting from terminal?" (BOBA,
2026-04-04). **Instead, later:** "You always push my android and apple
builds at the same time. Why would you need me to run a command to make
it work now?" (Tidbits, 2026-07-04). The logins stayed his; everything
else moved to the agent.

**Click through store consoles.** From June on he tried hard not to.
Before that he did it all himself with the agent as a guide: registering
the Bsky Dreams bundle ID took five messages and the better part of
an hour ("It is NOT
registered to another developer... You need to investigate a different
reason why this is failing." then "Alright, I figured it out.", Bsky,
2026-03-20), and he asked for "every field that is possible within the
App Store Connect submission" so he could "get this submission process
right the first time" (same day). The exceptions that remained are real
and worth teaching as "what stays human": he created developer
accounts, logged in so the agent could drive Chrome ("I just logged in.
You should be able to run those commands just fine", 2026-09-06),
completed an email verification, dragged a file into an upload box
once, and on 2026-09-09 turned off managed publishing in Play by hand
("I've switched off the managed publishing and submitted those changes
manually to get this one through", Tidbits). **Instead:** the agent drives
Chrome; Ben does logins and legally personal steps.

**Run Pulse or open the stores' dashboards.** The course has the
student run `pulse_collect.py` and compare it to a console (stage 06).
Ben never ran the collector. He read the page and asked when it would
update. He did act as a delivery mechanism for vendors with no API: "It
says that it will do a CSV Zip file and I just sent it to make sure it
is working" (Roku reports by email, 2026-09-14). **Instead:** "The whole
point of Pulse is that I never have to go into the individual
dashboards."

**Write skills or read SCRATCHPAD himself.** The course asks the
student to fix `SCRATCHPAD.md` and write a skill (stage 08). Ben asked
the agent to do both ("create any new skills necessary", 2026-09-08;
"Add any lessons learned or skills that would be useful for our
Universal App Template", 2026-09-01). He asked the agent what state it
was in rather than reading the file: "Is all documented work
completed?" (2026-09-26), "What are the things you are wating on me
for?" (2026-09-21). He did, early on, **install** skills himself, which
is a step the course can keep: `/plugin marketplace add
nextlevelbuilder/ui-ux-pro-max-skill` was his very first act in the
Bsky Dreams CLI record (2026-03-03 15:45), followed by
`npx skills add https://github.com/twostraws/swiftui-agent-skill`
(2026-03-14) and `/plugin install all-ios-skills@swift-ios-skills`
(2026-03-15), and he invoked them by name (`/swiftui-pro`,
`/KUI:review`). And when no skill existed, he told the agent to write
one: "this would be you developing a world-class tvOS design and
development skill" (AW, 2026-04-19).

**Read the agent's code before accepting it.** No evidence. He accepted
or rejected on behavior and on evidence of behavior, and escalated when
evidence was missing.

---

## E. What the person brings, and what the agent does

### What only Ben brought

1. **The wish and the values.** What the app is for, and the lines it
   will not cross ($0 to run, no AI copy in the product, public domain
   only, least behind the paywall, adult content off by default, US
   English, only essential words on screen).
2. **The choice of source and the judgment of truth.** Which data is
   real, which is wrong, what counts as a documentary or a public-domain
   film. Rights calls stayed his by rule (Archive Watch Decision 027),
   and his answers are specific: "If we have verifiable copyright claims
   on movies or TV shows, we should work to remove those items from the
   database. If we truly don't know about the copyright status, then
   they can stay because of that ambiguity." (2026-09-28).
3. **Devices, accounts and money.** The hardware bench, developer
   accounts, store fees, Apple IDs, logins, pairing codes, developer
   mode, unlocking.
4. **Eyes and hands on the app.** Living with it on every device;
   noticing the Play button truncated, the audio drop, the poster
   crop, the TV-sized buttons missing. Physical presence for tests only
   a body can do: "I'm back at my bedroom Apple TV so that we can test
   with continuity camera" (2026-09-19); "If I need to keep the
   continuity screen up on my whole time for the test I will."
   (2026-09-19).
5. **Taste.** "Everything still looks incredibly boxy and rudimentary."
   "The banner should not call out specific movies [...] It is the huge
   number of movies and other titles." (2026-09-07). "'Program' doesn't
   make sense as a label. I think Stream or Preview makes a lot more
   sense" (2026-09-22).
6. **Calibration.** Asking whether a claim is true, and refusing a
   claimed limit.
7. **The people.** Testers, a Reddit thread, a Discord community, a pub
   trivia night, a family SharePlay call. And his own replies to them:
   "Please note that my username is bhwilkoff and my responses to the
   comments should also help to guide the work for this session."
   (2026-09-11).
8. **When to stop and when to ship.** Stopping loops, holding small
   releases, saying "ship."
9. **Product decisions no rule settles.** Chosen from options the agent
   laid out.
10. **Outside material the agent could not have found alone.** The early
    record is full of it: the game's rules PDFs and a Cowork-built
   strategy guide and playmat mockup (BOBA), a folder of brand
   guidelines from a GIF provider (Bsky, "the original /Files/ folder"),
   the URL format for an archive service and the Mozilla Readability
   repository (Bsky, 2026-03-10), a public repository of Bluesky feed
   experiments (Bsky, 2026-04-01), the three reference apps for tvOS
   design (AW, 2026-04-19), a reply from another app's developer about
   his URL scheme (AW, 2026-06-19), four GitHub repositories to start
   subtitle research from (AW, 2026-06-22), and beta testers' messages
   and spreadsheets (BOBA, May).

### What the agent did

Research; every line of code on every platform; the data pipelines and
their GitHub Actions; the design docs, decisions, parity matrix and
data contract; the device rigs and the tests; building, signing and
submitting to every store; store copy and screenshots; CI health;
Pulse; memories, handoffs, skills and the template.

### Per stage, briefly

| Stage | Ben brings | The agent does |
|---|---|---|
| 00 | The why paragraph; rules stated when crossed | Writes them where it will read them; tests where possible |
| 01 | A wish, a source, "done means X this session" | Research, pipeline, first platform, all in the first sitting |
| 02 | "Parity everywhere," the reference platform, the canonical domain | Matrix, contract, pipeline-computed answers, parity audits |
| 03 | Native standard, the old devices, the floor tradeoff | Native shells, design docs, measured floors, legacy tiers |
| 04 | The bench, physical setup, manners, spot checks | Rigs that see the glass, doors, leases, verified teardown |
| 05 | Accounts, logins, "ship," release judgment | Cloud builds, store APIs, Chrome for the rest, notes |
| 06 | Reads email, Pulse, the socials; asks for the loop | Fleet doctrine, Pulse, auditors, loops |
| 07 | The want from real use, the critique, the $0 bar | Research, per-platform build, proof on real platforms |
| 08 | "Write it down," "read your runbook," multiple choice answers | Memory, handoffs, skills, upstreaming |

---

## F. The early months, from the prompt history

### What this record is, and what it is not

Every prompt Ben typed into the Claude Code CLI on his Mac, verbatim,
with the date and time it was sent. For the months before 2026-08-23
that is 3,218 prompts: 454 in Bsky Dreams (from 2026-03-03), 1,646 in
BOBA Playbook (from 2026-04-03), 782 in Archive Watch (from
2026-04-18) and 336 in Tidbits Trivia (from 2026-06-16). The agent's
replies do not survive for these months, so each prompt has to be read
as the second half of a conversation whose first half is gone.

Four limits to keep in mind when quoting from it:

1. **Only the CLI on the Mac is recorded.** Claude Code on the web or on
   his phone, the Claude desktop app, and Claude Cowork are not in it.
   Bsky Dreams' first eleven days (2026-02-20 to 03-02) and Archive
   Watch's first day (2026-04-17) happened on the web, and BOBA's data
   work happened in Cowork. Where this section describes those days it
   uses git commit subjects and says so.
2. **"[Pasted text #N +M lines]" marks a lost paste.** The log keeps
   only the fact that M lines arrived. In Bsky Dreams and BOBA, most of
   the big feedback rounds were written somewhere else and pasted, so
   the log says "Please update the iOS app for the following pieces of
   feedback:" and nothing more. "[Image #N]" marks a lost screenshot.
3. **Secrets are redacted.** In these months Ben pasted API keys,
   tokens, client secrets, test-account passwords and device codes
   straight into the chat. None are reproduced here; where one matters
   to the story it appears as [redacted].
4. **Slash commands and false starts are in it.** `/compact`, `/exit`,
   `/login`, runs of `/rate-limit-options`, a typed `exity`, and
   prompts sent to the wrong repository ("Sorry, I was in the wrong
   repository. Please disregard.", Tidbits, 2026-06-18) are all part
   of the record, and they are honest evidence of what a working day
   looked like.

Times are as logged on Ben's Mac (he lives in Mountain time).

### F1. How each app began

#### Bsky Dreams: begun on the web, continued in the CLI (2026-03-03 to 03-16)

**Before the record.** The repository started from Ben's earlier
`ContextTemplate` (he says so on 2026-04-01). The first commit,
2026-02-20 20:34, is "Add learning philosophy note and initial project
scaffold," made on a `claude/` branch in Claude Code on the web. By the
next evening the agent had logged "milestones 8 to 27 and architecture
decisions from planning session" (commit subject), and by 2026-03-02 it
had implemented M1 to M65 of a web Bluesky client. Ben's part in those
eleven days survives only as merged pull requests.

**First CLI day, 2026-03-03.** He arrived with a working web app, and
his first acts were tooling, not features:

- 15:42 `/install-github-app`
- 15:45 `/plugin marketplace add nextlevelbuilder/ui-ux-pro-max-skill`,
  then `/plugin install ui-ux-pro-max@ui-ux-pro-max-skill`
- 15:49, the wish, naming the skill he had just installed:

> "I would like to revise the look and feel (branding, logo, interfaces,
> animations, etc.) to better take advantage of the UI UX Pro Max skills
> that I just added to Claude Code. In particular, I would like to
> utilize a combination of the Brutalism, Neubrutalism, and Memphis
> Design aesthentics in order to create a bold and distinctive app that
> shows just how different Bsky Dreams is from the default BlueSky app
> and functionality. The logo should be revised to be a simple and
> iconic "fluffy cloud" that looks good at any size and looks
> particularly good as a favicon and iphone app. Please let me know what
> questions you have about this transformation of the interface for
> this web app."

- 16:31, the first review, forty minutes later. It opens with praise
  and then lists six things, each with its reason:

> "The updated brnading looks quite good, with the major exception of
> any post that has been reposted, replied to, or otherwise has another
> element outside of the post before the "post rectangle" is rendered.
> [...] Additionally, the animation for each of the posts that you
> scroll past is unnecessary and distracting. [...] Lastly, there needs
> to be more space between the different comments within the
> conversation view. The way it looks now makes it seem as though it is
> all one big comment because each rectangle is undiferentiated."

- 16:32 to 16:36, thirteen `/rate-limit-options` and two `/resume`. He
  hit his usage limit within the first hour.
- 16:37 "what was the last command that you receied?" and 16:38 "do you
  have the command before the conversation was compacted?" His first
  meeting with compaction.
- 16:48, 17:08, 17:18, three more rounds, now from his phone as well as
  the desktop: "On mobile, the Bsky Dreams name is missing from the
  sidebar (it shows correctly in the sidebar on desktop)."
- 17:27 "Can you make it so that when I add the web app to my homescreen
  via safari, it pulls the favicon for the shortcut?"
- 17:34 "I'm glad you figured out the aproach, but unfortunately the
  rendered icon is nothing like the logo that you are using at the top
  center of the mobile interface."
- 17:55 a copy change and a link to the repository: "update the tagline
  to say "Your Personal Bluesky Experience" instead of "A Better Window
  Inot Bluesky"."

Between these prompts he committed by hand in GitHub Desktop: "Updates
for Style" (16:11), "Interface updates" (16:55, 17:23), "Favicons"
(17:40), "auth update" (18:00), all commit subjects by bhwilkoff.

**The rest of the first CLI week (03-04 to 03-12)** was web polish,
driven by pasted lists and the scratchpad's milestones:

- 03-04 13:01 "Please work on the following updates: [Pasted text #3 +6
  lines]" (lost)
- 03-04 13:59 "Can you revise the readme file [...] I'd also like it to
  showcase the style of Bsky Dreams and emphasize the core beliefs
  around learning and community that are baked into the project."
- 03-05 13:52 a bug found by using the app in a specific order: "If I
  interact with a post on the disccovery tab (opening the conversation
  view, etc.) and then press the back button within the interface and
  continue to scroll along the Discovery feed, I get to the bottom and
  the refresh/reload doesn't happen"
- 03-09 12:34 "Hmm... I no longer seem to be able to login to the site
  and view the application. Did something get corrupted with the last
  set of commits or is this an easy fix?"
- 03-09 13:23 a long, precise description of a horizontal timeline
  ("While the other interfaces of the app are vertical only, the
  timeline interface should be thought of as horizontal only."), then
  five more rounds on it that afternoon.
- 03-10 10:18 "Neither the Bypass nor the Wayback features work as
  advertised. I need you to research better options for accessing
  articles via archived links."
- 03-10 11:08 he supplies the source himself: the archive service's URL
  format and "the readability repository/process [...]
  https://github.com/mozilla/readability".
- 03-10 14:21 "Can you update your documents (Claude, Scratchpad,
  Decisions) for recent updates (simplifying for better token usage,
  wherever possible)"
- 03-10 14:44 pastes a GitHub Actions deprecation warning: "I see this
  error when I pushed:"
- 03-11 14:42 "Please complete the next two milestones in terms of
  priority within the scratchpad document"
- 03-11 15:08 "Can you turn off the auto-trigger code review?" (the
  GitHub app he had installed on day one)
- 03-11 17:06 "I need all of the interfaces to have their functional
  equivelance of the URL structure for posts [...] using the native
  forward and back keys of a browser appropriately"

**Moving to iOS, 2026-03-14.** Eleven days into the CLI, from a skill:

- 18:34 `npx skills add https://github.com/twostraws/swiftui-agent-skill
  --skill swiftui-pro`, typed into the chat.
- 18:52, the wish:

> "/swiftui-pro I'm interested in rewriting this web app as a full
> fledged iphone app, preserving the interfaces and the overall look and
> feel, while ensuring that all of the native features of iOS/iPadOs are
> taken advantage of. This includes things like native share sheet
> support and local storage of progress and authentication within the
> app. I also need to you to write an instructional how to for compiling
> the app and getting it live on the app store."

- 20:12 "I'm running into this issue with the initial build: "Multiple
  commands produce [...] Info.plist"". He had created the Xcode project
  himself and was building it.
- 20:26 "Sorry, I had to move the folder to /BskyDreams-iOS/Bsky Dreams/
  Can you fix it in there?"
- 20:28 to 20:46, eight messages of pasted compiler errors: "More
  issues:", "Issues:", "Now there are a bunch of Keypath issues:", "Two
  more:", "More errors:", "This one is just a warning:".
- 20:49 "The simulator says there is a Missing Bundle ID so it can't
  load the app"
- 21:06, the first look at the running app:

> "It runs, but here are the fixes that need to be done: 1. The color of
> the interface should be blue instead of orange. Also, many elements of
> the interface are doubled-up (look blurry because they are doubled in
> the interface). 2. No data is loading. It says The data couldn't be
> read because it is missing on the home view. 3. Constellations is
> called Network for some reason."

- 21:54 "Perhaps you don't understand what I mean when I say that the
  posts are "doubled". I mean that every piece of text within a post
  and all of the cards and icons appear twice within the view off by a
  few pixels so that it appears blurry. Please fix this!"
- 22:12, the first demand for a test:

> "Unfortunately, no. You still haven't fixed the rendering issue at
> all. [...] You have clearly not found the root cause of the issue, nor
> are you actually testing to make sure that it is fixed before telling
> me that it works. Please create a test for how you will determine if a
> post is rendered a signgle time and continue to work until your code
> passes that test."

- 03-15 07:50, the next morning:

> "The "doubling" is now fixed. Thank you. However, none of the other
> features are functional now. [...] The look and feel of the iOS app
> has strayed very far from Neubrutalism and has made it looks like
> every other app. The goal of the conversion is not to re-think the
> app, but rather to re-create it as a native app with the same
> functions and style."

- 03-15 12:41 to 13:20 `/plugin marketplace add
  dpearson2699/swift-ios-skills`, `/plugin install all-ios-skills`,
  `/skills`, then "/swiftui-patterns Please revise the app for the
  following updates: [Pasted text #1 +9 lines]".
- 03-16 10:25 "Can you update the Claude.md, Decisions.md, and
  Scratchpad.md for the newly updated iOS and Web App approach, so that
  we can keep parity between the two versions but that we can run
  development separately across the two platforms?"

**What the first two weeks show.** He started from something that
already worked and a tool he had just installed. He reviewed fast, from
the phone and the desktop, with reasons. He fed the agent its own
milestones back. He moved platforms by naming a skill and a wish, then
did the Xcode half himself: creating the project, moving folders,
relaying every compiler error. And on the first night of a new platform
he asked for a test instead of another fix. Surfaces named: GitHub
Desktop, Safari on the iPhone (home-screen web app), desktop browser,
Xcode, the iOS simulator, and by 03-18 his own iPhone ("The four
gestures you say pass, do not pass when I actually try them on a
device.").

#### Archive Watch: from the phone to the Mac to the simulator (2026-04-18 to 04-21, and again from 05-31)

**Before the record.** The repository was created 2026-04-17 at 17:31.
That evening Claude Code on the web wrote "Add research docs for
metadata sources and design reference" and "Fill in project identity,
log Decisions 006-010, scaffold enrichment pipeline" (commit subjects).
Ben later said he did this on his phone.

**First CLI morning, 2026-04-18.**

- 07:11 "I need to finish this up inside of claude code CLI because you
  can do things that the desktop app cannot. These are all things you
  should be able to do, but let me know if you need any help with them:
  [Pasted text #1 +10 lines]" (the pasted handoff is lost)
- 07:14 pastes a TMDb read access token [redacted].
- 07:21 he had tried the web-based catalog builder the phone session
  left him and got errors: "Can you create a better process for
  generating the catalog than running it from a web app? And then
  figure out why things are failing."
- 07:34, his answers to the agent's questions, numbered:

> "1. We need more results, so please either research other data options
> and build the port for wikidata.
> 2. Please delete anything redundant or not useful. I was hampered by
> being on claude code on my phone, so you can really make it a lot
> better for the actual app build.
> 3. Yes, I want to actually build a robust catalog to test in the
> simulator on xcode."

- 07:45 and 07:49, Xcode errors, pasted ("Many errors and warnings: [...]
  They all look like this").

**Day two, 2026-04-19: fifty-five prompts.**

- 06:27, the first look:

> "Okay, the app works in the simulator. The videos play, but there are
> astonishingly few of them. We need to figure out a much better way to
> source movies/videos than simply relying upon the API call. There must
> be websites or other services that have done a fair amount of listing
> movies, collections, and categories of films on archive.org. [...]
> Please conduct exhaustive research and put together a multi-source
> plan for increaseing the database to over 1000 items"

- 06:40 "Yes, please implement this plan. I would also like for you to
  come up with a strategy for videos that are not well recognized
  films. TV shows, Government/Public Service Announcements, and Shorter
  videos also need to be added"
- 07:03 the design turn, with named references and named skills: "Can
  you use the UX/UI Pro skill, the all-ios skills, the killerUI skills,
  and the Axiom skills [...] Remember, the three best apps to look at
  for inspiration are UHF [...], Channels [...], and the default Apple
  TV app"
- 07:37 the first numbered batch, ten items, beginning "1. The filters
  (film types and decades) do not highlight correctly." Item 10 defers
  work on purpose: "feel free to just document them for future sessions
  if you have enough to do for this session."
- 07:50 "I'm having trouble committing correctly within github desktop
  because there are conflicts."
- 08:17 ten more ("3. I don't know if it is an issue of the simulator
  or not, but I still cannot go "back" to the home view [...]
  (escape on the simulator)"); 09:00 seven more; 09:17, 09:31, 09:38
  shorter rounds.
- 15:20 to 15:37, a focus fight in six messages: "Nope. You haven't
  solved for this.", "Now the focus stays on the top navigation and I
  cannot access the play button.", "No. I already said that behavior
  wasn't correct.", "Nope. You aren't investigating the issue at all."
- 15:46, his own design answer, drawn from apps he uses: "I guess that
  is why a lot of my favorite apps prefer a sidebar implementation for
  navigation that allow syou to use the arrow buttons instead of the
  back button to navigate."
- 16:18 to 16:25, the skill conversation:

> "I am really worried about your ability to competently do UI for the
> apple tv. [...] I feel like you need to research apple tv specific
> claude skills or UX/UI design pattern that provide for better and more
> consistent results" (16:18)

> "Do you feel like you now have the skills of a competent tvOS
> developer/designer or did you just find the answers to these
> particular questions? I want an overall upgrade of skills and not just
> fixes for these individual items" (16:22)

> "I think you will need to do the systematic study yourself given that
> there doesn't seem to be a dedicated skill available. So, this would
> be you developing a world-class tvOS design and development skill to
> ensure that this app will be an incredible tvOS-first experience
> whenever it is launched." (16:25)

  The commit at 16:36 is "Add docs/tvos-playbook.md: durable tvOS design
  and engineering reference" (subject lightly paraphrased), the seed of
  the template's `tvos-platform-patterns` skill.
- 16:56 "You are essentially making me the auditor rather than doing
  this programatically. I want the "auditor" to fix all of the
  interface elements, and not make me responsible for fixing them. That
  feels backwards."
- 17:19 "Is there a reason why we have focused so much on tvOS 17+ when
  the modern version of tvOS is 26" and 17:24 "My app should absolutely
  require an Apple TV 4k."
- 20:00 "This looks and works SO MUCH BETTER!"
- 22:00 he brings in work of his own: "I worked on a significant update
  to the video/movie database and the schema for how we find and serve
  up videos and I've placed it within the /SchemaWork/ directory"
- 22:08 "I also think you should "teach" the pipeline all of the things
  that you have learned throughout iteration within the app [...] The
  goal is the have "the best of both worlds""
- 22:39 "I just want to be clear, there is no "cellular users" on Apple
  TV. Apple TV is a wifi only device. [...] Also, I'm about to go to
  sleep, so you should be able to run all of this in the background"
- 22:45 "Can you make it verbose so that I can see it happening?" and
  23:58 "Is it still running?"

**Days three and four.** 04-20: "Where are we at?", "How is the
progress?", `/remote-control` at 13:56 (checking in from away from the
desk). 04-21: "Can you research sources for tv art, if it is so hard to
find in our current sources?"; "Can you push please. I don't need them
locally. I need to test the app"; then a new capability answered as
three separate one-line messages to the agent's three questions ("1.
Definitely series should show and then let you dig into each episode
individually", "2. Treat anthology as one series", "3. Deep end-to-end
please"); and by afternoon "The app seems to just sit on the "Loading
catalog" screen (spinning wheel) forever (so far, 10 minutes)."

**The second start, 2026-05-31.** After five weeks away:

> "It has been a while since we worked on this project, and I'd like to
> see what we can do to pick up where we left off as we look to get
> this app ready to submit to the app store (after testing on my own
> Apple TVs first). Please read through all documentation and recommend
> the best course of action [...] so that we end up with Apple TV's
> premier app for discovering public domain movies, tv shows, and
> ephemera from the past 100+ years."

Then "We do have xcode command line tools that you can use to build
simulators and test code, so don't forget about those." (05-31 13:05),
and on 06-01 the first real hardware: "I don't see how to add my apple
tv to xcode in order to push new builds over there, so can you please
walk me through how to do that as well?" (08:27), followed thirty-five
minutes later by the first device crash (see F3).

**What the first two weeks show.** A start on the wrong device for the
job, fixed by moving. Data before design. The first review in a
simulator, with the simulator's quirks in the feedback. Six rounds in a
day, numbered, with deferrals named. A refusal to accept fixes without
understanding, turned into a request for a skill. Ben's own work (a
schema, reference apps, taste) brought in, not typed out. And the
background job and the "is it still running?" check that later became
loops.

#### BOBA Playbook: Cowork's files, Ben's hands, two platforms at once (2026-04-03 to 04-16)

**First afternoon, 2026-04-03.**

- 12:20, the kickoff:

> "I'm starting work on a iOS/Web App regarding Bo Jackson's Battle
> Arena cards. I have been working on it in Cowork and in the folder
> FromCowork, you will find the transition files to help replace your
> Decisions, Scratchpad, and Claude files. However, I have set up a
> robust template repository that has very strong opinions already in
> it for how development should happen and the values for all apps
> created with the template. This needs to be presered (particularly the
> values), so as you are merging the files and following the transition
> instructions to fully realize this app, please make sure none of that
> gets lost from the template files."

- 12:32 "I'd like you to walk me through these steps one by one. I think
  I put the 4 data JSONs you need into the right spot. Did I do it
  correctly?"
- 12:34 "I have a cloudflare account, but I don't think I have installed
  rclone", then `!brew install rclone`, then eight `! rclone` commands
  of his own between 12:42 and 12:55 to configure storage and upload
  the card images (credentials [redacted]), with "(Bash completed with
  no output)" pasted back once as if it were a message.
- 13:01 "It is very hard to copy and paste from claude code in macos
  because it doesn't copy cleanly. Is there any way to make it easier
  to copy out of terminal cleanly?"
- 13:03 pastes the database project URL and key [redacted].
- 13:09 asks what to use as his organization identifier in Xcode.
- 13:15 to 13:18 `! ls [...].xcodeproj`, `! git add -A && git status`,
  "Github pages are live at [the github.io address]", `! git push`.
- 13:19 "Shall we proceed?" then "Let's do it!"
- 13:35, the first review of real data: "It seems as though the card
  information and the images are entirely mismatched. There seem to be
  duplicate entries. And the Loading Card Catalog spinning wheel is
  persistent on the homepage."
- 14:04 "Please iterate upon this first version with the following
  pieces of feedback: [Pasted text #1 +7 lines]" (lost)
- 14:27 a domain correction only he could make: "The power levels of
  cards go up to 200, so the power ranges don't make sense (they go up
  to 10 for elite)"
- 14:50 and 14:57, the logo:

> "Oh my, no. Animation on a logo?! That is incredibly busy and
> unnecessary. Also, I don't love BOBA PB when the name is BOBA
> Playbook. [...] This is the THE APP for collectors of the cards and
> players of the game. You know all the plays. You know all the moves to
> make for your collection. The logo and textmark should embrace that
> and not something that is a "flash in the pan" as this shimmer does
> now."

- 15:14 "Can you check with the UIUX Pro skill and how well all of the
  fonts we are using right now match with one another"
- 15:21, the platform decision, three hours in: "Yes, Start M1 iOS. I'd
  like to move both versions of the app together along the development
  path"
- 15:45 "Can you check to see if I added everything correctly?" (in
  Xcode) and 15:49 "I want the fonts to work. I have put those files
  into the correct folder, as far as I can tell."
- 16:02 "The app says Could Not Load Cards, The data couldn't be read
  because it is missing. This is from the console:" and the console
  lines.
- 16:25 "I'm using my iPhone 15 Pro for testing. The initial card
  catalog loaded slower this time but the images loaded more quickly."
- 16:55 "It is still not nearly good enough. The 500 cards show up as
  loading after 10 seconds (and not less than one second)"
- 17:05 "the "Rules" view should change to "Play" (because the rules
  are about playing more than they are about staying within them). This
  change should happen on the web app too."
- 18:06 "For some reason when I add the web app to my homescreen on my
  iphone and then launch it, I get a github 404 page."
- 18:19 "Alright, it is finally time to start on the next milestone.
  Before you do that, can you document everything we've worked on so
  far and clean up anything that needs to be done on either the web app
  or iOS app?"
- 18:25 "Great. Let's begin on M2. Do you have any question at the
  beginning of this milestone that are unanswered by the current
  documentation?"
- 18:37, four numbered answers, including a request for research: "3. I
  think custom URL schemes don't work well on newer versions of iOS, so
  I'd like to do the most modern version of authentication from email
  to iOS app. This may require you to research what the most modern
  solution of that is." (item 4 included marketplace credentials,
  [redacted])

**The rest of the first two weeks**, in brief:

- 04-04: Sign in with Apple and email accounts, with Ben in the Apple
  developer portal and the database dashboard ("I would prefer that
  Xcode set up the Identifier, as it does a much better job. Can you
  walk me through that?"); M3 opened the same way ("Alright, let's get
  started on M3. What questions do you have for me before you begin?")
  and answered with seven numbered items; the card scanner iterated on
  his phone all evening, scored in his own numbers ("Well, now it is
  recognizing 0 cards. I tested about 20 different cards and it found
  0.", 21:11; "This version is very nearly perfect. I only had 1
  problematic scan out of 20 this time.", 22:00).
- 04-05: a research guide he wrote in Cowork arrives ("I worked on a
  comprehensive guide that you should use to build the M4 features");
  the first parity catch (see F2, stage 02).
- 04-06: five failed fixes on one page end with "Still no. Can you
  please build in a diagnostic tool to see what is happening. Good
  lord." and then colored debug borders he reports back (see F2,
  stage 04). `/remote-control` that evening.
- 04-07: "Alright, I'm ready to get the app onto Testflight (App Store
  Connect). Can you walk me through the remaining steps?" then "You
  have already done a few of these things for me. Can you go through
  and see how many of them I actually still have to do rather than just
  showing the full process?" and "What should my SKU be?"
- 04-09: App Store review preparation using two named skills, the
  first privacy policy modeled on Bsky Dreams', a unique ID for every
  card, and the first written handoff between Claude Code and Cowork.
- 04-13 to 04-16: deck builder and practice battle built from a Cowork
  mockup and the game's rules PDFs, with long numbered rounds from the
  iPhone.

**What the first two weeks show.** A beginner's setup afternoon, in the
open: files placed by hand, commands run with `!`, keys pasted, "did I
do it correctly?" asked three times. Two platforms from the first day,
by decision. Milestones opened by inviting the agent's questions and
closed by asking it to document. Research and data prepared in another
tool and handed over as files. Review on his own iPhone from the first
afternoon.

#### Tidbits Trivia: the template does the setup (2026-06-16 to 06-30)

By June the template carried the scaffolding, and the first day shows
it.

- 18:12 (commit) the repository is created from the template.
- 19:05 "[Pasted text #1 +22 lines]". The history lost the kickoff
  brief, but Ben's notes kept it (quoted in full in G2); the
  first commit quotes it as "A fully realized multi-player trivia game
  based entirely upon facts pulled from the open Wikipedia API ... The
  final outcome of this session should be a working iOS version with
  all v1 versions of the features fully implemented."
- 20:00 "Go ahead and commit and change my standing instruction to
  commit and the communicate rather than ask and then commit. Also,
  keep pushing forward with the next round of work to fully build out
  this game/app"
- 20:41 "Let's tackle the quality moat next"
- 22:57 "I thought I told you to commmit and push and then communicate
  about it. Please keeep pushing forward with the next set of work to
  build this app!"

**Day two, 2026-06-17.**

- 06:01 the first content critique and the first research request:
  "It seems as though there are very vew different question types [...]
  (you can figure out the right answer because of the way that the
  distractors and correct answers are written). [...] "Is best
  described" seems to be the most common cliche in the questions right
  now [...] Please conduct additional research to understand all of
  the options for creating truly great trivia questions and question
  types."
- 06:11 "Are you still waiting for the background agent to finish or
  can you continue the work?"
- 07:47 "Can you check on the progress?"; 09:16 "It has been over an
  hour, and progress?"; 09:33 "I don't see any changes to the questions
  on the web app"
- 11:19 "Okay, can you prep for our first compaction by documenting
  everything we need in order to push forward with the next iteration
  of the apps across all platforms?"
- 13:45 "I think before we head into the pursuing the launch of the
  apps, we need to get the question asking and the game modes fully
  functioning. I'm testing on the web, which is the easiest way for me
  to see the progress, and I still see mostly the same kinds of
  questions [...] If we have over 10,000 questions now, the likelihood
  that I would see the same question twice should be almost 0."
- 14:21 screenshots as evidence: "There are multiple instances of
  questions were the answer is literally in the question: [Image #1]
  [Image #2]"
- 15:23 "The cardiff question has come up in every single question set
  I've tried."

**The rest of the first two weeks**, in brief:

- 06-18 15:48 "We aren't the first to do it, but we are going to be the
  best! Make your own skills if necessary."
- 06-19 09:01 bought the domain and pointed the web app at it; 09:33
  "We want the questions to feel like they are being asked in a bar
  during trivia night."
- 06-19 15:20 "Alright, let's get the first version of the iOS app ready
  for my iPhone. What do we need to do in order to get it ready for
  testing on testflight/" and 15:30 "Let's get it set up in xcode
  rather than through the command line, shall we?"
- 06-19 16:13 the first phone review; 16:16 "I don't know the name of
  colors. Whatever color is behind the icon is what I want to fill the
  full screen on the splash screen."; four icon rounds ending 17:18 "I
  like the sqaure looking T. Let's ship it everywhere!"
- 06-20 08:03 the first feature research: "please deeply research and
  document all of the different types of "bar trivia" games so that
  Tidbits Trivia can innovate on them"
- 06-20 14:25 "I see that you have in fact stopped. I see nothing
  running." and 15:13 "Have you instituted an autonomous loop to make it
  all the way through the backlog?"
- 06-22 09:16 managing cost: "I cannot just keep burning tokens to make
  this happen [...] Can you strategize a way to allow a smaller model or
  a more economic method of handling this task"
- 06-22 15:00 "I just launched the app for the first time on Apple TV
  and the interface is showing as far bigger than the screen size."
- 06-23 11:55 the first multi-device play: "The buzzer from the iphone
  to the apple tv seems to work very well, but I would prefer that the
  first person to buzz in be able to answer the question on their
  device"
- 06-30 11:01 "I would like to submit the first beta of Tidbits Trivia
  to google play [...] You should have documentation for how to submit
  using the CI"

**What the first two weeks show.** When the template carries the
setup, the first day is four prompts and the second day is about the
content. The first review happened on the live web app because it was
easiest. The first corrections were about quality only real data could
show. The phone and the TV came on days four and seven, and his
standing instructions (commit then tell me; loop through the backlog)
were set in the first forty-eight hours.

### F2. Stage-by-stage harvest

The best early examples for each stage of the course, chosen for how
plainly they show a beginner the move. Each carries one sentence on
what was happening.

#### 00. Values and why

- "However, I have set up a robust template repository that has very
  strong opinions already in it for how development should happen and
  the values for all apps created with the template. This needs to be
  presered (particularly the values)" (BOBA, 2026-04-03 12:20). The
  first sentence of a new app, before any feature, protects the values
  paragraph while merging in files from another tool.
- "I'd also like it to showcase the style of Bsky Dreams and emphasize
  the core beliefs around learning and community that are baked into
  the project." (Bsky, 2026-03-04 13:59). On his second CLI day he asks
  for the README to say why the app exists, not just what it does.
- "Please also make sure we are continuing to highlight the values and
  the important decisions being made about how we build and not just
  what we build." (BOBA, 2026-04-12 13:53). A routine request to tidy
  the working docs carries an explicit instruction to keep the values
  in them.
- "This is NOT what I want. I want my app to be indpendent from Radish.
  You can look at the stucture from Radish, but if we are just using
  Radish, there is no reason for this feature to exist. People should
  just go to radish, right?" (BOBA, 2026-04-12 12:33). The agent had
  built a price feed by leaning on another site, and Ben rejects it on
  the grounds of why the feature should exist at all.
- "Can we try to ensure that the data from discord is not actually
  being saved in the app but rather simply being used for that session
  and then removed. This should ensure that Data is not actually being
  used to track you." (BOBA, 2026-04-08 10:31, item 6 of his answers).
  Answering the agent's design questions for a chat feature, he sets a
  privacy line before any code exists.
- "I did some more digging, and it looks like OpenSubtitles have
  depricated opensubtitles.org in favor of a higher cost for
  opensubtitles.com. This doesn't fit with my interest in keeping costs
  at $0. So, we have to find another source." (Archive Watch,
  2026-06-22 14:05). The $0 rule, stated as a reason to drop a source
  he had just chosen.
- "I'd like to make sure we are leaning into creating feeds that are
  more about conversations, question asking, and authentic engagement
  rather than rage baiting or simply re-posting the same things over
  and over. This is a check to see how aligned the feed is with the
  values for how we build software." (Bsky, 2026-06-17 11:58). He asks
  for a values audit of a shipped feature by name.
- "The free features should NEVER feel like a compromised experience.
  Daily Tidbits and other casual gaming types on the mobile apps should
  never cost money or be hidden behind a paywall." (Tidbits, 2026-07-19
  10:10, rule 1 of 8). Before any pricing research, he writes the
  values the monetization must meet as a numbered list.

#### 01. First prototype

- "1. We need more results, so please either research other data
  options and build the port for wikidata. 2. Please delete anything
  redundant or not useful. I was hampered by being on claude code on my
  phone, so you can really make it a lot better for the actual app
  build. 3. Yes, I want to actually build a robust catalog to test in
  the simulator on xcode." (Archive Watch, 2026-04-18 07:34). The first
  session had happened on his phone; he moves to the Mac, answers the
  agent's questions by number, and names the first place he will look
  at the app.
- "Okay, the app works in the simulator. The videos play, but there are
  astonishingly few of them. [...] Please conduct exhaustive research
  and put together a multi-source plan for increaseing the database to
  over 1000 items" (Archive Watch, 2026-04-19 06:27). His first look at
  a running prototype judges the data, not the screens, and asks for
  research before more code.
- "I would like to revise the look and feel [...] Please let me know
  what questions you have about this transformation of the interface
  for this web app." (Bsky, 2026-03-03 15:49). A wish with a named
  aesthetic and a named skill, closed by inviting questions.
- "It seems as though the card information and the images are entirely
  mismatched. There seem to be duplicate entries. And the Loading Card
  Catalog spinning wheel is persistent on the homepage." (BOBA,
  2026-04-03 13:35). The first review of the first build,
  sixteen minutes after "Let's do it!": three plain observations, no
  diagnosis.
- "The power levels of cards go up to 200, so the power ranges don't
  make sense (they go up to 10 for elite)" (BOBA, 2026-04-03 14:27). A
  one-line correction that only someone who knows the domain could
  make.
- "Go ahead and commit and change my standing instruction to commit and
  the communicate rather than ask and then commit. Also, keep pushing
  forward with the next round of work to fully build out this game/app"
  (Tidbits, 2026-06-16 20:00). Fifty-five minutes after the kickoff,
  he sets a working rule and asks for the next round rather than polishing.
- "I'm testing on the web, which is the easiest way for me to see the
  progress, and I still see mostly the same kinds of questions [...] If
  we have over 10,000 questions now, the likelihood that I would see
  the same question twice should be almost 0." (Tidbits, 2026-06-17
  13:45). He picks the easiest surface to review on and reasons from
  the numbers to the bug.
- "Great. Let's begin on M2. Do you have any question at the beginning
  of this milestone that are unanswered by the current documentation?"
  (BOBA, 2026-04-03 18:25). How he opened each early milestone: ask the
  agent what it needs to know, then answer in a numbered list.

#### 02. Shape: data plane and parity

- "Yes, Start M1 iOS. I'd like to move both versions of the app
  together along the development path" (BOBA, 2026-04-03 15:21). Three
  hours in, he decides two platforms will advance in step rather than
  one after the other.
- "Why does the iOS app say there are 17,838 items in the database but
  the web app says it has only 12,036? I would like there to be parity
  across both versions of the app and to have the most cards available
  to be searched" (BOBA, 2026-04-05 12:16). The first parity catch
  comes from reading one number on two screens.
- "I think this is the wrong approach because the art for each of these
  cards is different (the image file is also different). You should
  always use the image file difference to determine if the card is
  different and not the card number." (BOBA, 2026-04-05 12:21). The
  agent proposed deduplicating by card number; Ben defines what makes
  a record distinct, which later became a unique ID for every card.
- "I need all of the interfaces to have their functional equivelance of
  the URL structure for posts [...] These url structures should be easy
  to understand and should allow for the most usage throughout the
  webapp (linking diretly to elements and using the native forward and
  back keys of a browser appropriately)" (Bsky, 2026-03-11 17:06). He
  asks for a canonical URL for every surface of the web app, the idea
  behind the template's "every screen has a link" rule.
- "First, I want it to be clear that the "seen posts" methodology from
  the web app is the one that I would prefer, so please attempt to
  match the way that "seen posts" are calculated [...] All of this
  should be able to be synced across devices using the metadata within
  the AT Protocol API." (Bsky, 2026-03-16 15:16). He names which
  platform's behavior is the reference and where the shared data lives.
- "I would like you to take a look at all of your documentation as well
  as the web app itself [...] to write up a full list of all features
  that are only available within the iOS app. And then I would like you
  to systematically attempt to create parity for everything that is
  possible to implement within the web app version" (Bsky, 2026-03-23
  14:40). The first parity audit, asked for in plain words, a week
  after the iOS app began.
- "I noticed that the daily tidbit on android is different than it is
  on iOS and it is also different than it is on the web. For it to be
  truly daily across all platforms (and for the right and wrong answers
  to mean the same thing), it has to be the same across all platforms."
  (Tidbits, 2026-07-01 17:33). The origin of the cross-platform
  determinism lesson, found by playing the daily game on two devices.
- "If you anticipate a gigibyte size database, how are we going to
  manage that within an Apple TV app? Should we rethink the archetecture
  [...] Or, have we done good enough filtering on the data" (Archive
  Watch, 2026-04-19 22:35). On day two, he asks the shape question
  himself, in product terms.

#### 03. Native platforms and floors

- "The goal of the conversion is not to re-think the app, but rather to
  re-create it as a native app with the same functions and style."
  (Bsky, 2026-03-15 07:50). The morning after the first iOS build, he
  states the difference between porting a design and rebuilding it
  natively.
- "Is there a reason why we have focused so much on tvOS 17+ when the
  modern version of tvOS is 26 and has many design elements that are
  new and much more modern looking (liquid glass, etc.)" then "My app
  should absolutely require an Apple TV 4k." (Archive Watch,
  2026-04-19 17:19 and 17:24). The floor decision, made in two
  sentences on day two.
- "I guess that is why a lot of my favorite apps prefer a sidebar
  implementation for navigation that allow syou to use the arrow
  buttons instead of the back button to navigate." (Archive Watch,
  2026-04-19 15:46). After six failed focus fixes, he reaches for how
  the platform's best apps solve it.
- "NO! This is absolutely 100% not the case. When I share an image from
  the photos app to Bluesky, it launches the Bluesky app with the image
  contained within the Bluesky compose window. [...] I can do this for
  Facebook, Discord, Gmail, Notion and many others. Please stop telling
  me it isn't possible and implement it the same way that these other
  apps have." (Bsky, 2026-03-19 11:31). The agent claimed a platform
  limit; Ben answers with the apps on his own phone. It worked an hour
  later ("It worked!!! Thank you.", 12:34).
- "The universal gesture for "go back" a screen is to swipe in from the
  left side of the screen toward the right. This gesture should be
  preserved for every interface within the app" (Bsky, 2026-03-17
  10:42). A platform convention stated as a rule, with the reason.
- "Alright, given that we are releasing a version of the app for iPad,
  we should probably optimize for those screen sizes [...] (iPads are
  far more often used in landscape than portrait) [...] I'd like to make
  that version of the app a first-class and native experience as well."
  (BOBA, 2026-05-06 13:20). The iPad is not a big iPhone, said in May,
  three months before he said it for Archive Watch.
- "I don't want this to be a simple port of the iOS app. I want it to
  feel native to Android and I want feature parity with the iOS version"
  (BOBA, 2026-05-19 10:06). His first Android prompt: native and parity
  in the same sentence, with research first.
- "You should not build a plan to make the Apple TV version into the
  definitive version, but rather to build the features for the specific
  platform" (Archive Watch, 2026-06-09 10:55). Starting three new
  platforms at once, he forbids the easy route of copying the first
  one.

#### 04. Seeing it work on devices

- "Please create a test for how you will determine if a post is
  rendered a signgle time and continue to work until your code passes
  that test." (Bsky, 2026-03-14 22:12). The first night of a new
  platform, after three failed fixes, he asks for a way to know, not
  another attempt.
- "Single taps do not work to select nodes unless I first tap and drag
  outside of the network visualization. [...] I need you to create a
  way for you to determine that the following actions will work before
  implementing yet another fix that doesn't work. 1. Individual taps of
  a node should select the node. 2. [...] 3. Pinch to zoom with two
  fingers should function. 4. [...]" (Bsky, 2026-03-18 11:18). He turns
  a stuck gesture bug into four numbered acceptance criteria.
- "Can you update the Claude.md, Decisions.md, and Scratchpad.md for
  the recent updates and to update an approach toward testing so that
  we don't have to go through 16 iterations on any single feature
  before you simply implement tests for me to do with results in the
  console?" (Bsky, 2026-03-18 13:34). After the sixteenth attempt, he
  asks for the lesson to be written into the working docs.
- "The debug says: DBG: vsc=regular req=T land=F. The values do not
  change when I tilt the phone to landscape view (as if it isn't even
  listening for landscape orientation on that screen)" (Bsky,
  2026-03-24 14:35). He reads a temporary on-screen debug overlay off
  his phone and reports what it proves, the exact technique the
  template's debugging section now teaches.
- "Still no. Can you please build in a diagnostic tool to see what is
  happening. Good lord." then "The Red border show on the Rookie and
  Playmaker pages. However, A blue border and a green border show on
  the substitution page." (BOBA, 2026-04-06 16:13 and 16:17). Five
  blind fixes, then colored debug borders that gave him something
  concrete to report within four minutes; the fix followed that
  afternoon ("Finally, the rubber banding and horizontal scroll is
  gone. Please document this so that it doesn't happen again.", 16:59).
- "You are essentially making me the auditor rather than doing this
  programatically. I want the "auditor" to fix all of the interface
  elements, and not make me responsible for fixing them. That feels
  backwards." (Archive Watch, 2026-04-19 16:56). The agent built a
  validator that reported problems to Ben; he wants one that fixes
  them.
- "Alright, please read the handoff and divergence notes. I believe we
  need to test the app on real hardware in order to finish the last
  group of work before moving forward. I don't see how to add my apple
  tv to xcode in order to push new builds over there, so can you please
  walk me through how to do that as well?" (Archive Watch, 2026-06-01
  08:27). Six weeks in, the first real device, and he asks to be walked
  through it.
- "Alright, I watched the same one that kept stalling for 5 minutes
  without any stalls. I think it is fixed." (Archive Watch, 2026-06-03
  19:27). After pasting stall logs from his Apple TV, he verifies the
  fix by repeating the exact case that failed.

#### 05. Shipping

- "Okay, I think we are ready to upload the initial version of the app
  to the app store. Can you update the App_Store_Guide.md for this
  process, giving more detail to Part 3 and later, as I'm running into
  errors with registering/finding my bundle ID" (Bsky, 2026-03-20
  09:27). His first store submission, asked for as a guide he would
  follow himself.
- "It is NOT registered to another developer. Everything that I've
  tried to put in there (this is now the fourth change including one
  that had my name in it). You need to investigate a different reason
  why this is failing." then "Alright, I figured it out." (Bsky,
  2026-03-20 10:03 and 10:12). The bundle ID saga: most of an hour in
  the developer portal, the agent guessing, and Ben solving it himself
  (at 09:57 he had found he was signing with his personal team rather
  than his company's; the final fix he never described).
- "My version number won't increment even when I change it in the
  identity section before archiving. Why does it still say version 1.0
  when it archives instead of 1.01?" then "Can you make it so that when
  I increment the identity field for the Bsky Dreams target (the
  version number and the build number) that these numbers match
  everywhere else that they need to?" (Bsky, 2026-03-21 08:11 and
  2026-03-23 08:27). The origin of the template's single version file;
  two weeks later he asked BOBA for "an AppVersion document" like the
  one in Bsky Dreams (2026-04-07 14:47).
- "My first version of the iOS app was rejected by Apple App Review.
  [...] Can you please resolve the issues within the code and provide me
  with a response that will allow the app to be accepted" then
  "Doesn't the app have orientation lock and is only avaialble for
  iPhone, so the orientation shouldn't matter on the iPad [...] Also,
  shouldn't we point to other bluesky apps instead of email apps for
  precedent?" (Bsky, 2026-03-24 06:53 and 06:56). The first rejection:
  he asks for a fix and a reply, then corrects the agent's reasoning
  before it goes to Apple.
- "The iOS app is now live on the app store at [the App Store link].
  Please add both a "Smart App Banner" to the web app version" (Bsky,
  2026-03-31 08:44). Launch day's first request is to connect the web
  app to the native one.
- "You have already done a few of these things for me. Can you go
  through and see how many of them I actually still have to do rather
  than just showing the full process?" (BOBA, 2026-04-07 13:58). He
  asks for the list of what only he must do, the seed of the later
  "owner tasks" habit.
- "Can you manage the file versioning and build numbers for each change
  we make from here on out? I like the 1.001 structure for versioning
  so that we don't get to 2.0 too quickly." and "Can you add the
  compliance aspect (App Encryption documentation), so I don't have to
  do it every time a new version drops?" (Archive Watch, 2026-06-04
  09:19 and 09:30). Each repeated manual step becomes a request to
  automate it.
- "Please push to all of the app stores. I was asking you to do that so
  that I could test." (Tidbits, 2026-07-01 15:05). By July a store
  build is how he gets the app onto his own devices.

#### 06. Keeping it running

- "Also, I'm about to go to sleep, so you should be able to run all of
  this in the background (assuming you auto approve things that might
  come up while I'm asleep). Can we set that up once you update
  things?" then "Can you make it verbose so that I can see it
  happening?" (Archive Watch, 2026-04-19 22:39 and 22:45). The first
  unattended job, on day two, and the first demand to see progress.
- "The cannonical TV build failed: [the Actions run link] Can you
  figure out why and fix it" (Archive Watch, 2026-06-02 11:42). The
  earliest pattern for CI: paste the failing run, ask for the cause.
- "Are you sure removing the weekly cron is the right move? We had set
  up all of the crons so that the catalog continues to improve every
  day/week on its own without my manual intervention." (Archive Watch,
  2026-06-03 09:57). He defends the scheduled pipeline as the point of
  the design.
- "I don't see you doing anything. I need you to implement a loop to
  continue tasks so that you don't just stop when you finish the first
  set." (Archive Watch, 2026-06-03 20:14). The first request for a
  loop, because the agent stopped after one batch.
- "Are there any outstanding tasks that can be worked on in the
  meantime, and did you build an hourly progress update for the
  background tasks you are running? I always like to know just how
  long things will take with regular progress updates." (Archive Watch,
  2026-06-08 09:26). What he wants from long-running work, stated early.
- "You were in the middle of a very large playbook task that made my
  machine completely unusable AND caused it to shut down because of the
  work you were doing. Can you research how to do this work in a less
  resource intensive way" (Archive Watch, 2026-06-20 10:30). The
  incident behind "keep the Mac light."
- "I want to make sure that we are transitioning to the cloudflare
  workers entirely for the future. I'm okay to run more locally now, but
  the whole point is to make it so that the estimator and the data is
  getting better over time without being dependent upon my mac running."
  (BOBA, 2026-05-30 09:09). The reason work moves off his Mac.
- "It seems like these loops are really circling around the same exact
  features and are never expanding out into areas that actually need
  work. [...] I'm not sure you ever investigated the research folder
  for the discord exports to mine them for additional feature
  ideas/requests." (BOBA, 2026-05-21 07:02). His first correction of a
  loop's choice of work.

#### 07. Raising the ceiling

- "Yes, I would like you to set this up to ingest these commercials
  into our database. [...] The real purpose of these commercials is to
  suppliment and build out the Channels interface. [...] it should
  actually look like an old school channel guide [...] Here is a modern
  and a retro version of what I am talking about: [Image #3] [Image #4]"
  (Archive Watch, 2026-06-05 08:33). A new feature described by its
  purpose, with reference images and a request to research before
  building.
- "Can you investigate this github repository to determine if there are
  any ways to further improve the discover (on the home interface),
  reader, search [...] views" then "I'd really like to avoid
  overcomplicating the Home feeds/view as much as possible with a lot of
  different options (a significant drawback of the official Bluesky
  app)." then "I'm open to [...] a self-hosted feed generator as long as
  it can be done via a similar setup to the Github Pages web app
  implementation (i.e., no implementation costs)." (Bsky, 2026-04-01
  13:56, 14:04, 14:13). Research from a source he found, bounded by
  simplicity and $0 within twenty minutes.
- "How easy would it be to implement a single Discord channel chat from
  the official BOBA discord [...] Let me know what questions you have
  about this implementation." then "I don't want bot access. I want
  people to be able to login with their own accounts and simply send
  messages as themselves." (BOBA, 2026-04-08 10:21 and 10:24). A
  feasibility question, then a correction on how people should
  experience it.
- "This request came from the following feedback from a beta tester:
  [...]" and "Definitely Plan A is the way to go." (BOBA, 2026-05-15
  13:37 and 13:40). A feature that started as a tester's sentence.
- "I'd like to start working on alternative game modes, particularly
  ones that let you use your phone as the "buzzer" [...] please deeply
  research and document all of the different types of "bar trivia"
  games so that Tidbits Trivia can innovate on them" (Tidbits,
  2026-06-20 08:03). Research first, framed as learning from an
  existing tradition.
- "I think this interface needs a pretty fundamental rethink. All of
  the elements are there, but it is not intuitive [...] You could learn
  how to do this better by research how CapCut does their scrubbers and
  clipping" (Archive Watch, 2026-06-16 09:27). A critique that names the
  app people already know.
- "Alright, I'd like to work on integration from my app to one of my
  favorite apps (Callsheet [...]). I have written to the creator of
  Callsheet [...] and this was his response when I asked about it:
  [Pasted text #4 +14 lines]" (Archive Watch, 2026-06-19 15:09). He
  wrote to another app's developer himself and handed the answer over.

#### 08. Working with AI: memory, skills, handoff

- `/plugin marketplace add nextlevelbuilder/ui-ux-pro-max-skill`
  (Bsky, 2026-03-03 15:45). His first act in the CLI record was
  installing a skill, and his first request used it by name.
- "Befoore you compact again, can you please document everything you
  have tried so far to fix the rounded rectangle outline for the post
  button [...] I want you to be aware of what has been tried thus far."
  (Bsky, 2026-03-17 08:48). Writing down failed attempts so the next
  context does not repeat them.
- "It worked!!! Thank you. Also, can you document this
  process/iterations to ensure that all deprecated approaches are not
  attempted again the future." (Bsky, 2026-03-19 12:34). The moment of
  success used to capture the lesson.
- "I think you will need to do the systematic study yourself given that
  there doesn't seem to be a dedicated skill available. So, this would
  be you developing a world-class tvOS design and development skill"
  (Archive Watch, 2026-04-19 16:25). When no skill exists, the agent
  writes one.
- "I would like to be able to go back and forth between this claude
  code instance and my research claude cowork instance [...] Can you
  create a way that I can easily handoff changes from claude code to
  Cowork and back so that nothing gets missed?" (BOBA, 2026-04-09
  13:54). The first written handoff between two AI surfaces.
- "I am looking to create a new web app and iOS app that is completely
  different than Bsky Dreams [...] I would like to create a new version
  of this template that takes the best things that we have learned"
  (Bsky, 2026-04-01 15:16). The first upstreaming, the day after the
  first app went live; the Xcode Cloud "project does not exist at the
  root" error is named as a reason.
- "Can you also look through all of your documentation for the lessons
  learned and the way in which I do web, iOS and iPadOS development with
  the values I have and make claude skills that will help to produce
  repeatable and highly sophisticated results within this repository
  and others?" (BOBA, 2026-05-18 09:50). Skills asked for as the
  deliverable, not as a side effect.
- "I'd like you to document a skill for autonomous loops that documents
  the cadence we have established for updating all platforms, the
  balance of fixes, new features, and optimization" (BOBA, 2026-05-21
  09:49). The origin of the template's `autonomous-loop-cadence` skill.
- "I need you to verify that you are both using the right model for
  such work AND that you are using agents sequentially instead of
  concurrently. If you do them concurrently, they will all hit the
  session limit at the same time and return no useful information."
  (Tidbits, 2026-07-14 11:10). A cost lesson turned into a rule.

### F3. Moments that would make good stage-opening stories

1. **The phone that could not finish the job (stage 01, Archive Watch,
   2026-04-17 to 04-19).** Ben started Archive Watch in Claude Code on
   his phone, then moved to the Mac the next morning because "you can do
   things that the desktop app cannot." His first look at the app, in
   the tvOS simulator a day later, was not about screens at all: "The
   videos play, but there are astonishingly few of them," followed by a
   request for exhaustive research.
2. **Four prompts and a morning on the web (stage 01, Tidbits,
   2026-06-16 to 06-17).** A pasted brief, "commit then tell me,"
   "tackle the quality moat," "keep pushing," and by the next afternoon
   Ben was playing the web version and noticing the same question about
   Cardiff in every set. The lesson is that real data exposes the real
   problem on day two.
3. **"Oh my, no. Animation on a logo?!" (stage 00 or 01, BOBA,
   2026-04-03 14:57).** Under three hours into a new app, Ben rejects a shimmer
   logo by saying what the app is for: "This is the THE APP for
   collectors of the cards and players of the game." Taste stated as
   purpose.
4. **Two numbers that should match (stage 02, BOBA, 2026-04-05
   12:16).** The iOS app said 17,838 cards and the web app said 12,036.
   The agent's fix would have merged cards by number; Ben said a card is
   defined by its image, which led to a unique ID for every card four
   days later.
5. **"Not to re-think the app, but to re-create it" (stage 03, Bsky
   Dreams, 2026-03-14 to 03-15).** Ben creates the Xcode project
   himself, pastes a dozen messages of compiler errors, finds every post
   drawn twice, asks for a test, and the next morning writes the
   sentence that separates a native rebuild from a redesign.
6. **"Why can other apps accomplish this?" (stage 03, Bsky Dreams,
   2026-03-19).** The agent says a share sheet cannot open the app. Ben
   answers with Bluesky, Facebook, Discord, Gmail and Notion on his own
   phone, pastes console logs five times, and at 12:34 writes "It
   worked!!!" and asks for the failed approaches to be documented.
7. **Sixteen tries at one gesture (stage 04, Bsky Dreams, 2026-03-18).**
   Dragging a node in a network graph failed for a whole morning. Ben
   wrote four numbered acceptance criteria, reported that passing tests
   did not mean a working feature, and ended by asking for the testing
   approach itself to change "so that we don't have to go through 16
   iterations on any single feature."
8. **The first real Apple TV (stage 04, Archive Watch, 2026-06-01).**
   Six weeks of simulator work, then "walk me through how to do that,"
   and thirty-five minutes later a fatal error: the app could not write
   to a folder the simulator had always allowed. It is the tvOS
   writable-directory lesson in the template, found the first time the
   app touched hardware.
9. **Colored borders after five blind fixes (stage 04, BOBA,
   2026-04-06).** One page scrolled sideways and five fixes changed
   nothing. "Can you please build in a diagnostic tool to see what is
   happening. Good lord." The agent drew colored borders; Ben reported a
   blue and a green border that should not exist, and within the hour
   wrote "Finally, the rubber banding and horizontal scroll is gone.
   Please document this so that it doesn't happen again."
10. **The bundle ID that would not register (stage 05, Bsky Dreams,
    2026-03-20).** Four identifiers rejected, the agent apparently
    suggesting the name was taken, Ben insisting it was not. Along the
    way he found he had been signing with his personal team instead of
    his company's, and ten minutes after his last complaint he wrote
    "Alright, I figured it out." and moved straight on to a dark-mode
    fix. A true account of what shipping the first time feels like.
11. **The version number that would not change (stage 05, Bsky Dreams,
    2026-03-21 to 03-23).** Ben changed the version in Xcode and the
    archive still said 1.0; then the share extension's version stopped
    matching the app's. His request to make the numbers "match
    everywhere else that they need to" is where the template's single
    version file comes from.
12. **Going to sleep with the job running (stage 06, Archive Watch,
    2026-04-19 22:39 to 04-20).** Ben asks for the catalog build to run
    overnight, asks for it to be verbose "so that I can see it
    happening," and checks at 23:58, 07:09, 08:37, 13:10 and 19:07. The
    first unattended job, and every question a loop later has to answer.
13. **"I need you to implement a loop" (stage 06, Archive Watch,
    2026-06-03 19:42 to 20:14).** Ben hands over a pasted backlog (the
    commit calls it "the 20 requested items") to be done autonomously, sees the agent ask him questions and then
    stop, and says "I don't see you doing anything. I need you to
    implement a loop to continue tasks so that you don't just stop when
    you finish the first set."
14. **The first rejection answered twice (stage 05, Bsky Dreams,
    2026-03-24).** Apple rejected the first build. Ben asked for fixes
    and a reply, then three minutes later corrected the agent's draft:
    the app is iPhone only, and the precedent should be other Bluesky
    apps, not email apps. The reply that goes to a reviewer is his.
15. **"A check to see how aligned the feed is with the values" (stage
    00, Bsky Dreams, 2026-06-17).** Three months after launch, Ben
    notices what the Discover feed is showing, tests it with a second
    account, and asks for research into a feed built around
    "conversations, question asking, and authentic engagement rather
    than rage baiting." Values used as an audit, not a slogan.

### F4. What the early record changes about sections A to E

In short, and already folded into the sections above:

- **He started where a beginner starts.** On his phone, in the web
  version of Claude Code, and in the simulator; with GitHub Desktop
  commits and merge conflicts; with a usage limit hit in the first hour.
- **He did the Xcode half by hand for three months.** Creating
  projects and targets, moving folders, pasting compiler errors one
  message at a time, pressing the Play button to reach his iPhone,
  archiving and uploading.
- **He ran commands and handled keys himself.** `!` commands for
  storage, workers, git and logins; service keys pasted into the chat.
  The later credential friction (sections B05 and D) is the other end
  of this.
- **He asked for tests and diagnostics from the first iOS night,** and
  ran them himself, before he asked the agent to run them.
- **He installed skills himself and named them in prompts,** and told
  the agent to write one when none existed.
- **He brought work from elsewhere:** Cowork data and guides, his own
  schema pass, rules PDFs, reference repositories, a developer's reply,
  testers' messages.
- **His early feedback rounds were mostly pasted** from notes written
  away from the chat, so the most detailed early critiques are the ones
  the prompt history lost. Section G recovers many of them from the
  notes themselves.

## G. Ben's notes: where the prompts were drafted

Sections A to F read Ben's prompts from the Claude Code side. This
section reads them from the other side: the Apple Notes he kept while
building, where most of his long prompts were written before they were
pasted. Six exports were available:

- **"Tidbits Trivia"**, the running note for Tidbits Trivia.
- **"Public Domain Apple TV App"**, the running note for Archive Watch
  (the app's working title before it had a name).
- **"Boba App ideas"**, the running note for BOBA Playbook, by far the
  longest (about 100 KB).
- Three single-prompt notes, each titled by its first line because that
  is how Notes names a note: "We need to work on a few things within
  the Android TV version of the app", "1. Yes. Move forward with a single
  clock", and "/loop It is now time to do a full audit of our
  database". All three are Archive Watch.

How the blocks were dated. The prompt history records a pasted block as
"[Pasted text #N +M lines]", where M is one less than the block's line
count, and keeps the sentence Ben typed around it. A note block is
treated as matched when its line count fits, its content fits the
prompts on either side, and (where there is one) a commit or a
follow-up prompt refers to it. Blocks he typed or pasted as plain text
match word for word. Where a block is not in the CLI history, this
section says so; some sessions ran on other surfaces (the phone, the
web, Cowork), and the history only covers the CLI on his Mac.

The notes also held things that must never be copied: service keys,
tokens, a keystore's certificate fingerprints, a database password, an
OAuth secret, project numbers, channel URLs. All of it sat in the same
note as the feedback rounds. None of it is reproduced here, and where a
quote touched it, it reads [redacted]. Names of friends and testers are
replaced with "a friend" or "a tester". Typographic quotes are
normalized; Ben's spelling is kept.

### G1. The practice: one running note per app

**One note per app, kept for the life of the app.** Each running note
starts with the wish and then grows downward, round by round, for
months. The Archive Watch note runs from the April feature ideas to the
September Roku search feed. The BOBA note runs from the first vision
list, through thirteen numbered "Feedback" rounds, to the Android beta,
a partner's data revocation in late May, and a CDN domain move after
it.

**The shape of a running note**, top to bottom:

1. **The kickoff or vision at the top.** A one-sentence wish, then a
   numbered feature list, then research asks, then what the session
   should produce (G2 quotes all three).
2. **Naming, before anything is built.** The BOBA note keeps two
   numbered lists of candidate app names ("Alternative app names" and
   "App Names", twenty-one in all, with his own verdicts in brackets
   such as "(still too close)" and "(too close?)").
3. **Numbered rounds with a plain heading.** "Next:", "Next feedback:",
   "Next Feedback:", "Next round of updates:", and in BOBA "Feedback 2"
   through "Feedback 13". Some rounds are named for their subject
   instead: "Navigation Update:", "Streaming Features:", "Profile view
   updates:", "Web App Updates:", "Updates to the Practice Battle setup
   screen:", "Feedback on Pricing inconsistencies:", "Feedback on Web App
   Version of Deck Builder and Practice Battle:". Each item is one
   observation from using the app: where it is, what is wrong, what it
   should be, and on which platforms.
4. **A ledger.** The Archive Watch note has "Done:" (five items moved
   there from the idea list), "Fix:" (two data errors he spotted), and
   "Outstanding items:" (social media promotion). The BOBA note has
   "Future:" (a long list of ideas with question marks) and checkboxes
   for non-code tasks. Archive Watch ends with "Ideas for further
   execution and/or monetization".
5. **Loop charters drafted ahead.** Whole `/loop` prompts, written in
   the note with the `/loop` already typed at the front, sometimes days
   before they were sent (G3, stage 06).
6. **Answers to the agent's numbered questions,** written as a numbered
   list that mirrors the agent's numbering ("1. Yes. Move forward with
   a single clock", G3 stage 08).
7. **Outside voices.** A friend's request ("Request from [a friend]: Oh
   please do Google home integration!"), testers' messages with Ben's
   draft replies underneath, a partner's email pasted whole, and
   experts' feedback on card terminology.
8. **Owner actions the agent handed back.** Instructions Ben had to act
   on himself, kept until he did: an OAuth client to create in a cloud
   console ("One owner action: create a Desktop app OAuth client in
   Google Cloud project [redacted] ..."), a DNS move written out as
   numbered steps, the setup steps for connecting a second tool's
   services to the CLI, and a table of Android Studio menu items next to
   their Xcode equivalents.

**How the notes relate to what reached Claude Code.** The notes are
where the long prompts were written; the terminal is where they were
sent. Ben wrote a round while using the app on a device, away from the
chat, then pasted the whole block with a one-line preamble that set the
scope. The preambles are the part he typed at the Mac:

- "Please work on the following ten tasks as a set of large updates for
  Tidbits Trivia across all platforms. However, before you start please
  read through your documentation for how we build and where we are in
  the progress of each platform:" (Tidbits, 2026-07-01 12:39)
- "Here are the intitial pieces of feedback for the two new features.
  Although they were written while only looking at the web app version
  of the features, some of them also have implications for how the iOS
  version is built, so please pay attention to both for any issues that
  need to be resolved for b[oth]" (BOBA, 2026-04-13 14:29)
- "Please use any iOS software building skills to make the following
  updates on the iOS app (while paying attention to anything that would
  also need to be updated on the web app to be completed in a
  subsequent session):" (BOBA, 2026-04-14 12:03)
- "Alright, it is now time to build out the big backlog to take this
  app through to its first version I want to make available on the app
  store. [...] I would like you to prioritize and group them so that
  you are able to work on them across multiple sessions. I would also
  like you to attempt to build out all of them prior to doing testing
  them myself on device." (Archive Watch, 2026-06-03 19:42)
- "I'll verify on device. Now it is time to genuinely move on from
  subtitles to a new scope of work that I'm very excited about."
  (Archive Watch, 2026-06-22 15:06)

When he was not sure a round had landed, he pasted it again: "Did all
of these issues get solved for? I think there was at least one
compacting during that last session:" followed by the same thirteen
items (BOBA, 2026-04-14 08:58).

**The matches.** Where each note block reached Claude Code:

| Note block | Reached Claude Code | How it was matched |
|---|---|---|
| Tidbits kickoff (22 lines) | 2026-06-16 19:05, the whole first message: "[Pasted text #1 +22 lines]" | Line count; the first commit quotes its opening and closing sentences |
| Tidbits first "Next:" (10 items) | 2026-07-01 12:39, "the following ten tasks [...] [Pasted text #1 +9 lines]" | Ten items, ten lines |
| Tidbits second "Next:" (6 items, Firebase) | Not in the CLI history | Its Firebase decision follows the 07-02 06:43 request to "research 3rd party matching services" and precedes his first `! firebase login` (07-03 06:03) |
| Tidbits `/loop` for Tidbits Live | 2026-09-09 08:43, and again 09-10 11:43 | Word for word |
| Tidbits "Next round of updates" (Windows) and the Chrome extension line | Not found | The extension line ends mid-sentence in the note: a prompt still being drafted |
| Archive Watch feature ideas 1 to 20 | 2026-06-03 19:42, "[Pasted text #5 +19 lines]" | Twenty lines; the commit calls it "the 20 requested items"; at 19:47 Ben answers the agent on items 11 and 14 (Sign in with Apple, the BOBA repository) |
| Archive Watch Creation Studio kickoff | 2026-06-22 15:06, "[Pasted text #4 +12 lines]" | Thirteen lines; the Creation Studio prompts start that week |
| Archive Watch Roku search feed | 2026-09-10 11:22, after "Resume after API error. Also," (sent four times through API errors) | Word for word |
| Archive Watch Android TV six items | 2026-09-03 09:47, the whole message: "[Pasted text #1 +16 lines]" | Seventeen lines as exported; the next prompt (10:14) adds "feedback from one my users on Android (phone)" |
| Archive Watch "1. Yes. Move forward with a single clock" | Not in the CLI history | |
| Archive Watch database audit `/loop` | Not in the CLI history word for word | Its closest typed relative is "/loop 5 minutes I continue to find descriptions and other metadata that are not appropriate for the films and titles that they are attached to" (09-16 08:55) |
| BOBA vision list | Before the CLI record | BOBA began in Cowork; the CLI kickoff (04-03 12:20) is about merging Cowork's files |
| BOBA search/share/swipe bullets, then the Play view bullets | 2026-04-06 10:48 and 13:54, "[Pasted text #1 +4 lines]" each | Five bullets each; the 13:54 preamble names "the "Play" view" |
| BOBA "Feedback 2" (9 bullets) | 2026-04-06 21:25, "[Pasted text #1 +8 lines]" | Line count and preamble ("Please update both apps (iOS and Web App)") |
| BOBA "Feedback 5" and "Feedback 6" | Typed directly, 04-08 07:50 and 04-11 21:03 | Word for word |
| BOBA "Feedback on Web App Version of Deck Builder and Practice Battle" (12) | 2026-04-13 14:29, "[Pasted text #1 +11 lines]" | Line count; preamble quoted above |
| BOBA "Feedback 9" to "Feedback 13" | 04-13 15:41 (+7), 04-14 08:17 (+12, resent 08:58), 04-14 12:03 (+9), 04-14 12:56 (+6), 04-15 11:58 (+7) | Each count is the round's item count minus one |
| BOBA practice-battle and deck-builder "Next Feedback" (4 bullets) | 2026-04-21 08:58, "[Pasted text #1 +3 lines]" | Line count |
| BOBA long deck-builder round with the deck CSV | 2026-04-22 07:54, pasted with the same CSV file's path | The CSV attachment in the note has the same file name |
| BOBA "Navigation Update" (8 items) | 2026-04-22 09:04, "[Pasted text #1 +7 lines]" | Line count |
| BOBA "Streaming Features" 1 to 5 | 2026-04-23 07:11, "[Pasted text #1 +7 lines]" | Next prompt, 07:33: "I don't see the ability to make any of the users into a "streamer" role" |
| BOBA "Showcases" round (4 bullets) | 2026-04-23 09:57, "A couple of good updates for the next version of the iOS and Web App: [Pasted text #1 +3 lines]" | Line count |
| BOBA practice battle / deck builder round (7 items) | 2026-04-24 11:54 to 11:55, pasted and then resent as plain text | Word for word (renumbered 4 to 10 in the terminal, and "Boba" corrected to "BoBA" in the resend) |
| BOBA card-taxonomy round with the experts' CSV | 2026-04-24 14:23, "One more major update for today: [Pasted text #2 +10 lines]" plus the path to "Card Treatments.csv" | The note's expert quote says "See the CSV attached" |
| BOBA "M0 Development for Android App" (11 answers) | 2026-05-19 11:24, "[Pasted text #1 +11 lines]" | Twenty-two minutes after "Can you list out the questions that you need answers to so that I can start answering them?" |
| BOBA all-night loop charter | Not in the CLI history | It cites "the loop documentation/skills that is already available", which Ben asked for on 05-21 09:49; he stopped an overnight loop on 05-22 08:01 |
| BOBA partner email and the replacement loop | Not in the CLI history | On 05-26 13:29 he asks about "the ongoing 30-day process to fully replace all of the radish functionality" |

Two things follow from the table. First, the rounds were frequent and
fast in April (BOBA had five pasted rounds between 04-13 15:41 and
04-15 11:58), which means Ben was using the build between rounds, not
waiting for a finished app. Second, the same practice ran through
September: the Roku search feed and the Tidbits Live loop were drafted
in notes and sent word for word, five months after the first BOBA
round.

### G2. The kickoffs, verbatim

**Tidbits Trivia, the kickoff.** The whole first message of the
project, 2026-06-16 19:05. Section F1 records it as lost because the
history kept only "[Pasted text #1 +22 lines]"; this is that block.

> # Tidbits Trivia:
> A fully realized multi-player (both local and online) trivia game that is based entirely upon facts pulled from the open Wikipedia API.
>
> Full features should include:
> 1. Game Center support on Apple TV and iOS
> 2. Multiple game categories and modes (time-based, team-based, etc.)
> 3. Ability to create quizzes on the fly from a given wikipedia article or topic
> 4. Well constructed design aesthetic with pops of color, an intentional color pallete, and specific choices about text and backgrounds that are playful and somewhat 90's inspired.
> 5. All game questions are well constructed from a repository of question templates to allow for easy conversion of wikipedia articles into engaging trivia questions.
> 6. Ability to match people to compete against either head-to-head or in a group.
> 7. Ways to share questions and scores via social media (although, never X/Twitter)
> 8. Support for multiple platform play (TV, iPhone, Web, Android) to allow for playing across all platforms
> 9. Single-player mode with the ability to keep records and compete against your previous scores.
> 10. A huge number of questions (10,000+) in a responsive local database (on device, if possible) to help make sure that you never see the same question twice.
>
> Please research other quiz/trivia/game/competitions apps that are in the space and determine what key features are not listed above and would allow for this app to compete on its merits and also introduce a number of differentiating factors/features to set it apart from the rest (design should be a part of that too).
>
> Additionally, research quiz/trivia theory and look for best practices that best for using with digital-mediated trivia games (bar quizzes, online games, etc.). You should use all of the tools at your disposal (claude code skills, documentation, web search, etc.) to truly understand game theory and the best way to construct a mobile game for engagement, entertainment, and learning.
>
> Please use your repository documentation to help you build out the project/plan and determine the best plan for ensuring all features are well outlined and can be executed by claude code via markdown files. A full parity matrix should be written with any important platform-specific decisions that will need to be considered.
>
> The final outcome of this session should be a working iOS version with all v1 versions of the features fully implemented.

Its parts, in order: one sentence of wish that names the data source;
ten numbered features, each a capability rather than a screen; two
research asks (the competition, and the theory of the form); an
instruction to plan with the repository's own documentation, ending in
a parity matrix; and what the session should produce. Right under it in
the note sits the first outside request: "Request from [a friend]: Oh
please do Google home integration! I used to get random facts from my
Google home until they swapped to Gemini and now it just gives me one of
like 5 canned facts". The CLI history shows no smart-speaker prompt; it
stayed a note.

**BOBA Playbook, the vision list.** Written before the CLI record,
when the app was being shaped in Cowork. It is the top of the note,
above the naming lists.

> # Boba App ideas:
> 1. The design of the app: Highly stylized view of cards with emphasis on bold colors and big stat/info text/numbers. The interface should be a combination of Retro-futurism, hyper-realism, cyberpunk UI, and glassmorphism. The emphasis should be on ease of use an intuitive look and feel, but with an opinionated design that draws you in and engages you with great artwork, just the same way that the BOBA cards do.
> 2. Search Mode: A fully functional database of all BOBA cards that can be searched and filtered. It should also have pre-built categories based upon card taxonomy that can be independently browsed (sets, variations, etc.). Ideally, the app would have current pricing comps pulled for cards from both Radish Price Guide (https://radishpriceguide.com) and eBay. You should also be able to look up Boxes (hobby, double mega, jumbo, etc.) lookup and show comps on eBay.
> 3. Scan Mode: Use the iOS camera to scan for the presence of a BOBA card, conducting photo scanning entirely with on-device processing based upon the knowledge of where the key features are within a BOBA card (numbers around the edges, product name in the bottom middle of the card, etc.) and that will automatically identify the card and pull up the correct information about set, hero, power, etc. There should be a mode to scan Multiple cards at once and create a queue of searches that will tally up the value of the cards based upon comps from Radish or eBay.
> 4. Book Mode: Rules and strategy lookup for specific cards (providing advice for how to play). This should also produce advice for how to make decks of cards for playing the BOBA game. It should pull from your own collection to provide examples for how to use the cards you already own to play the game.
> 5. Collection Mode: You should be able to add cards you have searched for or scanned to a collection in order to keep track of your portfolio of cards. This should keep track of how much your collection is worth as well as allow you to create different designations for cards (Personal Collection, To Sell, To Trade, etc.). This should be saved into your personal account and have it be synced/available on both iOS and the Web App.
> 6. Feature for future release: Embedding a single Discord channel ([redacted]) form the BOBA discord for use in trading cards

Design first, then four "modes" named for what a collector does, then
one item deliberately labeled "for future release." Item 2's reliance on
a third-party price guide is the dependency that was revoked in May
(G3, "What stays human").

**Archive Watch, the feature ideas list.** Headed "Scratchpad Feature
Ideas:" under the working title. Items 1 to 20 are the block Ben pasted
on 2026-06-03 19:42 as "the big backlog to take this app through to its
first version". The "Done:" list below it is his ledger of what had
already moved out of the list.

> # Public Domain Apple TV App:
> Scratchpad Feature Ideas:
> 1. 24-hour programming channels for specific types of content (eras, genres, collections, and the ability to create your own based upon filters set for the full database)
> 2. Cartoon-only overlay that turns your app into a cartoon wonderland (great for kids and ambient watching)
> 3. A background/party play that shows video only with no audio (with the ability to turn on audio), but that focuses upon high contrast/high-interest videos that are visually interesting and that autoplays in the background.
> 4. Full support for cast and crew connections (scrolling through images of cast and crew and allowing the selection of each one to navigate to other movies with those people in them). Also character support (multiple movies with the same characters should be connected too)
> 5. Full support for subtitles (via API or automatically generated), video speed, audio language, and video quality.
> 6. Ability to do on-device upscale videos for higher resolutions of televisions
> 7. Category for documentary films
> 8. Skip credits and intro options for tv shows and movies
> 9. Info overlays on the video and the ability to go between episodes of tv shows
> 10. Autoplay options for the same show, same category, same year, etc. You should be able to set these globally in settings or on an individual playing video in the settings for the video.
> 11. Login with Apple ID and the ability to save favorites with cloud syncing of progress across multiple Apple TVs
> 12. The ability to add playlists (beyond just favorites) or create your own collections that are saved to your account
> 13. Cover image generation from videos with emphasis on actor faces and key scenes from the movie wherever posters are unavailable
> 14. Movie cover art screen saver that mimics the old cover art visualization from iTunes (can use code from a similar feature built out within the BOBA-Playbook repository)
> 15. Public domain day celebrations and the ability to see all movies/tv that entered the public domain in a particular year.
> 16. Ability to share individual videos to your phone or to anywhere else
> 17. Make it so you don't see titles that you have already watched on the home screen
> 18. There are still many examples of individual TV episodes that show as movie/films. They need to be fixed to put them into their correct TV show and season.
> 19. Sometimes when you attempt to play a title, it shows the player with a crossed out circle instead of playing the video. Please investigate.
> 20. There are also still many examples of incorrect poster (for example, movies from the 2000s for a title that was from the 1960s) and the description matches the modern/incorrect poster and not the original title. We need better validation for the videos themselves and better matching from our sources of truth for the metadata and images. Other times the title and the video just do not match and so you aren't really sure what movie you are playing. We need validation at every step of the process (sourcing, metadata writing, poster alignment, etc.)
>
> Done:
> 1. Full support for tv shows with episode navigation and plot summaries for individual episodes
> 2. The focus of the app upon launch is still the sidebar instead of the home page hero content.
> 3. The content is still "indented" by the size of the icons in the sidebar, when it should fill the full screen
> 4. The surprise screen tiles still do not match the tiles on the other views and they should
> 5. Full icon and logo development

The list mixes kinds on purpose: features (1 to 17), bugs he had seen
(18 to 20), and a reference to another of his own repositories (14).
The "Done" items keep their original bug wording ("is still the
sidebar"), which shows they were written as feedback and moved to the
ledger once fixed, not rewritten.

### G3. Stage by stage: the note excerpts that show the move

Each excerpt is verbatim from the notes, with one sentence on what was
happening. The date is when it reached Claude Code, where the history
shows it.

#### 00. Values and why

- The values restated inside a loop charter, with the stop condition in
  the same breath (Tidbits, sent 2026-09-09 08:43):

  > "Remember, we build software for parity and our values fully out in front. Our trivia app is based upon the idea that everyone who uses it should be learning, so our connection to learn more from Wikipedia should be clear. We are also building for PEOPLE, so we want people to experience joy when they run an event, when they join a live experience, or when they are using the daily tidbit."

- A content critique judged by what the player learns, not by whether
  it works (Tidbits, second "Next:" round, item 5):

  > "These are not only easy questions but are intensely uninteresting and do not cause the user to learn anything in the process."

- A values line inside a feature list (Tidbits kickoff, item 7): "Ways
  to share questions and scores via social media (although, never
  X/Twitter)".
- A rule stated as a mantra so the agent cannot trade it away for a
  shortcut (BOBA, appended to the partner-revocation loop in late May):

  > "Oh, and I want to be super clear about the card art. EVERY SINGLE CARD ART is different. We have to continue with the mantra of one card, one image, one BOBAid. We can never use another set of card art to represent a different card. Do not pursue options that will go against that mantra."

- The audience named in an answer about data (Archive Watch, the single
  clock answers, item 2): "We are creating/finding collections that
  everyone will want to watch, so they need to be generally
  understandable to the public."

#### 01. First prototype

- What the first session should produce, stated as the last line of the
  kickoff (Tidbits, 2026-06-16): "The final outcome of this session
  should be a working iOS version with all v1 versions of the features
  fully implemented."
- The first reaction to a first build, written in the note as item 1 of
  the first BOBA round (early April), asking which skill was used:

  > "1. I would like to iterate upon the look and feel. It feels very much like a "first draft effort", which makes sense, but it must have far more personality than a generic AI-built web app. Did you use the UXUI Pro Max skill or just the guidelines from the claude documentation? I want this platform to be truly unique and look specific to a BOBA Playbook App that is recognizable instantly as itself."

- Plain first-look observations from the same round, one line each:
  "4. Any text on the screen needs to be legible, so please figure out
  ways to ensure there are no dark text on dark backgrounds." and "5. We
  need to create a cool image for any "missing image" cards. Right now,
  they are just question marks."
- A first-look bug described by feel, from a phone (Tidbits, first
  "Next:", item 3, sent 2026-07-01): "The iPhone app main screen has the
  ability to partially scroll horizontally with a rubber banding
  effect. This should not be possible. It should only allow for
  vertical scrolling on the home page."

#### 02. Shape: data plane and parity

- The one-value-everywhere requirement, found by using the app (Tidbits,
  first "Next:", item 2, sent 2026-07-01 12:39):

  > "2. Although Daily Tidbits says that "everyone gets the same set", this doesn't seem to be the case. Every time I open the Daily Tidbit, it shows a different set of questions. I would like for there to be a single set of daily tidbits per category that you can select from, but that are selected and are the same for everyone for the full 24 hours. Additionally, when you share your score, it should link back to https://tidbitstrivia.com rather than just asking folks to compete and not giving a link."

  Five hours later he typed the cross-platform half: "For it to be
  truly daily across all platforms (and for the right and wrong answers
  to mean the same thing), it has to be the same across all platforms."
  (2026-07-01 17:33)
- A shared clock decided in one line (Archive Watch, single clock
  answers, item 1): "1. Yes. Move forward with a single clock. If you
  need a time zone to organize around, you can choose UTC, but all
  times should show as their local times when they look at channels.
  This should only be to sync all titles to the same time."
- Interoperability with another tool's file format as the data contract
  (BOBA, web deck builder round, item 3, sent 2026-04-13 14:29):

  > "3. The deck export button seems to simply generate a markdown list of cards that doesn't really seem to be useful. The web deck builder (https://deck-builder.bobattlearena.com) allows you to download as a csv complete with info about all of the cards in the deck and it allows you to import a json deck as well. I'd like to create a format for import/export of decks that is compatible with this tool and would allow for interoperability between these tools."

- Validation named as a property of the pipeline, not of one record
  (Archive Watch, idea 20): "We need validation at every step of the
  process (sourcing, metadata writing, poster alignment, etc.)"
- A parity catch between two platforms' own views (BOBA, a later
  round): "3. I'd like to add the ability to see pricing info on the
  grid view for the collection tab. Currently, you can only see this
  info on the list view and I need full parity across both views."

#### 03. Native platforms and floors

- The macOS kickoff that asks for a platform-only feature set, not a
  port (Archive Watch, sent 2026-06-22 15:06):

  > "We need to start building out a brand new set of skills, design patterns, and API research in order to build a first-in-class MacOS app that has both parity with the current state of the other platforms as well as building out functionality that is specific to MacOS/desktop operating systems control of file APIs and the ability to run far more complex processes upon videos. The goal is not to simply make a MacOS app that works the same way on all of the other platforms, but to enable a new set of features that are only available within the MacOS version and to do so in a complete native way for the Mac (and not just a retread of old iOS/iPadOS/tvOS ways of doing things).
  > Specifically, we are going to make a "Create" feature set on MacOS that will take the work we built for the "clip studio" and expand it to be a fully featured video/scene editor with the ability to combine multiple clips (across different titles) into a single unified video that can be exported/saved in multiple ways. The backlog of the "Creation Studio" feature should include the following, so please ensure that all of your research includes ways that we would look to implement the following (as well as documentation for all smaller features hidden within the ones I've enumerated):"

  Followed by ten numbered items, of which these three show the range:

  > "2. The ability to save "clips" from different video titles into a library without having to download the videos to your hard drive (i.e., using the archive.org videos as our source, but with the ability to create "proxy" clips that simply link to individual start and stop times. This will allow for far less hard drive space needed to make clips. It will also let you save key items for use in multiple different final exports.) This would look a lot like tagging specific scenes as a layer on top of archive.org's content. We would own the annotation layer, but Archive.org would own the file hosting."
  >
  > "9. Huge feature that would be a differentiator for our app: The ability to write out a sentence or two of text, and then have the app find those individual words and phrases that make up the custom text you entered within videos from the database (using subtitle and metadata). The app should then clip the videos together to have the final result be a single video of different characters all saying the custom text words. This would require a lot of different skills, but should be doable for a robust Mac app."
  >
  > "10. The ability to do most of the functions of a timeline video editor (please research modern functionality of Final Cut Pro, Adobe Premiere, or even CapCut)"

- A new platform answered item by item, native idiom first (BOBA, "M0
  Development for Android App", sent 2026-05-19 11:24):

  > "4. Since I want to start testing quickly, I have access to a Chromebook right now, so Chromebook compatibility and Tablet support needs to be available in the first few versions. I don't need foldable to be a part of this, though, as it is such a small part of the market right now.
  > [...]
  > 10. Let's add Sign in with Google for Android and remove Sign in with Apple on Android. It doesn't make sense to keep it included for a platform that doesn't really want to use apple login that way.
  > 11. I'd like to use native design cues/patterns from Android. We are translating the overall design colors and choices for a brand new platform and it should look perfectly at home on any android device but with the BOBA Playbook branding and design aesthetic."

- A platform's own discovery channel treated as part of the platform
  (Archive Watch, sent 2026-09-10 11:22):

  > "Now that the Roku app is live, we need to build out a Search Feed for all of the content (or a large subset of verifiable public domain movies, at least) in our app. The goal would be to organically have people searching for the movies in our app and then have them download it in order to play the movies. Here is the documentation for search feeds from Roku, let's build a robust feed and use Claude in Chrome to write it up. Documentation: https://developer.roku.com/dev/docs/search. Search feed builder: https://developer.roku.com/apps/search/overview."

- A platform kickoff caught mid-draft (Tidbits, the last line of the
  note): "We need to build for one more platform that could really make
  Tidbits Trivia special on the desktop. I'd like to build out a chrome
  extension". The note is where the reason ("special on the desktop")
  gets written before the scope does.
- One canonical asset across platforms (Tidbits, first "Next:", item
  5): "The iOS version should be the canonical icon and should be used
  everywhere."

#### 04. Seeing it work on devices

- The Android TV round, written from the couch with the remote, sent
  whole (Archive Watch, 2026-09-03 09:47):

  > "We need to work on a few things within the Android TV version of the app:
  > 1. The home loading is much quicker than it has ever been, but even though the home screen loads within a couple of seconds, the posters still take about 10 seconds longer to load, so it looks like it is stuck/frozen.
  > 2. The first item on each shelf is inaccessible. If you try to access it, it will take you directly to the sidebar items. This needs to be fixed.
  > 3. When I search for Archive Watch on the Google Play store, it shows up as Archive Watch - Beta. I would like for it to read as the full and non-beta version on Android TV now that we have it working much better.
  > 4. I don't believe we have done a full audit of every screen, button, and interface element. Please write up a full audit for Android TV and test each component to be sure that it works as intended.
  > 5. There doesn't seem to be any way to log in on Android (phone) or Google TV. The goal for this would be to allow for the same kind of syncing of content that happens on apple platforms between devices. We would implement Google Sign-in and syncing for this, and I'd like for it to be seemless across android devices.
  > 6. A few issues unrelated to the Google/Android TV work - The titles in the Library section on Android (phone) do not flow correctly. They all seem to have their plurals on a second line rather than just allowing you to scroll across the full top bar. Also, I would love to be able to login with my apple login on the web app and have content sync across to that platform. Once we have the google login working, I'd like that to work on the web as well.
  >
  > Please make use of the full suite of devices you have access to in order to build out and test all of these features."

  Six items, each a single observation with its expected behavior; one
  item (4) asks the agent to own the audit; one (6) is labeled as
  unrelated rather than left out; and the last line hands verification
  to the devices.
- The perceived-speed item, which only a person watching the screen
  notices: item 1 above ("so it looks like it is stuck/frozen").
- A phone's physical constraints written as requirements (BOBA,
  "Feedback 11", item 8, sent 2026-04-14 12:03): "First, it should
  respect the Dynamic Island area and not show any content there that
  could be covered up by the camera. [...] Second, it should respect the
  rounded corners on most phones and not put content all the way up
  into the corners that is cut off by the rounded corners. [...]
  Overall, the size of the screen should never hamper the ability to see
  text or information about the cards".
- A platform-specific round on a device the agent had not been watching
  (Tidbits, "Next round of updates"): "The windows app has significant
  parity issues, including the Daley Tidbits for multiple days show on
  the play homepage, there is nothing that shows on the right side of
  the app interface until you select an option in the left side bar,
  and the buttons do not flow correctly on Tidbits live and the second
  screen does not show correctly as a separate window when you are
  doing Tidbits live".
- A correction that asks why the check missed it, not only for the fix
  (BOBA, a round filed under "Streaming Features", late April): "Play card
  effects that aren't working correctly (I don't understand how these
  effects are still not working correctly based upon the exhaustive
  audit we worked on yesterday. Please investigate each individually as
  well as figure out why the audit didn't catch these issues):"

#### 05. Shipping

- A store listing's wording noticed as a user would see it (Archive
  Watch, Android TV round, item 3, above): "it shows up as Archive Watch
  - Beta. I would like for it to read as the full and non-beta version".
- The pre-beta list, headed by the thing that kept regressing (BOBA,
  late May): "Things we still need to fix before we can launch the
  initial beta of the android app: 1. The Android App Icon needs to be
  fixed once and for all. You keep reverting back to a generated (and
  incorrect) icon to show on the Home Screen. Please use the one that
  we generated for the Google Play Console and include it within the
  app to show everywhere."
- The first public version named as the goal of a backlog (Archive
  Watch, 2026-06-03 19:42 preamble, quoted in G1): "to take this app
  through to its first version I want to make available on the app
  store".
- The ledger's reminder that shipping includes being found: "Outstanding
  items: 1. Promotion on social media: 1. Automated posting to Threads,
  Facebook," with a saved article about free streaming apps underneath
  (Archive Watch).
- A share that leads somewhere (Tidbits, first "Next:", item 2): "when
  you share your score, it should link back to https://tidbitstrivia.com
  rather than just asking folks to compete and not giving a link."

#### 06. Keeping it running: Pulse, CI, loops

- The database audit charter, drafted in full as a note of its own
  (Archive Watch, September). A goal, five numbered areas, a stated end
  state that includes the pipelines, and one explicit permission:

  > "# /loop It is now time to do a full audit of our database looking for the following issues and fixing them or further enhancing them wherever they exist:
  > 1. Malformed metadata, including poorly structured descriptions/summaries, issues with years/dates, categorization, cast/crew info, and any other copy that shows up on an individual detail view (look out for all caps information, user/uploader-specific text, etc.)
  > 2. Non-professional posters or backdrops. Any place we can get the correct professional poster or backdrop (for use on the hero row or the individual view on some platforms)
  > 3. Incorrect copyright data or incorrectly categorized films as Creative Commons, public domain, or otherwise copyright free works
  > 4. Archive.org links and other video files that will ensure every video in our app plays correctly every time
  > 5. Issues with the database build process, the "wanted titles" process, or any of the other Github workers/actions that touch the database
  >
  > The goal is that every single entry for every single title has exclusively accurate information and that the information will only improve over time with our processes set up on Github (and other runners/workers we are utilizing). Also, you are allowed to rewrite copy if that is the only way that you can make the data work for translating user-generated copy into workable copy for our app."

- The all-night loop charter (BOBA, drafted around 2026-05-21, after
  Ben had the agent write the loop skill it refers to). Goal,
  environment, three ranked priorities, an anti-repetition rule, and a
  morning file:

  > "I would like you to start an autonomous loop to run all night without intervention from me. You should use the loop documentation/skills that is already available, which will tell you the right cadence and priorities to focus upon. The goal is to make real and substantive improvements to the apps across all platforms while ensuring there are no build errors on Github, Xcode, or Android Studio. You have access to command line tools and I also have the Mac apps for both Xcode and Android Studio. Feel free to use the simulators in either to confirm your work. You can also build simulators with the command line as needed. Your documentation should indicate this, but your priorities are:
  > 1. Parity across all platforms: Web App (limitations on some elements like 3d modeling, but otherwise should be fully featured with anything android and iOS have), iOS (in many ways, the flagship app that receives the most sophisticated features and the most native implementation and design), Android (the newest platform with the most room for improvement - should also be considered a first-class mobile experience)
  > 2. New Feature development - The ideas for this scope of work should be developed from the extensive exports from Discord available in the research folder, the blog post archive from the official Bo Jackson Battle Arena blog, and your ability to conduct research about other TCG-specific apps or BoBA content on the web. You should explicitly build in ticks of the loop to do this research and not just rely upon your first pull of this information. All new features should be built with claude skills for design and our documentation for how to build and important rules about how every interface/feature should be specifically built to  most take advantage of the platform-specific design language and native (iOS or Android) APIs to the fullest extent. For any new feature implemented, make sure that it is the "best" and most intuitive way to do it.
  > 3. Code optimization - For the ticks dedicated to further streamlining the code and prioritizing efficient and error-free building, you should work to lower complexity and ensure that we are building this app to last rather than to keep on adding engineering debt as we build out more and more functionality without making the app experience slow or creating cruft or engineering debt.
  >
  > As you continue with this loop, please ensure that you do not keep iterating on the same few problems or ideas. The goal of this whole looping cycle is to allow me to wake up with a bunch of new things to try and not just a few super optimized and polished things that are already there. We are building for user need, so spending a tick on a regular cadence at doing additional research on the needs of TCG collecting apps or BoBA users is how to ensure this happens. If there are things that you need to have me do when I wake up, please keep a record of what I need to do in a markdown file I can check in the morning. If you need to compact, please make sure you documenting all actions thoroughly so that you can resume from where you left off."

  The anti-repetition paragraph answers a complaint he had typed the
  morning before: "It seems like these loops are really circling around
  the same exact features and are never expanding out into areas that
  actually need work." (2026-05-21 07:02). The note is where the lesson
  became part of the next charter.
- A loop with a finish line instead of a clock (Tidbits, sent
  2026-09-09 08:43 and 09-10 11:43): "You should stop the loop only once
  we have fully built out Tidbits Live on both Mac and Windows as well
  as the ability to join those full experiences on all other platforms
  (I'm particularly keen to see if we can have video questions or other
  media types that get broadcast even on the web app)."

#### 07. Raising the ceiling

- Ideas parked in the ledger that became real work months later. The
  Archive Watch note's last list:

  > "Ideas for further execution and/or monetization:
  > 1. SharePlay Event Builder (watch an old movie with friends or family)
  > 2. Twitch/Youtube Streaming from the app to your own channel
  > 3. Support for low end Google and Apple devices"

  SharePlay was tested across his own devices on 2026-08-31, streaming
  to your own channel became the "Watch Together" loops ("/loop Let's
  move on to the documented work to create the feature set to stream
  your watching of PD movies to Youtube and Twitch", 09-17), and older
  devices came up with the Roku 2 XD ("I'd really like to find a way to
  allow folks to get my app on their older devices", 09-14). All three
  started as one line in the note.
- A research-and-document ask for a feature that is not yet buildable
  (Tidbits, first "Next:", item 10): "We need to start researching the
  ability to play online with others (i.e., compete against one another
  in real-time). [...] Please write a playbook for how we would develop
  this possibility and also have a fallback for a CPU player for any
  time that there isn't a human player who wants to play tidbits
  together across the world. Please document all that you find out
  about this possibility for Tidbits Trivia so that on a future
  session, we can implement it."
- A feature scoped by the user it serves (BOBA, "Streaming Features",
  item 5): "The overall goal of this feature is to allow streamers to
  prep for their shows on whatnot in order to determine the full amount
  of their "giveaways" and the "chasers" that will be sent to folks who
  buy cards within the show. All features should serve this purpose
  within the app if you have a "streamer" role set for your user."
- Records that explain themselves (Tidbits, first "Next:", item 8):
  "Each item on the records page should be intentionally chosen to show
  your skills and should be instantly understandable. No strange
  abbreviations like "Lifetime Acc." should show on the page (what does
  Acc. Mean?)"

#### 08. Working with AI: memory, skills, handoff

- **Research first, in the round itself.** "Please read through
  official Game Center APIs to determine the way forward." (Tidbits,
  first "Next:", item 1). "I believe that you should be able to use API
  calls in order to set all of these achievements up for Game Center so
  that I don't have to directly input them individually, so please
  research that ability (and the ability to do it on the android side)."
  (item 8). "I'd like you to research design language that will allow
  for more simplified selections" (item 6). "Please research the best
  way to accomplish this, as the current questions are either entirely
  obvious or entirely nonsensical." (item 7).
- **Find a better source instead of iterating.** "I really don't
  understand the icons that have been developed as SVGs for either of
  these features. I think we need to find a design source for SVG icons
  that will work better. Please lookup a claude skill or repository of
  well designed icons for this purpose, as none of them look like what
  they are supposed to and I don't want to go back and forth on
  development when better alternatives exist." (BOBA, web deck builder
  round, item 9, 2026-04-13)
- **Answering the agent's decisions as a numbered list.** The whole of
  one Archive Watch note:

  > "1. Yes. Move forward with a single clock. If you need a time zone to organize around, you can choose UTC, but all times should show as their local times when they look at channels. This should only be to sync all titles to the same time.
  > 2. I don't mind if you touch up some of the collection descriptions from archive.org, but I'd like all of the collections to be written from archive.org language originally. I notice that a few collection titles will also need to be touched up (all capital letters, etc.). We are creating/finding collections that everyone will want to watch, so they need to be generally understandable to the public.
  > 3.  The wording is fine for now.
  > 4. You can use the Apple TVs whenever you want right now.
  > 5. This seems like a bug. It shouldn't constantly ask for syncing all of the time."

  Five answers, five kinds: a decision with its constraint (1), a
  permission with its limit and reason (2), a short approval (3), device
  access granted (4), and a reframing of a question as a bug (5). The
  BOBA M0 answers (2026-05-19) follow the same form and were requested
  that way: "Can you list out the questions that you need answers to so
  that I can start answering them?" (11:02), then the eleven answers
  pasted at 11:24, including "5. Since I don't have subscription
  monetization set up for iOS or Web, it doesn't make sense to ship it
  on Android first. Please differ." and "6. Personal Showcase, House of
  Boba, and Hero Shot features can all be differed until later."
- **Dividing work between two agents in the note.** A bullet that
  begins "For cowork: the gum cards seem to be significantly mislabeled
  with incorrect images." (BOBA, first round), and later, sent with a
  pasted block: "Does it make more sense for you or claude cowork to
  tackle this set of tasks first?" (2026-04-24 12:17).
- **Hide, do not delete.** "Because I don't yet have the ability to
  integrate that, we need to "hide" the feature from view until I can
  add the bot to the discord server and get functionality working.
  Please hide the feature but do not remove any of the code that will
  make it work." (BOBA, "Feedback 7", item 3)
- **Ask for the agent's view at the end of a spec.** "Let me know if
  there is anything else that you think should go in this section (and
  is currently unaccounted for either within the app or as a component
  of a robust profile/account settings system in a top-tier native iOS
  app)." (BOBA, "Profile view updates", item 4)

#### What stays human, as the notes show it

The notes are the clearest record of the work only Ben could do,
because that work lives there rather than in the chat:

- **Using the app.** Every round is a list of things seen on a device.
  None of them could have come from the agent.
- **Collecting other people's words.** A friend's feature request,
  testers' messages copied in with a question-mark marker, card experts'
  terminology feedback quoted at length, and his own replies drafted
  under the testers' messages. One reply shows him turning a tester's
  request into a design idea: "Yes! I need to think more about "custom
  goals" or "custom rainbows" that you could set in the rainbows view so
  that it would let you see exactly how close you are to getting what
  you want rather than the entire universe of cards that exists. Great
  suggestion."
- **Receiving a partner's decision and turning it into requirements.**
  In late May the price-guide partner behind BOBA's vision item 2 wrote
  that its data could not be used in the app, only ordinary links out.
  Ben pasted the email into the note and wrote the instruction around
  it: "You should treat every statement in this email as a requirement
  of our next shipping version on each platform", kept one link per
  card that opens outside the app, and asked for a loop that would
  "fundamentally recreate all of the functionality using only our own
  IP and access. [...] If there are things that I need to do (signing
  up for APIs, etc.), please let me know, but don't stop until the
  requirements from the email have been met AND we have replaced the
  full functionality".
- **Accounts and owner actions.** Creating the cloud project ("I've
  created a project within my firebase account with the following info
  (please let me know what additional info you need in order to be able
  to work within this project using the CLI)", Tidbits, details
  [redacted]), creating an OAuth client, moving a domain's DNS. The
  agent wrote the steps; the note held them until Ben did them.
- **Deciding what is done.** The "Done:", "Fix:" and "Outstanding
  items:" lists are his, not the agent's. The agent's own ledger lives
  in the repository (SCRATCHPAD, PARITY); the note is the human's.
- **Naming the app,** in two lists with his own verdicts.

### G4. Implications for the course

Offered as notes, not decisions. They extend the list that follows.

1. **Teach a running notes page per app as the human's backlog and
   drafting space.** One page, opened on day one, kept for the life of
   the app. The wish goes at the top; everything else is appended.
   This is what Ben actually did for all three apps, and it is where his
   best prompts were written.
2. **Teach the round, not the message.** Use the app, write numbered
   observations under a "Next:" heading while you use it (where, what is
   wrong, what it should be, which platforms), then paste the whole
   round with one line of scope in front ("across all platforms", "read
   your documentation first", "I'll verify on device"). His rounds ran
   from four items to thirteen.
3. **Teach the kickoff as a template the learner fills in:** one-line
   wish with the data source, numbered capabilities, research asks
   about the field and the form, "use your repository documentation",
   a parity matrix, and what this session should produce. Use the
   Tidbits kickoff (G2) as the worked example.
4. **Teach the ledger.** "Done", "Fix", "Outstanding", "Future". Ideas
   left in the ledger are not lost: three one-line Archive Watch ideas
   became features months later. Moving an item to "Done" without
   rewriting it keeps a record of what was actually reported.
5. **Teach drafting loop charters in the notes, ahead of time.** A goal,
   ranked priorities, a stop condition or finish line, the permissions
   granted, and a file for "what I need to do in the morning". Fold in
   what went wrong in the last loop (the anti-repetition paragraph).
6. **Teach answering the agent by number.** Ask for the questions as a
   list, answer each by its number in the notes, and give each answer a
   reason or a limit. "Please differ" is an answer too.
7. **Teach the notes as the place outside voices land.** Friends,
   testers, experts, partners: copy their words in first, decide second,
   and draft replies there.
8. **Do not model the notes' one bad habit.** Ben's notes mix keys,
   tokens and certificate details with feedback. The course should say
   plainly that secrets never go into a notes page or a chat; they go
   into a password manager, the platform's secret store, or CI secrets,
   and the agent is told where to find them.
9. **Keep the stage timing honest.** In April Ben pasted five rounds in
   two days while the builds were still rough; the notes were not a
   plan written up front but a record kept while using each build. A
   learner at stage 01 can start the page with one wish and one round.

---

## Implications for the rewrite

Offered as notes, not decisions.

1. **Each stage's "What to do" should be prompts and observations, not
   files and commands.** Where the course says "save twenty records,"
   Ben said "use this source, build the pipeline." Where it says "run
   http.server," Ben opened the live URL. Where it says "open
   `js/api.js`," Ben said what was wrong on the screen.
2. **The learner's real steps are the human ones:** write the wish and
   the values, pick the source, set up the devices and accounts, use the
   app, say what they see, correct with a reason, decide when asked, say
   ship, say stop.
3. **Teach the prompt patterns in C as the skill,** with the corrections
   in A5 as the most valuable examples. The corrections are where the
   method lives.
4. **Keep "what stays human" honest,** including the credential friction
   and the few console clicks. Ben's own record shows those are the
   real remaining hand steps.
5. **Be step-aware:** a learner at stage 01 has no devices bench, no
   CI, no loops. Ben's first evening on Tidbits used four prompts, and
   the next morning he judged the result on the live web app; his
   device bench came in August. The course can mirror that growth
   rather than front-loading the bench.
6. **Use the early months for stages 00 to 03 (section F).** Ben's
   beginnings look much more like a beginner's than his September
   practice does: a phone session that had to move to the Mac, a first
   look in the simulator, compiler errors pasted one at a time, a
   bundle ID that would not register, a sixteenth failed attempt at the
   same gesture. Those are the moments a learner will recognize, and
   each one ends with the move the course wants to teach.
