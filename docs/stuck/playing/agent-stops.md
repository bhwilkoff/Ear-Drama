# The agent keeps stopping

*Written by Claude, awaiting Ben's review.*

You gave the agent a list of things to do, it did the first one, said it
was finished, and waited. I have typed "you clearly have stopped again"
more than once (prompt archive, Tidbits Trivia, June 20, 2026), and the
same complaint shows up in Archive Watch, where I finally asked for "a
loop to continue tasks so that you don't just stop when you finish the
first set" (prompt archive, Archive Watch, June 3, 2026), both read in
[research note 01](../../research/curriculum/01-mining-bens-process.md#10-living-with-it-and-letting-the-agent-keep-going).

**Ask yourself first.** Is the next step written down somewhere the
agent can read, or only in my head?

**Try this.** Make the agent keep the list instead of you, and make it
write a handoff before every fresh session, which are the moves in
[talking to your agent](../../path/talking-to-your-agent.md#make-it-write-things-down):

> Write the remaining work as a numbered list in our running note, with
> what done looks like for each one. Then work through it in order,
> checking each one on the device before you move on, and tell me only
> when you need a decision from me or the list is empty.

When a session gets long, ask for a handoff before you start a new one:
"Write down where we are and what is next, so a fresh session can pick
up from here."

**From my apps.** Archive Watch made 17 commits in May and 2,216 in
September, and the difference was a written backlog the agent worked
through, plus handoff documents before every reset ("Docs: compaction
handoff," Tidbits-Trivia a9502f1, June 17, 2026), read in
[research note 01](../../research/curriculum/01-mining-bens-process.md#10-living-with-it-and-letting-the-agent-keep-going).

**In each tool.** In Claude Code a fresh session is `/clear`, and the
running note and `AGENTS.md` carry what matters across it. Antigravity
reads the same files and can `/fork` a session. On the open path, small
models hold much less at once (Ollama's default is a 2,000-token window
unless you raise it), so keep the list short and start fresh often
([research note 04](../../research/curriculum/04-open-pathway.md)).

**Go deeper.** Read [put big work on a loop](../../path/talking-to-your-agent.md#put-big-work-on-a-loop-and-hold-it-to-real-work)
and notice what it asks you to keep checking yourself.

**Who to ask.** Your trio, because someone who has gotten an agent to
keep going usually has a sentence that worked for them.

Write the list where the agent can read it.
