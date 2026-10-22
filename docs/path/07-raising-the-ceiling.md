# 07. Raising the ceiling

<!-- Rebuilt by the method of curriculum research note 06
(docs/research/curriculum/06-instructional-design.md, section 4), which
Ben approved on October 7, 2026: designed backward from the "Be ready to"
line, with Ben's own wants and his stage 00 questions as the models and
criteria, a log kept while using the app, and a rough version watched in
real hands. Written by Claude, awaiting Ben's review. -->

**Where you are.** Your app is shipped, Pulse is watching it, and you use
it every day. Using it is where the next feature comes from.

<!-- The question, the first two steps, the step labels, the last step,
the per-agent lines, and everything between the bar and the last line:
written by Claude, awaiting Ben's review (curriculum C8, the lesson page
template in docs/templates/LESSON-template.md). -->
**The question.** What do you want from your app now that you live with
it, and does it need anything new to give you that?

On September 12, 2026, I asked for something that sounded like it needed
a server:

> letting our users share their playlists via URL … they would get
> published on the web app for anyone to browse and potentially add to
> their account and view them on native apps as well.

At the time, Archive Watch had no server and no accounts. People's saved
films lived on their own devices and synced through their own iCloud or
Google Drive. There was nowhere for us to put a playlist, and building
somewhere would have undone a decision the whole app rests on.

So, the investigation began with a different question. Not how to
build a sharing service, but whether one was needed at all.

It was not. A playlist is a name and a list of film IDs. Compressed and
encoded, fifty films fit in a link of about 1,368 characters, measured
across 300 random playlists from the real catalog. The whole playlist
travels inside the URL. The web app opens it for anyone. The native apps
open the same link and offer to save it. No server was built.

Stage 03 was about the floor: the oldest device the app reaches. This
stage is about the ceiling: everything the newest devices can do. The
playlist link is the lesson the whole stage runs on, because it raised
the ceiling for every platform without adding a single thing the app
needed in order to run:

**Raise the ceiling without raising the floor.**

## What I want

I want the newest devices to get everything they can do: SharePlay on
the Apple TV, Top Shelf, live captions, widgets, picture in picture,
casting. I want each of those to arrive on every platform that can have
it, in that platform's own idiom. And I want none of it to cost the
hand-me-down phone its ability to open the app, or cost me a server I
now have to keep alive.

## Four ways the ceiling went up in Archive Watch

**1. The feature fits in what already exists.** Before building, ask
what the app already has that could carry it.

- Shared playlists live in the link.
- The web app reads the same iCloud database the Apple apps write to
  (Apple publishes a JavaScript library for it), so the web joined the
  Apple sync without a server of its own.
- The Apple TV's Top Shelf and the home-screen widgets read a tiny JSON
  file the data pipeline already publishes each day, rather than the
  full catalog.

**2. Capability, not effort, decides where a feature appears.** "Watch
Together" in Archive Watch is really three features, and each platform
offers the ones its hardware and operating system allow. The rule is in
the decision log:

> Every surface must state which of the three THIS device can do, and
> why it cannot do the others. Never a silently missing button.

A device that can never have a feature gets `n/a` in `PARITY.md`, with
the reason. A device that could have it but does not yet gets a sentence
on screen. Some doors get closed for good, and saying so is a kindness:
Roku can never *receive* a shared playlist, because nothing on a phone
can hand a link to a Roku, so that row says "closed", not "later".

**3. Let people keep what they already use.** Watch Together was
stuck on how to carry people's voices: servers, relays,
billing, free-tier limits. Then I asked a different question:

> I mean, calling services like Google Meet, Zoom, Phone Calling or
> other services that every device has if we wanted to separate out the
> calling part from the movie playing, syncing, and streaming to
> youtube.

People already have a way to talk to one another. The app only has to
keep the film in sync. Everything the voice problem had required simply
stopped existing.

**4. When you do need a server, make it small and free.** Archive Watch
eventually needed one: to keep watch-party rooms in sync across
platforms, to count visits without tracking anyone, and to serve a few
feeds for other apps. It is one Cloudflare Worker on the free tier,
split into small files by job. `pulse/worker-example/` in this template
is a smaller version of the same idea. The `zero-cost-hosted-backend`
skill covers the case where people truly need to see one another's
data.

## Parity for ceiling features

A feature that exists on only some platforms still gets a row in
`PARITY.md`. The difference between the cells matters:

- ✅ shipped, 🚧 in progress, ⏳ planned: the usual.
- 🚫 not doing it, with the reason.
- n/a: the platform cannot have it at all.

When a feature is big enough to have its own rules (captions, SharePlay,
playlist sharing), it gets its own design document beside the platform
ones, with a table of which operating system versions on which
platforms can do what, and a checklist for bringing it to a new
platform.

## Build it with the people it is for

Living with the app is the third move, and by now you are not the only
one living with it. Across four apps, the people I brought in came as
testers, through a Reddit thread, and at a trivia night. Other people
want things from your app that you do not, and the only way to find out
what they are is to hand it to them.

People used to design with the folks they were building for using paper
and cardboard, because real software was too expensive to throw away.
It is not anymore. With an agent, a working rough version of a feature
costs an afternoon, so the people it is for can use the real thing and
reshape it before you settle on it.

Two rules keep that honest. Keep their words, as they said them, in
your note, the same way you keep your own. And give something back:
their name in the credits, a reply to what they said, the feature they
asked for. Asking for people's ideas and giving nothing back is not
building with them. It is taking from them.

## Their data outlives your interest

Some day you will stop working on this app. The people who used it will
still have what they made in it: their saved films, their lists, their
scores. Archive Watch keeps that on people's own devices and in their own
iCloud or Google Drive rather than on a server of mine, so it does not
vanish when I stop paying for something. The rest of the promise belongs
in writing: a way to export what people made, in a form they can read
without the app, and a sentence on the website saying what happens to
their data if the app stops being maintained.

## What it costs

Every ceiling feature is a promise on every platform that has it, and
promises need upkeep. Picture in picture had to be tested on an iPhone,
an iPad, an Android phone and in web browsers, each with its own
way of doing it. A feature on one platform is cheap. A feature on six is
six features.

That is the other reason to ask the first question honestly. The
cheapest feature to maintain is the one you found you did not need to
build.

## The skills for this stage

- `shareplay-activities` for SharePlay, with what shipping it on three
  Apple platforms actually taught.
- `resilient-media-streaming` for video from hosts you do not control.
- `cross-platform-multiplayer` and `cross-platform-determinism` for
  anything live or shared across platforms.
- `smart-tv-platform-expansion` for the living room beyond Apple.
- `app-intents`, `widgetkit` and the other Apple framework skills for
  each system feature.

## Working with your agent

This stage leads with write, then publishes to everyone. The steps are
one round of write, play, publish: the first two come before the agent
is open, the middle ones are play, with the agent and the people it is
for, and the last one shows the feature and the reason it exists.

1. **Write your first answer.** Before any prompt, answer this stage's
   question in two or three sentences in your note: the one thing you
   want most from your app, and whether you think it needs a server, an
   account, or anything else new. Being wrong is fine. Guessing first is
   what lets the research in step 4 change your mind (the research on
   productive failure, gathered in the
   [curriculum research](../research/curriculum/05-inquiry-and-evidence.md)).

2. **Write your questions.** For five minutes, write as many questions
   as you can about that want, without stopping to answer or judge any
   of them. Then mark the one you most want answered by the end of the
   stage. (These are the Right Question Institute's rules for asking
   your own questions, also in the
   [curriculum research](../research/curriculum/05-inquiry-and-evidence.md).)

3. **Write: notice the want while using the app.** The best features I built
   started as a sentence like this one, typed on September 14 while
   Archive Watch played on the TV beside me:

   > I've been leaving the 'Party Play' going on my TVs to enjoy ambient
   > videos as I work and I realized that I wanted three different
   > features to be built into the view that don't currently exist

   Party Play itself started the same way, as item 3 on the list of
   feature ideas in my Archive Watch note, before it existed:

   > A background/party play that shows video only with no audio (with
   > the ability to turn on audio), but that focuses upon high
   > contrast/high-interest videos that are visually interesting and that
   > autoplays in the background.

   Both of mine name the moment, what I was doing, and what was missing.
   Use them as your models. For a week, keep the same kind of log you kept
   before week 1, while you use your own app: each time you reach for
   something it does not do, write the moment, what you were doing, and
   what was missing, the moment it happens (an event-based diary study,
   [Kim Flaherty, "Diary Studies," Nielsen Norman Group, March 29, 2024](https://www.nngroup.com/articles/diary-studies/)).
   At the end of the week, choose the want that came back most often.

4. **Play: ask for research before code.** Ask whether it is possible, on
   which platforms, and what it would cost, including whether it needs
   a server. On August 31, wanting people to be able to watch Archive
   Watch together:

   > Can you investigate the ability for the Apple versions of the app
   > to take advantage of SharePlay and synchronous viewing of movies
   > together using Apple's API's and version 27 platform features?

   Read the answer against the three questions you asked of the idea in
   stage 00, starting with "Should it exist at all?", before you say
   yes.

5. **Play: say build it, everywhere it can go.** When the research says yes,
   ask for the full feature on every platform that can have it, and an
   honest row in the parity matrix for the ones that cannot. Seven
   minutes after that research question, once the answer was yes:

   > I'd like you to fully implement SharePlay for all Apple platforms.

6. **Play: hold the bars.** When the agent reaches for a custom control where
   the platform has one, or a paid server where none is needed, stop it.
   On August 27, the iPhone app grew its own captions button instead of
   using the one the system already provides:

   > There is now a persistent captions icon on the screen rather than
   > using the build in captions UI on iPhone [...] The goal is native
   > support for all features using native UI and APIs

7. **Play: use it for real, then critique.** Use the feature the way it is
   meant to be used, with the people it is meant for. Then send a
   round. The day after SharePlay went in, after the first real call:

   > That worked. The videos were in sync while the call was live.
   > However, I noticed that I had to initiate the facetime call first
   > and then do the share button within Archive Watch. [...] Can we have
   > the call initiate from the app or have it tell you what to do when
   > you try to select 'Watch Together' without first having a call
   > going?

8. **Publish: put a rough version in front of the people it is for.** Before the
   next big feature is finished, ask the agent for a working rough
   version you can hand to two or three of the people you named in stage
   00. Watch them use it the way you watched in stage 05: they say out
   loud what they expect, and you do not help. Write down what they say
   in their words, and send it as a round. Then tell them what changed
   because of them.

9. **Play: check the older device.** Open the app on your oldest supported
   device and make sure it says, in a sentence, what it cannot do,
   rather than showing a button that does nothing.

10. **Write: make the data promise.** Ask the agent how someone would take what
   they made in your app with them, and what happens to it if you stop.
   If there is no answer yet, ask for an export and for the sentence on
   your website.

11. **Publish: show the feature, and why it exists.** Show it to your
    group, or at the cohort's last session, on the device it was made
    for. Say one thing someone else changed about it, and ask the group
    for feedback by Ron Berger's rules: kind, specific, and helpful
    ([Berger, "Fostering an Ethic of Excellence"](https://jaymctighe.com/wp-content/uploads/2011/04/Ron-Berger-Article.pdf)). Then, with the
    agent closed, write two sentences in your note: why you decided it
    should exist at all, and what it cost.

Where the agents differ, one line each
([curriculum research, 03 and 04](../research/curriculum/03-claude-code-and-antigravity.md)):

- **Claude Code:** ask for the research in step 4 in plan mode, so
  nothing is built until you have read the plan and said yes.
- **Antigravity:** keep plans on **Request review**, so the research
  comes back as an artifact you can comment on before step 5.
- **The open path:** a small model may not know the newest platform
  features, so ask it to name the documentation page each answer comes
  from, and keep ceiling features to what your computer can build and
  test ([the open pathway](../research/curriculum/04-open-pathway.md)).

**When you are ready to move on,** a feature you wanted from your own
use is live on every platform that can have it, someone other than you
has shaped it, and the older devices say honestly what they cannot do.
Why it exists is written in your note, in two sentences of your own. By
now you have built a lot, and taught the agent a lot along the way.
Stage 08 is about making sure it remembers.

**Go deeper.** Before the next feature, write down what the app already
has that could carry it, the way the playlist link did, and ask the
agent to argue for the version that adds nothing new. It is never
required, and it is never counted.

**If you get stuck.**

- *You do not know what you want it to do next.* Ask yourself: what did
  I reach for the last time I used it? Try
  [I do not know what I want it to do next](../stuck/writing/what-next.md).
- *It works, and it still feels wrong.* Ask yourself: what would the
  person it is for say? Try
  [it works, and it still feels wrong](../stuck/playing/feels-wrong.md).
- *You do not know when it is enough.* Ask yourself: does it bring joy to
  one person in the form it has today? Try
  [I do not know when it is enough](../stuck/publishing/when-is-it-enough.md),
  then ask your group.

**Before you close your note.** Four short lines, from my
[Educational Model Spec's AI Disclosure Protocol](https://github.com/bhwilkoff/educational-model-spec/blob/main/docs/implementation-tools/ai_disclosure_protocol.md):
the agent's role, your essential work, one thing you learned, and your
growth edge.

Be ready to show the feature on your newest device, the sentence an
older device shows instead, and one thing someone else changed about
it, and to explain why you decided it should exist at all.
