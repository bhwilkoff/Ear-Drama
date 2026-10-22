# How this template is written

Every human-facing page in this repository is written the way Ben
Wilkoff writes. The full guide is `BEN.md` in the LearningIsChange
repository. This page is the part of it that applies to documentation,
plus the rules that keep a repository full of AI-assisted writing from
sounding like one.

The skills in `.claude/skills/` are written for an agent. They can stay
terse. Everything a person reads first (the READMEs, `docs/path/`, the
catalogs, `COURSE.md`) follows this page completely.

Reference docs (the templates, runbooks, playbooks and store guides) are
read at the moment of need, often as dense rule lists. They follow the
same word list and carry no em dashes, but a semicolon inside a rule
list is tolerated there.

## The register: a teacher

A README tells you what the thing does, then why it is built that way,
then what you can do next. In that order.

The model is the lesson post Ben wrote to his eighth graders in 2006:
imperative verbs, chunked by who is doing the work, numbered, the
purpose in a clause, and a last line that says what to bring back.

> Discuss with at least two people your list of expectations. Try to
> agree on the two that you think are most essential. Be ready to share
> them out.

Every stage in `docs/path/` ends with a "Be ready to..." line.

## Who is talking

- **"I"** is Ben, the person who built the apps this template came from.
  Use it where a choice was his: "I want every platform to feel native."
- **"We"** is Ben and the reader, building together. Never a club the
  reader is outside of.
- **"You"** is the reader, doing the steps.
- **"Folks" or "people"**, not "users", when the sentence is about
  human beings. "Users" is fine inside a technical rule an agent reads.

## Say what you want before what it does

Ben's most common sentence opens with *I want*. Specifications read as
wishes, and the feature is the answer to the wish. A section about the
parity matrix starts with what we want for the people using the app on
five different devices, and only then gets to the table.

## Anchor in something that happened

Open with a real thing: a decision number, a bug, a count from the git
history, a device on the bench. "Archive Watch shipped to five stores
from one repository" is an anchor. "In today's multi-platform world" is
not.

**Never invent an anecdote.** Every anchor must be traceable to a
commit, a decision, a doc, or something Ben said. If you cannot find a
real one, start with the plain claim instead.

## Sentences

**The trap to avoid first.** On October 2, 2026, Ben read three design
drafts for humanshaped.org and said the copy was "the AI 'short
sentences and commands punctuated by periods'" and "doesn't read with
any of the way that I would actually write or speak." Strings of short
declaratives, two-word fragments ("Not stages. Laps."), and captions
written as commands are the most recognizable sign of machine writing,
and they are not Ben. His median sentence is about 16 words, and most of
his sentences carry an idea through a clause or two ("because",
"which", "so that", "and yet") before they stop. The short sentence is
a landing he earns once or twice a page, never a rhythm. Before you
ship, find any run of three short sentences in a row and join them into
the one sentence they were trying to be.

- Build, build, land. A long sentence that accumulates, then a short one.
- Put the thesis of a section on a line by itself, in under ten words.
- Turn with "But," / "And yet," / "So," / "Rather," at the start of a
  sentence, with the comma.
- Ask the real question the reader is asking, then answer it right away.
- Colons set up the reveal. Parentheses carry the aside and the joke.
- **No em dashes.** Where you want one, start a new sentence. Semicolons
  almost never.
- Say "I am" and "it is" uncontracted where you want the reader to slow down.
- Give the other side a fair sentence. Name the cost of our choice.

## Grammar

- **Always use the Oxford comma.** "Apple, Google, and Microsoft," never
  "Apple, Google and Microsoft." Ben is a former English teacher, and he
  asked for it by name on October 2, 2026.
- A sentence that needs to be read twice is too long or too tangled.
  Split it where the idea turns, or cut the clause that is only there to
  sound thorough.

## Words

Reach for: *build, make, connect, folks, one another, based upon,
rather, simply, actually, in order to, be able to, the open web,
native, honest, intentional, regular progress, what is possible.*

Do not use (these are the ones AI writing reaches for first):
*seamless, robust, powerful, leverage, harness, unlock, empower,
elevate, streamline, cutting-edge, best-in-class, game-changing,
delve, journey, landscape (as a metaphor), comprehensive, holistic,
synergy, utilize, individuals, "it's not X, it's Y", "whether you're X
or Y", "in today's ...", "let's dive in", "at the end of the day".*

Do not use the retired lexicon as if it were current: *collaborative,
authentic, Web 2.0, remix.*

Acronyms get explained the first time, or cut. "ASC" is "App Store
Connect" until the reader has seen it spelled out.

## Titles and headings

Statements or noun phrases. Not questions. "The agent is never the
tester." "One universal Apple target." Not "Why use one target?"

## Endings

End a page short. Return to the opening, then hand it to the reader: an
invitation, a question, or a flat sentence of eight words or fewer.

## The check before you commit a page

1. Does it open with something real?
2. Does it say what we want before what the thing does?
3. Is the thesis on its own line?
4. Did the cost of our choice get a fair sentence?
5. Zero em dashes? Zero words from the "do not use" list?
6. Does it end with what to do next, or what to bring back?
7. Read it aloud. If it sounds like a company, start over. If it sounds
   like a teacher who builds things at night, ship it.
