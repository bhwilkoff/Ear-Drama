# The agent fixes what I cannot see

*Written by Claude, awaiting Ben's review.*

The agent says it is done, you look at your app, and nothing is
different. This is the most common stuck moment in my whole record, and
I have typed some version of it hundreds of times: "Hmm... I don't see
the new card-focused approach" (prompt archive, Bsky Dreams, March 11,
2026) and "I don't see any changes to the questions on the web app"
(prompt archive, Tidbits Trivia, June 17, 2026), both read in
[research note 01](../../research/curriculum/01-mining-bens-process.md#where-i-got-stuck-and-what-got-me-out).

**Ask yourself first.** Did I say what I saw, where on the screen, and
on which device?

**Try this.** Take a screenshot of what you actually see, and give the
agent all three parts, which is the move in
[talking to your agent](../../path/talking-to-your-agent.md#say-what-you-see-where-on-which-device):

> On my phone, in Safari, on the questions screen, I still see the old
> layout. Here is a screenshot. Before you change anything else, tell
> me how we can be sure the version I am looking at is the newest one.

Then look on the device the way the agent suggests: close the app or the
tab completely and open it again, and check whether the change reached
the place the app actually runs from (the live web address, not only
the agent's own copy).

**From my apps.** In Tidbits Trivia the fix had been made all along,
and my phone was simply showing an old copy the browser had saved, so
what got me out was not another change to the questions but a change to
how the app updates itself ("Fix stale-cache," Tidbits-Trivia 79e1fd6,
read in [research note 01](../../research/curriculum/01-mining-bens-process.md#where-i-got-stuck-and-what-got-me-out)).

**In each tool.** In Claude Code, the desktop app's preview and Claude
in Chrome let the agent look at the page itself, and its own docs ask
for "a screenshot of the result" as evidence. Antigravity can drive its
own browser and save screenshots as artifacts you can comment on
([research note 03](../../research/curriculum/03-claude-code-and-antigravity.md)).
On the open path the model cannot see pictures, so you are the eyes:
describe what you see in words, and paste any error text
([research note 04](../../research/curriculum/04-open-pathway.md)).

**Go deeper.** Ask the agent to explain where your app's files are
served from and how a browser decides to keep an old copy, so the next
time you can tell a cached screen from an unfinished fix yourself.

**Who to ask.** Your trio, with your screenshot: open the app on their
device too, because if they see the change and you do not, the problem
is your copy, not the code.

Screenshot, three parts, then the question.
