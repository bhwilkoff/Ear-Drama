# 08. Working with AI

<!-- The screenshots on this page, and the one-line notes under them, were placed by Claude on October 7, 2026, from docs/images/agents/, and await Ben's review. -->

**Where you are.** You have been building for weeks. By now the agent
has forgotten something you told it at least once, and you have had to
explain it again. This stage is about making that stop.

<!-- The question, the first two steps, the step labels, the last step,
the per-agent lines, and everything between the bar and the last line:
written by Claude, awaiting Ben's review (curriculum C8, the lesson page
template in docs/templates/LESSON-template.md). The bar's opening words
changed from "When you are done with the stages," to "When you are done
with the path," which is what humanshaped.org's path pages read. Rebuilt
by the method of curriculum research note 06 (docs/research/curriculum/
06-instructional-design.md, section 4), which Ben approved on October 7,
2026: designed backward from the "Be ready to" line, with Ben's Archive
Watch case study as the model of a value tied to a decision, and the
declaration shown to everyone, guests welcome. -->
**The question.** What did this app teach you that your next app, and
the next builder, should not have to learn again?

On September 24, 2026, I wrote this to the agent working on Archive
Watch:

> You have fully documented device testing pathways for each device.
> Please stop trying to reinvent things you already know how to do.

It had improvised a way to wake an Apple TV and install a build, step
by step, when a runbook in the same repository already said exactly how,
and the tools to do it were sitting in `tools/`. The agent was not
careless. It simply did not remember. Every session starts fresh, and
the only memory it has is what it reads.

**The agent remembers only what the repository remembers.**

Stage 00 said the same thing about values. This stage says it about
everything else: the method, the lessons, the state of the work, and
the reasons behind the choices.

## What I want

I want every session to start where the last one ended. I want every
hard lesson to be learned once, and then to be the thing the agent
reaches for first. And I want to be able to read, at any point, what was
done, what was verified, and what was only hoped.

## Where the memory lives

There are two halves. Your note, which you have kept since stage 00, is
yours: the wish, the rounds, the ledger, what other people said. The
rest is the agent's, a set of files each with one job, read at a
different moment. You will not edit those yourself. Your part is to ask
the agent to keep them, and to notice when it has not.

| File | Its job | Read |
|---|---|---|
| `AGENTS.md` (`CLAUDE.md` and `GEMINI.md` import it) | Who the app is for, the rules, and the table of which skill to use when. | At the start of every session |
| `SCRATCHPAD.md` | The current state, the next actions, and the last two session-log entries (state found, work done, state left). Older entries move, word for word, to `docs/SESSION-LOG.md`. | At the start of every session |
| `DECISIONS.md` | Why the app is built the way it is. Each entry leads with the rule, then why, then how to apply it. | Before changing anything it covers |
| `PARITY.md` | What exists on which platform, honestly. | Before and after any feature |
| The agent's memory | Corrections and confirmations from you, each with a "Why" line. Claude keeps them in its memory folder. A rule for the whole project goes in `AGENTS.md`, which every agent reads. | At the start of every session |
| `.claude/skills/` | Lessons that should travel to the next app. Gemini finds them through `.agents/skills/`. | When a request matches |

Two rules keep these useful.

**Keep what is loaded every session small.** Archive Watch's
always-loaded files grew to about 382 KB, which crowded out the code
being worked on. Rolling old decisions and old session logs into
archives, word for word, brought it to about 80 KB. The decision log now
rolls at about 50 KB. Nothing is summarized in place. A summary loses
exactly the detail the next person needed.

**A stale file is worse than no file.** A scratchpad that says a
feature is unfinished when it shipped yesterday sends the next session
to do it again. When you find drift, fix the file before doing anything
else.

## How the lessons compound

- **Corrections become memories.** When you tell the agent "don't do
  that", it saves the rule with the reason. When you say "yes, exactly
  that" about a choice that was not obvious, it saves that too. Quiet
  confirmations matter as much as corrections.
- **Recurring lessons become skills.** When the same mistake could
  happen in the next app, the lesson goes into a skill, and the template
  gets it too. `docs/PROVENANCE.md` records where every lesson came from,
  so nothing learned in one app stays trapped there.
- **Fix the doc first, then the feature.** When a design rule and a
  feature disagree, the rule is where the bug is. Change it on purpose,
  then build.
- **Commit messages quote the request.** Months later, the words you
  actually used explain a change better than anyone's summary of them.

## From reason to rule to check

Stage 00 said values climb. Here is the whole ladder, because by now
your app has values on every rung.

1. **A reason.** The "Why we build" paragraph. The agent reads it and
   weighs it, the way a person weighs advice.
2. **A rule.** A standing instruction in your own words, with a date,
   written the day the agent crossed a line. The agent reads it every
   session, but reading is not the same as obeying. `AGENTS.md` is
   context, and an agent working hard on something else can still miss
   a sentence in it.
3. **A check.** A test, or a hook that runs before the agent acts, that
   fails when the line is crossed. Now the agent cannot cross it without
   being told.

Not every value can climb all the way. "Only essential words on screen"
needs a person's judgment, and probably always will. But, when a rule is
specific enough to test, test it. "One spelling locale" climbed from a
word I noticed on a label to a test that reads every string in the app.
In `AGENTS.md`, each value rule says what holds it: a check, or "no check
yet."

## Honesty in the log

An agent reports what it intended. So, the log keeps two words apart:
**fixed** (the code changed) and **verified** (something outside the
agent saw it work, per stage 04). A feature is not verified because the
agent says so, and it is not shipped because it is verified (stage 05).

One more rule came from a hard week. A note in Archive Watch's docs once
said that a page in Amazon's developer console did not exist, and added:
"Do NOT re-walk the console nav." The page did exist, one menu over. The
note written to save time is what stopped anyone from looking, and
Amazon's reporting API stayed unreachable for five weeks over a
two-click setting. So now, **a negative finding says how it was found
and when it should be checked again.** An absence you searched for once
is weak evidence, and consoles change.

## Give it a check, and keep git as the undo

*Written by Claude, awaiting Ben's review.*

Anthropic's own advice for Claude Code starts with one line: "Give Claude
a check it can run: tests, a build, a screenshot to compare. It's the
difference between a session you watch and one you walk away from"
([best practices](https://code.claude.com/docs/en/best-practices)).
Antigravity asks for the same thing in its own way, by showing you its
plan and the screenshots its browser took as artifacts you can comment
on ([Antigravity, browser](https://antigravity.google/docs/ide/browser/)).
A check is the honest log's partner: it is how **fixed** turns into
**verified** without you having to be the one who looks every time. So
when you ask for something, ask for its check too, and ask the agent to
show you what the check returned rather than telling you it passed.

![Antigravity's list of what it did: each file it edited with lines added and removed, then the template's checks it ran](../images/agents/antigravity-agent-checks.png)

Both tools can also take a step back, and both are careful about what
that means.

- **In Claude Code,** `Esc` twice or `/rewind` takes the conversation,
  the code, or both back to an earlier prompt. But "Checkpoints only
  track changes made through Claude's file editing tools," and Anthropic
  says plainly, "This isn't a replacement for git." After two
  corrections that did not take, `/clear` and a better first request
  usually do more than a third correction
  ([best practices](https://code.claude.com/docs/en/best-practices)).
- **In Antigravity,** `/rewind` (also `/undo`) goes back to an earlier
  checkpoint, and since September 30, 2026 it can take back only the
  conversation and leave your files alone. `/fork` lets you try
  something without losing where you were
  ([changelog](https://antigravity.google/docs/changelog/)).

![Claude reports the one line it changed, says its browser preview loaded without styles so you should open the site yourself, and shows an Undo beside the change](../images/agents/claude-checked-with-undo.png)

The honest report names what the check could not show, and the Undo beside the change takes back only that change.

**Checkpoints are not git.** A commit is the only undo that covers every
change, whoever or whatever made it, so ask the agent to commit each
small step that works. The research behind this section is
`docs/research/curriculum/03-claude-code-and-antigravity.md`.

## Why loops depend on all of this

The loops from stage 06 are where memory matters most, because a loop
runs for hours with nobody watching each step. A loop without a plan
file forgets what it was doing. A loop without the stage 04 rules
reports fiction. A loop whose always-loaded files have grown too large
runs out of room to think. `docs/AUTONOMOUS-LOOPS.md`,
`docs/ENGINEERING-PROCESS.md` and the `autonomous-loop-cadence` skill
carry the rest.

## What it costs

Writing things down is slower than not writing them down, every single
time. A decision entry takes ten minutes. A skill takes an hour. And
written things go stale: the "Consequences" paragraph of a decision can
be wrong before the session that wrote it is over.

But, the alternative is paying for the same lesson again. Archive Watch
learned how to wake an Apple TV once. The session that forgot paid for
it a second time.

## Where AI does not belong

Go back to stage 00 before you finish. Everything in this stage makes
the agent a better builder. None of it makes the agent the right one to
write your app's words, choose what your people should see, or do the
part of the work that was supposed to be theirs. Those lines are yours
to draw, in writing, where the agent will read them.

## Working with your agent

This stage leads with write, then publishes to everyone, guests welcome.
The steps are one round of write, play, publish: the first two come
before the agent is open, the middle ones are play and writing with the
agent, and the last one shows your app and your declaration to everyone.

1. **Write your first answer.** Before any prompt, answer this stage's
   question in two or three sentences in your note: the one lesson from
   this app you would most want carried forward. Being wrong is fine.
   Naming it first is what lets you see whether the agent's files
   actually hold it (the research on productive failure, gathered in the
   [curriculum research](../research/curriculum/05-inquiry-and-evidence.md)).

2. **Write your questions.** For five minutes, write as many questions
   as you can about what your agent remembers and what it forgets,
   without stopping to answer or judge any of them. Then mark the one you
   most want answered by the end of the stage. (These are the Right
   Question Institute's rules for asking your own questions, also in the
   [curriculum research](../research/curriculum/05-inquiry-and-evidence.md).)

3. **Write: before a session ends, ask it to write everything down.** Any time
   you are about to stop, restart, or run low on context. This was the
   middle of a long Archive Watch session in September:

   > We are close to needing to compact, please document everything we
   > might need before I do that.

4. **Write: when you correct something twice, make it a rule.** The first of
   these came after Archive Watch's loop kept re-arming without saying
   when it would next wake; the second after a Tidbits loop stopped
   itself, again, to report that its context was running low.

   > Can you make a memory so that after every tick when you re-arm the
   > loop, you give a time when the next tick should occur?

   > If you are low on context, compact. Can't you simply add that as a
   > rule?

5. **Play: when it reinvents something, send it back to what it wrote.** On
   September 7, the agent was rebuilding parts of Archive Watch's video
   player to fix problems we had solved months earlier:

   > I feel like we had solved all of this so so long ago as we were
   > building the last resilient player for apple's platforms. Are we
   > redoing work that has already been done and is documented already?

6. **Play: ask it what it is waiting on.** Instead of reading its notes, ask.
   I asked Archive Watch's agent exactly this on September 21:

   > What are the things you are wating on me for?

   And when there are decisions to make, ask for them as choices.

7. **Write: turn this app's lessons into skills.** When you have learned
   something the next app should not have to learn again, ask for it.
   This was the end of a long day in September, most of it spent on
   Archive Watch's social posting:

   > Document everything we have done today, as we are needing to
   > compact. (create any new skills necessary)

   Then ask the agent to bring those skills back into your copy of the
   template, so your next app starts with them.

8. **Write: draw the line again.** Reread your "Why we build" paragraph and your
   standing rules from stage 00. Ask the agent whether anything you have
   built since crosses them. Decide what to do about each answer
   yourself. Then ask which of your rules are now specific enough to
   become checks, and have it write them.

9. **Write: find the decision each value changed.** First read the
   September section of my
   [Archive Watch case study](../human-shaped/case-study-archive-watch.md),
   "nine platforms, and the values written down," as a model: notice
   that the $0 rule is tied to a dated thing I refused to build (the paid
   voice server, September 20), and that the section ends with values
   climbing "from a reason, to a standing instruction, to a test." Then go through your own values one
   at a time and name a decision it changed: something you built
   differently, or did not build, because of it. A value that never
   changed a decision is decoration. Rewrite it until it does work, or
   let it go.

10. **Publish: ask for a human-shaped review, then declare.** Ask your agent for
   a human-shaped review of your app, read what it found and what it
   could not see, and answer its questions for yourself. Then copy
   `docs/human-shaped/HUMAN-SHAPED-template.md` to the root of your
   repository as `HUMAN-SHAPED.md`, and answer each principle in your own
   words. The directory at humanshaped.org reads that file.

11. **Publish: show it to everyone, guests welcome.** At the cohort's
    last session, show your app on the device it was made for, your
    `HUMAN-SHAPED.md`, and one value with the decision it changed. Ask
    the room, guests included, for one kind, specific, and helpful note
    by Ron Berger's rules
    ([Berger, "Fostering an Ethic of Excellence"](https://jaymctighe.com/wp-content/uploads/2011/04/Ron-Berger-Article.pdf)).
    A public product shown to people beyond the cohort, and a reflection
    on it, are what project-based learning ends with
    ([PBLWorks, Gold Standard Project Design Elements](https://www.pblworks.org/what-is-pbl/gold-standard-project-design)). Then,
    with the agent closed, write two sentences in your note: what is
    enough about this version, for now, for the people you named in stage
    00, and what waits, written down rather than built.

Where the agents differ, one line each
([curriculum research, 03 and 04](../research/curriculum/03-claude-code-and-antigravity.md)):

- **Claude Code:** corrections become memories in its memory folder, and
  a rule for the whole project goes in `AGENTS.md`, which `CLAUDE.md`
  imports.
- **Antigravity:** `/learn` turns a session's corrections into rules or
  skills in your repository (`.agents/rules/`, `.agents/skills/`), where
  you can read them.
- **The open path:** a small model reads `AGENTS-SHORT.md`, so the most
  important lessons go there in a line each, and the full ones in
  `AGENTS.md` and `DECISIONS.md`
  ([the open pathway](../research/curriculum/04-open-pathway.md)).

**When you are done with the path,** your app is shipped and running,
your agent remembers what you taught it, your `HUMAN-SHAPED.md` answers
each principle in your own words, and the lessons from this app are
waiting for the next one. The next app starts at stage 00 again, with a
new note and a new why. It will go faster, because this time the
repository remembers.

**Go deeper.** Pick one rule from your `AGENTS.md` that says "no check
yet", and ask the agent to make it a check: a test or a hook that fails
when the line is crossed. It is never required, and it is never counted.

**If you get stuck.**

- *The agent keeps forgetting.* Ask yourself: is the lesson written where
  every session reads it? Try
  [the same bug keeps coming back](../stuck/playing/same-bug.md).
- *You cannot say what your app refuses to do.* Ask yourself: what did I
  stop the agent from doing? Try
  [I cannot say what it refuses to do](../stuck/writing/what-it-refuses.md).
- *You do not know when it is enough.* Ask yourself: does it bring joy to
  one person in the form it has today? Try
  [I do not know when it is enough](../stuck/publishing/when-is-it-enough.md),
  then ask your group.

**Before you close your note.** Four short lines, from my
[Educational Model Spec's AI Disclosure Protocol](https://github.com/bhwilkoff/educational-model-spec/blob/main/docs/implementation-tools/ai_disclosure_protocol.md):
the agent's role, your essential work, one thing you learned, and your
growth edge.

Be ready to show one skill your app taught, the mistake it will save the
next person from, and one value with the decision it changed.
