# Ear Drama

Ear Drama is a free place to listen to radio drama and old-time radio
from the Internet Archive: series and episodes with their dates, casts,
networks, and sponsors, a Radio tab that rebuilds a real broadcast
evening from the newspaper listings of the day, and a player made for
the two places people actually listen, at bedtime and in the car. No
ads, no account. It lives at [eardrama.org](https://eardrama.org).

It is Archive Watch's sister app. Both read the same archive, and Ear
Drama was researched inside Archive Watch for six days before it moved
here, with its history, on October 22, 2026.

## Where things are

| Path | What |
|---|---|
| `docs/research/RESEARCH.md` | The research, start here: content, rights, metadata, platforms, design, the brand, and the owner's open questions |
| `catalog/` | The catalog pipeline (stdlib Python), its own `DECISIONS.md`, reports, and tests |
| [Release `catalog-2026-10-21`](https://github.com/bhwilkoff/Ear-Drama/releases/tag/catalog-2026-10-21) | The built database (157,503 episodes in 16,113 series) and every harvest cache; never in git |
| `SCRATCHPAD.md` | Current state and next steps |
| `DECISIONS.md` | Architecture decisions (054 onward are Ear Drama's) |
| `AGENTS.md` | Instructions every AI agent reads |
| `index.html`, `apple/`, `android/`, `tv/`, `windows/` | The web app and the native apps, from the Universal App Template |

## How it is built

Ear Drama was made from the
[Universal App Template](https://github.com/bhwilkoff/UniversalAppTemplate):
one data plane, native apps per platform, feature parity rather than
design consistency. The template's own front page is kept at
`docs/TEMPLATE-README.md`, and its method lives in `docs/path/` and the
skills in `.claude/skills/`.
