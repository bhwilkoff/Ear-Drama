"""The verse's line numbers, printed in the margin and read as words (catalog DECISIONS 048, BACKLOG-LOOP B28).

A text that numbers its verse prints the number after the row's end ("how wert thou fallen          20" over "Son of the
Morning!"), and the rows of a speech are joined, so a speaker says "fallen twenty Son of the Morning".

A play is numbered when its spoken words hold at least FEWEST numbers, every one a multiple of five with three spaces or more
before it, and nearly all larger than the one before. In such a play those numbers are taken off, and with them the few
printed without the spaces ("no pilgrim 30" ending a row), each only where it falls between the number before and the one
after and nothing but a row's end or a capital follows. No other word or digit is touched; a play that is not numbered is the
same entry. Run after `play_corrections.apply`.
"""
import re

import play_corrections as PC

FEWEST = 5
RISING = 0.8
NEXT = 30  # how far past the last number one printed without the spaces may stand
WIDE = re.compile(r"(?<=\S)[ \t]{3,}(\d{1,4})(?=\s|$)")
NUMBER = re.compile(r"(?<!\S)(\d{1,4})(?=\s+[\"'“‘(\[]*[A-ZÀ-Þ]|\s*$|[ \t]*\n)")


def _spans(entry):
    """[(line index, part index, start, end, number, whether the spaces are printed)] in the play's order."""
    out = []
    for i, line in enumerate(entry["lines"]):
        for k, part in enumerate(line.get("parts") or ()):
            if "say" not in part:
                continue
            wide = {m.start(1): m for m in WIDE.finditer(part["say"])}
            found = {**{m.start(1): m for m in NUMBER.finditer(part["say"])}, **wide}
            for at in sorted(found):
                n = int(found[at].group(1))
                if n and n % 5 == 0:
                    out.append((i, k, at, found[at].end(1), n, at in wide))
    return out


def margin_numbers(entry):
    """The spans of the play's margin numbers, or none when it is not numbered."""
    spans = _spans(entry)
    wide = [s[4] for s in spans if s[5]]
    if len(wide) < FEWEST or sum(a < b for a, b in zip(wide, wide[1:])) < RISING * (len(wide) - 1):
        return []
    out, last = [], 0
    for x, s in enumerate(spans):
        if not s[5]:
            ahead = next((t[4] for t in spans[x + 1:] if t[5]), None)
            if not last < s[4] <= last + NEXT or ahead is not None and ahead > last and s[4] >= ahead:
                continue
        last = s[4]
        out.append(s)
    return out


def _without(say, spans):
    out, at = "", 0
    for a, b in spans:
        head, tail = say[at:a], re.match(r"\s*", say[b:]).group(0)
        gap = head[len(head.rstrip()):] + tail
        out += head.rstrip() + ("\n" if "\n" in gap else " ")
        at = b + len(tail)
    return (out + say[at:]).strip()


def mend(entry):
    """The entry with its margin numbers taken off, or the entry itself when it has none."""
    gone = {}
    for i, k, a, b, _, _ in margin_numbers(entry):
        gone.setdefault(i, {}).setdefault(k, []).append((a, b))
    if not gone:
        return entry
    lines = list(entry["lines"])
    for i, by_part in gone.items():
        line = lines[i]
        parts, em = [], []
        for k, p in enumerate(line["parts"]):
            if k in by_part:
                p = {"say": _without(p["say"], by_part[k])}
                if not p["say"]:
                    continue
            parts.append(p)
            if k in (line.get("em") or ()):
                em.append(len(parts) - 1)
        new = {k: v for k, v in line.items() if k != "em"}
        new["parts"] = parts
        if em:
            new["em"] = em
        lines[i] = new if any("say" in p for p in parts) else PC._direction(line["id"], PC._segments(new)) if parts else line
    return {**entry, "revision": PC._revision(lines), "lines": lines, "roles": PC._roles(lines)}
