# How we teach: a question at the center, and evidence a person can open

*Curriculum research, part 5 of 5. Written by Claude for Ben's review,
October 7, 2026. Every quotation from the Educational Model Spec is cited
to its file and line in `~/Documents/GitHub/educational-model-spec` as it
stood on that date; every outside source is listed at the end, marked
"checked" when the page itself was read for this note.*

Ben's Educational Model Spec asks one question of every moment a learner
spends with an AI, and it is the question this course has to answer for
people who are building an app with one:

> **The fundamental test:** Does this AI interaction make the student a
> stronger thinker, or does it make thinking unnecessary?
> (`docs/overview.md:238`, EMS-AGR-01a)

In this course the agent writes nearly all of the code, so the thinking
we protect cannot be the code. It is the deciding and the judging: what
the app is for, who it is for, what it will never do, whether it works,
and whether it is ready. Every lesson below is built so that those stay
with the person, and every assignment leaves something behind that the
person can open, show, and choose to put on their credential.

**A question first, the agent second, and the evidence last.**

This note has four parts: (a) the principles from the Spec that govern
every lesson, (b) a lesson template with a question at its center, (c)
performance-based assignments across the cohort, each mapped to the
credential, and (d) a model for supporting people when they get stuck.

## (a) The principles that govern every lesson

These are Ben's own words from the Spec, chosen because each one changes
how a lesson in this course is written. The line after each quotation
says what it changes.

1. **The problem has to be theirs.** "Learning must be personally
   relevant. When students connect new information to their lived
   experiences and real challenges, they develop the ability to transfer
   knowledge across situations" (`docs/overview.md:69`, EMS-FLP-01b).
   *In a lesson:* the driving question is always asked about the
   student's own app and their own human-shaped problem, never about a
   practice app.

2. **Their questions drive it.** "Students who learn to pursue their own
   questions, direct their inquiry, and take ownership of their growth
   develop the intrinsic motivation and self-direction that leads to
   fulfilling lives" (`docs/overview.md:79`, EMS-FLP-01g). *In a lesson:*
   the student asks questions of their own idea before the agent does,
   and the lesson keeps a place for the questions they want to chase next.

3. **Understanding is said out loud.** "When students engage in
   dialogue, debate, and reflection, they develop their own voice and
   learn to articulate complex ideas" (`docs/overview.md:77`,
   EMS-FLP-01f). *In a lesson:* every week ends with explaining one
   decision to a person, with the agent closed.

4. **Revising is the work.** "Students who embrace uncertainty, revise
   their thinking based on new evidence, and adapt their approaches to
   changing contexts develop the cognitive flexibility necessary for
   lifelong learning" (`docs/overview.md:75`, EMS-FLP-01e). *In a
   lesson:* a "not yet" is a normal outcome, and every round of feedback
   is a commit the student can point to.

5. **The student controls the path, the pace, and the mistakes.**
   Students keep control over "Their learning goals and pathways", "How
   they express understanding", "What they share and with whom", "The
   pace and depth of their exploration", and "Their mistakes and growth
   process" (`docs/overview.md:166-171`, EMS-HCD-02a). *In a lesson:*
   every lesson has a novice path and a "go deeper" extension, the
   student picks, and nothing a student shares leaves the cohort without
   their choice.

6. **Assessment is for learning, done by the learner first.** The Spec
   asks for "Self-assessment tools that develop metacognitive skills"
   and "Portfolio systems that capture learning journeys over time"
   (`docs/overview.md:207-208`, EMS-ASS-02a), and for "Presentations to
   authentic audiences beyond the classroom" (`docs/overview.md:212`,
   EMS-ASS-02b). *In a lesson:* the builder judges "ready or not yet"
   before anyone else does, and the final showing is open to guests.

7. **The agent asks before it answers.** Before helping, the Spec's AI
   asks "What have you tried so far? What specific part is challenging
   you?" and "Explain back to me what you think the main challenge is
   here" (`docs/overview.md:264` and `:272`, EMS-AGR-03). *In a lesson:*
   the student writes their own first answer before opening the agent,
   and the course's agent prompts start by asking the student what they
   think.

8. **The process is kept, not just the product.** "Students maintain
   **thinking journals** that capture their intellectual journey" and
   "**Process portfolios** show how understanding evolved over time,
   including AI interactions" (`docs/overview.md:308-309`, EMS-AGR-05).
   *In a lesson:* the student's note in their repository is the thinking
   journal, and the repository's history is the process portfolio.

9. **The student owns their learning story.** Students control "**What
   gets included** in their portfolio and what remains private" and
   "**Who has access** to different parts of their portfolio"
   (`docs/overview.md:362` and `:364`, EMS-SOP-03a), and AI never
   "Compares students to each other or to normative standards"
   (`docs/overview.md:405`, EMS-SOP-05b). *In a lesson:* evidence goes on
   the credential only when the student chooses, and nothing is ranked.

10. **Nobody is shamed for not knowing.** AI interactions "should never
    ... Shame students for not understanding" or "Compare students to
    others in ways that diminish confidence" (`docs/overview.md:448-450`,
    EMS-PSW-02a). *In a lesson:* this is the course's second rule for how
    we talk to one another ("No acting surprised", `COURSE.md:110`),
    applied to the agent as well as to people.

Two of the Spec's implementation tools fit the course directly. The
Thinking Engagement Rubrics give students a private check, "Am I
Building or Bypassing My Thinking?", with red flags such as "I can't
explain the AI-suggested solution in my own words" and green lights such
as "I questioned, modified, or improved upon AI responses"
(`docs/implementation-tools/thinking_engagement_rubrics.md:18-38`). The
AI Disclosure Protocol's quick version asks for four lines: "AI Role",
"Your Essential Work", "Learning Insight", and "Growth Edge"
(`docs/implementation-tools/ai_disclosure_protocol.md:112-116`).

**Where the Spec and this course pull against each other.** The Spec's
blocked behaviors include "Complete homework solutions without requiring
student analysis, synthesis, or original connection-making" and
"Step-by-step solutions to problems without ensuring student
understanding" (`docs/overview.md:245` and `:247`, EMS-AGR-02). In this
course the agent writes complete code on purpose. The way through is to
be exact about what the homework is: the code is the agent's, and the
decision, the judgment, and the explanation are the student's. The
guardrail applies to those, and the course should say so in week 1
rather than leave students to guess. The cost of the other path is real,
too: the site's research found that guarded tutors that withhold help
drew the lowest ratings and the most switching to outside chatbots
(humanshaped.org `research/notes/facilitation-assessment-social-learning-notes.md`,
Part 5, "Do not police the tool"). So, we ask people to keep the deciding,
not to use the agent less.

## (b) A lesson with a question at its center

Every stage in `docs/path/` already ends with a "Be ready to..." line,
and every week's session already has the same six parts
(`COURSE.md:151-212`). What is missing is a shape for the lesson itself,
the part a student works through on their own between sessions, that
puts a question first.

The template below borrows from three places. Project-based learning's
Gold Standard starts every project with "a meaningful problem to be
solved or a question to answer, at the appropriate level of challenge"
and keeps "a rigorous, extended process of posing questions, finding
resources, and applying information" (PBLWorks, checked). The Right
Question Institute's Question Formulation Technique gives students four
rules for producing their own questions: "Ask as many questions as you
can", "Do not stop to discuss, judge, or answer the questions", "Write
down every question exactly as it is stated", and "Change any statement
into a question" (Right Question Institute, checked). And the research
on productive failure found that trying a problem before being taught
improved conceptual understanding and transfer, with an overall effect
of g = 0.87 after correcting for publication bias, though the advantage
reversed for young children and for domain-general skills (Sinha and
Kapur 2021, checked through the abstract and publisher's summary).

The research also says how much to hold back. Worked examples help
people with little prior knowledge most, and the same examples can get
in the way of people who already know the material, which is the
expertise reversal effect (Kalyuga, Ayres, Chandler, and Sweller
2003). That is why each lesson has a novice path
with a worked example and a "go deeper" path without one, and why the
student chooses.

### The template

Each lesson is one page, in this order.

1. **The question.** One open question about the student's own app,
   that cannot be answered by looking something up, and that the week's
   work will answer. It goes at the top, on its own line. ("Who is this
   app for, and what will it never do to them?")
2. **Your first answer, before the agent.** Two or three sentences in
   the student's note, written before any prompt is sent. This is the
   Spec's checkpoint, "Take 5 minutes to brainstorm your own ideas about
   this. I'll wait." (`docs/overview.md:266`), and it is the "trying it
   first" that productive failure rests on.
3. **Your questions.** Five minutes with the four rules above: as many
   questions about the idea as you can, written down as stated, none
   answered yet. Then mark the one you most want answered this week.
   The lesson names a starting stimulus (the Question Formulation
   Technique calls it a Question Focus), such as a screenshot, a line
   from the student's note, or a classmate's app.
4. **The work, as a conversation with the agent.** Numbered steps, each
   a prompt the student adapts, the way every stage already reads. On
   the novice path, step 1 is a worked example: one real prompt from
   Ben's own apps, what the agent did, and what he checked. On the "go
   deeper" path, the student writes the first prompt themselves and
   compares it to the example afterward.
5. **Look on the device.** The evidence step. Open the app where people
   will use it and write down what you saw, because "'it works' is a
   claim and a phone in someone's hand is evidence" (`COURSE.md:229-230`).
6. **Explain one decision with the agent closed.** Two sentences in the
   note: what you decided, and what it cost. This is the test of whether
   the decision is still yours.
7. **Ready, or not yet.** The stage's "When you are ready to move on"
   paragraph, read by the student against their own app. Self-assessment
   works best "when it is used formatively and supported by training"
   (Andrade 2019, checked), so the first week practices it on an app
   that belongs to nobody (`COURSE.md:92-97`).
8. **Be ready to...** The stage's line, unchanged. This is what comes to
   the live session.
9. **Go deeper.** One extension for anyone who wants it: a harder
   question, a second platform, a reading, or a part of the template to
   open up. Never required, never counted.
10. **If you get stuck.** A link to the support ladder in part (d), and
    the one stuck moment from earlier cohorts that this lesson most often
    produces.

The page ends with the AI Disclosure Protocol's four quick lines in the
note (role, your essential work, learning insight, growth edge). They
take two minutes, they are the student's own record, and they are the
raw material for the final showing.

### What it costs

A question-first lesson is slower than a list of steps, and people who
are new to all of this sometimes want the list. The research on open
discovery without guidance is clear that it leaves many beginners lost
(`COURSE.md:365-369`), which is why the questions sit around numbered
steps rather than replacing them. The question frames the work, and the
steps still carry it.

## (c) Assignments that leave evidence behind

Evidence-centered design builds an assessment as an argument: a claim
about what the learner can do, the evidence that would support it, and
the task that produces that evidence (Mislevy, Steinberg, and Almond
2003, checked through the CRESST and ETS summaries). Performance
assessment asks people to do the thing itself rather than answer
questions about it (Darling-Hammond and Adamson 2014). Open Badges 3.0
carries the result: its Evidence class holds "a URL to an artifact
produced by the Learner" with a narrative and a genre (1EdTech, checked
in part; the full property table was not visible in the page as read).

The credential already works this way. Its criteria say "The evidence
is the app's repository, which holds the app and the record of how it
was made", a live web app is the first level, and each further platform
"where other people can get it for themselves" adds a level
(humanshaped.org `assets/credential-lib.js:61-67`). In-class
recognitions go into the evidence, each naming a skill from a short
list tied to the principles (`assets/recognition-lib.js:8-20`, and
DECISIONS.md, "Recognitions in the credential"). So, each assignment
below names the claim, the task, the evidence, how the student shows it,
and where it lands on the credential.

| When | The question | The task | Evidence a person can open | How it is shown | On the credential |
|---|---|---|---|---|---|
| Cohort Prep | What hums? | List the human-shaped problems in your own life, sort a few into human-shaped and computer-shaped with a partner, and choose one. Set up and open your app's address on your phone. | The choice and why, in the note; the repository; the address | On the phone, in the setup session | The repository is the credential's first evidence |
| Week 1 | Who is this for, and what will it never do to them? | Write "why we build", the people outside your screen, and one rule; get a first version running on real data | The note's first paragraph and rule; the live address; two feedback rounds in the history | Explained with the agent closed, in the trio | Level 1 (the web); recognitions "Wrote down what they value", "Explained a decision their values made" |
| Week 2 | What should this app do the same everywhere, and what should it do differently? | Read and trim the parity matrix; run a second platform on your own device | The matrix and one cell your eyes proved wrong; two screenshots | One verb shown on both platforms | Recognition "Took another round instead of shipping a first draft" |
| Week 3 | How do I know it works, and how do I want it to look and feel? | Have the agent test on your device; make a look that comes from your why | The screenshot that proved a fix, with what it would have shown if the fix failed; the look beside the template's | Side by side, in the trio and two apps outside it | Recognitions "Tested it the way people will actually use it", "Wrote it in their own voice", "Helped a classmate see their work more clearly" |
| Week 4 | What happens when someone else holds it? | Get the app onto a device you did not build it on, and read one honest number | The install link (store, test track, or direct share) and what that person did first | The other person's device, or their words | A further platform adds a level when people can get it there; recognitions "Got it onto someone else's device", "Asked for feedback and used it" |
| Week 5 | What did I learn that the next builder should not have to? | Build one feature you wanted from your own use; write a skill and one value with the decision it changed; fill in HUMAN-SHAPED.md | The feature; the DECISIONS.md entry; the skill file; the declaration | The final showing, guests welcome | Recognitions "Shared what they learned", "Credited the people and tools behind it", "Found whose work they are building on" |

Every week also asks for the same small things, which are evidence of
the thinking rather than the app:

- **The disclosure lines** in the note (role, essential work, insight,
  growth edge). They stay in the repository, which is already the
  credential's evidence, so the student decides what to keep there.
- **The private check,** "Am I Building or Bypassing My Thinking?", done
  alone and never handed in. It is for the student, the way the rubric
  says: "This is for YOUR learning, not evaluation"
  (`docs/implementation-tools/thinking_engagement_rubrics.md:42`).
- **The two questions at the end of each session** (the week's question
  and "What is still muddy?", `COURSE.md:203-212`), read only by the
  teacher.

### Two changes worth making to the credential

These are recommendations for Ben, not built.

1. **Let the student add their declaration as evidence.** HUMAN-SHAPED.md
   is the clearest single page of what a student learned, and it is
   already in their repository. Naming it as its own Evidence item (genre
   "Declaration") would let a reader find it without opening the whole
   repository. The student chooses, per principle 9 above.
2. **Name each level's claim in the student's own words.** Open Badges
   Evidence has a narrative. Letting the student write one or two
   sentences for it ("what this app does for the people it is for")
   would put their voice on the credential, which is principle 13 of the
   human-shaped principles (`docs/human-shaped/HUMAN-SHAPED-template.md:193`).

## (d) When someone is stuck

The site's notes already cover the moves around a session: a stuck line
in the chat as people arrive, the group working one stuck moment with
permission, a room open while everyone starts the week, the teacher
reading the "muddy" answers, and a private note within two days of a
missed session (`COURSE.md:158-165`, `:198-202`, and `:248-255`). What
is missing is the ladder a student climbs on their own, between
sessions, before any of that.

The research on help-seeking draws one useful line. **Instrumental** help
seeking asks for hints or explanations that make the person more able
next time, and is linked to better achievement; **executive** help
seeking asks for the answer to finish the task, and is linked to worse
(Karabenick and Newman; Karabenick and Dembo 2011, checked through
summaries). Studies of novices working with AI find the same line from
the other side. In Anthropic's randomized study of 52 mostly junior
engineers learning a new library, the group with AI scored 50 percent on
the comprehension quiz and the group without scored 67 percent, and the
people who kept their understanding were the ones who "asked the AI
assistant follow-up questions to improve understanding" or "only asked
conceptual questions" (Shen and Tamkin 2026, checked). Generative AI can
also widen the gap between stronger and weaker novices, because the
weaker ones accept output they do not understand (Prather et al. 2024,
checked through the abstract). And when students build a web app with an
agent, most of what they send is testing and debugging, and beginners'
prompts carry much less context about the app than advanced students'
do (Geng et al. 2025, checked).

So, the ladder is built to keep help instrumental and to put context in
the prompt.

### The ladder, between sessions

1. **Name the kind of stuck.** Four kinds, because each has a different
   way out: *the tools* (an account, a build, a device), *the loop* (the
   agent keeps trying and nothing changes), *the decision* (you do not
   know what you want the app to do), and *life* (no time or no energy
   this week).
2. **Write three lines in the note.** What you were trying to do, what
   you expected to see, and what you saw instead. This is the Spec's
   first checkpoint ("What have you tried so far? What specific part is
   challenging you?", `docs/overview.md:264`), and it is also the context
   a good prompt needs.
3. **Ask the agent for a way to understand it, not for the fix.** Paste
   the three lines and ask what it thinks is happening and what to check
   first. If the agent has tried the same thing twice with no change,
   stop the loop: sending the error back a third time is executive help
   with extra steps.
4. **Look on the device, and look at the last thing that worked.** Most
   tool and loop problems end here, because the history shows what
   changed.
5. **Bring it to your trio.** Post the three lines in the cohort's
   thread or to your two partners. A partner's question ("what did you
   expect?") often does what the agent could not.
6. **Bring it to the teacher.** Office hours, the room open during
   Start, or a private note. A decision or life stuck usually belongs
   here first, because no agent can tell you what your app should be or
   whether this week is the week.

**Time boxes, not rules.** About twenty minutes on steps 2 to 4 before
step 5 is a good default, and the student moves it. Productive struggle
is worth something, and an evening of the same error is not.

### In the live session

- **Arrive:** a stuck line in the chat is welcome, and the teacher asks
  privately whether it can be the group's stuck moment (`COURSE.md:163-165`).
- **While groups work:** a trio can ask for the teacher from their room
  without stopping their work, and the teacher visits, says so, and asks
  one of the Spec's curious questions rather than fixing it: "Tell me
  more about your thinking process here..." or "How did you approach this
  problem when you first saw it?"
  (`docs/implementation-tools/thinking_engagement_rubrics.md:128-130`).
- **Read one real prompt together:** from week 3 on, the situation is a
  classmate's real stuck moment, shared with their permission
  (`COURSE.md:193-195`).
- **After:** the teacher reads every "What is still muddy?" before the
  next session and says what changed because of it (`COURSE.md:208-212`).

### A stuck library that grows

Each cohort's stuck moments, with the people's permission and their
names only if they want them, become a short "If you get stuck" entry on
the lesson they came from (step 10 of the template). Over cohorts, each
lesson collects the three or four stuck moments it actually produces,
with what got people out. That is the same move the course already makes
when a cohort sends one lesson back to the template (`COURSE.md:315-325`),
done one stuck moment at a time.

## What this note did not settle

- **How much question time a novice can carry.** Five minutes of
  question-asking before every lesson may be too much in week 1, when
  setup is already heavy. Trying it in the first cohort is the honest
  test.
- **Whether self-judged "ready" holds up for beginners.** Andrade's
  review supports formative self-assessment with training, not
  self-grading without it, which is why the first practice uses an app
  that belongs to nobody.
- **The study nobody has done.** No study found here follows
  non-programmers shipping a real app with an agent over several weeks;
  the closest are a nine-hour hackathon (Gama et al. 2026) and a
  think-aloud study (Geng et al. 2025). The course should say so, as
  week 1's opening already does.

Be ready to read the template against one real stage, and to say what
you would cut.

## Sources

The Educational Model Spec (Ben Wilkoff), read in full for this note:
`README.md`, `docs/overview.md`, and
`docs/implementation-tools/` (`thinking_engagement_rubrics.md`,
`ai_disclosure_protocol.md`, `ai_guardrails_prompt.md`), at
https://github.com/bhwilkoff/educational-model-spec.

This template: `COURSE.md`, `docs/teaching/`, `docs/path/` (every stage's
"Be ready to..." line), `docs/human-shaped/HUMAN-SHAPED-template.md`.
humanshaped.org's `site` branch: `assets/credential-lib.js`,
`assets/recognition-lib.js`, and the research notes
`assessment-and-credentials-notes.md`,
`facilitation-assessment-social-learning-notes.md`, and
`pedagogy-and-showcase-notes.md`.

Outside sources:

- Right Question Institute, "What is the QFT?" https://rightquestion.org/what-is-the-qft/ (checked)
- PBLWorks, "Gold Standard PBL: Essential Project Design Elements." https://www.pblworks.org/what-is-pbl/gold-standard-project-design (checked); and "Gold Standard PBL: Challenging Problem or Question." https://my.pblworks.org/resource/blog/gold_standard_pbl_challenging_problem_or_question (checked)
- Sinha, T., and Kapur, M. (2021). When Problem Solving Followed by Instruction Works: Evidence for Productive Failure. *Review of Educational Research* 91(5), 761-798. https://journals.sagepub.com/doi/10.3102/00346543211019105 (checked through the abstract and summaries)
- Kalyuga, S., Ayres, P., Chandler, P., and Sweller, J. (2003). The Expertise Reversal Effect. *Educational Psychologist* 38(1), 23-31. https://www.researchgate.net/publication/48829036_The_Expertise_Reversal_Effect (from summaries, not the paper)
- Andrade, H. (2019). A Critical Review of Research on Student Self-Assessment. *Frontiers in Education* 4:87. https://doi.org/10.3389/feduc.2019.00087 (checked)
- Mislevy, R. J., Steinberg, L. S., and Almond, R. G. (2003). On the Structure of Educational Assessments. *Measurement* 1(1), 3-62; introduced in Mislevy, Almond, and Lukas, A Brief Introduction to Evidence-Centered Design, CSE Report 632. https://www.researchgate.net/publication/234591969_A_Brief_Introduction_to_Evidence-Centered_Design_CSE_Report_632 and CRESST Report 800, https://files.eric.ed.gov/fulltext/ED522835.pdf (checked through summaries)
- Darling-Hammond, L., and Adamson, F. (2014). *Beyond the Bubble Test: How Performance Assessments Support 21st Century Learning.* Jossey-Bass. https://onlinelibrary.wiley.com/doi/book/10.1002/9781119210863 (from the publisher's description)
- 1EdTech, Open Badges Specification 3.0, Evidence (section B.1.9). https://www.imsglobal.org/spec/ob/v3p0/ (checked in part)
- Karabenick, S. A., and Dembo, M. H. (2011). Understanding and Facilitating Self-Regulated Help Seeking. *New Directions for Teaching and Learning* 126. https://ssrlsig.org/wp-content/uploads/2018/01/karabenick-dembo-2011-understanding-and-facilitating-self-reg-help-seeking.pdf; and Karabenick, S. A., and Newman, R. S. (eds.), *Help Seeking in Academic Settings.* (checked through summaries)
- Shen and Tamkin (2026). How AI assistance impacts the formation of coding skills. Anthropic. https://www.anthropic.com/research/AI-assistance-coding-skills (checked)
- Prather, J., et al. (2024). The Widening Gap: The Benefits and Harms of Generative AI for Novice Programmers. ICER '24. https://doi.org/10.1145/3632620.3671116 and https://arxiv.org/abs/2405.17739 (checked through the abstract)
- Geng, F., Shah, A., Li, H., Mulla, N., Swanson, S., Soosai Raj, G., Zingaro, D., and Porter, L. (2025). Exploring Student-AI Interactions in Vibe Coding. https://arxiv.org/abs/2507.22614 (checked)
- Gama, K., Calegario, F., Jackson, V., Nolte, A., Morais, L. A., and Garcia, V. (2026). "Can you feel the vibes?": An exploration of novice programmer engagement with vibe coding. ICSE SEET 2026. https://arxiv.org/abs/2512.02750 (checked)
- Kazemitabaar, M., et al. (2024). CodeAid: Evaluating a Classroom Deployment of an LLM-based Programming Assistant that Balances Student and Educator Needs. CHI '24. https://arxiv.org/abs/2401.11314 (from the abstract; not cited above, kept for the next pass on guarded agents)
