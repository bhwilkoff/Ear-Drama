"""No DOM call is handed a bare null child.

`replaceChildren`, `append` and `prepend` turn a null argument into the text
"null"; the `el()` helpers skip nulls, the DOM does not. Library drew "null" beside
"Join a room" on 2026-10-28 (js/together-ui.js paintRow: a ternary ending `: null`).
A call whose arguments contain a ternary null must filter its children first.

    python3 tools/test_js_null_children.py            # every js/*.js
    python3 tools/test_js_null_children.py FILE ...   # given files (the negative control)
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CALL = re.compile(r"\.(replaceChildren|append|prepend)\(")
TERNARY_NULL = re.compile(r"[?:]\s*null\b")


def args_at(src, i):
    """The text between the call's '(' at i and its matching ')'."""
    depth, j = 0, i
    while j < len(src):
        c = src[j]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                return src[i + 1:j]
        elif c in "'\"`":
            q, j = c, j + 1
            while j < len(src) and src[j] != q:
                j += 2 if src[j] == "\\" else 1
        j += 1
    return src[i + 1:]


def top_level(a):
    """The arguments with every nested (...) [...] {...} and string emptied: a null
    inside an el() call is that helper's to skip, not the DOM's."""
    out, depth, j = [], 0, 0
    while j < len(a):
        c = a[j]
        if c in "'\"`":
            q, j = c, j + 1
            while j < len(a) and a[j] != q:
                j += 2 if a[j] == "\\" else 1
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif depth == 0:
            out.append(c)
        j += 1
    return "".join(out)


def offenders(path):
    src = Path(path).read_text(encoding="utf-8")
    out = []
    for m in CALL.finditer(src):
        a = args_at(src, m.end() - 1)
        if TERNARY_NULL.search(top_level(a)) and "filter(Boolean)" not in a:
            out.append(f"{path}:{src.count(chr(10), 0, m.start()) + 1}: .{m.group(1)}(...) can draw \"null\"")
    return out


def main():
    files = sys.argv[1:] or sorted(str(p) for p in (REPO / "js").glob("*.js") if not p.name.endswith(".test.js"))
    bad = [o for f in files for o in offenders(f)]
    for b in bad:
        print("FAIL", b)
    print(f"{'FAIL' if bad else 'ok'}: {len(files)} files, {len(bad)} null-child calls")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
