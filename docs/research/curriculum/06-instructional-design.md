# Instructional design for finding a human-shaped problem

*Written by Claude, awaiting Ben's review. October 7, 2026.*

This note exists because the first rewrite of stages 00 and 01 failed.
On October 7, Ben read them and said the approach was "pretty off":
"the hum" is a metaphor and "doesn't work as an instructional move," the
lesson built "a single line in my writing into the entirety of the
approach," and the hum sort asked students "to do something that I have
already given them answers to." He asked for "better instructional
design," researched, that makes "activities meaningful from the content
(the whole template and website!!)" (site `DECISIONS.md`, "The first
lessons missed; instructional design comes first," October 7, 2026).

So, this note does three things in order, and rewrites nothing:

1. It collects every way Ben has already described or identified a
   human-shaped problem, across the template and the hub, and marks what
   he has already answered for students.
2. It summarizes the research on designing projects and inquiry, and on
   finding a problem worth solving, and says what fits Ben's ethos.
3. It proposes a design for week 1 by backward design, inside Write,
   Play, Publish, and sketches the same method for the rest of the path.

It ends with the list of files that carry the rejected approach.

## 1. What Ben has already written

### Definitions

- **The long definition (October 6).** "A human-shaped problem is
  something, really anything, in your life that will in some way make
  your life better, happier, or more deeply resonant with the universe if
  you could only solve for it. [...] It is a thing that you wonder and
  question about often. It is something that has gone unsolved for months
  or even years [...] And most of all, it is something that you cannot do
  yourself. Your current tools and resources are insufficiently up to the
  challenge." (`docs/human-shaped/computer-shaped-problems.md:26-34`; the
  original is site `DECISIONS.md`, "Human-shaped problems.")
- **The two ways of seeing (October 6).** "Human-shaped problems see the
  world as interrelated stories to be told, experienced, and added to.
  Computer-shaped problems see the world as disparate data points to be
  aggregated, quantified, and leveraged."
  (`computer-shaped-problems.md:64-68`.)
- **What only people can do.** "Learning, community, friendship, taste,
  and the people we love [...] only happen when a person does the work"
  (`computer-shaped-problems.md:19-21`). The README says the same of
  "learning, community and relationships" (`README.md:25-29`), and the
  hub's home page asks people to "bring a problem only people can solve"
  (site `index.html`, the cohorts section).
- **Principle 1.** "Starts from a human-shaped problem, one that affects
  real people in the real world" (`docs/human-shaped/PRINCIPLES.md:64-65`).
- **The pitch (October 6).** "If anyone can build their own apps (with
  AI), it matters even more which apps they choose to build and how they
  choose to build them" (site `DECISIONS.md`, "The pitch, and principles
  that stand alone").

### Tests a problem can be held to

Ben never wrote these as a checklist, but each is a test he states
plainly, and together they are the criteria a student can hold their own
problem to:

1. It would make your life better, happier, or more resonant
   (`computer-shaped-problems.md:26-29`).
2. You wonder and question about it often (`:30`).
3. It has gone unsolved for months or even years (`:31`).
4. You cannot do it yourself with the tools and resources you have now
   (`:32-34`; `PRINCIPLES.md:73-75`).
5. Real people have it, and you can name them (`PRINCIPLES.md:64-65`,
   `:78-81`: "it helps to name the actual people who have the problem").
6. It is rarely yours alone: human-shaped problems "tend to be
   identifiable to many people and possibly even universal" (site
   `DECISIONS.md`, "The method is Write, Play, Publish"; stage 00 before
   the curriculum loop, `d70c674:docs/path/00-why-we-build.md:94-97`).
7. A computer cannot simply solve it for them: principle 1's "how you
   can tell" is that "the builder has written down what the problem is,
   who has it, and why a computer cannot simply solve it for them"
   (`PRINCIPLES.md:83-84`).
8. It sees people as stories, not data points
   (`computer-shaped-problems.md:64-68`).
9. Solving it creates no new human-shaped problem (`PRINCIPLES.md:251-262`).
10. At least one person would be glad of it as it ships
    (`PRINCIPLES.md:297-309`).

### Questions Ben already asks of an idea

Stage 00 as it stood before the curriculum loop (commit `d70c674`) was
already full of good instructional moves, and the rewrite buried them:

- **Start the note with the why:** the problem, who it is for, and what
  you hope it does for them (`d70c674:docs/path/00-why-we-build.md:199-209`).
- **Name one line you will not cross,** in your words, with a date
  (`:217-230`).
- **Three questions of the idea:** should it exist at all, who does it
  touch (including the people outside the screen), and what will people
  learn from using it, and stop learning (`:232-254`).
- **The strongest case against it,** made by the agent on behalf of the
  people outside the screen, which "does not replace asking real people"
  (`:256-259`; principle 12, `PRINCIPLES.md:258-262`).
- **The four questions:** does it deepen understanding, invite
  participation, support agency, and stay clear rather than clever
  (`:129-137`).

### Examples Ben has already published

Two lists of four, one of each shape, on the template
(`computer-shaped-problems.md:36-62`) and in part on the hub's home page
(one of each, site `index.html`, "Human-shaped problems are ones worth
solving"). His own apps are worked examples of where a problem came
from: Bsky Dreams began "with Bluesky feeling unfinished to me," BOBA
Playbook "with a card game," and Archive Watch with "watching old
public-domain films on an Apple TV" (research note 01, phase 1;
`case-study-archive-watch.md:3-5`). The Archive Watch film notes are a
worked example of choosing the human-shaped part inside an app
(`computer-shaped-problems.md:110-147`).

### What Ben has already answered

These are settled, and no activity should ask a student to work them out
again as if they were open:

- **Which of his eight examples is which shape.** He labeled all eight.
- **What makes a problem human-shaped in general.** He defined it.
- **Whether the film notes should be AI-written.** He decided, and said
  why.

What he has not answered, and only the student can, is which problem in
**their** life is worth building for, who else has it, and why a
computer cannot simply solve it for them. That is where every activity
should point.

### What Ben does himself, and what he never wrote down

Research note 01 found that none of his four apps began as an idea for
an app. Each began with part of his life that kept bothering him, and he
wrote the why and researched before building (note 01, phases 1 and 2,
citing Bsky-Dreams `9df79a3` and Archive-Watch `32217eb`). It also found
the record silent on three things the course must teach: choosing the
problem, talking to the people it is for, and deciding when it is enough
(note 01, "What the record cannot teach").

## 2. What the research says

### Designing a project

**PBLWorks' seven elements.** A project is "framed by a meaningful
problem to be solved or a question to answer"; students engage in
"sustained inquiry," with "real-world context, tasks and tools [...] or
[...] personal concerns, interests, and issues in the students' lives";
they have "voice and choice"; they reflect; they "give, receive, and
apply feedback"; and they share a "public product" with "people beyond
the classroom" ([PBLWorks, Gold Standard Project Design Elements](https://www.pblworks.org/what-is-pbl/gold-standard-project-design)).
Ben's method already holds most of these: the student's own problem is
the project, playing is sustained inquiry, and publishing is the public
product. What the first rewrite lacked was a meaningful task at each
step and real critique and revision.

**A need to know, and an entry event.** "Many students find schoolwork
meaningless because they don't perceive a need to know what they're
being taught." Teachers "activate students' need to know [...] by
launching a project with an 'entry event' that engages interest and
initiates questioning." A good driving question is "provocative,
open-ended, complex, and linked to the core of what you want students to
learn" (Larmer and Mergendoller, ["Seven Essentials for Project-Based Learning,"](https://www.ascd.org/el/articles/seven-essentials-for-project-based-learning)
*Educational Leadership*, September 2010). After an entry event,
students list the questions they "need to know" to succeed, and the list
guides the work ([PBLWorks, Need to Knows](https://my.pblworks.org/resource/ntks)).

**Writing a driving question.** PBLWorks' Driving Question Tubric builds
a question from opening words, a person, an action, and an audience or
purpose ([Driving Question Tubric 2.0](https://my.pblworks.org/resource/document/driving_question_tubric)).
The question names who acts, what they make, and for whom. Krajcik and
Blumenfeld describe the driving question as the organizing feature of a
project in the learning sciences (["Project-Based Learning," *The Cambridge Handbook of the Learning Sciences*, 2006, pp. 317-333](https://www.cambridge.org/core/books/abs/cambridge-handbook-of-the-learning-sciences/projectbased-learning/355AA45D92D7FCD5D312FD1C343FDBB2)).
I could not read the chapter's text, so I cite it only for that.

**Models of excellence, critique, and revision.** Ron Berger's five
practices are "assign work that matters; study examples of excellence;
build a culture of critique; require multiple revisions; and provide
opportunities for public presentation." Before a project, students
"examine models of excellence" and ask "What makes a particular [...]
piece of writing [...] so good?" Critique follows three rules: "Be kind;
be specific; be helpful," with suggestions phrased as questions: "Have
you considered . . . ?" (Berger, ["Fostering an Ethic of Excellence,"](https://jaymctighe.com/wp-content/uploads/2011/04/Ron-Berger-Article.pdf)
*The Fourth and Fifth Rs* 12(1), 2006). This is the right use of Ben's
published examples: as models students study to make their own work
better, not as a set to sort.

### Designing inquiry

**Levels of inquiry.** Banchi and Bell describe four levels:
confirmation (question, method, and result known), structured (question
and method given), guided (only the question given), and open (students
pose the question too) ([Banchi and Bell, "The Many Levels of Inquiry," *Science and Children* 46(2), 2008](https://www.semanticscholar.org/paper/The-many-levels-of-inquiry-Banchi-Bell/96e94ce3ebf14c158746cc86653e553caa4ac8cd)).
The hum sort was confirmation inquiry with the answer already printed.
Finding one's own problem is guided inquiry: the course gives the
question, and the student finds the method and the answer.

**Guidance matters for novices.** Kirschner, Sweller, and Clark argue
that minimal guidance fails learners without prior knowledge
([*Educational Psychologist* 41(2), 2006](https://eric.ed.gov/?id=EJ736299)),
and Hmelo-Silver, Duncan, and Chinn answer that good inquiry and
problem-based learning are heavily scaffolded, not minimal
([*Educational Psychologist* 42(2), 2007](https://eric.ed.gov/?id=EJ772220)).
For adults who have never built an app, that means structure at every
step: a log with prompts, interview rules, and criteria to test against.

**Students' own questions.** The Right Question Institute's Question
Formulation Technique gives a focus, four rules ("Ask as many questions
as you can," "Do not stop to discuss, judge, or answer the questions,"
"Write down every question exactly as it is stated," "Change any
statement into a question"), then improving, prioritizing, and deciding
next steps ([Right Question Institute, What is the QFT?](https://rightquestion.org/what-is-the-qft/)).
It is a good way to build a need-to-know list from an entry event.

**Backward design.** Wiggins and McTighe plan in three stages: identify
desired results, determine acceptable evidence, then plan learning
experiences, thinking "like an assessor" before choosing activities
([McTighe and Wiggins, *Understanding by Design* framework](https://files.ascd.org/staticfiles/ascd/pdf/siteASCD/publications/UbD_WhitePaper0312.pdf)).
Every stage of the path already ends with a "Be ready to" line, which is
a desired result written as evidence. The stages were designed backward
before anyone named it.

### Finding a problem worth solving

- **Noticing, not thinking up.** "The verb you want to be using [...] is
  not 'think up' but 'notice,'" and "the place to start looking for ideas
  is things you need" ([Paul Graham, "How to Get Startup Ideas," November 2012](http://www.paulgraham.com/startupideas.html)).
  This fits Ben's ethos for the noticing, and not for its aim: Graham is
  looking for companies, and we are not.
- **Your own itch.** "Every good work of software starts by scratching a
  developer's personal itch" (Eric S. Raymond, *The Cathedral and the
  Bazaar*, lesson 1, 1997, [as quoted on Wikipedia](https://en.wikipedia.org/wiki/The_Cathedral_and_the_Bazaar)).
  It matches how all four of Ben's apps began. It misses principle 1's
  "real people," so it is a start and not a test.
- **A log over time.** A diary study collects "insights about user
  behaviors, activities, and experiences over time and in context," with
  entries made when something happens, at set times, or when prompted
  ([Kim Flaherty, "Diary Studies," Nielsen Norman Group, March 29, 2024](https://www.nngroup.com/articles/diary-studies/)).
  A student keeping one on themselves for a week is the closest thing to
  Ben's months of living with a problem that a cohort can fit.
- **Conversations with people.** The d.school's interview rules: ask
  why; never say "usually," but ask "Tell me about the last time you
  ____"; encourage stories, because "they reveal how they think about
  the world"; look for inconsistencies; don't be afraid of silence
  (Stanford d.school, "Interview for Empathy," Bootcamp Bootleg; summarized
  by [Product Discovery Methods](https://pdmethods.com/interview-for-empathy/)
  and others; I could not open the d.school's own PDF). Rob Fitzpatrick's
  three rules say the same: "talk about their life instead of your
  idea," "ask about specifics in the past instead of generics or opinions
  about the future," and "talk less and listen more" (*The Mom Test*,
  2013, [as summarized by Michael Lynch](https://mtlynch.io/book-reports/the-mom-test/)).
  Stories fit Ben's line that human-shaped problems "see the world as
  interrelated stories" exactly.
- **Watching people where they live.** Contextual inquiry has the
  researcher learn as an apprentice to the person, in their own setting,
  on four principles: context, partnership, interpretation, and focus
  (Beyer and Holtzblatt; [Wikipedia, "Contextual inquiry"](https://en.wikipedia.org/wiki/Contextual_inquiry)).
  It is more than a novice needs in week 1, and a good "go deeper."
- **Framing.** IDEO.org's "How Might We" rewrites an insight as a
  question that is "specific enough to guide your starting point, yet
  open enough" ([Design Kit, How Might We](https://www.designkit.org/methods/how-might-we.html)).
  Ben's own examples already have a stronger frame: a situation in the
  first person, then "I need something that..." We should teach his.
- **Time spent finding the problem pays.** In Getzels and
  Csikszentmihalyi's study of art students, those who spent longer
  exploring before committing made work critics judged more original,
  and more of them were still working as artists years later
  ([*The Creative Vision*, 1976](https://www.semanticscholar.org/paper/The-Creative-vision-:-a-longitudinal-study-of-in-W.-Getzets/73ae72058e5e7171a42dc57ce1784d6b119fc06c);
  the summary of findings here is secondary). It argues for giving
  finding the problem a full week rather than a first hour.

What does not fit: methods built to size a market, rank ideas by
revenue, or validate "willingness to pay." They ask a computer-shaped
question about people.

## 3. A design for week 1

### Desired results (backward design, stage 1)

By the end of week 1, a student can:

1. Name one problem in their own life, in plain words, that meets Ben's
   tests (section 1).
2. Show that other people have it, from real conversations, not guesses.
3. Say why a computer cannot simply solve it for them, and what part
   only people can do.
4. Say what their app is for and one thing it will never do.

These come straight from principle 1's "how you can tell"
(`PRINCIPLES.md:83-84`), stage 00's old ending
(`d70c674:docs/path/00-why-we-build.md:286-299`), and the Educational
Model Spec's first principle that "learning must be personally relevant"
(research note 05, principle 1).

### Evidence (stage 2)

- **A problem statement,** written in Ben's form (a situation in the
  first person, then "I need something that..."), revised at least once
  after critique and after the conversations. Kept in the student's
  note and the repository.
- **Notes from two conversations** with people who might share the
  problem, each about a specific time in the past.
- **The why, in `AGENTS.md`,** with one line the app will not cross,
  dated, in the student's words.
- **A short public post** to the cohort (and, if they like, back to the
  people they talked to): the problem, who has it, and why a computer
  cannot simply solve it. This is principle 1's evidence, and the start
  of the credential's record.

### Learning plan (stage 3), as rounds of Write, Play, Publish

**Before week 1: a noticing log (Write).** For five days, the student
writes one line whenever one of these happens: "I wished something
worked differently," "I gave up on something I care about," "I did
something the long way because nothing helped," or "someone I know
struggled with the same thing." These prompts are plain and come from
Ben's own tests (unsolved, cannot do it yourself, shared by others) and
from Graham's "notice." It is an event-based diary study on oneself
(Flaherty, NN/g). No app ideas yet.

**Entry event, in the live session.** Show the Archive Watch choice from
`computer-shaped-problems.md:110-147`: a film note an AI could write in
a second, beside the real note written by someone who watched the film
and uploaded it. Ask one question: "Which would you rather read, and
what would be lost if the app only had the first kind?" Then put Ben's
pitch on the screen as a Question Focus ("If anyone can build their own
apps, it matters even more which apps they choose to build") and run the
QFT's four rules for five minutes. The class's questions become the
need-to-know list for the five weeks. Both are Ben's own content, and
neither has an answer the student is asked to reproduce.

**Round 1. Candidates (Write, Play, Publish).**
- *Write:* from the log, five candidate problems in their own words.
- *Play:* hold each candidate to Ben's tests (section 1, the ten
  tests), marking each "yes," "not yet," or "I don't know," and choose
  two to carry forward. This uses Ben's criteria as tools on new
  material: the student's own life.
- *Publish:* read the two to their trio and say why each might matter.

**Round 2. Learning from Ben's examples (Write, Play, Publish).**
- *Play:* study Ben's four human-shaped problems as models (Berger,
  "study examples of excellence"). The question is not which shape they
  are, since Ben already said, but what makes them strong: each names a
  real situation in the first person, says what a better life looks like
  ("still let me enjoy great novels and non-fiction every day"), and
  never names a technology. Then look at what his four computer-shaped
  problems have in common, which is verbs like measure, find the best
  price, categorize, and map.
- *Write:* rewrite the stronger candidate in Ben's form, and write one
  sentence about what the computer-shaped version of the same wish would
  be, so the student can see what to steer away from.
- *Publish:* gallery critique in the trio with Berger's rules (kind,
  specific, helpful; suggestions as "Have you considered...?"), then
  revise.

**Round 3. Outside the screen (Write, Play, Publish).**
- *Write:* a short conversation guide: three "tell me about the last
  time you..." questions, no pitch of an app (d.school; Fitzpatrick).
- *Play:* two conversations with people who might share the problem,
  between sessions. Notes in the student's own words, kept private
  unless they choose to share them.
- *Write:* revise the problem statement with what they heard, then
  write who has it and why a computer cannot simply solve it for them.

**Round 4. The why (Write, Play, Publish).** Ben's original stage 00
steps, kept: tell the agent the why and have it draft the "Why we build"
paragraph until it sounds like the student; name one line it will not
cross; ask the three questions of the idea; have the agent make the
strongest case against it on behalf of the people outside the screen;
run the four questions. Then publish the problem, who has it, and why
it is human-shaped, as the week's bring-back.

### Sample driving questions

1. "Which app should you build, and how should you build it?" Drawn from
   Ben's pitch (site `DECISIONS.md`, October 6). A course-wide question.
2. "What problem in your own life is worth building something for, and
   who else has it?" Drawn from his definition and principle 1. Week 1's
   question.
3. "What should your app do for the people you are building it for, and
   what should it never do?" Drawn from old stage 00's why and one line
   (`d70c674:docs/path/00-why-we-build.md:199-230`).

Each is plain, open, about the student's own work, and answerable by a
novice on day one. None is a metaphor.

### Sample entry event

The Archive Watch film notes, as above: two notes for one film, side by
side, and "Which would you rather read, and what would be lost if the
app only had the first kind?" It comes from
`computer-shaped-problems.md:110-147` and site `DECISIONS.md` ("10,000
movie summaries written by AI is more efficient, and yet it is a worse
experience"). It raises the course's central question about what to hand
to the machine before anyone has an app.

### Level of inquiry and support

Week 1 is guided inquiry (Banchi and Bell): the course gives the
question, and each student finds their own method and answer. Novices
get structure at every step, per the guidance debate above: the log's
prompts, Ben's tests as a table, his examples as models, an interview
guide, and critique rules. "Go deeper" options: contextual inquiry with
one person in their own setting, a longer log, or a third conversation.

## 4. The same method for the rest of the path

**Stage 01, the first prototype.** Desired result: one real thing in the
hands of one person the student talked to in week 1, and their reaction
in their words. Evidence: the link, the person, and what they said.
Learning plan from Ben's own record: real data first and one platform
he could see easily (note 01, phases 3 and 4), with Tidbits Trivia's
two days to TestFlight as a model of how small a first version can be
(note 01). The question is plain: "What is the smallest thing you could
put in the hands of one person you talked to this week?"

**Every other stage.** The "Be ready to" line at the end of each stage is
already the desired result and the evidence, so each stage is designed
backward from it. The question at the top asks about the student's own
app in plain words. Ben's stories and prompts are worked examples and
models students study to do their own work better, never answers to
reproduce. Each round ends in a real publish, with critique and
revision. Where a stage needs a research method (watching a person use
it in stage 05, reading one honest number in stage 06), it is named,
cited, and used as a way to do one of the three moves well.

## 5. Files that carry the rejected approach

The phrase "gentle hum of worry" in Ben's own definition stays wherever
it quotes him: `computer-shaped-problems.md`, `PRINCIPLES.md`, and the
hub's home page. What has to change is the use of "hum" as the frame of a
lesson or an activity, and the hum sort.

**Template (`main`):**
- `docs/path/00-why-we-build.md`: the question, "Find your hum," and the
  new steps 1 to 4. Restore old steps 2 to 6 and redesign the opening.
- `docs/path/01-first-prototype.md`: the question and the hum language
  in steps and the publish step.
- `docs/path/02` to `05`: "hum" in their publish steps and bars.
- `docs/human-shaped/hum-sort.md`: retire it.
- `COURSE.md`: lines 50-57 and the weekly table's week 1 question.
- `docs/teaching/before.md`, `week-1.md`, `week-2.md`, `week-3.md`,
  `week-5.md`, and `README.md`.
- `docs/teaching/runs-of-show.json`, week 1's `template: "hum-sort"` and
  its questions, and `tools/test_runs_of_show.py`, which checks for it.
- `docs/stuck/README.md`, `docs/stuck/writing/README.md`,
  `docs/stuck/writing/find-your-hum.md` (rename and rewrite), and
  `docs/stuck/writing/what-it-refuses.md`.
- `docs/research/curriculum/00-curriculum-design.md`, which should point
  to this note for week 1.

**Hub (`site`):**
- `assets/board-lib.js` (the Hum sort board template) and
  `tools/test/board-lib.test.mjs`.
- `assets/curriculum-lib.js` (week 1's defaults and questions) and
  `tools/test/curriculum-lib.test.mjs`.
- `assets/curriculum-pages-lib.js` (week 1's question and the stuck page
  list) and `assets/render.js`.
- `cohorts/index.html` and `teach/guide/index.html`.
- `stuck/writing/find-your-hum/index.html`, `stuck/writing/index.html`,
  `stuck/writing/what-it-refuses/index.html`,
  `stuck/writing/what-next/index.html`, and `sitemap.xml`.

None of these should change until Ben has read this note.
