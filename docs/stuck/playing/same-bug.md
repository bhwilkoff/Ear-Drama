# The same bug keeps coming back

*Written by Claude, awaiting Ben's review.*

You report a bug, the agent fixes it, you look again, and it is back, or
a cousin of it is. On Archive Watch's worst day, the agent and I went
back and forth over the Apple TV's focus all afternoon ("DetailView:
stop fighting the tvOS focus engine," Archive-Watch ee3ad36, April 19,
2026), and what ended it was not one more fix.

**Ask yourself first.** Has the agent tried the same kind of fix twice,
with no change I can see?

**Try this.** If the answer is yes, stop the loop instead of sending
the error back a third time. Write your three lines (what you tried,
what you expected, what you saw), then ask for a check rather than a
fix:

> We have tried this twice and it keeps coming back. Stop fixing it for
> a minute. Build me a way to check whether this bug is present, so we
> both know for sure when it is gone. Then write down what we learned
> in a page you will read next time.

When the check exists, run it on the device yourself, and only then ask
for the next fix.

**From my apps.** What ended Archive Watch's focus loop was two tools
and a document: a visual validator, a layout checker, and a playbook
that remembers what the Apple TV needs (Archive-Watch ddf6393, fcf5317,
and 2c0be46, all April 19, 2026, read in
[research note 01](../../research/curriculum/01-mining-bens-process.md#8-seeing-it-work-with-something-other-than-the-agents-word)).
The word "audit" appears in 225 commit messages across my four apps,
because a check outlasts a fix.

**In each tool.** In Claude Code, after two failed corrections start a
clean session with a better prompt (`/clear`), because "a clean session
with a better prompt almost always outperforms a long session with
accumulated corrections," and you can rewind with `Esc` twice or
`/rewind`. In Antigravity, `/rewind` (also `/undo`) rolls back, and
`/fork` lets you try a different approach without losing the first
([research note 03](../../research/curriculum/03-claude-code-and-antigravity.md#small-steps-and-getting-back)).
With Aider on the open path, `/undo` takes back the last change it made
and `/clear` starts the conversation fresh
([Aider, in-chat commands](https://aider.chat/docs/usage/commands.html)).

**Go deeper.** Ask the agent what the check actually tests, and what it
would miss. A check you understand is evidence you can show someone.

**Who to ask.** Your trio, after the check exists, because a partner
playing with your app often finds the case the check missed.

Stop at two, then build the check.
