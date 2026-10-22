#!/usr/bin/env python3
"""
Each session's default run of show is one the hub will accept.

docs/teaching/runs-of-show.json holds the six sessions of a cohort under
`weeks` (Prep is week 0, then weeks 1 to 5) as scenes in the hub's own shape, and humanshaped.org
seeds a new cohort from it. This checks the file's shape here, and then,
when the hub's code is reachable (the `site` branch of this repository, or
a path in HUB_SHOW_LIB), runs every scene through the hub's own
ShowLib.problem, the same rules the class builder and the database use.
In a copy of the template without the hub, that second part is skipped
and says so.

Run: python3 tools/test_runs_of_show.py   (exit 0 = pass)
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FILE = ROOT / "docs/teaching/runs-of-show.json"
fails = []

# The hub's scene kinds and what each may carry (assets/show-lib.js, KINDS).
KEYS = {
    "talk": set(),
    "presenter": {"prompt"},
    "question": {"prompt", "options", "kind", "points", "question_id"},
    "design": {"template"},
    "rooms": {"prompt", "room_scenes"},
    "break": set(),
    "reflection": {"prompt"},
}
# The board templates the hub has, and the one this curriculum adds
# (`problem-tests`, a board for holding a candidate problem against the
# tests in docs/research/curriculum/06-instructional-design.md).
TEMPLATES = {"blank", "prompt", "moves", "questions", "problem-tests"}


def check(ok, what, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'}  {what}" + (f"  ({detail})" if detail and not ok else ""))
    if not ok:
        fails.append(what)


data = json.loads(FILE.read_text())
sessions = data.get("weeks", [])
check([s.get("week") for s in sessions] == [0, 1, 2, 3, 4, 5],
      "`weeks` holds the six sessions, Prep (0) to week 5, in order", ", ".join(str(s.get("week")) for s in sessions))

for s in sessions:
    scenes = s.get("scenes", [])
    name = s.get("key", "?")
    total = sum(sc.get("minutes", 0) for sc in scenes)
    check(total == data.get("minutes"), f"{name}: the scenes fill the {data.get('minutes')} minutes", f"{total}")
    check(s.get("move") and s.get("question"), f"{name}: names its move and its question")
    check((ROOT / "docs/teaching" / s.get("guide", "")).exists(), f"{name}: its guide exists", s.get("guide", ""))
    for sc in scenes:
        k = sc.get("kind")
        check(set(sc) <= {"kind", "title", "minutes", "body", "config", "note"},
              f"{name}: {sc.get('title')} carries only the hub's scene fields", ", ".join(sorted(set(sc) - {"kind", "title", "minutes", "body", "config", "note"})))
        extra = set(sc.get("config", {})) - KEYS.get(k, set())
        check(k in KEYS and not extra, f"{name}: {sc.get('title')} is a {k} scene with only its own settings",
              ", ".join(sorted(extra)))
        tpl = sc.get("config", {}).get("template")
        if tpl is not None:
            check(tpl in TEMPLATES, f"{name}: {sc.get('title')} uses a known board template", tpl)
        if k == "rooms":
            inner = sum(r["minutes"] for r in sc["config"].get("room_scenes", []))
            check(0 < inner * 3 <= sc["minutes"], f"{name}: three turns fit inside {sc.get('title')}",
                  f"{inner} x 3 > {sc['minutes']}")
    check(any(sc["kind"] == "question" for sc in scenes), f"{name}: has a question scene")
    check(any(sc["kind"] == "design" for sc in scenes), f"{name}: has a design stage scene")
    for q in s.get("questions", []):
        check(set(q) <= {"kind", "prompt", "choices", "points"} and q.get("prompt"),
              f"{name}: bank question has the bank's shape", q.get("prompt", "?"))
    check(len(s.get("questions", [])) >= 2, f"{name}: prepares questions for the bank")


# The hub's own rules, when its code can be reached.
def hub_show_lib():
    path = os.environ.get("HUB_SHOW_LIB")
    if path and Path(path).exists():
        return Path(path).read_text()
    for ref in ("origin/site", "site"):
        r = subprocess.run(["git", "-C", str(ROOT), "show", f"{ref}:assets/show-lib.js"],
                           capture_output=True, text=True)
        if r.returncode == 0 and r.stdout:
            return r.stdout
    return None


source = hub_show_lib()
node = shutil.which("node")
if not source or not node:
    print("  SKIP  the hub's own rules (no `site` branch or HUB_SHOW_LIB, or no node)")
else:
    with tempfile.TemporaryDirectory() as tmp:
        lib = Path(tmp) / "show-lib.js"
        lib.write_text(source)
        script = (
            "const L = require(process.argv[1]);"
            "const d = require(process.argv[2]);"
            "const out = [];"
            "for (const s of d.weeks) {"
            "  for (const sc of s.scenes) { const p = L.problem(sc); if (p) out.push(s.key + ': ' + sc.title + ': ' + p); }"
            "  for (const q of (s.questions || [])) {"
            "    const c = { prompt: q.prompt, kind: q.kind }; if (q.choices) c.options = q.choices; if (q.points) c.points = q.points;"
            "    const p = L.problem({ kind: 'question', title: 'bank', minutes: 1, config: c }); if (p) out.push(s.key + ': bank: ' + q.prompt + ': ' + p); } }"
            "console.log(JSON.stringify(out));"
        )
        r = subprocess.run([node, "-e", script, str(lib), str(FILE)], capture_output=True, text=True)
        problems = json.loads(r.stdout or "[\"node failed: " + r.stderr.strip().replace('"', "'") + "\"]")
        check(not problems, "every scene and bank question passes the hub's ShowLib.problem", "; ".join(problems))

print()
if fails:
    print(f"{len(fails)} failed")
    sys.exit(1)
print("all passed")
