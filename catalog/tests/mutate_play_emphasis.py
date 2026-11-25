"""Mutation controls for test_play_emphasis.py and test_play_margins.py: each guard removed in turn must fail a case.

    python3 tests/mutate_play_emphasis.py       # exits 1 when a removed guard fails nothing, or a tool is not mended at all
"""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.join(HERE, "..", "tools")

# (module, name, text to find in it, what replaces it)
MUTANTS = [
    ("play_emphasis", "nothing is spoken", "    if not found:", "    if True:"),
    ("play_emphasis", "every italic is spoken", "    d = parts[k][\"direction\"]\n", "    d = parts[k][\"direction\"]\n    return 'x'\n"),
    ("play_emphasis", "a bracketed direction is read", "if not isinstance(d, P.Italic) or BRACKET.search(d) or", "if BRACKET.search(d) or"),
    ("play_emphasis", "a bracket inside the span is read", "P.Italic) or BRACKET.search(d) or _bracket_open(parts, k) or _mostly", "P.Italic) or _bracket_open(parts, k) or _mostly"),
    ("play_emphasis", "an open bracket is not seen", "BRACKET.search(d) or _bracket_open(parts, k) or _mostly", "BRACKET.search(d) or _mostly"),
    ("play_emphasis", "a mostly italic line is read", "or _mostly_italic(parts):", "or False:"),
    ("play_emphasis", "a note's words are read", "if not ws or NOTE_NEAR.search(prev[-40:]) or", "if not ws or"),
    ("play_emphasis", "a stage word in quotation marks is read", "<= MAX_QUOTED and not stage_words(d):", "<= MAX_QUOTED:"),
    ("play_emphasis", "words in quotation marks are not", "if QUOTE_OPENS.search(prev) and QUOTE", "if False and QUOTE"),
    ("play_emphasis", "a long span is read", "if len(ws) > MAX_WORDS or not", "if not"),
    ("play_emphasis", "a span between two spans is read", "or not words(prev) and (prev or not after):", "or not prev and not after:"),
    ("play_emphasis", "capitals beside it are not seen", "if any(map(_caps, prev", "if False and any(map(_caps, prev"),
    ("play_emphasis", "capitals after it are not seen", " + after.split()[:2])", ")"),
    ("play_emphasis", "I is a name in capitals", "return len(w) > 2 and", "return len(w) > 0 and"),
    ("play_emphasis", "an entrance still going on is read", "elif ENTERS.match(next(iter(part.values()))):", "elif False:"),
    ("play_emphasis", "a sentence's end does not end an entrance", "            if re.search(r\"[.!?]\", part[\"say\"]):\n                break", "            continue"),
    ("play_emphasis", "a label's stop is not seen", "if LABEL_LIKE.search(d) and not (", "if False and not ("),
    ("play_emphasis", "a pronoun with its stop is not read", "if LABEL_LIKE.search(d) and not (closed", "if LABEL_LIKE.search(d) and not (False"),
    ("play_emphasis", "prose after a quoted speech is read", "if opens and prev[-1:] in", "if False and prev[-1:] in"),
    ("play_emphasis", "a closed word is no evidence", "return 1 <= len(ws) <= 3 and", "return False and"),
    ("play_emphasis", "a possessive is not closed", " or key(w).removesuffix(\"'s\") in CLOSED", ""),
    ("play_emphasis", "any play gives a closed word before a name", "in a play that brackets its directions\" if conv.emphasis else None\n    lead", "in a play that brackets its directions\"\n    lead"),
    ("play_emphasis", "any play gives a stage word", "if conv.emphasis and not opens and lead in DETERMINER and len(ws) == 1", "if not opens and lead in DETERMINER and len(ws) == 1"),
    ("play_emphasis", "a stage word is no bar", "    if stage_words(d):\n        if conv", "    if False:\n        if conv"),
    ("play_emphasis", "any play gives an exclamation", "if conv.emphasis and exclaims and upper", "if exclaims and upper"),
    ("play_emphasis", "a label opens a sentence", "if not upper or not d[-1].isalpha() or conv.is_label(d) and not after.startswith(\",\"):", "if not upper or not d[-1].isalpha():"),
    ("play_emphasis", "any play gives a word set off", "if conv.emphasis and len(ws) <= 3 and re.match(r\", ", "if len(ws) <= 3 and re.match(r\", "),
    ("play_emphasis", "any play gives a word that opens", "in lower case\" if conv.emphasis and len(ws)", "in lower case\" if len(ws)"),
    ("play_emphasis", "any play gives a word before a name", "        if conv.emphasis and lead in DETERMINER and len(ws) <= 2", "        if lead in DETERMINER and len(ws) <= 2"),
    ("play_emphasis", "a word the others need is no evidence", "if lead in NEEDS_MORE or ABBREVIATION.search(prev):", "if False:"),
    ("play_emphasis", "a title's stop ends a sentence", " and not ABBREVIATION.search(prev)\n", "\n"),
    ("play_emphasis", "a name is no evidence", "        return \"a name inside a sentence\"", "        return None"),
    ("play_emphasis", "a play's own business is not counted", "business <= 0.1 * (plain + business)", "True"),
    ("play_emphasis", "brackets are not counted", "bracketed >= 10 and business", "business"),
    ("play_emphasis", "the print's joined word is cut", "            elif after:\n", "            elif False:\n"),
    ("play_emphasis", "a word joined to the one before is cut", "            if before:\n", "            if False:\n"),
    ("play_emphasis", "a dash joins", "re.search(r\"[^\\W\\d_]['’\\-]?$\"", "re.search(r\".$\""),
    ("play_emphasis", "the emphasis is not kept", "                em.append(len(out) - 1)\n            glue", "            glue"),
    ("play_emphasis", "the old emphasis is lost", "            if k in em_old:\n", "            if False:\n"),
    ("play_emphasis", "a line nothing is found in is copied", "    if not found:\n        return line", "    if not found:\n        return dict(line)"),
    ("play_emphasis", "a play nothing is found in is copied", "for a, b in zip(lines, entry[\"lines\"])):\n        return entry", "for a, b in zip(lines, entry[\"lines\"])):\n        return dict(entry)"),
    ("play_emphasis", "the revision does not follow", "\"revision\": PC._revision(lines)", "\"revision\": entry[\"revision\"]"),
    ("play_emphasis", "the roles do not follow", "\"roles\": PC._roles(lines)", "\"roles\": entry[\"roles\"]"),
    ("play_margins", "nothing is taken", "    if not gone:", "    if True:"),
    ("play_margins", "few numbers are enough", "FEWEST = 5", "FEWEST = 3"),
    ("play_margins", "they need not rise", "RISING = 0.8", "RISING = 0.0"),
    ("play_margins", "spaces are not needed", "[ \\t]{3,}", "[ \\t]{1,}"),
    ("play_margins", "any number goes", "if n and n % 5 == 0:", "if n:"),
    ("play_margins", "nought goes", "if n and n % 5 == 0:", "if n % 5 == 0:"),
    ("play_margins", "one before its place goes", "if not last < s[4] <= last + NEXT or", "if not s[4] <= last + NEXT or"),
    ("play_margins", "one far past its place goes", "if not last < s[4] <= last + NEXT or", "if not last < s[4] or"),
    ("play_margins", "one past the next goes", "and s[4] >= ahead:", "and False:"),
    ("play_margins", "a number in the middle of a sentence goes", "(?=\\s+[\\\"'“‘(\\[]*[A-ZÀ-Þ]|", "(?=\\s+|"),
    ("play_margins", "a row loses its break", "(\"\\n\" if \"\\n\" in gap else \" \")", "\" \""),
    ("play_margins", "an empty part stays", "                if not p[\"say\"]:\n                    continue\n", ""),
    ("play_margins", "emphasis does not keep its place", "em.append(len(parts) - 1)", "em.append(k)"),
    ("play_margins", "a speech of no words stays a speech", "new if any(\"say\" in p for p in parts) else", "new if parts else"),
    ("play_margins", "the revision does not follow", "\"revision\": PC._revision(lines)", "\"revision\": entry[\"revision\"]"),
    ("play_margins", "the roles do not follow", "\"roles\": PC._roles(lines)", "\"roles\": entry[\"roles\"]"),
]


def run(module, old, new, where):
    src = open(os.path.join(TOOLS, module + ".py"), encoding="utf-8").read()
    mutant = src.replace(old, new, 1)
    assert mutant != src, (module, old)
    os.makedirs(where, exist_ok=True)
    open(os.path.join(where, module + ".py"), "w", encoding="utf-8").write(mutant)
    code = ("import sys; sys.path[:0] = [%r, %r]; sys.argv = ['t']; import %s as m; assert m.__file__.startswith(%r); "
            "import runpy; runpy.run_path(%r, run_name='__main__')") % (where, TOOLS, module, where, os.path.join(HERE, f"test_{module}.py"))
    done = subprocess.run([sys.executable, "-B", "-c", code], capture_output=True, text=True)
    return re.findall(r"^FAIL (\w+)", done.stdout, re.M), done.returncode, (done.stdout + done.stderr).strip().splitlines()[-1:]


def main():
    unheld = []
    for module, name, old, new in MUTANTS:
        with tempfile.TemporaryDirectory() as d:
            failed, code, last = run(module, old, new, d)
        print(f"{name:48} {len(failed)} failed: {', '.join(failed)[:70]}" + ("" if failed else f" rc={code} {last}"))
        if not failed:
            unheld.append(name)
    print("every guard is held" if not unheld else "not held by a case: " + ", ".join(unheld))
    sys.exit(1 if unheld else 0)


if __name__ == "__main__":
    main()
