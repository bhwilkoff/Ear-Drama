"""Mutation controls for test_play_punctuation.py: each guard of play_punctuation removed in turn must fail a case.

    python3 tests/mutate_play_punctuation.py       # exits 1 when a removed guard fails nothing, or the tool is not mended at all
"""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.join(HERE, "..", "tools")

# (name, text to find in play_punctuation.py, what replaces it)
MUTANTS = [
    ("nothing is mended", "if now != p[\"say\"]:", "if False:"),
    ("an ellipsis may lose its stops", 'and not t.startswith("..")', ""),
    ("only stops are taken, a dash goes too", 'STOPS = ".,;:"', 'STOPS = ".,;:-—"'),
    ("a comma-ended sentence loses its own stop", 'before[-1] in ".!?"', 'before[-1] in ".,!?-e"'),
    ("a stop is taken from the middle of a sentence", "else _mid(p[\"say\"], said)", "else _lead(p[\"say\"])"),
    ("a say with no direction before it is mended", 'if "say" in p and i and "direction" in parts[i - 1]:', 'if "say" in p:'),
    ("a say left empty stays", "if not now.strip():", "if False:"),
    ("an italic mark does not follow its part", "return out, [where[k] for k in em if k in where]", "return out, list(em)"),
    ("a speech left with no words stays a speech", 'if not any("say" in p for p in parts):', "if False:"),
    ("the roles follow the lines", '"roles": PC._roles(lines)}', '"roles": entry["roles"]}'),
    ("the revision follows the lines", '"revision": PC._revision(lines)', '"revision": entry["revision"]'),
    ("a line nothing is mended in is copied", "if parts is line[\"parts\"]:", "if False:"),
]


def run(old, new, where):
    src = open(os.path.join(TOOLS, "play_punctuation.py"), encoding="utf-8").read()
    mutant = src.replace(old, new, 1)
    assert mutant != src, old
    os.makedirs(where, exist_ok=True)
    open(os.path.join(where, "play_punctuation.py"), "w", encoding="utf-8").write(mutant)
    code = ("import sys; sys.path[:0] = [%r, %r]; sys.argv = ['t']; import play_punctuation; assert play_punctuation.__file__.startswith(%r); "
            "import runpy; runpy.run_path(%r, run_name='__main__')") % (where, TOOLS, where, os.path.join(HERE, "test_play_punctuation.py"))
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
