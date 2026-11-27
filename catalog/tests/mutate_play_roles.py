"""Mutation controls for test_play_roles.py: each rule of play_roles.refine removed in turn must fail a case.

    python3 tests/mutate_play_roles.py       # exits 1 when a removed rule fails nothing
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.join(HERE, "..", "tools")


def run(step, where):
    src = open(os.path.join(TOOLS, "play_roles.py"), encoding="utf-8").read()
    mutant = src.replace(f"r.{step},", "", 1) if f"r.{step}," in src else src.replace(f", r.{step})", ")", 1)
    assert mutant != src, step
    os.makedirs(where, exist_ok=True)
    open(os.path.join(where, "play_roles.py"), "w", encoding="utf-8").write(mutant)
    code = ("import sys; sys.path[:0] = [%r, %r]; sys.argv = ['t']; import play_roles; assert play_roles.__file__.startswith(%r); "
            "import runpy; runpy.run_path(%r, run_name='__main__')") % (where, TOOLS, where, os.path.join(HERE, "test_play_roles.py"))
    # -B: two mutants of one size written in the same second would otherwise share a stale .pyc (seen 2026-11-27)
    out = subprocess.run([sys.executable, "-B", "-c", code], capture_output=True, text=True).stdout
    return re.findall(r"^FAIL (\w+)", out, re.M)


TEXT_MUTANTS = [("a label's part may speak once", 'self.n[role] >= 1 and not level(left)', 'self.n[role] >= CASTABLE and not level(left)')]


def run_text(old, new, where):
    src = open(os.path.join(TOOLS, "play_roles.py"), encoding="utf-8").read()
    mutant = src.replace(old, new, 1)
    assert mutant != src, old
    os.makedirs(where, exist_ok=True)
    open(os.path.join(where, "play_roles.py"), "w", encoding="utf-8").write(mutant)
    code = ("import sys; sys.path[:0] = [%r, %r]; sys.argv = ['t']; import play_roles; assert play_roles.__file__.startswith(%r); "
            "import runpy; runpy.run_path(%r, run_name='__main__')") % (where, TOOLS, where, os.path.join(HERE, "test_play_roles.py"))
    out = subprocess.run([sys.executable, "-B", "-c", code], capture_output=True, text=True).stdout
    return re.findall(r"^FAIL (\w+)", out, re.M)


def main():
    import tempfile
    src = open(os.path.join(TOOLS, "play_roles.py"), encoding="utf-8").read()
    steps = re.findall(r"\br\.(\w+)", re.search(r"for step in \((.*?)\):", src, re.S).group(1))
    unheld = []
    with tempfile.TemporaryDirectory() as d:
        for step in steps:
            failed = run(step, d)
            print(f"{step:24} {len(failed)} failed: {', '.join(failed)[:110]}")
            if not failed:
                unheld.append(step)
    for name, old, new in TEXT_MUTANTS:
        with tempfile.TemporaryDirectory() as d:
            failed = run_text(old, new, d)
        print(f"{name:24} {len(failed)} failed: {', '.join(failed)[:110]}")
        if not failed:
            unheld.append(name)
    print("every rule is held" if not unheld else "not held by a case: " + ", ".join(unheld))
    sys.exit(1 if unheld else 0)


if __name__ == "__main__":
    main()
