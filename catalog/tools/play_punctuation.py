"""The stop a split-off direction leaves behind (catalog DECISIONS 046, BACKLOG-LOOP B27).

A speech that opens on a bracketed direction ("[yawning impatiently]. Come! I am weary...") is cut into a
`direction` part and a `say` part, and the stop that closed the direction is left at the head of the words:
[{"direction": "yawning impatiently"}, {"say": ".\\nCome! I am weary..."}]. The stop belongs to the direction's
closing, not to the speaker, and a voice reads it as a pause or a stray "dot".

`mend` takes it off, in the one place that is certain, and only there:

- a `say` that comes after a direction with no words said before it in the speech loses its leading run of
  `. , ; :` (and the space around it);
- a `say` that comes after a direction in the middle of a speech loses a leading ". " (or a lone ".") when the
  words said before it already end in `. , ! ?`: the print gave that sentence its stop already, and the direction's
  closing stop is the second one. Where the words before do not end in a stop ("(do). This"), the stop is the
  sentence's own and stays.

Never an ellipsis ("..." or the one-character form), never a dash, a quote, a bracket or a letter. A `say` left
empty goes; a speech left with no words becomes a direction, as `play_corrections` makes one. Every line keeps its
id and its place; a line nothing is mended in is the same object, byte for byte, so a play nothing is mended in is
the same entry. Run after `play_corrections.apply`, so the corrections' revisions and quoted evidence are read
against the play as the roles left it.
"""
import re

import play_corrections as PC

STOPS = ".,;:"


def _lead(say):
    """The said words without the direction's closing stops at their head, or the words as they are."""
    s, took = say, False
    while True:
        t = s.lstrip()
        if t[:1] in STOPS and t[:1] and not t.startswith(".."):
            s, took = t[1:], True
        else:
            break
    return s.lstrip() if took else say


def _mid(say, before):
    if before and before[-1] in ".!?" and re.match(r"\.(?!\.)(\s|$)", say):
        return say[1:].lstrip()
    return say


def mend_parts(parts, em=()):
    """(parts, em) with the stray stops off, or the arguments themselves when none is."""
    out, keep, said = [], [], None
    changed = False
    for i, p in enumerate(parts):
        if "say" in p and i and "direction" in parts[i - 1]:
            now = _lead(p["say"]) if said is None else _mid(p["say"], said)
            if now != p["say"]:
                changed = True
                if not now.strip():
                    continue
                p = {**p, "say": now}
        out.append(p)
        keep.append(i)
        if "say" in p:
            said = p["say"]
    if not changed:
        return parts, em
    where = {old: new for new, old in enumerate(keep)}
    return out, [where[k] for k in em if k in where]


def mend(entry):
    """The entry with its stray stops taken off, or the entry itself when it has none."""
    lines, changed = [], False
    for line in entry["lines"]:
        if line["kind"] != "speech":
            lines.append(line)
            continue
        parts, em = mend_parts(line["parts"], line.get("em") or [])
        if parts is line["parts"]:
            lines.append(line)
            continue
        changed = True
        if not any("say" in p for p in parts):
            lines.append(PC._direction(line["id"], PC._segments({**line, "parts": parts})))
            continue
        new = {k: v for k, v in line.items() if k != "em"}
        new["parts"] = parts
        if em:
            new["em"] = em
        lines.append(new)
    if not changed:
        return entry
    return {**entry, "revision": PC._revision(lines), "lines": lines, "roles": PC._roles(lines)}
