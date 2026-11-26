"""Mutation controls for test_play_voices.py: each guard of tools/play_voices.py removed in turn must fail a case.

    python3 tests/mutate_play_voices.py       # exits 1 when a removed guard fails nothing
"""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.join(HERE, "..", "tools")

# (name, text to find in play_voices.py, what replaces it)
MUTANTS = [
    ("a possessive hides the noun after it", "            continue  # \"Helmer's wife\"", "            skip = True\n            continue  # \"Helmer's wife\""),
    ("a preposition hides nothing", "        if w in PREPS:\n            skip = True", "        if False:\n            skip = True"),
    ("a description runs past its clause", "    desc = CLAUSE_END.split(", "    desc = re.compile('$^').split("),
    ("a crowd or a pair is marked", "    if JOINERS.search(up) or any(w in GROUP_WORDS for w in words):\n        return True", "    if False:\n        return True"),
    ("the words before a possessive count", "    if \"'S \" in up:\n        up = up.rsplit(\"'S \", 1)[1]", ""),
    ("the words after OF count", "    return words[:words.index(\"OF\")] if \"OF\" in words[1:] else words", "    return words"),
    ("one heading is enough", "reg or (h if len(heads) == 2 else None)", "reg or h"),
    ("a brace says nothing", "            reg = from_description(label) if label and not ACTOR.search(label) else None", "            reg = None"),
    ("two rows may be the role", "    if not pick or len({h[1][0] for h in pick}) > 1 and len({from_name(h[3] or \"\") for h in pick}) > 1:", "    if not pick:"),
    ("the row's own title is lost", "                title = m.groupdict().get(\"title\")", "                title = None"),
    ("someone else's direction in a speech is the speaker's", "                    if m and not OTHER_PRONOUN[reg].search(d):", "                    if m:"),
    ("an opening pronoun in a speech counts fully", "add([(reg, 3 if r and SELF_TALK.search(d) else 1)])", "add([(reg, 3)])"),
    ("the votes run past the next person", "    stop = min(later) if later else len(rest)", "    stop = len(rest)"),
    ("a pronoun before the part is not seen", " or PRONOUN_BEFORE.search(before):", ":"),
    ("the part need not be the subject", "    if len(words) > 3 or any(", "    if False and any("),
    ("a title's stop ends a sentence", "        if m.group(1) and m.group(1)[0] == \".\" and ABBREVIATION.search(text[:m.start()]):", "        if False:"),
    ("directions decide on a slight lead", "    if hi >= least and hi >= 6 * lo:", "    if hi >= least and hi >= lo:"),
    ("conflicting directions are ignored", "    if \"group\" in ev or \"conflict\" in ev.values():", "    if \"group\" in ev:"),
    ("a census name weighs as much as the print", "    if strong:\n        return strong.pop() if len(strong) == 1 else None", "    if False:\n        return None"),
    ("an actor's title is trusted in any play", "            return {r: evidence(r, entry, rows, names, actors_trusted=False) for r in roles}", "            return evs"),
    ("a family's name speaks for one of them", "    return (0, 0) if len(firsts) > 1 else (hi, lo)", "    return (hi, lo)"),
    ("a name another role carries speaks", "    if any(word in re.findall(r\"[A-ZÀ-ÞÉÈÑ]+\", r[\"name\"].upper()) for r in entry[\"roles\"] if r[\"name\"] != role):\n        return 0, 0", ""),
    ("a mixed address vetoes", "    if a in (HIGH, LOW):  # \"Lady Bracknell\"", "    if a:  # \"Lady Bracknell\""),
    ("a stale register is kept", "{**{k: v for k, v in r.items() if k != \"register\"}, **(", "{**r, **("),
]


def run(old, new, where):
    src = open(os.path.join(TOOLS, "play_voices.py"), encoding="utf-8").read()
    mutant = src.replace(old, new, 1)
    assert mutant != src, old
    os.makedirs(where, exist_ok=True)
    open(os.path.join(where, "play_voices.py"), "w", encoding="utf-8").write(mutant)
    code = ("import sys; sys.path[:0] = [%r, %r]; sys.argv = ['t']; import play_voices as m; assert m.__file__.startswith(%r); "
            "m.NAMES = %r; import runpy; runpy.run_path(%r, run_name='__main__')") % (
        where, TOOLS, where, os.path.join(HERE, "..", "plays", "given-name-registers.json"), os.path.join(HERE, "test_play_voices.py"))
    done = subprocess.run([sys.executable, "-B", "-c", code], capture_output=True, text=True)
    return re.findall(r"^FAIL (\w+)", done.stdout, re.M), done.returncode, (done.stdout + done.stderr).strip().splitlines()[-1:]


def main():
    unheld = []
    for name, old, new in MUTANTS:
        with tempfile.TemporaryDirectory() as d:
            failed, code, last = run(old, new, d)
        print(f"{name:52} {len(failed)} failed: {', '.join(failed)[:70]}" + ("" if failed else f" rc={code} {last}"))
        if not failed:
            unheld.append(name)
    print("every guard is held" if not unheld else "not held by a case: " + ", ".join(unheld))
    sys.exit(1 if unheld else 0)


if __name__ == "__main__":
    main()
