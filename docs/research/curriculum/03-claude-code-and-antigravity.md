# Claude Code and Antigravity, for someone who has never built software

*Curriculum research 3 of 5, done October 7, 2026, for the cohort
curriculum Ben asked for that day. Every claim has its source beside it,
and the official documentation comes first. Anything I could not confirm
is marked **(unverified)**. This page builds on
`docs/research/gemini-and-other-agents.md` (October 3), which covers how
each agent reads `AGENTS.md`, finds skills, and runs MCP servers, so
those parts are summarized here rather than repeated.*

*Checked on Ben's Mac without launching or signing in to anything:
Antigravity 2.19.1 and the Claude desktop app are installed in
`/Applications`, the `claude` command-line tool is 2.1.292, and the
`agy` command-line tool is not installed.*

## Why this page exists

I want a student in a cohort to be able to open either agent on the
first night, say what they want in their own words, see something on
their own device, and know how to get back to where they were when it
goes wrong. The course says students bring their own AI and that it
never requires one vendor (humanshaped.org `DECISIONS.md`, "Students
bring their own AI"), so whatever the path teaches has to work in Claude
Code and in Google's Antigravity, and say plainly where they differ.

**Both tools now teach the same loop: plan, build, check.**

That is good news for a course, because the lesson can be the loop and
the tool can be a footnote. The differences that matter for a novice
are cost, where the work happens, and how you undo.

## Claude Code

### Getting it running

Claude Code runs on macOS 13 or later, Windows 10 (1809) or later, and
recent Ubuntu, Debian, and Alpine, with 4 GB of memory and an internet
connection ([advanced setup](https://code.claude.com/docs/en/setup)).
There are two ways in, and a novice should take the first:

1. **The Claude desktop app's Code tab.** It "gives you Claude Code with a
   graphical interface, so you can ask Claude to work on the code in a
   folder on your computer and review its changes without using a
   terminal," and it needs no Node.js or separate install
   ([desktop quickstart](https://code.claude.com/docs/en/desktop-quickstart)).
   You sign in, click **Code**, choose **Local**, click **Select folder**,
   and type what you want. It also offers **Cloud**, which keeps running
   after you close the app, and **WSL** on Windows.
2. **The terminal.** `curl -fsSL https://claude.ai/install.sh | bash` on a
   Mac, or `irm https://claude.ai/install.ps1 | iex` in Windows
   PowerShell, then `claude` in the project folder. On Windows, Git for
   Windows is recommended so Claude can use Bash, and without it Claude
   uses PowerShell instead ([advanced setup](https://code.claude.com/docs/en/setup)).
   Anthropic also has a [terminal guide](https://code.claude.com/docs/en/terminal-guide)
   for people who have never opened one.

**Chromebooks and tablets.** No Chromebook install is documented. The
supported Linux list suggests a Chromebook's Linux environment (Debian)
would work **(unverified)**. On a phone or iPad, the Claude app "is a
client for Claude Code sessions rather than a place where code runs":
its **Code** tab reaches cloud sessions, which run on Anthropic's
machines from a GitHub repository, and Remote Control, which drives a
session on your own computer ([Claude Code on mobile](https://code.claude.com/docs/en/mobile)).
So a student with only a Chromebook or an iPad can build through cloud
sessions, but not with files on that device.

### What it costs

Claude Code "requires a Pro, Max, Team, Enterprise, or Console account.
The free claude.ai plan does not include Claude Code access"
([advanced setup](https://code.claude.com/docs/en/setup)). Pro is $20 a
month, or $17 a month billed yearly, and Max is $100 or $200 a month
([Claude pricing](https://claude.com/pricing); the $200 figure for Max
20x is from [SaaS Price Hub](https://saaspricehub.io/ai-products/claude-max-20x),
since the pricing page summary I read did not state it plainly). There
is no free way into Claude Code, which is the cost of this choice and
the reason the course names a second route.

### The loop

Anthropic's own best-practices page is built on one constraint and one
loop. The constraint: "Claude's context window fills up fast, and
performance degrades as it fills." The loop is four phases, **Explore,
Plan, Implement, Commit**, with plan mode keeping the first two from
touching any file ([best practices](https://code.claude.com/docs/en/best-practices)).
It also says when to skip the plan: "If you could describe the diff in
one sentence, skip the plan."

The line I would put in front of every student is the first tip on that
page: "Give Claude a check it can run: tests, a build, a screenshot to
compare. It's the difference between a session you watch and one you
walk away from." Without one, "you become the verification loop."

### Where the instructions live

`CLAUDE.md` is read "at the start of every conversation," and the advice
is to keep it short: "For each line, ask: *Would removing this cause
Claude to make mistakes?* If not, cut it. Bloated CLAUDE.md files cause
Claude to ignore your actual instructions!" Knowledge that only matters
sometimes belongs in skills, which "Claude loads on demand"
([best practices](https://code.claude.com/docs/en/best-practices)).
Claude Code reads `AGENTS.md` only when there is no `CLAUDE.md`, and a
`CLAUDE.md` that starts with `@AGENTS.md` loads it once
([memory](https://code.claude.com/docs/en/memory), via the October 3
research page). Skills live in `.claude/skills/`, and a student can call
one by name with `/skill-name` ([skills](https://code.claude.com/docs/en/skills)).

### Permissions and safety

Claude Code has named permission modes. `default` (shown as **Manual**)
runs only reads without asking, `acceptEdits` also lets file edits and
common file commands through, `plan` changes nothing, and **auto** has
"a second model, the classifier," review actions instead of you. From
v2.1.283, auto is the starting mode for terminal and VS Code sessions
([permission modes](https://code.claude.com/docs/en/permission-modes)).
In the desktop app the same choices are **Auto, Manual, Accept edits,
and Plan**, in a selector next to the send button ([desktop quickstart](https://code.claude.com/docs/en/desktop-quickstart)).
`Shift+Tab` cycles them in the terminal ([best practices](https://code.claude.com/docs/en/best-practices)).

For a first session I would start a novice in **Manual**, so they see
each change as a diff and press Accept, and move them to Auto once they
know what a diff is. The cost is tedium, which the docs name directly:
"After the tenth approval you're clicking through rather than
reviewing."

### Checking the work

The desktop app's **Browser** pane opens the running app when the dev
server starts, and Claude "can view the running app, test endpoints,
inspect logs, and iterate on what it sees" ([desktop quickstart](https://code.claude.com/docs/en/desktop-quickstart)).
In the terminal, Claude in Chrome lets it use the student's own browser
([best practices](https://code.claude.com/docs/en/best-practices) links
it as the "browser screenshot" check). The docs ask for evidence over
assertion: "the test output, the command it ran and what it returned,
or a screenshot of the result."

### Small steps, and getting back

- **Stop** with `Esc` (or the stop button in the app), and redirect.
- **Rewind** with `Esc` twice or `/rewind`, which restores the
  conversation, the code, or both to any earlier prompt. "Every prompt
  you send that starts a turn creates a checkpoint."
- **The warning a student needs**: "Checkpoints only track changes made
  through Claude's file editing tools. Changes made through Bash
  commands or external processes are not captured. This isn't a
  replacement for git."
- **Start fresh** with `/clear` after two failed corrections: "A clean
  session with a better prompt almost always outperforms a long session
  with accumulated corrections."

All four are from [best practices](https://code.claude.com/docs/en/best-practices).

### Privacy

For Free, Pro, and Max accounts, "We will train new models using data
from Free, Pro, and Max accounts when this setting is on (including when
you use Claude Code from these accounts)." With the setting on, data is
kept five years; with it off, 30 days, and it can be changed at
[claude.ai/settings/data-privacy-controls](https://claude.ai/settings/data-privacy-controls).
Transcripts sit on the student's own computer in plain text under
`~/.claude/projects/` for 30 days, and anything sent with `/feedback` is
kept five years. Usage metrics "never include your code, prompts, or
file paths," and `DISABLE_TELEMETRY=1` turns them off
([data usage](https://code.claude.com/docs/en/data-usage)).

A student should make that choice on the first night, on purpose, and
the setup stage should show them where.

### Accessibility

Claude Code has a screen reader mode, `claude --ax-screen-reader` (or the
`axScreenReader` setting, v2.1.181 and later), which replaces the visual
terminal with "plain, linear text that screen readers (like VoiceOver
and NVDA) can follow" (announced by [@ClaudeDevs](https://x.com/ClaudeDevs/status/2079315549163778366);
details from [AI Catchup](https://aicatchup.com/news/claude-code-screen-reader-mode-accessibility)).
I could not find this on code.claude.com, so the setting name is
**(unverified against the official docs)**. The desktop app's
screen reader support is not documented **(unverified)**.

## Antigravity

### Getting it running

Antigravity 2.0 runs on macOS 12 or later, Windows 10 (64-bit), Linux,
and Googlebook ([getting started](https://antigravity.google/docs/getting-started/)).
It comes as three surfaces: the **Antigravity 2.0 Hub** desktop app
"with conversation management," the `agy` command-line tool, and the
**Antigravity IDE**. The CLI installs with
`curl -fsSL https://antigravity.google/cli/install.sh | bash` on a Mac
or `irm https://antigravity.google/cli/install.ps1 | iex` in Windows
PowerShell, and first launch asks for a color scheme, a rendering mode,
and "workspace trust" ([getting started](https://antigravity.google/docs/getting-started/)).
A novice should start in the desktop app, which is what the template's
setup stage already says (`docs/path/setup.md`).

**Chromebooks and tablets.** Googlebook is listed. Whether that covers
ordinary Chromebooks, and whether the web version works on a tablet, is
**(unverified)**, as it was on October 3.

### What it costs

The **Individual** plan is $0 with "Access to a variety of agent models,"
unlimited tab completions, and "basic weekly rate limits"; Google AI Pro
and Ultra add "more rate limits" and a credit pool
([pricing](https://antigravity.google/pricing)). Google AI Pro is $19.99
a month in the US ([Google AI plans](https://gemini.google/subscriptions/),
via the October 3 page). Google does not publish the free limit in
numbers, and the free terms changed twice this year (October 3 page), so
the course should keep labeling it "may change."

### The loop

Google's CLI best practices name the same loop in their own words:
"Ensure your workspace directory has a test suite ready" before asking
for changes, then **explore, plan, execute**, approving the plan before
anything is written ([CLI best practices](https://antigravity.google/docs/cli/best-practices/)).
`/plan` makes an "Implementation Plan artifact" with "clear task
breakdowns and verification checkpoints," which the student can comment
on inline, line by line, before pressing **Proceed**. Google suggests it
for "ambiguous requirements" and "high-risk changes"
([/plan](https://antigravity.google/docs/plan/)).

Plans, diffs, screenshots, and browser recordings are all **artifacts**
a student can comment on ([features](https://antigravity.google/docs/features/)),
which is closer to how a teacher gives feedback than anything in Claude
Code today.

### Where the instructions live

Antigravity reads `AGENTS.md`, `GEMINI.md`, and `.agents/rules/*.md`, cuts
any single rule file at 24,000 bytes, and reads skills from
`.agents/skills/<folder>/`, callable as `/<skill-name>`
([rules](https://antigravity.google/docs/rules/),
[skills](https://antigravity.google/docs/skills/), via the October 3
page). `/learn` "distills session feedback and corrections into
persistent Rules or Skills" ([slash commands](https://antigravity.google/docs/slash-commands/)),
which is Antigravity's version of Claude's memory, and it writes into the
repository, where a student will see it.

### Permissions and safety

There are three presets ([permissions](https://antigravity.google/docs/permissions/)):

- **Default**: commands run in an "isolated Terminal sandbox" with the
  workspace and temp folders and no network, and ask outside it.
- **Request Review**: no sandbox, and every terminal command asks.
- **Turbo**: no sandbox, any command, the whole file system, and the web.

Rules are checked Deny, then Ask, then Allow. The docs recommend
**Default** for beginners, adding Allow rules only for commands the
student uses often, like `command(git)`. Separately, the **artifact
review** policy decides whether a plan waits for approval, and "Request
review (recommended)" is the one a student should keep
([agent settings](https://antigravity.google/docs/agent-settings/)).

### Checking the work

`/browser` starts "a sandboxed browser subagent" that can "open, read,
and actuate a local Chrome browser," take screenshots, and record its
actions as WebM videos, all saved as artifacts the student can comment
on. It runs "inside a completely separate Chrome profile to protect your
personal data" ([browser](https://antigravity.google/docs/ide/browser/),
[browser recordings](https://antigravity.google/docs/ide/browser-recordings/),
[screenshots](https://antigravity.google/docs/screenshots/)). So it
cannot see a page the student is signed in to in their own Chrome, which
is the one step in `talking-to-your-agent.md` that works differently.
Whether it needs Google Chrome installed separately is **(unverified)**.

### Small steps, and getting back

`/rewind`, also called `/undo`, "rolls back conversation history to a
previous checkpoint," and since v2.19.1 (September 30, 2026) the undo
dialog can revert only the conversation and leave the files
([changelog](https://antigravity.google/docs/changelog/),
[CLI best practices](https://antigravity.google/docs/cli/best-practices/)).
`/fork` branches the session to try something without losing the main
one. A **VCS panel** shows uncommitted changes and branch diffs
([features](https://antigravity.google/docs/features/)), and **worktree
mode** runs the agent "in an isolated Git worktree" ([getting started](https://antigravity.google/docs/getting-started/)).
Whether rewind restores file changes made by terminal commands is not
documented **(unverified)**, so git is the safety net here too.

### Privacy

Antigravity has an **Enable Telemetry** toggle under **Account**: "When
toggled on, Antigravity collects interactions for use in evaluating,
developing, and improving Antigravity" ([settings](https://antigravity.google/docs/settings/)).
People on Google's own forum report that this toggle is not the same as
model training, and that a personal account's prompts and code may be
used for training unless **Gemini Apps Activity** is also turned off
([Google AI Developers Forum](https://discuss.ai.google.dev/t/antigravity-data-training-opt-out/125236);
[a reader's walk through the terms](https://note.com/enushi817/n/n8d810b756dc2?hl=en)).
I could not find Google stating this plainly, so how training works on
the Individual plan is **(unverified)**, and the honest instruction is
"turn off both."

### Accessibility

Antigravity has `/voice` dictation, "Speak naturally without worrying
about pauses or perfect phrasing" ([features](https://antigravity.google/docs/features/)),
which helps a student who would rather talk than type. It has themes
and custom keybindings, and screen reader support is not mentioned in
the settings docs ([settings](https://antigravity.google/docs/settings/))
**(unverified)**.

## The two, side by side

| | Claude Code | Antigravity |
|---|---|---|
| Free to start | No (Pro, $20 a month) | Yes (Individual, weekly limit not published) |
| Novice surface | Desktop app, Code tab | Antigravity 2.0 Hub |
| Phone or tablet | Claude app drives cloud sessions or your computer | **(unverified)** |
| Plan first | Plan mode (`Shift+Tab`) | `/plan`, with inline comments |
| Instructions | `CLAUDE.md` (imports `AGENTS.md`) | `AGENTS.md`, `GEMINI.md`, `.agents/rules/` |
| Skills | `.claude/skills/` | `.agents/skills/` |
| Safe starting mode | Manual, then Auto | Default (sandboxed) with Request review |
| Check in a browser | Desktop Browser pane, or Claude in Chrome on your own browser | `/browser`, a separate Chrome profile |
| Undo | `Esc Esc` or `/rewind` (Claude's edits only) | `/rewind` or `/undo`, `/fork` |
| Long work | `/goal`, `/loop` | `/goal`, `/schedule` |
| Training on your data | Off if you turn it off; 30 days kept | Turn off telemetry **and** Gemini Apps Activity **(unverified)** |
| Screen reader | `--ax-screen-reader` **(unverified in docs)** | not documented |

The loop is the same, so the course can teach **plan, build, check, and
commit** once, and give each step one line per tool.

## What should change in the template

1. **`docs/path/setup.md`.** Add a privacy step before the first prompt:
   where each tool's training setting lives, and a sentence on what is
   kept and for how long. Say that Claude Code starts in Auto from
   v2.1.283 and suggest Manual for the first night. For a student on a
   Chromebook or iPad, name Claude's cloud sessions as the route, and
   say the Antigravity answer is not known yet.
2. **`docs/path/08-working-with-ai.md`.** Add a short section on the
   check, quoting Anthropic's line that a check is "the difference
   between a session you watch and one you walk away from." Put
   "checkpoints are not git" in plain words, with each tool's undo.
3. **`docs/path/talking-to-your-agent.md`.** The section "Research first,
   then build" should name the plan step in both tools (plan mode,
   `/plan`). "Let it drive, and do the one human step" already has the
   Antigravity note about the separate browser. Add `/fork` beside
   rewinding, and add "after two failed corrections, start fresh" with
   its source.
4. **`AGENTS.md`.** It already stays under 24,000 bytes for Antigravity.
   Add one line under "How we collaborate" telling any agent to show
   evidence (the command and what it returned, or a screenshot) rather
   than saying it is done, since both tools' docs ask for it.
5. **`CLAUDE.md`.** No change. It is already the short import Anthropic
   recommends.
6. **The `human-shaped-review` skill.** It already says it works in any
   agent and is linked into `.agents/skills/`. Add one line telling it,
   in Antigravity, to return the review as an artifact the student can
   comment on, and in Claude Code to write the review file and show its
   path. Confirming that Antigravity follows the symlink is still open
   from October 3 **(unverified)**.

## Screenshots to capture on Ben's Mac

Both apps are installed, so these can be made here, with a throwaway
practice folder and Ben signed in. Neither app was opened for this page.

**Claude desktop app**
1. The three tabs, with **Code** selected.
2. **Local** chosen, and the **Select folder** button.
3. The permission mode selector open, showing Auto, Manual, Accept
   edits, and Plan.
4. A first prompt typed in, before sending.
5. Manual mode's diff view with **Accept** and **Reject**.
6. The `+12 -1` change indicator, and the diff it opens.
7. The Browser pane showing a running app.
8. The rewind menu (or the app's equivalent) with a checkpoint chosen.
9. claude.ai's data privacy controls page, with the training setting.

**Claude Code in the terminal** (for the extension track)
10. `claude --version`, then the first prompt.
11. `⏸ plan mode on` in the status bar, with a plan.
12. The `/rewind` menu.

**Antigravity**
13. First launch: the color scheme, rendering mode, and workspace trust
    prompts.
14. The Hub with a project open and a conversation started.
15. The permission preset picker, with **Default** selected.
16. A `/plan` artifact with an inline comment on one step, and
    **Proceed**.
17. A `/browser` screenshot artifact with a comment on it.
18. The `/rewind` (or Confirm Undo) dialog, showing "revert only the
    conversation."
19. Settings, **Account**, with **Enable Telemetry**.
20. The VCS panel showing a diff.

Each screenshot should use a practice project with nothing personal in
it, and be retaken when the app's version changes, since both shipped
several releases in the last month.

## What I could not verify

- Claude Code on a Chromebook's Linux, and Antigravity on a Chromebook
  or a tablet.
- The screen reader setting's name in Anthropic's own docs, and screen
  reader support in either desktop app.
- Whether Antigravity's rewind restores files changed by terminal
  commands, whether its browser needs Chrome installed, and whether it
  follows symlinked skills.
- How Google treats an Individual plan's prompts and code for training.
- Max 20x's price on Anthropic's own page.

## Practitioners worth reading alongside the docs

- Simon Willison's *Agentic Engineering Patterns*, begun February 2026,
  which leans on the same habits: tests first, small reviewable
  changes, and real manual testing
  ([How coding agents work](https://simonwillison.net/guides/agentic-engineering-patterns/how-coding-agents-work/)).
  It is written for working engineers, so it belongs in the extensions,
  not the main path.
- *Claude Code for Everyone*, a free course for non-programmers that
  teaches inside Claude Code itself ([ccforeveryone.com](https://ccforeveryone.com/)),
  worth a look by curriculum research 1 for how it chunks a first night.

Bring this page back to the curriculum plan with one question attached:
do we teach the loop first, or the tool first?
