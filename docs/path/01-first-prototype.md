# 01. The first prototype

<!-- The screenshots on this page, and the one-line notes under them, were placed by Claude on October 7, 2026, from docs/images/agents/, and await Ben's review. -->

**Where you are.** Your note starts with a problem statement you revised
after two conversations, with who has it and why a computer cannot
simply solve it. The agent knows the why, and there is one rule in your
own words in `AGENTS.md`. There is no app yet.

<!-- The question, the first two steps, step 4's model study, the step
labels, the last step, the per-agent lines, and everything between the
bar and the last line: written by Claude, awaiting Ben's review
(curriculum C2, then rebuilt from research note 06, section 4, October
7, 2026). -->
**The question.** What is the smallest thing you could put in the hands
of one person you talked to this week?

Archive Watch began on April 17, 2026, and the first thing the agent
made was not a screen. It was a set of research notes on where film
metadata could come from. The next day brought a pipeline to gather
films from archive.org. On the third day the catalog held 799 real
films, and only then did the Apple TV app start to look like something.
Four days in, the pipeline had built a catalog of 25,000.

Tidbits Trivia began faster. I pasted in a description I had been
drafting in my notes: one sentence of wish, ten numbered features, a
request for research, and what "done" meant for the session. Four and a
half hours and three more prompts later, it played on four platforms
with ten thousand real questions.

One was slow and one was fast, but they started the same way. Neither
began with me typing in data or drawing screens. Both began with a wish,
a real source of truth, and a clear idea of what "done" meant for that
sitting. Those three things are the whole first stage, and they fit in a
single line:

**One platform, real data, this week.**

How small can that first thing be? Tidbits Trivia went from its first
commit to a TestFlight build in two days, because it started from a
template three other apps had already built
([curriculum research, note 01](../research/curriculum/01-mining-bens-process.md)).
Yours starts from the same template, so the first version can be that
small too, and it should be.

## What I want

I want someone who has never shipped an app to see their idea running
on their own phone, with real data in it, before the first week is out.
Not a mockup. A thing they can hold and be disappointed by in useful
ways, because the disappointment is where the next round of work comes
from.

## One platform

Pick the platform where your people are. Archive Watch started on the
Apple TV because it is an app for watching old films on a couch. A
trivia game for a classroom might start on the web, because every
student already has a browser.

If you do not know where your people are, start on the web. It costs
nothing, it needs no developer account, and the agent can put it live
on GitHub Pages at a real address you can open on your phone the same
day. The native apps come in stage 03, and they come faster because the
web version already taught you what the app is.

## Real data

Real data is uneven. Titles run long. Images come in every shape. Some
records are missing the one field the design assumed. You want to find
that out now, while the design is still a sketch.

So, you never type data in. You tell the agent where the truth lives (an
open API, a public dataset, a site with a feed), and it builds the
pipeline that brings the data in and keeps it fresh. Your job is to look
at what arrives, one real item at a time. Months into Archive Watch, I
was still doing exactly that. Browsing the live site in late August, I
found a film whose title had its cast pasted into it:

> Why does https://archivewatch.org/item/shakedown-1950 have actors
> names in the title?

One real item, and then the request that matters more: find every other
case like it.

## This week

The week is a series of rounds, not one big build. On April 19, Archive
Watch's commits run "UI feedback pass", "UI feedback round 2", "round
3", all the way to "round 7", in a single day. Each round was me using
the Apple TV and sending back a list of what was wrong. In BOBA
Playbook's second week, I sent five rounds in under two days, each one
after using the latest build.

You will not get it right the first time, and neither will the agent.
That is not a sign the process is failing. That is the process, and the
steps below are one lap of it.

## Working with your agent

You need one thing set up first: a GitHub account, with your copy of the
template kept public so GitHub Pages can host the web app for free. The
agent does the rest of the setup, and will tell you if it needs you.

The steps are one round of write, play, publish. The first three come
before the agent is open, the middle ones are play, with the agent and
on your phone, and the last one publishes to a person.

1. **Write your first answer.** Before any prompt, answer this stage's
   question in two or three sentences in your note. Being wrong is fine.
   Trying first, before you are shown, is what helps the rest of the
   stage stick (the research on productive failure, gathered in the
   [curriculum research](../research/curriculum/05-inquiry-and-evidence.md)).

2. **Write your questions.** For five minutes, write as many questions
   as you can about the smallest version of your app that one of the
   people you talked to could use this week,
   without stopping to answer or judge any of them. Then mark the one you
   most want answered by the end of the stage. (These are the Right
   Question Institute's rules for asking your own questions, also in the
   [curriculum research](../research/curriculum/05-inquiry-and-evidence.md).)

3. **Write the wish.** Under the why you wrote in stage 00,
   write the wish in one sentence. Under it, list what the app should
   do, numbered. (`talking-to-your-agent.md` shows the shape my notes
   took.)

4. **Play: study my kickoff as a model, then write and send yours.** A
   good kickoff has four parts: the wish, the source of real data, what
   you want researched before anything is built, and what "done" means
   for this sitting. Find all four in mine below, and mark where each one
   starts. Then hold your draft to the same four parts and fill in any
   that are missing, so you are borrowing the shape, never the app (this
   is how models of strong work are used in project-based classrooms,
   Ron Berger's practice, gathered in
   [note 06](../research/curriculum/06-instructional-design.md)). If this
   is your first app, read mine first. If it is not, write yours first
   and read mine after. Here is most of mine for Tidbits Trivia, June 16:

   > A fully realized multi-player (both local and online) trivia game
   > that is based entirely upon facts pulled from the open Wikipedia
   > API.
   >
   > Full features should include: [ten numbered features, from Game
   > Center support to "A huge number of questions (10,000+) ... to help
   > make sure that you never see the same question twice."]
   >
   > Please research other quiz/trivia/game/competitions apps that are in
   > the space and determine what key features are not listed above and
   > would allow for this app to compete on its merits [...]
   >
   > Please use your repository documentation to help you build out the
   > project/plan [...] A full parity matrix should be written with any
   > important platform-specific decisions that will need to be
   > considered.
   >
   > The final outcome of this session should be a working iOS version
   > with all v1 versions of the features fully implemented.

   Yours can be smaller, and it should be: the smallest thing that does
   what your problem statement says for the person you have in mind. If
   you are starting on the web, make "done" mean that the web version is
   live on GitHub Pages and you can open it on your phone. Then paste the
   whole kickoff in one message. The agent will do the research, build the pipeline for
   your source, build the first screens, and put it live. The
   `web-platform-patterns` and `universal-feature-states` skills carry a
   lot of that work without you asking for them.

   ![Antigravity has written a plan, lists three questions for the builder, and waits behind a Proceed button](../images/agents/antigravity-plan-review.png)

   If the agent shows you a plan first, answer its questions before you say go: that is your decision, not its.

5. **Play: keep it going.** When the agent reports back, do not polish yet.
   Ask for the next round of the wish. The night I started Tidbits, two
   of the three prompts after the kickoff were some version of this, and
   each one added a platform or a whole feature:

   > keep pushing forward with the next round of work to fully build
   > out this game/app

6. **Play: use it, with your note open.** Open the live address on your phone
   and use the app for real, for ten minutes, the way the person you are
   building it for would. Under a "Next:" heading in your note, write
   each thing you notice as its own numbered item: where it is, what is
   wrong, what it should be.

7. **Play: send the round.** Paste the whole list, with one line in front of
   it that sets the scope. In BOBA's first week, mine was as short as
   this:

   > Please update both apps (iOS and Web App)

   Ask the agent to fix all of it and to tell you which numbers are
   done. Move those to a "Done:" list in your note, use the app again,
   and start the next round. Do at least two laps.

8. **Play: steer the data with one real item.** Somewhere in those laps, find
   one record that is wrong (a bad title, a missing image, a question
   that makes no sense). Paste its link, ask why, and ask the agent to
   look for the same problem everywhere.

9. **Play: try it the hard way.** Turn on airplane mode and open the app. Run
   a search that should find nothing. Tell the agent what you saw. Every
   list in this template has a loading, empty, error, and offline state,
   and this is how you find out whether yours are real.

10. **Publish it to one person you talked to.** Send the live address to
    one of the two people you talked to in stage 00, and ask them to use
    it once, however they like, without you explaining it first. Write
    down what they did first and what they said, in their words, and
    then one line on whether it did what your problem statement says.
    Then, with the agent closed, write two sentences in your note: one
    thing you decided in this stage, and what it cost.

Where the agents differ, one line each
([curriculum research, 03 and 04](../research/curriculum/03-claude-code-and-antigravity.md)):

- **Claude Code:** in the desktop app's Code tab, start the first night
  in **Manual**, so you see each change before it is made.
- **Antigravity:** start in the **Default** preset, which runs the
  agent's commands in a sandbox, and use `/plan` to read its plan and
  comment on it before it builds.
- **The open path:** use Aider with a fully open model in Ollama. These
  models cannot see your phone, so in step 6 you are the agent's eyes:
  describe what you see in words. Start on the web
  ([the open pathway](../research/curriculum/04-open-pathway.md)).

**When you are ready to move on,** your app is live at a real address,
it is full of real data that a pipeline brought in, you have sent at
least two rounds from your own phone, and one of the people you talked
to has used it, with what they did first and what they said written in
your note. The app works on one platform.
Stage 02 is about deciding what it means for it to be the same app on
the next one.

**Go deeper.** Ask the agent to walk you through the pipeline it built:
where the data comes from, how often it refreshes, and what the app does
when the source is down. Write one thing you would change, and why. It
is never required, and it is never counted.

**If you get stuck.**

- *The agent says it fixed something you still see.* Ask yourself: did I
  say what I saw, where, and on which device? Try a screenshot, and check
  that your phone is not showing an old cached version of the page. Ask
  your group if it keeps happening ([stuck playing](../stuck/playing/cannot-see-the-fix.md)).
- *There is not enough real data, or it is not the right kind.* Ask
  yourself: what is this app actually about, in real things? Try asking
  the agent to research sources before it builds anything more. Ask the
  teacher if no open source seems to exist ([stuck playing](../stuck/playing/not-enough-data.md)).
- *You are not ready to show anyone.* Ask yourself: what would one person
  learn from it as it is? Try showing your group first, then one of the
  people you talked to ([stuck publishing](../stuck/publishing/not-ready.md)).

**Before you close your note.** Four short lines, from my
[Educational Model Spec's AI Disclosure Protocol](https://github.com/bhwilkoff/educational-model-spec/blob/main/docs/implementation-tools/ai_disclosure_protocol.md):
the agent's role, your essential work, one thing you learned, and your
growth edge.

Be ready to show the app on your phone, to name one thing the real data
taught you that fake data would have hidden, to say what the person you
talked to did with it and whether it did what your problem statement
says, and to explain why you started on the platform you chose.
