# The Human-Shaped Principles

*Version 0.6, October 5, 2026. Written by Ben Wilkoff, and open to
argument.*

I want anyone to be able to say "my software is human-shaped" and have
it mean something about how that software was made, not just about what
its builder hoped it would be. So, these principles are guidelines for
making and shipping. Each one is something you can actually do, and
something another person can check, whether this is your first app or
your fiftieth, and whether or not you have ever worked with an AI agent.

## The principles

Each principle starts with what human-shaped software does, so that any
piece of software, and the way it was made, can be measured against it.

Human-shaped software:

1. **Starts from a human-shaped problem,** one that affects real people
   in the real world.
2. **Increases what people are able to do,** rather than how much profit
   can be made from them.
3. **Has its values written down as guardrails** for both the people and
   the AI agents who build it.
4. **Treats iteration as the path to innovation,** so that no first
   draft of a feature, design, or piece of writing is ever shipped.
5. **Is grounded in research,** so that its builder always knows whose
   work they are building on, from tools and services to authors and
   design patterns.
6. **Makes every decision with feedback** from another person, an AI
   agent, or a piece of documentation.
7. **Is tested the way people will actually see, hear, and use it,** not
   only the way a machine would check it.
8. **Treats documentation as seriously as code,** so that it grows and
   changes with the software, in the builder's own language.
9. **Shares its code, tools, and lessons** as openly as the problem it
   solves allows.
10. **Counts learning as success,** so that if at least one thing was
    learned in building it, the software has succeeded.
11. **Lets people own their data** and make every decision about what
    happens to it.
12. **Creates no new human-shaped problems** while solving the one it
    set out to solve.
13. **Is written in the builder's own voice,** so that every word is
    shaped by a human, and no machine pretends to be one.
14. **Credits everyone and everything responsible for it,** including
    people, communities, AI agents, tools, and processes.
15. **Brings joy to at least one person** in the form it ships today,
    even if that person is the builder.

## What each principle means

Each principle below finishes the sentence "Human-shaped software...".
The principles are meant to stand on their own. What follows is for
when you want to know why each one matters, what it looks like while
you are building, and how someone else could tell whether your software
lives up to it. Not every principle will be met on the first day, and
"not yet, and here is what I am doing about it" is an honest answer.
Silence is not.

## 1. A human-shaped problem

**Starts from a human-shaped problem, one that affects real people in
the real world.**

Some problems are computer-shaped. You can hand them to a machine and
be done with them, and there is nothing wrong with that. But, learning,
community, relationships, and most of the things that make a life worth
living are not like that, because they only happen when a person does
the work. Human-shaped software is built for those problems. A
human-shaped problem is the gentle hum of worry or concern you have
about an area of your life: it has gone unsolved for months or even
years, and you cannot do it yourself with the tools and resources you
have now
([examples of each shape](computer-shaped-problems.md#computer-shaped-and-human-shaped)).
I have
found that it helps to name the actual people who have the problem,
because software built for "users" tends to drift toward whatever is
easiest to build, while software built for the people you know has to
work for them.

**How you can tell:** the builder has written down what the problem is,
who has it, and why a computer cannot simply solve it for them.

## 2. More possible, not more profit

**Increases what people are able to do, rather than how much profit can
be made from them.**

Software can make money and still be human-shaped. What it cannot do is
make its money by taking something away from the people it serves:
their attention, their data, or the part of the work that was supposed
to be theirs. The question I keep asking is whether the person using the
software can do more after using it than they could before. When a
feature fails that test, the answer is usually to keep the core free and
simple, and to say plainly what anything extra costs.

**How you can tell:** the heart of the software works without payment,
any price is stated plainly, and nothing in it is designed to keep
people longer than they want to stay.

## 3. Values as guardrails

**Has its values written down as guardrails for both the people and
the AI agents who build it.**

An AI agent keeps only the values you write down. Left alone, it will
do whatever satisfies a request most cheaply, and it is not wrong to
(nobody told it otherwise). So, the values belong in writing, in the
place the agent reads before it does anything, along with the rules the
project has earned along the way, each one dated and in the builder's
own words. The strongest of those rules can become automatic checks,
so that the agent cannot cross a line without being stopped.

**How you can tell:** the values are written in the project itself,
where both people and agents read them, and at least one of them has
visibly changed a decision.

## 4. Iteration, never a first draft

**Treats iteration as the path to innovation, so that no first draft of
a feature, design, or piece of writing is ever shipped.**

An AI agent will happily hand you a first draft that looks finished.
That is exactly the moment to slow down. I have learned to use the
draft, write down everything that is wrong with it, and send that back
as the next round, over and over, until it is right. Some features take
two rounds and some take seven. None of them were right the first time,
and the ones I rushed are the ones I have had to rebuild.

**How you can tell:** the history of the project shows rounds of
feedback and revision before each feature, design, or piece of writing
went out.

## 5. Grounded in research

**Is grounded in research, so that its builder always knows whose work
they are building on, from tools and services to authors and design
patterns.**

Before anything new gets built, I ask for research: what already
exists, where the information will come from, what others have learned
trying the same thing, and what it will cost. Knowing your sources is
how you know what you are allowed to use, what will break when someone
else changes their service, and whom you owe a thank-you. It is also
how you avoid spending a week reinventing something that a stranger
solved years ago and wrote down.

**How you can tell:** the research behind the major choices is
recorded, and the tools, data sources, and borrowed ideas are named.

## 6. Decisions with feedback

**Makes every decision with feedback from another person, an AI agent,
or a piece of documentation.**

Building alone does not have to mean deciding alone. An AI agent can
ask you the questions you had not thought to ask, and it can argue the
other side when you are too close to an idea. The project's own
documentation can remind you of what was already decided, so that you
do not decide it twice. And other people (testers, friends, the folks
the software is for) will always see what you cannot. A decision made
with feedback can still be wrong, but it is never made blind.

**How you can tell:** the major decisions are written down with their
reasons, and the record shows where the feedback came from.

## 7. Tested the way people use it

**Is tested the way people will actually see, hear, and use it, not
only the way a machine would check it.**

An AI agent will tell you something is fixed and fully tested when what
it means is that the code changed. That is not the same thing as the
software working for a person. So, testing happens on real devices, and
the evidence is what a person would actually see, hear, or experience,
not a log line or the agent's own report. It also means testing for
people who are not like you: someone on an older phone, someone using a
screen reader, someone on a slow connection, and someone brand new to
the subject.

**How you can tell:** every claim that something works points to
evidence from a real device or a real person, and the software says
plainly where it does not work yet.

## 8. Documentation as seriously as code

**Treats documentation as seriously as code, so that it grows and
changes with the software, in the builder's own language.**

For an AI agent, the documentation is the only memory there is. Every
session starts fresh, and an agent that has not read what was already
learned will happily learn it again, at your expense. Documentation is
also how the next person, or you six months from now, understands why
the software is the way it is. So, it grows alongside the code, it is
fixed first when it disagrees with the code, and it sounds like the
builder, because the builder is the one who has to stand behind it.

**How you can tell:** the project has current documentation of its
decisions, its state, and its design, and the builder's own words are
in it.

## 9. Shared openly

**Shares its code, tools, and lessons as openly as the problem it solves
allows.**

Most of what I know about building software, I learned from people who
shared what they knew, and the least I can do is the same. Some problems
call for privacy (software about health, children, or someone's safety
may not be able to share everything), which is why this principle asks
for as much openness as the problem allows and not more. Where the code
cannot be shared, the lessons almost always can.

**How you can tell:** the code, or at least the lessons, are public
under terms that let others use them, and anything kept private has a
stated reason.

## 10. Learning as success

**Counts learning as success, so that if at least one thing was learned
in building it, the software has succeeded.**

Building software this way is a form of learning in three directions at
once: as a student of the method, as a builder discovering what your
software actually is, and as a human deciding what to hand to a machine
and what to keep for yourself. Software that never finds a big audience
can still be a success by this measure. And software with a million
downloads that taught its builder nothing has missed something
important.

**How you can tell:** the builder can say what they learned, and the
lesson is written down where the next builder can find it.

## 11. People own their data

**Lets people own their data and make every decision about what happens
to it.**

What people make and save in a piece of software belongs to them, not to
the person who built it. I would rather keep people's data on their own
devices, or in an account they already control, than on a server of
mine that could disappear the day I stop paying for it. People should
be able to see what the software keeps, take it with them, and delete
it whenever they choose.

**How you can tell:** the software collects only what it needs, says
what it keeps, and offers a way to export and delete it.

## 12. No new problems

**Creates no new human-shaped problems while solving the one it set out
to solve.**

Solving one problem can quietly create another: a feature that leaves
people lonelier, a notification that steals attention, a test that
leaves music playing on every speaker in someone's house. Before
building anything big, it helps to ask an AI agent to make the strongest
case against it on behalf of everyone it touches, including the people
who will never open the software at all. Some of that case will be
wrong. The rest is the part you would not have seen alone.

**How you can tell:** the builder has asked, in writing, whom the
software could harm, and has answered.

## 13. The builder's own voice

**Is written in the builder's own voice, so that every word is shaped
by a human, and no machine pretends to be one.**

An AI agent can write copy, labels, and lists faster than any person
can. But, the words people read are where software speaks to them, and
they should come from a person: the builder, or the people whose
knowledge the software shares. The same honesty applies to anything
automated. A computer opponent, a suggestion, or an automatic reply
should say plainly what it is, because a machine dressed up as a person
creates a relationship that does not exist.

**How you can tell:** the words people read were written or chosen by a
person, and every automated part of the software says what it is.

## 14. Credit everything

**Credits everyone and everything responsible for it, including people,
communities, AI agents, tools, and processes.**

No software is made by one person anymore, if it ever was. It is made
with AI agents, on top of open tools, out of other people's knowledge,
and with help from the communities that tested it and argued with it.
Credit is honesty about how the thing was actually made. It is also a
thank-you, and it tells the next builder where to look.

**How you can tell:** the software and its project credit the people,
communities, sources, agents, and tools behind it.

## 15. Joy for at least one person

**Brings joy to at least one person in the form it ships today, even if
that person is the builder.**

Software does not have to be finished to be good, and it does not have
to be popular to matter. But, someone should be glad it exists, in the
form it is in right now. Very often that someone is the builder, and
very often that joy is where the next round of work comes from, because
the things you love using are the things you notice how to make better.

**How you can tell:** the builder can name someone who enjoys the
software as it is today, even if that someone is the builder.

## Declaring software human-shaped

There are two marks, and nobody stands at the door. Each one says
something true about how a piece of software was made, and you can use
either one as soon as it is true of yours.

- **Aligned with Human Shaped.** You have written down how your software
  lines up with each of the fifteen principles. Copy
  `HUMAN-SHAPED-template.md` from this folder into the root of your
  project as `HUMAN-SHAPED.md`, and answer each principle with *meets*,
  *not yet*, or *does not apply*, a sentence or two in your own words,
  and a link to the evidence.
- **Endorsed by Human Shaped.** Your software started from the Universal
  App Template, or you have written your commitment to the principles
  into your project. Either one is enough, and the mark is yours from
  that moment.

Both marks, and how to show them in your README or on your app's
website, are at https://humanshaped.org/start/brand/#declare. A mark links to
your own `HUMAN-SHAPED.md`, so anyone who sees it can read your answers
and check the evidence for themselves. The directory at humanshaped.org
reads that file, and any software with either mark can ask to be listed.

When something changes, change your answer and record what changed and
when, rather than deleting the old answer. A declaration that shows its
own corrections is more trustworthy than one that never needed any.

## Where these came from

These principles came out of building real software with AI agents, and
the lessons from that work live in the Universal App Template. They also
draw on the
[Educational Model Spec](https://github.com/bhwilkoff/educational-model-spec),
Value Based Engineering and IEEE 7000 (values turned into requirements
and checked), Value Sensitive Design (the people software touches who
never use it), Design Justice (who benefits and who pays),
constructionism (learning by making), local-first software (data that
outlives the app), and Microsoft's guidelines for human-AI interaction
(automation that says what it is). The fuller story of each borrowing is
in `docs/research/values-based-approaches.md`.
