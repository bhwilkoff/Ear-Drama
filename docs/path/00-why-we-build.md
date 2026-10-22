# 00. Why we build

<!-- Rebuilt from curriculum research note 06 (docs/research/curriculum/
06-instructional-design.md), which Ben approved on October 7, 2026 (site
DECISIONS.md, "Note 06 is the basis for the curriculum"). New prose is
written by Claude, awaiting Ben's review. Ben's own words, stories, and
his original steps from commit d70c674 are kept as he wrote them. -->

**Where you are.** You have your own copy of this template, and maybe an
idea for an app, or maybe only a sense that some part of your life
should be easier than it is. Nothing is built yet, and that is exactly
the right moment for this stage.

**The question.** What problem in your own life is worth building
something for, and who else has it?

On September 26, 2026, deep into building Archive Watch, I told the
agent I was working with this, and it became one of the project's
standing instructions:

> I don't want AI making lists and writing copy. Any time we can use
> metadata or user copy/categorization from archive.org.

Archive Watch had 4,306 commits by the end of that month, and 2,753 of
them carry Claude's name as co-author. It runs on iPhones, iPads, Macs,
Apple TVs, Android phones, Google TVs, Fire TVs, Rokus and the web. An
AI wrote most of the code, and yet the rule I cared about most that week
was a limit on what AI is allowed to do *inside* the app.

Both of those are true at once. This template is built to hold them
together, and the reason starts with something I wrote six months
earlier.

## Computer-shaped problems

Nilay Patel calls it software brain: seeing the whole world as a set of
databases, each one waiting for the right code to take control of it.
In March I typed a page about that habit in myself. Community is not a
computer-shaped problem, and neither are relationships or learning. And
yet there are so many computer-shaped problems, and making everything
into something I can feed into the Claude Code window is "so seductive
and more than a little thrilling."

The page ends here:

> Sometimes the window isn't showing me the future. It is just showing
> me another way to avoid the hard work of living.

This template is for building software with that window open. So, how
do you keep the window from doing the part that was supposed to be
yours, or your users' part, the part where the learning happens?

You write it down.

**An agent keeps only the values you write down.**

An agent building your app will do whatever satisfies the request most
cheaply. Writing a blurb for ten thousand films is cheap for a model.
Building a pipeline that pulls each film's notes from the people who
actually uploaded and reviewed it is not. Left alone, the agent will
reach for the blurb, and it is not wrong to: nobody told it otherwise.
The values have to live where the agent reads them, at the moment it
makes the choice.

## Human-shaped software

I call what this template builds *human-shaped software*. A
computer-shaped problem is one you can hand to the window. Learning,
community, and relationships are not, because they only happen when a
person does the work. Human-shaped software uses AI as a tool that
people wield for human purposes, built around those parts rather than
over them. It takes the mechanical work off people's hands and leaves
them the learning
([computer-shaped problems](../human-shaped/computer-shaped-problems.md)
tells the longer story, with examples of each shape).

Learning is the frame for everything in this template, and it runs in
three directions at once.

- **As a student,** you are learning a way of building, one stage at a
  time. Every stage ends with something to bring back and show another
  person, because a method is learned by showing it, not by reading it.
- **As a builder,** you are learning what your app is. The agent writes
  the code. Deciding what to build, judging what came back, and using it
  every day are yours, and they are where you learn. Hand those to the
  agent and the app gets built while you learn nothing.
- **As a human,** you are deciding, at every step, what to hand to the
  window and what to keep. The app should leave the people who use it
  more capable, and building it should do the same for you.

So, every round of every stage makes the same three moves:

1. **Write.** Writing gets it out of your head. The values, the
   features you want, the feedback you hear, and everything else you
   think is important go where you and the agent can both read them,
   because a value you have not written down is one the agent cannot
   keep.
2. **Play.** Playing makes your thinking tangible. Whatever came back
   from the agent, you use it, test it, and probe it on a real device,
   and you think about what to try next. The agent is never the tester
   (stage 04), so every "it works" is something you have played with
   yourself.
3. **Publish.** Publishing releases the work into the world so that
   other people can play with it too, which gives your work a real
   audience. Human-shaped problems are rarely yours alone. They tend to
   be shared by many people, and sometimes by nearly everyone, so the
   people who play with what you publish tell you what to write next.

**Write, play, publish.**

The moves are not stages. Each round of each stage makes all three, and
the principles decide what you write, what you play with, and what is
ready to publish. This stage is where the first move starts, and it
starts before there is anything to build.

## Choosing the problem

<!-- Written by Claude, awaiting Ben's review (note 06, sections 1 and
3). -->

Every app in this course starts with a problem in someone's life, and
the first job is choosing that problem well. It is also the step my own
record says least about. None of my four apps began as an idea for an
app, and for each one I wrote the why and did the research before
building ([curriculum research, note 01](../research/curriculum/01-mining-bens-process.md)).
Archive Watch started on an evening in April "for watching old
public-domain films on an Apple TV"
([the case study](../human-shaped/case-study-archive-watch.md)). Bsky
Dreams' README asks of every feature, "does this invite deeper
engagement, more critical thinking, or more meaningful connection?" BOBA
Playbook's pitch says its goal is "to help you engage with the game more
deeply." How I chose those problems over others happened in my head, so
this stage gives you the steps I never wrote down.

This is what I mean by a human-shaped problem:

> A human-shaped problem is something, really anything, in your life
> that will in some way make your life better, happier, or more deeply
> resonant with the universe if you could only solve for it. [...] It is
> a thing that you wonder and question about often. It is something that
> has gone unsolved for months or even years [...]. And most of all, it
> is something that you cannot do yourself. Your current tools and
> resources are insufficiently up to the challenge.

That definition, my principles, and my published examples are not a
quiz to pass. They are the tools you use on the one thing only you can
answer: which problem in *your* life is worth building for.

### Notice before you choose

Ideas for problems come from noticing, not from thinking one up on the
spot. Paul Graham's version is that "the verb you want to be using [...]
is not 'think up' but 'notice'" ([How to Get Startup Ideas, 2012](http://www.paulgraham.com/startupideas.html)).
So, before you choose, you keep a short log for five days, a small
version of what researchers call a diary study, where a person writes an
entry whenever something happens ([Nielsen Norman Group, 2024](https://www.nngroup.com/articles/diary-studies/)).
The log has four prompts, in plain words. Write one line whenever one of
these happens:

- I wished something worked differently.
- I gave up on something I care about.
- I did something the long way because nothing helped.
- Someone I know struggled with the same thing.

No app ideas in the log. Just what happened.

### Ten things to hold a problem to

These come from what I have already written about human-shaped problems.
I never wrote them as a checklist, but each is something I say plainly
([note 06, section 1](../research/curriculum/06-instructional-design.md)).
Hold each of your candidates to them, and mark each one "yes," "not
yet," or "I don't know."

| | The test | Where I wrote it |
|---|---|---|
| 1 | Solving it would make your life better, happier, or more resonant. | [computer-shaped problems](../human-shaped/computer-shaped-problems.md#computer-shaped-and-human-shaped) |
| 2 | You wonder and question about it often. | the same |
| 3 | It has gone unsolved for months or even years. | the same |
| 4 | You cannot do it yourself with the tools and resources you have now. | the same, and [principle 1](../human-shaped/PRINCIPLES.md) |
| 5 | Real people have it, and you can name them. | principle 1 |
| 6 | It is rarely yours alone: other people would recognize it. | "Write, play, publish," above |
| 7 | A computer cannot simply solve it for them. | principle 1, "How you can tell" |
| 8 | It is about people's stories, not about counting data points. | computer-shaped problems, its closing lines |
| 9 | Solving it would not create a new problem for someone else. | [principle 12](../human-shaped/PRINCIPLES.md) |
| 10 | At least one person would be glad of a first version. | [principle 15](../human-shaped/PRINCIPLES.md) |

A "not yet" or an "I don't know" is not a failure. It is the next thing
to find out, and most of them are answered by talking to people.

### Say it the way my examples say it

My [four human-shaped problems](../human-shaped/problem-statements.md)
are worth studying before you write your own, the way you would study a
good paragraph before writing one. Which shape each one is, I have
already said. What you are looking for is what makes them strong enough
to build from. Ron Berger calls this studying "examples of excellence,"
and it comes before critique and revision
([Berger, 2006](https://jaymctighe.com/wp-content/uploads/2011/04/Ron-Berger-Article.pdf)).

### Talk to people who have it

A problem you have only thought about is a guess about other people. So,
you talk to two of them before you build anything. The rules are simple,
and they come from people who do this for a living: ask about a
specific time in the past ("Tell me about the last time you..."), ask
why, and listen more than you talk (the Stanford d.school's interview
rules and Rob Fitzpatrick's *The Mom Test*, both gathered in
[note 06](../research/curriculum/06-instructional-design.md)). Do not
pitch an app. You are listening for their story, because human-shaped
problems "see the world as interrelated stories to be told, experienced,
and added to."

## Where the values live in this template

There are three places, and each one is read at a different moment.

1. **`AGENTS.md`, "Why we build."** Your agent loads this file at the
   start of every session (`CLAUDE.md` imports it for Claude Code, and
   `GEMINI.md` for Gemini). The paragraph at the top is the one I wrote
   for every app I build:

   > Every feature in this app is built in service of human learning and
   > growth, not to replace thinking, but to deepen it. [...] The goal is
   > never a slick product. It is a tool that makes someone more human.

   The paragraph sounds abstract until it has to decide something. In
   July, Tidbits Trivia's agent was deciding how much of a new paid club
   to put behind locks, and I answered with the reason the app exists:

   > the whole point of Tidbits Trivia is that we are the world's best
   > trivia app with the least amount behind a paywall.

   That one sentence decided the design: one quiet row for the club,
   and everything else free. Your app's paragraph will do the same work
   for questions you cannot see yet.

2. **The four questions** (the `learning-orientation-design` skill). Before
   any feature is built, the agent asks:

   1. Does it deepen understanding?
   2. Does it invite participation?
   3. Does it support human agency?
   4. Is it clear rather than clever?

   A "no" to any of them is a redesign, and it happens at the proposal,
   not after the code exists. The questions came from BOBA Playbook, a
   trading-card app, where search shows its filter tokens (Weapon: Fire,
   Treatment: Battlefoil) instead of hiding them behind a "for you" box.
   Folks who search that way learn how the catalog is organized. Folks
   handed a "for you" box learn nothing, and come to depend on it.

3. **Standing instructions.** These are the dated rules, in your own
   words, that an app earns as you build it. I did not write mine in
   advance. I said each one the moment the agent crossed it, and asked
   for it to be written down. Archive Watch earned three in one week:

   - **Only essential words on screen.** "You and I are having a
     conversation, but not everything I say or what you discover needs
     to be listed in the interface." A caption stays only if it explains
     why something is disabled, warns about something the person could
     not otherwise know, or states a fact they cannot find by looking.
   - **No AI-written lists or copy in the product.** Lists and notes come
     from data and from people. A human editor may write. A model may
     not.
   - **Side doors stay out of the way.** Finding and playing a film is
     the app. Feeds for other apps are documented on the website, never
     a button in the app.

   Tidbits Trivia earned another: a computer opponent that fills in
   while nobody else is online must be labeled as a computer opponent.
   A labeled bot is an honest way to get a game started. A bot dressed
   as a person manufactures a relationship that does not exist.

   A rule in your own words, with a date, is also your name on the
   decision. Anyone who reads it later, including the agent, knows who
   drew the line and why.

Values climb, too. A value starts as a reason in the paragraph. The day
the agent crosses it, it becomes a standing instruction. Once you know
exactly what it means, it can become a check: a test that fails when the
line is crossed, so the agent cannot cross it without being told. In
Archive Watch I found "programme" on a label and assumed there was
already a rule about spelling. There was not. Now there is a rule, and
`tools/test_us_english.py` checks every string a person can see, because
a rule nobody checks drifts again. Stage 08 comes back to this ladder.

## What it costs

These rules are slower. Pulling Archive Watch's notes from archive.org's
own metadata, and from the words of the people who uploaded and reviewed
each film, meant building a pipeline and keeping it running. A model
could have written ten thousand blurbs in an afternoon, and a lot of
folks would never have known the difference.

I could be wrong about where the line sits for your app. Maybe a model
summarizing a long document is exactly what your people need, and it
leaves them more capable instead of less. But, I want you to draw the
line on purpose, in writing, before the agent draws it for you by
default.

## Working with your agent

<!-- Steps 1 to 12 and step 18: written by Claude, awaiting Ben's
review (note 06, section 3). Steps 13 to 17 are Ben's original steps 1
to 6 from commit d70c674, kept as he wrote them. -->

This stage takes about a week, because noticing takes days and talking
to people takes time. Steps 1 to 12 are yours, with the agent closed:
they are writing and listening, and the problem has to be yours before
anyone helps you shape it. From step 13 on, open your agent (Claude
Code, or Antigravity for Gemini) in your copy of the template. Those
steps are conversations, and `talking-to-your-agent.md` has the moves.
Keep everything in one plain note, in whatever notes app you already
use. You will keep it for the life of the app, and it is where your
prompts will be drafted from now on.

1. **Write your first answer.** At the top of your note, answer this
   stage's question in two or three sentences: what problem in your own
   life is worth building something for, and who else has it? Being wrong
   is fine. You will come back to it at the end.

2. **Write your questions.** Read the line from my pitch that this course
   starts from: "If anyone can build their own apps (with AI), it matters
   even more which apps they choose to build and how they choose to build
   them." For five minutes, write as many questions about it as you can.
   Do not stop to discuss, judge, or answer them, write each one exactly
   as it came, and change any statement into a question (the Question
   Formulation Technique's four rules,
   [Right Question Institute](https://rightquestion.org/what-is-the-qft/)).
   Then mark the three you most want answered by the end of the course.
   In a cohort, these become the group's list of what we need to know.

3. **Write: keep the log for five days.** Use the four prompts from
   [Notice before you choose](#notice-before-you-choose), one line each
   time something happens. In a cohort, the log starts in the week
   before week 1. On your own, give it five days anyway.

4. **Write: five candidates.** From the log, write five problems in your
   own words, one or two sentences each. Do not name an app or a
   technology yet.

5. **Play: hold them to the ten tests.** Put your five candidates beside
   [the ten tests](#ten-things-to-hold-a-problem-to) and mark each one
   "yes," "not yet," or "I don't know." Choose the two that hold up best.

6. **Publish: say the two out loud.** Read your two candidates to your
   trio, or to one person you trust, and say in a sentence why each might
   matter. Write down what they asked you.

7. **Play: study my examples as models.** Work through
   [What a strong problem statement looks like](../human-shaped/problem-statements.md):
   list what makes my four human-shaped statements strong enough to
   build from, and what my four computer-shaped ones have in common.

8. **Write: your problem statement.** Rewrite the stronger of your two
   candidates in the same form as my examples: your situation, in the
   first person, then "I need something that..." Under it, write one
   sentence for the computer-shaped version of the same wish, the one
   that measures, ranks, or optimizes. That is the app you are choosing
   not to build.

9. **Publish: trade it for critique, then revise.** Read your statement
   to your trio, or to one person you trust. Ask them to "be kind; be
   specific; be helpful," with suggestions as questions: "Have you
   considered...?" ([Berger, 2006](https://jaymctighe.com/wp-content/uploads/2011/04/Ron-Berger-Article.pdf)).
   Revise once, and keep both versions in your note.

10. **Write: a short conversation guide.** Three questions that begin
    "Tell me about the last time you..." and one that asks why. Nothing
    about an app.

11. **Play: two conversations.** Talk to two people who might have the
    same problem, in person or on a call, for ten or fifteen minutes
    each. Listen more than you talk, and write down their stories in your
    own words afterward. Keep the notes private unless they agree you can
    share them.

12. **Write: revise, and say why it is human-shaped.** Change your
    problem statement with what you heard. Then, under it, write who has
    this problem and why a computer cannot simply solve it for them. That
    sentence is what principle 1 asks for.

13. **Start your note with the why.** Move your problem statement to the
    top of your note. Under it, write who the app is for, and what you
    hope it does for them.

14. **Tell the agent why.** Say what you wrote, the way you would to a
    friend. Then ask the agent to rewrite the "Why we build" paragraph in
    `AGENTS.md` from what you said, and to read it back to you. Correct
    it until it sounds like you and not like a company. Five sentences
    or fewer.

15. **Name one line you will not cross.** Something the app will never
    do, or never let AI do inside it, even if doing it would work. Say it
    plainly and say why. Mine usually came out the moment the agent
    proposed crossing one. In September, the agent designed Archive
    Watch's Watch Together feature around a paid voice server, and I
    stopped it:

    > It is absolutely not acceptable. The goal of this app (and all of
    > my apps) is for them to cost $0 to run.

    You do not have to wait for the agent to cross yours. Say it now,
    and ask the agent to add it to the standing instructions in
    `AGENTS.md` with today's date and your words in quotes. You will add
    more of these as you build.

16. **Ask three questions of the idea.** Work through these with the
    agent, and write your answers in your note.

    1. **Should it exist at all?** If something already does this, what
       does yours give people that it does not? This one comes back
       before every big feature. Nine days into BOBA Playbook, the agent
       built a price feature that leaned on another site's prices, and I
       asked it out loud:

       > This is NOT what I want. I want my app to be indpendent from
       > Radish. You can look at the stucture from Radish, but if we are
       > just using Radish, there is no reason for this feature to exist.
       > People should just go to radish, right?

    2. **Who does it touch?** Name the people who will use it. Then name
       the people outside the screen: the ones whose work it shows, whose
       data it uses, or whose lives it changes without their ever opening
       it. For Archive Watch, those are the people who uploaded and
       reviewed each film on archive.org, and the people on screen in the
       films. For Tidbits Trivia, they are the volunteers who wrote every
       fact on Wikipedia and Wikidata.
    3. **What will people learn from using it every day, and what will
       they stop learning?**

    Then ask the agent to argue the strongest case against your idea, on
    behalf of the people outside the screen. It is a second voice where
    there was only yours. It does not replace the two people you talked
    to, and stage 07 comes back to that.

17. **Test it against the four questions, and let it ask you the rest.**
    Ask the agent to run the `learning-orientation-design` skill against
    your idea and tell you where it fails. Where it does, change the idea
    now, while it is only words. Then ask the agent what it still needs
    to know before it starts. This is how I opened each early milestone
    of BOBA Playbook, starting the first evening:

    > Great. Let's begin on M2. Do you have any question at the beginning
    > of this milestone that are unanswered by the current documentation?

    Answer in your note first, numbered to match its questions, saying
    only what each decision needs. It is a habit that lasts. Here is
    Archive Watch, months later, answering five of the agent's questions
    in one message:

    > 1. Yes. Move forward with a single clock. If you need a time zone
    > to organize around, you can choose UTC, but all times should show
    > as their local times when they look at channels. [...]
    > 3. The wording is fine for now.
    > 4. You can use the Apple TVs whenever you want right now.

    The agent records your answers as decisions, with the why first.

18. **Publish: post the problem.** Write a short post, in your own words:
    your problem statement, who has it, and why a computer cannot simply
    solve it for them. Post it where your cohort shares work, or in the
    community discussions if you are on your own
    ([Showing your work](showing-your-work.md) says where), and offer it
    to the two people you talked to, if they would like to see it. Then
    reread your first answer from step 1, and write one line on what
    changed.

Where the agents differ, one line each
([curriculum research, 03 and 04](../research/curriculum/03-claude-code-and-antigravity.md)):

- **Claude Code:** in the desktop app's Code tab, start in **Manual**, so
  you see each change to `AGENTS.md` before it is made.
- **Antigravity:** start in the **Default** preset, and ask for a plan
  you can comment on before it edits `AGENTS.md`.
- **The open path:** a small model holds only the start of a long file,
  so keep your why and your one rule near the top of `AGENTS-SHORT.md`
  as well as in `AGENTS.md`
  ([the open pathway](../research/curriculum/04-open-pathway.md)).

**When you are ready to move on,** your note starts with a problem
statement in your own words, revised after critique and after two real
conversations, with who has it and why a computer cannot simply solve it
for them. The "Why we build" paragraph in `AGENTS.md` sounds like you,
there is one rule in your own words, your answers to the three questions
are written down, and the problem is posted where other people can read
it. Ready, or not yet: you judge first. You have written. Stage 01 is
the first chance to play with something you can hold, and to publish it
to one of the people you talked to.

Every stage ends the way this one does, with something to show and a
decision to explain in your own words, with the agent closed. [Showing
your work](showing-your-work.md) says how, in a cohort or on your own.

**Go deeper.** Spend an hour with one of the people you talked to while
they do the thing your problem is about, in their own setting, and ask
them to show you rather than tell you. Researchers call this contextual
inquiry ([note 06](../research/curriculum/06-instructional-design.md)).
Or keep the log for a second week, and see what changes. Neither is
required, and neither is counted.

**If you get stuck.**

- *You cannot find a problem worth building for.* Ask yourself: which
  line in my log would I most like to never write again? Then try
  [I cannot find a problem worth building for](../stuck/writing/find-a-problem.md).
- *You cannot say what your app will never do.* Ask yourself: what would
  the cheapest version of this app do to the people I talked to? Then try
  [I cannot say what it refuses to do](../stuck/writing/what-it-refuses.md).
- *You are not ready to talk to anyone.* Ask yourself: what is the
  smallest thing I could ask one person about a time it happened to
  them? Then try [I am not ready to show anyone](../stuck/publishing/not-ready.md).

**Before you close your note.** Four short lines, from my
[Educational Model Spec's AI Disclosure Protocol](https://github.com/bhwilkoff/educational-model-spec/blob/main/docs/implementation-tools/ai_disclosure_protocol.md):
the agent's role, your essential work, one thing you learned, and your
growth edge.

Be ready to share your problem statement and the version before it, what
you heard in your two conversations, your "why we build" paragraph, and
your one rule, and to explain why you drew that line where you did and
what it will cost you.
