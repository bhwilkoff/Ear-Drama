# It works, and it still feels wrong

*Written by Claude, awaiting Ben's review.*

Nothing is broken, the agent says it is done, and every time you use the
app something about it bothers you. This is the hardest kind of playing
stuck, because there is no error to paste. In Tidbits Trivia's first
week, the questions all worked and the game still felt off, until I
noticed that many questions gave their own answers away, and showed the
agent four screenshots of it (Tidbits Trivia, June 17, 2026, read in
[research note 01](../../research/curriculum/01-mining-bens-process.md#where-i-got-stuck-and-what-got-me-out)).

**Ask yourself first.** Can I point to the exact moment it feels wrong,
and could I count how often that moment happens?

**Try this.** Use the app for ten minutes and screenshot each moment
that bothers you, then ask the agent to turn the feeling into a number:

> Here are screenshots of moments that feel wrong to me. Describe what
> they have in common. Then measure how often that happens across the
> whole app, and tell me the number before you change anything.

Once there is a number, decide in your own words what "better" means,
and ask for that. Often the answer is fewer, better things rather than
more of them.

**From my apps.** The number in Tidbits Trivia was the share of
questions that leaked their own answers, and the fix took it from 48
percent to zero ("Fix broken question construction: answer-leak
(48%→0%)," Tidbits-Trivia 718cd2a). Two days later I chose quality over
quantity on purpose: "Regenerate corpus with reworked summary path:
10,776 → 4,743 (quality over quantity)" (Tidbits-Trivia 3a3573d, June
19, 2026), both read in
[research note 01](../../research/curriculum/01-mining-bens-process.md#3-real-data-first).

**In each tool.** The same in all three, except that on the open path
you describe each screenshot in words, because the model cannot see
pictures ([research note 04](../../research/curriculum/04-open-pathway.md)).

**Go deeper.** Ask for a [human-shaped review](../../path/talking-to-your-agent.md#ask-for-a-human-shaped-review)
and see whether the feeling you could not name matches a principle it
flags.

**Who to ask.** One of the people the app is for, because if it feels
wrong to them too, they will usually tell you why in a sentence.

A feeling, then a number, then fewer and better.
