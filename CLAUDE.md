@AGENTS.md

## Claude Code

The project instructions live in `AGENTS.md`, imported above, so every
agent reads the same file. Edit `AGENTS.md`, not this one. Only notes
that apply to Claude Code alone belong here.

- **Skills** live in `.claude/skills/` (catalog:
  `.claude/skills/README.md`). Claude Code loads them on its own;
  invoke one by name when its trigger in the AGENTS.md table matches.
- **Auto memory** is the memory ratchet's home:
  `~/.claude/projects/<repo>/memory/`, with `MEMORY.md` as its index.
  Save corrections and confirmed choices there with a `**Why:**` line.
- **Session start**: `.claude/hooks/session-start.sh` prints the
  Current State section of `SCRATCHPAD.md` at launch.
- **Verifying a picture**: render to PNG and `Read` it before you call
  a visual change done.
