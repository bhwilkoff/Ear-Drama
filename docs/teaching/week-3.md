# Week 3: proof that it works, and someone else's hands

<!-- This guide: rebuilt from research note 06 (docs/research/curriculum/
06-instructional-design.md, section 4) by Claude, awaiting Ben's review,
October 7, 2026. Ben's own stories and prompts are quoted from the
stages. -->

**Where the cohort is.** Week 2 was [stage 02](../path/02-shape-of-an-app.md)
and [stage 03](../path/03-going-native.md). Everyone read and trimmed a
parity matrix, wrote at least one rule about their data that the
pipeline now enforces, got a second platform running on their own device
in its own idiom, chose a floor from a measurement, and gave the app a
look that comes from its why. Everyone also opened two apps from outside
their group and left the three questions in writing.

Tonight shows that work, and starts the week ahead: [stage
04](../path/04-seeing-it-work.md), where the agent stops relying on the
builder to find its mistakes, and [stage 05](../path/05-shipping.md),
where the app reaches a device the builder did not build it on. This is
the week the app leaves your hands.

This is also the week the prompt reading starts to come from the cohort
itself. Tonight's situation is a classmate's real stuck moment, shared
with their permission, which is a bigger thing to ask of someone than a
story from the stages, so handle it with care.

**The agent is never the tester.**

## The move and the question

**Play, then publish.** This week leads with play, because proof comes
from using the app on the device, and ends with publish, because the
week ends with the app in someone else's hands.

The question the whole session turns on: **How do I know it works, and
what happens when someone I did not build it with holds it?**

Every session is one round of Write, Play, Publish at a larger size,
the same three moves as stage 00, and the principles decide what gets
written, played with, and published
([`00-curriculum-design.md`](../research/curriculum/00-curriculum-design.md)).

## The run of show

| Minutes (75) | Scene | Kind | What happens |
|---|---|---|---|
| 0-5 | Arrive | Talk | One line in the chat: the one cell your own eyes proved wrong this week. Then what I heard in last week's answers, and what I changed because of it. |
| 5-35 | Show what you brought back | Rehearsal rooms | Groups of three. The room's prompt: "Show one verb on both platforms, the cell your eyes proved wrong, and your app's look beside the template's." |
| 35-38 | Break | Break |  |
| 38-53 | Read one real prompt | Design stage | A classmate's stuck moment, with their permission (or the doubled-up feed from stage 04). Write the prompt you would send before you see the real one. On the board: *Read one real prompt*. |
| 53-57 | Watching someone hold it | Talk | How to watch one person use your app without explaining it, and what to write down. |
| 57-70 | Start | Reflection | Ask your agent to prove its next fix on your device. Then plan who will hold your app, on which device, and how it gets there for free. "Who will hold it, on which device, and how will it get there?" |
| 70-73 | What do you ask to see? | Question | "When your agent says something is fixed, what do you ask to see, and why is its word not enough?" (in their own words) |
| 73-75 | What is still muddy? | Question | "What is still muddy?" (in their own words) |

**In the rehearsal rooms,** each builder's turn runs these scenes, 10
minutes in all: their question (1), show it, and one decision (4), one
clarifying question (1), the three questions (3), what comes next (1).
The room's prompt is on screen the whole time.

These are the scenes a new cohort is made with on humanshaped.org, from
[`runs-of-show.json`](runs-of-show.json), and every one of them can be
changed in the class builder, before the session and during it. To fit
60 or 90 minutes, use the table in the [guides' index](README.md).

**What to watch for tonight.**

- A second platform that only runs in a simulator.
- A look chosen because the builder likes it, with no line back to the
  people the app is for.
- Anyone who has not yet named a person outside the cohort whose device
  the app could reach this week.

## The opening

> Welcome back. Two weeks ago your app was an idea and a problem
> statement. Tonight it runs on two devices and wears its own look. This
> week it leaves your hands, and that changes what "done" means: it is
> no longer done when it works for you. Before you show, say in one line
> what you want your partners to tell you.
>
> Tonight's prompt comes from one of you, with their permission, and I
> want to thank them now, before we start, because showing the moment
> you were stuck is the hardest kind of showing there is.

## What they bring back

The cohort's bring-back, from `COURSE.md`: one verb on both platforms,
each in its own idiom, one cell their own eyes proved wrong, and the
app's own look beside the template's. The stages' own lines:

> Be ready to show your matrix and one cell the audit or your own eyes
> proved wrong, and to explain the rule about your data that you decided,
> and why you drew it where you did.

> Be ready to name the oldest device your app will run on and why you
> chose it, the newest feature it will not show there, and why its new
> look fits the people it is for.

**The bar.** For stage 02: "there is a matrix you have read and trimmed,
one rule about your data that you decided and the pipeline now
enforces, and every Share button points at your web address." For stage
03: the second platform is on the student's own device, does the same
things as the first in its own idiom, has a floor chosen from a
measurement, and looks like the student's app rather than the template.

**What to look for.**

- One verb (search, save, share) done on both platforms, with each
  platform's own controls. The same result reached in two different
  ways is right. The same screen squeezed onto a second device is not.
- A matrix with marks on it: rows struck out, cells questioned.
- A rule about the data that the student decided, said in their words,
  with the reason it sits where it does.
- A floor chosen from what the agent measured.
- A look that came from choosing among directions, explained by who the
  app is for.

**Signs of "not yet."** A matrix nobody has read. "The agent picked the
floor." An app that still wears the template's colors and type.

## On the design stage: one real prompt

Put the board on the main stage from the *Read one real prompt*
template, filled with the situation below.

**Choosing the situation.** Use a stuck moment from last week's checks
or the cohort's conversation, and ask its owner privately, before the
session, whether you may use it. Put up what they saw and what the
agent said, never what they sent, so everyone tries it fresh. Then
everyone writes their prompt alone, compares with a partner, and sees
what the classmate actually sent, along with what happened next. Let
the classmate tell the story if they would like to, and never press
them if they would rather not.

**If nobody offers one,** use this situation from stage 04, in Bsky
Dreams' first month. The feed was showing posts twice. The agent had
tried three fixes, none of them had worked, and it was still telling me
that they did. Ask what they would send now. Then show the real prompt:

> You have clearly not found the root cause of the issue, nor are you
> actually testing to make sure that it is fixed before telling me
> that it works. Please create a test for how you will determine if a
> post is rendered a signgle time and continue to work until your
> code passes that test.

**What to talk about.** The prompt stops asking for a fourth fix, and
asks instead for a way to see the problem. That is the move stage 04 is
built on: the agent is never the tester, and every "fixed" should point
at something a person could look at. Ask what in their own app they
have taken the agent's word for.

## Watching someone hold it

Stage 05 ends with one person who did not build the app holding it. The
way to learn the most from that is old and simple: give them one thing
to do, then watch, without explaining, and write down what they did,
where they paused, and what they said, in their words. Nielsen Norman
Group's guide to thinking aloud
([Nielsen, 2012](https://www.nngroup.com/articles/thinking-aloud-the-1-usability-tool/))
is the plain version of the method, and the BOBA Playbook story in
[note 01](../research/curriculum/01-mining-bens-process.md) (one tester's
call becoming six written fixes) is what it looks like in a real app.

**What to talk about.** The urge to explain is strong, and every
explanation hides something the person would have found confusing.
Ask everyone to write the one thing they will ask their person to do.

## Start

Everyone begins [stage 04](../path/04-seeing-it-work.md) by telling
their agent, in their own words, that it should see what they see and
that they should not be the one testing its work, and asking it to set
itself up to test on their device. One phone is enough. Then they plan
[stage 05](../path/05-shipping.md): the person, the device, and the free
way to get it there this week (a direct share, a test track, or the web
version on an iPhone; stage 05's "Sharing it for free"). They send the
stage 04 prompt before they leave.

## The check

The question scenes at the end of the run of show, answered privately,
and shown on the main stage without names only if you choose:

1. **When your agent says something is fixed, what do you ask to see,
   and why is its word not enough?** (in their own words).
2. **What is still muddy?** (in their own words).

**Also prepared:** "How do you know your last fix is real?"

The answer you hope for names evidence from outside the agent: a
screenshot from the device, a measurement, or a test that could have
failed. An answer that trusts the agent's report is worth a word.

## The task, and its evidence

**The task, this week.** Have the agent prove a fix on your own device,
give your devices roles, and put the app on a device you did not build
it on, then watch one person use it.

**Evidence a person can open.** The screenshot that proved a fix, and
what it would have shown if the fix had failed; the app installed on
someone else's device; what that person did first, in their words.

**On the credential.** Recognitions: "Tested it the way people will
actually use it," "Got it onto someone else's device," and "Helped a
classmate see their work more clearly." Students do the thing itself,
and what they make is the evidence; nobody writes a report about it
([`05-inquiry-and-evidence.md`](../research/curriculum/05-inquiry-and-evidence.md)).

## When someone is stuck

Every entry in the [stuck library](../stuck/README.md) starts with a
question to ask yourself, then what to try, then who to ask. This week,
point people to:

- [Stuck playing](../stuck/playing/README.md), for when the agent fixes
  what you cannot see, a bug keeps returning, or the tools themselves are
  stuck.
- [I cannot get it onto someone else's device](../stuck/publishing/someone-elses-device.md).

And the ladder for any of them: name the kind of stuck, write three
lines (what you tried, what you expected, what you saw), ask the agent
for a way to understand it rather than the fix, look on the device and
at the last thing that worked, then your trio, then the teacher. About
twenty minutes before the trio is a default each person can move.

## The close

> Answer the questions on the live page before you go. Next week, bring
> a screenshot that proved a fix, and your app on a device you did not
> build it on, with what that person did and said, in their own words,
> in your note.

## After the session

Read the checks, write your two sentences, and reach out within two
days to anyone who missed the session or brought nothing back. Thank
tonight's classmate privately, and ask someone else for permission to
use their stuck moment in week 4. Week 4 is also the first of the
sessions where you look closely at every bring-back, so set aside time
the day after it.

Next week, the app in someone else's hands.
