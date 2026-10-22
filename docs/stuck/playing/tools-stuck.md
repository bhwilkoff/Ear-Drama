# The tools themselves are stuck

*Written by Claude, awaiting Ben's review.*

Sometimes the problem is not your app at all: an account will not sign
in, a build fails before anything runs, the device will not install it,
or you started in a tool that cannot do what the work needs. The quiet
sixth pattern in my record is starting in the wrong tool. Archive Watch
began in the desktop app and on my phone, and moved to the command line
because "you can do things that the desktop app cannot" (prompt archive,
Archive Watch, April 18, 2026), and BOBA Playbook began in another tool
and moved into this template on its first day (BOBA-Playbook 35b190d,
then 54404da), both read in
[research note 01](../../research/curriculum/01-mining-bens-process.md#where-i-got-stuck-and-what-got-me-out).

**Ask yourself first.** What is the last thing that worked, and what
changed between then and now?

**Try this.** Let the history answer before anyone guesses:

> Something in the tools is stuck, not the app. Here is exactly what I
> did and the message I got. Look at what changed since the last
> version that worked, tell me what you think broke, and tell me which
> step in it needs me (a sign-in, a setting, a button) rather than you.

If the agent says a step needs you, do that one step yourself and hand
it back, which is the move in
[let it drive, and do the one human step](../../path/talking-to-your-agent.md#let-it-drive-and-do-the-one-human-step).
If the work keeps needing something your tool cannot do, move to the
tool where the work will finish, early rather than late.

**From my apps.** Both moves above happened in the first two days of
an app, which is exactly why a cohort should start where the work will
finish.

**In each tool.** In Claude Code, the desktop app is the gentlest start,
and the terminal can do more. In Antigravity, start with the sandboxed
default setting, and if the agent is blocked, check whether the action
needs your permission ([research note 03](../../research/curriculum/03-claude-code-and-antigravity.md)).
On the open path, the most common silent problem is Ollama's default
context window, which "silently discards context that exceeds the
window," so raise it before blaming the model
([research note 04](../../research/curriculum/04-open-pathway.md), quoting [Aider's Ollama page](https://aider.chat/docs/llms/ollama.html)).

**Go deeper.** Ask the agent to explain the error message line by line,
so you can tell an account problem from a build problem next time.

**Who to ask.** Your teacher, sooner than for other kinds of stuck,
because accounts, stores, and devices often need a person who has been
through that exact screen.

The last thing that worked knows the way back.
