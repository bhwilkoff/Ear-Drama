"""Mutation controls for test_play_corrections.py: each guard of play_corrections removed in turn must fail a case.

    python3 tests/mutate_play_corrections.py       # exits 1 when a removed guard fails nothing
"""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.join(HERE, "..", "tools")

# (name, text to find in play_corrections.py, what replaces it)
MUTANTS = [
    ("the revision check", 'if c["revision"] != entry["revision"]:', "if False:"),
    ("the evidence check", 'if squash(c["evidence"]) not in whole:', "if False:"),
    ("the evidence is searched for in the labels too", '(l["role"] + ". " if l["kind"] == "speech" else "")', '""'),
    ("the check that no word is added or lost", 'if re.sub(r"\\s+", "", kept) != re.sub(r"\\s+", "", wrote):', "if False:"),
    ("the cut must stand at the start of its piece", "if not flat[a:b].lstrip().startswith(cut):", "if False:"),
    ("a quote must be in the line once", "if not q or flat.count(q) != 1:", "if not q:"),
    ("a line is corrected once", 'if c["line"] in seen:', "if False:"),
    ("a missing line is refused", 'if c["line"] not in at:', "if False:"),
    ("the next free letter", "while f\"{m.group(1)}{P._letters(n)}\" in taken:", "while False:"),
    ("the roles follow the lines", '"roles": _roles(new)}', '"roles": entry["roles"]}'),
    ("the revision follows the lines", '"revision": _revision(new)', '"revision": entry["revision"]'),
    ("a section's line may not go", "if s[\"line\"] not in ids:", "if False:"),
    ("a split makes pieces", "or len(pieces) == 1 and not pieces[0].get(\"cut\"):", ":"),
]


def run(old, new, where):
    src = open(os.path.join(TOOLS, "play_corrections.py"), encoding="utf-8").read()
    mutant = src.replace(old, new, 1)
    assert mutant != src, old
    mutant = mutant.replace("HERE = os.path.dirname(os.path.abspath(__file__))", f"HERE = {TOOLS!r}", 1)
    os.makedirs(where, exist_ok=True)
    open(os.path.join(where, "play_corrections.py"), "w", encoding="utf-8").write(mutant)
    code = ("import sys; sys.path[:0] = [%r, %r]; sys.argv = ['t']; import play_corrections; assert play_corrections.__file__.startswith(%r); "
            "import runpy; runpy.run_path(%r, run_name='__main__')") % (where, TOOLS, where, os.path.join(HERE, "test_play_corrections.py"))
    done = subprocess.run([sys.executable, "-B", "-c", code], capture_output=True, text=True)
    return re.findall(r"^FAIL (\w+)", done.stdout, re.M), done.returncode, (done.stdout + done.stderr).strip().splitlines()[-1:]


def main():
    unheld = []
    for name, old, new in MUTANTS:
        with tempfile.TemporaryDirectory() as d:
            failed, code, last = run(old, new, d)
        print(f"{name:48} {len(failed)} failed: {', '.join(failed)[:70]}" + ("" if failed else f" rc={code} {last}"))
        if not failed:
            unheld.append(name)
    print("every guard is held" if not unheld else "not held by a case: " + ", ".join(unheld))
    sys.exit(1 if unheld else 0)


if __name__ == "__main__":
    main()
