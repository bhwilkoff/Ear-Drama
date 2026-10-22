# Gemini, Antigravity, and the template

*Research done October 3, 2026, for milestone M7 ("works the same with
Gemini"). Every claim has a source beside it. Where the source is the
Gemini CLI installed on this Mac (v0.46.0, from Homebrew, with its docs
bundled inside it), the claim was also tested here, and the test is
described. Anything not confirmed is marked **(unverified)**. The site's
research notes this builds on are `research/notes/github-onboarding-and-ai-access-notes.md`
and `research/notes/agent-connection-notes.md` on the `site` branch.*

## Why this page exists

The course says students bring their own AI, that it never requires one
vendor, and that a Claude or a Gemini subscription should both work
(humanshaped.org `DECISIONS.md`, "Students bring their own AI"; Ben's
`VISION.md`, October 1, 2026). The template was written in Claude Code,
so I wanted to know, from the tools' own documentation and from running
one of them, what a Gemini student's agent actually reads when it opens
a copy of this template, and where the path asks for something only
Claude has.

**Gemini's agent for most students is now Antigravity, not Gemini CLI.**

## Google's agents in October 2026

**Gemini CLI stopped serving most people on June 18, 2026.** Google's
announcement, posted May 19: "On June 18, 2026, Gemini CLI will stop
serving requests for Google AI Pro and Ultra, as well as those using it
free of charge." Paid Gemini API keys, Gemini Code Assist Standard and
Enterprise licenses, and Google Cloud access stay supported, and the
named successor is Antigravity CLI
([discussion #27274](https://github.com/google-gemini/gemini-cli/discussions/27274)).
The quota page now opens with "Gemini CLI was replaced by Antigravity
CLI on June 18th, 2026" and was last updated that day
([quota and pricing](https://geminicli.com/docs/resources/quota-and-pricing/)).

*Tested.* Running `gemini -p` here with Ben's existing Google sign-in
(no new sign-in) fails before any model call with `IneligibleTierError`:
"This client is no longer supported for Gemini Code Assist [...] please
migrate to the Antigravity suite of products." The free tier is gone in
practice, not only on paper.

One conflict is open. The same quota page still lists a free Gemini API
key tier (250 requests a day, Flash only) in its table, while its notice
says the unpaid tier was replaced. Whether a free API key still works
with Gemini CLI is **(unverified)**.

**Antigravity is the successor.** It comes as a desktop app for macOS,
Windows, Linux, and Googlebook ([getting started](https://antigravity.google/docs/getting-started/)),
a web version (the slash command page names "Antigravity 2.0 (Desktop
and Web)", [slash commands](https://antigravity.google/docs/slash-commands/)),
and a command-line tool, `agy`, installed with
`curl -fsSL https://antigravity.google/cli/install.sh | bash` on a Mac
or Linux, or a PowerShell one-liner on Windows. It signs in through the
browser on first launch ([install and auth](https://antigravity.google/docs/cli/install/)).
Whether the web version works on a phone is **(unverified)**.

**Plans.** The Individual plan is $0, with "Basic weekly rate limits",
and Google AI Pro and Ultra add "More rate limits" and a credit pool
([pricing](https://antigravity.google/pricing)). The plans page says the
free tier's quota is "refreshed weekly", Pro's is "refreshed every five
hours until the weekly limit is reached", and that the CLI and
scheduled tasks are included on "All plans". It names Gemini models
only ("Gemini 3.1 Pro, Gemini 3.8 Flash") ([plans](https://antigravity.google/docs/plans)).
Google AI Pro is $19.99 a month in the US and includes "Entry rate
limits to agent model in Google Antigravity" ([Google AI plans](https://gemini.google/subscriptions/)).
The site's earlier notes listed Claude and `gpt-oss-120b` among
Antigravity's models. The current plans page does not, so which
non-Gemini models a student can pick is **(unverified)**. If
`gpt-oss-120b` is offered, it is OpenAI's model, and the course does not
recommend OpenAI.

## How each agent reads the project's instructions

**Gemini CLI** loads `GEMINI.md` by default, from the home folder, the
workspace and its parents, and on demand from folders a tool touches. A
`context.fileName` setting can add other names, such as `AGENTS.md`,
and `@file.md` lines import other files, with relative paths
([GEMINI.md docs](https://geminicli.com/docs/cli/gemini-md/), last
updated June 18, 2026; [import processor](https://github.com/google-gemini/gemini-cli/blob/main/docs/reference/memport.md)).
Nothing in those pages says Gemini CLI reads `AGENTS.md` without being
told to.

Folder trust decides whether any of that happens. In an untrusted
folder, workspace settings, MCP servers, and custom commands are off
([trusted folders](https://geminicli.com/docs/cli/trusted-folders/)).
The bundled settings reference gives `security.folderTrust.enabled` a
default of `true`, while the trusted folders page says the feature is
off by default. v0.46.0 behaved as if it were on.

*Tested on v0.46.0,* with a throwaway home folder and a fake API key so
that no account was touched, reading the CLI's own debug log of which
context files it loaded:

| Setup | Trusted | `--skip-trust` | Untrusted |
|---|---|---|---|
| Before M7: `context.fileName: [AGENTS.md, GEMINI.md]`, `GEMINI.md` says "read `AGENTS.md`" | both files | `GEMINI.md` only (the setting is ignored) | nothing |
| `GEMINI.md` imports `@./AGENTS.md` **and** the setting lists it | `AGENTS.md` twice (about 98 KB) | once | nothing |
| After M7: `GEMINI.md` imports `@./AGENTS.md`, no setting | once (50,562 characters) | once | nothing |

In an untrusted folder, v0.46.0 printed "project settings, hooks, MCPs,
and GEMINI.md files will not be applied for this folder", so no
arrangement of files helps there. The person has to trust the folder
when Gemini CLI asks. The current release is v0.62.0, and none of this was
rerun on it **(unverified on v0.62.0)**.

**Antigravity** reads `AGENTS.md`, `GEMINI.md`, and `.md` files in
`.agents/rules/`, and the rules are cumulative, with the more specific
folder winning a conflict. Two limits matter for this template:
"Antigravity truncates any single rule file that exceeds 24,000 bytes",
and global plus always-on rules share a 20,000-token budget, past which
the largest files become pointers the agent reads on demand. Its
`@filename` syntax only rewrites the path without inlining the file,
while `@[label](path)` inlines ([rules](https://antigravity.google/docs/rules/)).
The CLI reads the same files as Gemini CLI did, with "no modifications
needed for existing files" ([migration guide](https://antigravity.google/docs/cli/gcli-migration/)).

So, `AGENTS.md`, at 49,411 bytes, reaches Antigravity cut roughly in
half: everything from "Android app" on, including "How we collaborate"
and "Standing instructions", falls past the 24,000-byte mark. This is
from the documentation. Antigravity was not run here **(unverified in
practice)**.

**Claude Code** reads `CLAUDE.md`. It reads `AGENTS.md` on its own only
when there is no `CLAUDE.md` (v2.1.277 and later), and a `CLAUDE.md`
that starts with `@AGENTS.md` never loads it twice
([Claude Code memory](https://code.claude.com/docs/en/memory)).

## How each agent finds skills

**Gemini CLI** has Agent Skills, on the open SKILL.md standard. It
scans built-in, extension, user (`~/.gemini/skills/` or
`~/.agents/skills/`), and workspace (`.gemini/skills/` or
`.agents/skills/`) folders, puts each skill's name and description in
the system prompt, and loads the body through an `activate_skill` tool
after the person approves ([skills](https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/skills.md)).
There is no setting for another skills folder, such as `.claude/skills/`
(the bundled configuration reference has only `skills.enabled` and
`skills.disabled`). *Tested:* `gemini skills list` in this repository
lists the `template-skills` pointer, and after a symlink was added at
`.agents/skills/human-shaped-review`, it listed that skill too, loaded
from the link. Skills, like settings, wait on folder trust (the trust
dialog names "agent skills" among what it gates).

**Antigravity** reads workspace skills from `.agents/skills/<folder>/`
in the desktop app and the CLI. Only `description` is required, and
`name` defaults to the folder name. A skill fires on its own when a
prompt matches, or by name with `/<skill-name>`
([skills](https://antigravity.google/docs/skills/)). Its older
"workflows" became skills for the same reason
([workflows to skills](https://antigravity.google/docs/migration/workflows-to-skills/)).
Whether it follows a symlinked skill folder is not documented
**(unverified)**.

**Claude Code** reads `.claude/skills/`, does not search `.agents/`, and
follows symlinked skill folders ([Claude Code skills](https://code.claude.com/docs/en/skills)).

**Copilot** reads `.github/skills`, `.claude/skills`, and
`.agents/skills` (from the site's notes, citing
[GitHub's skills docs](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills)),
so the three linked skills appear to it twice. How it handles a
duplicate name is **(unverified)**.

## Custom commands

Gemini CLI loads project commands from `.gemini/commands/*.toml`, each
with a `prompt` and an optional `description`, and can inject a file
with `@{path}` ([custom commands](https://geminicli.com/docs/cli/custom-commands/)).
Antigravity does not list them. Its migration guide mentions converting
"legacy commands" to skills on plugin import, and a skill is already a
`/<skill-name>` command there ([migration guide](https://antigravity.google/docs/cli/gcli-migration/)).

So the template adds no TOML commands. Since June 18, a command file
would only reach people on a paid Gemini API key or a Code Assist
license, and a linked skill does the same job in both of Google's
agents.

## MCP servers

Gemini CLI configures MCP servers in `settings.json` under
`mcpServers`, a Streamable HTTP server with `httpUrl`, and
`gemini mcp add` writes to the project by default
([MCP servers](https://geminicli.com/docs/tools/mcp-server/); the site's
`agent-connection-notes.md` has the detail, including why every
instruction to a student must say `-s user`). Antigravity moved MCP to
`.agents/mcp_config.json` in a workspace and
`~/.gemini/config/mcp_config.json` globally, and renamed `url` and
`httpUrl` to `serverUrl` ([migration guide](https://antigravity.google/docs/cli/gcli-migration/)).
The template ships no MCP configuration, so nothing changed here. Any
humanshaped.org instructions for connecting a student's agent will need
Antigravity's form.

## The path's Claude-only steps, and Google's equivalents

| The path says | Claude | Antigravity | Gemini CLI |
|---|---|---|---|
| Run a loop (stages 06, talking) | `/loop` | `/goal` runs "until the goal is achieved without intermediate pauses"; `/schedule` runs an instruction on a timer or cron ([slash commands](https://antigravity.google/docs/slash-commands/)) | no equivalent found |
| "Use Chrome to take me to the right screen" (05, talking) | Claude in Chrome, in the person's own browser | `/browser`, "a sandboxed browser subagent"; whether it can reach a page the person is signed in to is **(unverified)**, and likely not | none |
| "Make a memory" (08, talking) | auto memory | `/learn` "distills session feedback and corrections into persistent Rules or Skills" | the memory tool, which writes shared project facts into the repository's `GEMINI.md` ([memory tool](https://github.com/google-gemini/gemini-cli/blob/main/docs/tools/memory.md)) |
| "We need to compact" (08) | `/compact` | none documented **(unverified)** | `/compress` |
| Use a skill by name | `/skill-name`, or ask | `/skill-name`, or ask | ask; it activates by description |
| Desktop app, cloud, phone (setup) | Claude desktop app, claude.ai/code, Claude phone app | Antigravity desktop app and web; phone **(unverified)** | terminal only |

Gemini CLI's memory tool matters for this template: left alone, it
would write project rules into `GEMINI.md`, and the whole point of
`AGENTS.md` is one source. `GEMINI.md` now says where rules go.

## What the template does now

- `GEMINI.md` starts with `@./AGENTS.md`, so Gemini CLI loads the
  instructions once whenever the folder is trusted, and it tells
  Antigravity to read `AGENTS.md` in full because of the 24 KB cut.
- `.gemini/settings.json` is gone. Its only setting loaded `AGENTS.md` a
  second time once the import was in place, and the import does its
  job even when Gemini CLI ignores workspace settings.
- `.agents/skills/` links to the three skills a learner asks for by
  name (`learning-orientation-design`, `make-it-look-like-itself`,
  `human-shaped-review`), beside the `template-skills` pointer for the
  other skills. The links point into `.claude/skills/`, so there is one
  copy of each skill.
- `tools/test_agent_files.py` checks the imports, the links, any
  `.gemini/` JSON or TOML, and that every skill a doc names exists.
- The path has a short note for Gemini where a step names something
  only Claude has.

## What waits on Ben

1. **Link every skill, or keep the pointer?** Linking all 146 folders
   into `.agents/skills/` would give Google's agents the same automatic
   triggers Claude has. It costs 146 links to keep in step (Windows
   clones without symlink support turn each into a small text file, and
   Gemini simply skips it), and Copilot would see each skill twice.
2. **Shorten `AGENTS.md` below 24,000 bytes?** Moving the platform
   sections into their skills or docs would let Antigravity load the
   whole file without being told. That is a larger edit to the one file
   every agent reads. *Decided October 3, 2026: yes.* The platform rules
   moved to `docs/platforms/`, `AGENTS.md` is about 21,800 bytes, and
   `tools/test_agent_files.py` holds it there
   (`docs/maintaining/AGENTS-MD-MAP.md`).
3. **Which Google lane the course names.** Antigravity's free plan has
   a weekly limit Google does not publish in numbers, and it has changed
   its free terms twice this year. *Decided October 3, 2026:* the course
   names Antigravity as Google's route, labeled as something that may
   change, with Gemini CLI as the paid option (`docs/path/setup.md`).

## What I could not verify

- Antigravity's behavior in practice: the 24 KB cut, symlinked skills,
  and whether `/goal` holds up for a stage 06 loop. It is not installed
  here, and installing it means signing in.
- Anything on Gemini CLI v0.62.0.
- Whether a free Gemini API key still works with Gemini CLI.
- Which models Antigravity's free plan offers besides Gemini.
- Whether Antigravity runs on a phone.
