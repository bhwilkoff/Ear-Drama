# Values-based approaches, and where this template stands

*Research done 2026-10-01. The detailed notes, with a source beside
every claim, are in `notes/value-based-engineering-notes.md` and
`notes/values-based-approaches-notes.md`. This page is the synthesis:
what other people have built for designing technology around values,
what this template can learn from them, where it deliberately differs,
and what it can build on top.*

## Why this page exists

Recently I came across Value Based Engineering, a method for
building technology around ethical values that has become an
international standard (IEEE 7000, adopted by ISO as ISO/IEC/IEEE
24748-7000). It felt close to how I build. It is also far more
interested in compliance than I am. So, I asked for a full look at it,
and at the other values-based traditions around it, to see where we
can learn and where we can go further.

The short version: these traditions agree with this template about
nearly everything that matters, and they have worked out several things
this template only does by instinct. None of them was designed for one
person building with an AI agent. That is the part we get to add.

## Value Based Engineering in one page

**What it is.** Value Based Engineering (VBE) is Sarah Spiekermann's
practical method for applying IEEE 7000-2021, the "Model Process for
Addressing Ethical Concerns during System Design". Spiekermann, at the
Vienna University of Economics and Business, was the standard's vice
chair. It was published in 2021 and adopted by ISO in 2022. The
standard itself is free to download through IEEE's GET program.

**The process,** in three phases with one activity running alongside
all of them:

1. **Concept and context.** Describe what the system is for and where
   it will be used. List the direct and indirect stakeholders. Work out
   how much control you actually have over the partner systems your
   system depends on. Check legal, social and environmental
   feasibility. If you cannot control what you would need to control,
   rescope or stop.
2. **Value exploration.** Stakeholders answer three questions, one from
   each major ethical tradition, plus one from the local culture:
   - **Consequences:** what positive and negative consequences can you
     imagine from this system's use, for direct and indirect
     stakeholders?
   - **Character:** what could widespread use of this system do to
     people's character, and which virtues or vices could it grow?
   - **Duty:** which of these values would you hold so firmly that you
     would want them protected as a universal law?

   The answers (hundreds of them in the published cases) are clustered
   into a handful of core values, ranked against seven criteria by
   leaders and stakeholders together, and published as a signed ethical
   mission statement. "Not building it" is an explicit, expected
   outcome.
3. **Ethically aligned design.** Each core value becomes Ethical Value
   Requirements (EVRs) with testable thresholds. Many EVRs turn out to
   be organizational, not technical (hire enough staff to answer the
   help line). Then one of three paths: organizational measures only,
   light agile design for low-risk values, or a full impact assessment
   for high-risk ones (health, security).

Running alongside: **transparency management.** A Value Register keeps
the whole chain, from core value to value quality to requirement to
threat to control, with executives and engineers signing their names
to the priorities and the risk decisions. The idea is that "when no one
wants to put down his or her name for a system design choice", that is
a signal to rethink it.

**The philosophy underneath** is Max Scheler's material value ethics.
Values are real, felt, and ranked, with higher values chosen over lower
ones rather than traded off ("efficiency is a lower value than
respect"). Systems do not "have" values. They carry them, through
specific design choices.

**The compliance side.** Only people are certified: a "VbE Ambassador"
certificate from Austrian Standards (a one-hour, open-book,
multiple-choice exam; €490, or about €2,949 with the course). A system or organization can only declare
its own conformance, and the standard says plainly that it "cannot
guarantee that the system … is ethical." VBE is marketed alongside the
EU AI Act, though the standard is not one of the Act's formally
recognized standards.

**What its own authors say is hard.** It is heavy: clustering one
case's values "took several days of analysis". It works best early,
with executives who are willing to act. In one real case, VBE arrived a
year into the project, and the CEO "did not want to hear" the findings. It offers no method for choosing which
stakeholders to involve. The evidence base is thin and mostly from
student studies. And the standard is "less usable for building a
generic product … for which the deployment context is indefinite",
which describes most consumer apps.

## What we already share

Reading VBE next to this template is a little uncanny.

| VBE | This template |
|---|---|
| Values are elicited before design and carried into it | `CLAUDE.md` "Why we build", written in stage 00 before any feature |
| Core values become testable requirements | Standing instructions become tests (`tools/test_us_english.py` holds "one spelling locale"; Pulse's tests hold "never draw a zero") |
| Many requirements are organizational, not technical | Store words rewritten by a person, replies to reviews, "what stays human" |
| "Not building it" is a valid outcome | The Radish check in BOBA: "there is no reason for this feature to exist" |
| Higher values over lower ones, not trade-offs | $0 to run is not weighed against a nicer feature. It wins. |
| Transparency: a record of who decided what, and why | `DECISIONS.md` leads with why; commit messages quote the request |
| Monitoring after launch; values that do not show up trigger a new look | Pulse, real-device checks, feedback rounds |
| One person may hold every role in a very small entity | One person, with an agent, is the whole team |

## Where we differ, on purpose

**Practice, not compliance.** VBE's documentation exists partly so an
auditor or regulator can see it. This template's documentation exists
so the next session of the agent reads it. Both are records of intent,
but the reader is different, and so is the cost of writing them. I do
not want a template that teaches people to produce evidence of ethics.
I want one that teaches them to build ethically, and to notice when
they did not.

**One builder, not an organization.** VBE assumes a Top Management
Champion, a Value Lead, a Risk Lead, a User Advocate and a Moderator,
and its safeguards against bias assume they are different people. This
template assumes one person and an agent. That is a real weakness: one
person's blind spots go unchallenged. Part of the answer is below (let
the agent argue the other side), and part of it is the people this
template already brings in: testers, a Reddit thread, a class.

**Living with the app, not workshops.** VBE learns values from
stakeholder workshops before design. I learned most of mine by using
the app every day and noticing when it crossed a line I had not known
was there. "Only essential words on screen" came from a caption that
said too much. Both are valid. VBE's way surfaces more values up front.
Mine surfaces the ones you only find by living with the thing. The
template should teach both.

**Generic products, not known contexts.** VBE is built for a system
with a known deployment context. Most apps built from this template are
generic products on several platforms, used by people the builder will
never meet. That makes indirect stakeholders harder to name, and more
important.

**AI is the builder, not just the product.** VBE's guidance on AI is
about AI components inside the system, and it presumes you control the
model's data and design, which almost nobody building on a third-party
model does. Nothing in the VBE literature addresses software written by
an AI agent. The nearest research (Treude, Baltes and Cheong, 2026)
studies developers writing values into the instruction files that
coding agents read, which is exactly what this template's `CLAUDE.md`
does.

## What we can learn from VBE

1. **The three questions.** Consequences, character, duty. They are
   better than an open "does this fit our values?" because each one
   surfaces different things: in VBE's studies, the consequences
   question produced the most ideas, the character question the most
   original ones, and the duty question the most critical. They fit
   beside the four questions in `learning-orientation-design`, as the
   questions to ask before a feature is designed.
2. **Indirect stakeholders, by name.** VBE always asks about people who
   never touch the system but are affected by it. This template rarely
   does. A trivia game's indirect stakeholders include the Wikipedia
   editors whose work it quotes. A film app's include the uploaders and
   the families of the people on screen.
3. **The chain from value to test.** Core value, then what it looks like
   in this app, then a requirement with a threshold, then a check. This
   template already does this for some values (US English has a test;
   Pulse's honesty has a test). It should do it on purpose, for every
   standing instruction that can be checked.
4. **Organizational requirements count.** Some values are kept by
   people, not code. Replying to every review, or reading every tester's
   message within a day, is a value requirement too, and can be a row
   in the note's ledger.
5. **A name on the decision.** The signature in VBE's Value Register is
   a performative act: you put your name to a value choice. A dated
   standing instruction in your own words, quoted, is the same act. The
   template could say so explicitly.
6. **"Should this exist?" is the first question.** VBE treats declining
   to build as a normal, expected outcome. The template should ask it
   out loud at stage 00 and again before every big feature.

## What the wider field adds

The second set of notes covers ten other traditions. The most useful
ideas, ranked:

1. **Values, norms, enforcement.** Value Sensitive Design describes a
   ladder from a value, to a norm, to a design requirement. Anthropic's
   constitution for Claude orders its values and explains the reasons,
   so that the model could derive the rules itself. And Claude Code's
   own documentation says `CLAUDE.md` is "context, not enforced
   configuration": anything that must never be broken belongs in a
   hook or a test. Together, these give the course a clean lesson. A
   value starts as a reason in `CLAUDE.md`, becomes a specific rule as
   you learn what it means, and becomes an automatic check once you are
   sure.
2. **Wide walls.** Papert gave us the low floor and the high ceiling;
   Mitchel Resnick added wide walls: room for "all different learning
   styles and ways of knowing". It is a sharp test for any AI feature.
   Does it lead everyone to the same output, or open many paths?
3. **Calm in the chrome, effortful in the core.** Calm technology (Mark
   Weiser, Amber Case) asks software to stay in the background. Yvonne
   Rogers argued that some technology should engage people instead.
   For a learning app, both are right in different places: the
   interface should be quiet, and the learning should be what Papert
   called "hard fun".
4. **Who participated, who benefited, who was harmed.** Design Justice
   (Sasha Costanza-Chock and the Design Justice Network) asks those
   three questions of every design. They are short enough to sit in
   every decision entry.
5. **Participation is cheap now.** Scandinavian participatory design
   used cardboard prototypes because real ones were expensive. With an
   agent, a working throwaway version costs an afternoon, so the people
   an app is for can use and reshape real software. The warning from
   that tradition still holds: participation that only extracts
   people's ideas, and gives nothing back, is not participation.
6. **Honest automation.** Microsoft's human-AI interaction guidelines
   include "make clear how well the system can do what it can do" and
   "scope services when in doubt". That is very nearly this template's
   rule that a reader that cannot read says so, and its labeled-bot
   rule, written for any automated feature.
7. **The data outlives the developer.** Local-first software (Ink &
   Switch) lists seven ideals, including that people's work "should
   continue to be accessible indefinitely, even after the company that
   produced the software is gone." This template's sync islands already keep data in people's own
   cloud. It could add a plain promise: a readable export, and a stated
   plan for people's data if the builder stops maintaining the app.

And the critiques worth teaching alongside them:

- Writing values into a file can feel like doing ethics without being
  it (Wong et al., "Seeing Like a Toolkit", 2023). The test of a value
  is whether it changed a decision.
- Interface fixes alone do not make technology humane (critics of the
  humane technology movement). Structural choices do: $0 to run, no
  tracking, people's data in their own cloud.
- Claims to universal values deserve suspicion (Borning and Muller,
  2012). Whose values, chosen by whom?
- Beginners need guidance, not just open exploration (Kirschner, Sweller
  and Clark, 2006). That bears on how much a learning app, or a course,
  should leave to discovery.

## What we can build on top

None of these traditions was made for a single person building across
many platforms with an AI agent. This template's contribution can be
exactly that.

- **Values written where the builder reads them.** VBE writes values for
  auditors and stakeholders. This template writes them for the agent,
  at the moment it makes a choice, and tests the ones that can be
  tested. The ladder from reason to rule to check is a method nobody
  has written down for agent-built software.
- **The agent as the missing roles.** One person cannot be a Value
  Lead, a Risk Lead and a User Advocate at once without blind spots.
  But the agent can be asked to argue the indirect stakeholder's case,
  to run the three questions, and to name the strongest objection to a
  feature before it is built. It is not a substitute for real people.
  It is a second voice where there was only one.
- **Values verified on real devices.** VBE checks values in documents.
  This template can check them on the glass: a caption that says too
  much, a button that does nothing on an old device, a zero that should
  have been a blank. Stage 04's instruments are value instruments too.
- **A course, not a certificate.** VBE's education is a certification
  exam. This template's is a path where each person builds one real
  app, for people they can name, and brings back what their values cost
  them.

## How it became human-shaped

On October 1, 2026, Ben named the method *human-shaped software* and
asked for the useful parts of this research to come into the template,
with one condition:

> Pulling in their exact language doesn't really work because it isn't
> authentic to the AI context and our learning orientation.

So, each idea below was rewritten in the template's own words, tied to
something that happened in a real app, and placed under one of the
three moves: write, play, publish (named on October 5, 2026, replacing
"write it down, prove it, live with it"). Learning (as a
student, as a builder, as a human) is the frame for all of it. The
credit lives here, so the stage pages can speak plainly.

| In the template | Where it lives | Where it came from |
|---|---|---|
| Human-shaped software, learning three ways, the three moves | `README.md`, stage 00, `COURSE.md`, `CLAUDE.md` | Ben's March 2026 page on "computer-shaped problems"; Nilay Patel's "software brain"; constructionism (Papert, Resnick) |
| Three questions of the idea: should it exist, who does it touch, what will people learn or stop learning | Stage 00 step 4, `learning-orientation-design` | VBE's three ethical lenses (consequences, character, duty), rewritten around learning. Duty became stage 00's "one line you will not cross". "Not building" from VBE; the wording from BOBA's Radish moment |
| The people outside the screen | Stage 00, `learning-orientation-design`, the talking guide | VBE and Value Sensitive Design's indirect stakeholders |
| Ask the agent to argue the other side | Stage 00, the talking guide, `learning-orientation-design` | VBE's User Advocate role, for a builder who holds every role alone |
| A dated rule in your words is your name on it | Stage 00 | VBE's signed Value Register |
| Reason, rule, check | Stage 00, stage 08, `CLAUDE.md` standing instructions | Value Sensitive Design's values hierarchy; VBE's value-to-requirement chain; Anthropic's constitution (reasons before rules); Claude Code's docs (`CLAUDE.md` is context, hooks enforce) |
| Who was in the room, who gains, who pays | `DECISIONS.md`, `architectural-decision-log` | Design Justice's "Who participated? Who benefitted? Who was harmed?" |
| The same honesty, inside the app | Stage 04, `learning-orientation-design` checklist | Microsoft's Guidelines for Human-AI Interaction (G1, G2, G10, G11) |
| Many ways in | `learning-orientation-design` | Resnick's "wide walls" |
| Quiet where it doesn't matter, effortful where the learning is | `learning-orientation-design` | Calm technology (Weiser and Brown, Case) against Rogers' engaging ubicomp; Papert's "hard fun" |
| Build it with the people it is for, and give something back | Stage 07 | Scandinavian participatory design; its critique of extractive participation |
| Their data outlives your interest | Stage 07, `per-ecosystem-sync-islands` | Ink & Switch's local-first ideals ("The Long Now") |
| A value is worth what it changed | Stage 08, `COURSE.md` | Wong, Madaio and Merrill, "Seeing Like a Toolkit" (2023) |
| How much to leave to discovery | `COURSE.md`, "What I am unsure about" | Kirschner, Sweller and Clark (2006) |

Left out on purpose: certification, the Value Register as a document,
Scheler's ranking and the seven criteria, the eight roles, stakeholder
workshops, the EU AI Act framing, VBE's three risk paths, the card decks,
and responsible research and innovation. They answer problems an
organization has, not problems a learner building with an agent has.

## Sources

The two notes files cite every claim. The primary sources most worth
reading are:

- IEEE 7000-2021, free through the IEEE GET program.
- Spiekermann and Winkler, "Value-based Engineering for Ethics by
  Design" (arXiv 2004.13676) and "Value-based Engineering with IEEE
  7000" (arXiv 2207.07599).
- vbe.academy and the WU Vienna Value-based Engineering pages.
- Friedman and Hendry, *Value Sensitive Design* (second edition, 2026),
  and vsdesign.org.
- Costanza-Chock, *Design Justice* (MIT Press, 2020, open access).
- Resnick on low floors, high ceilings and wide walls; Papert and Harel,
  "Situating Constructionism".
- Ink & Switch, "Local-first software".
- Microsoft, "Guidelines for Human-AI Interaction".
- Anthropic's constitution for Claude.
- Treude, Baltes and Cheong, "Operationalizing Ethics for AI Agents"
  (arXiv 2605.05584).
