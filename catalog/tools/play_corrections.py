"""Audited per-play corrections to a published play's reading (catalog DECISIONS 046, BACKLOG-LOOP B22).

`play_roles` settles every fault a rule can settle. What a class of three plays or more does not cover is one
person's reading of one line, listed in `editorial/play_corrections.json`, and applied after the roles, to the
entry the build has already judged, chosen and mended. A correction can only move the source's own words:

- `role`: a speech goes to the speaker the print names;
- `direction`: a speech is a stage direction, its words kept;
- `speech`: a direction is a speech of the speaker the print names, its words kept;
- `drop`: a line is set aside (a cast row, a title page); its id stays used;
- `split`: a line is cut where a quoted passage begins, into pieces that are each a speech of a named speaker or a
  direction; a printed label standing between two pieces may be cut away (`cut`, quoted), and a piece may be set aside (`as: drop`).

Never a word added: every piece is a slice of the line, and the words that leave are the quoted `cut` and `drop`
words, counted. Every correction names the `revision` of the entry it was read against; when a rule changes that
play afterwards the correction is refused, loudly, and a person reads the play again. Line ids never move: a piece
after the first takes the next letter its number has not used (`L0331` -> `L0331a`), as `play_roles` does.
"""
import collections
import hashlib
import json
import os
import re

import script_parse as P

HERE = os.path.dirname(os.path.abspath(__file__))
PATH = os.path.join(HERE, "..", "editorial", "play_corrections.json")
FORMAT = 1
OPS = ("role", "direction", "speech", "drop", "split")
EVIDENCE_WORDS = 12


_LOADED = None


class Refused(ValueError):
    """A correction that does not apply to the play as built."""


def squash(s):
    return re.sub(r"\s+", " ", s).strip()


def load(path=PATH):
    """{play id: [correction, ...]}, in file order; the file's own shape is checked here."""
    with open(path, encoding="utf-8") as f:
        doc = json.load(f)
    if doc.get("format") != FORMAT:
        raise Refused(f"{path}: format {doc.get('format')!r}, expected {FORMAT}")
    out = collections.defaultdict(list)
    for c in doc["corrections"]:
        for k in ("play", "revision", "line", "op", "evidence", "why"):
            if not isinstance(c.get(k), str) or not c[k].strip():
                raise Refused(f"{c.get('play')} {c.get('line')}: no {k}")
        if c["op"] not in OPS:
            raise Refused(f"{c['play']} {c['line']}: unknown op {c['op']!r}")
        if len(c["evidence"].split()) > EVIDENCE_WORDS:
            raise Refused(f"{c['play']} {c['line']}: evidence is more than {EVIDENCE_WORDS} words")
        out[c["play"]].append(c)
    return dict(out)


def _segments(line):
    if line["kind"] == "speech":
        segs = []
        for p in line["parts"]:
            if len(p) != 1:
                raise Refused(f"{line['id']}: a part with several keys")
            (k, v), = p.items()
            segs.append((k, v))
        return segs
    return [("direction", line["source"])]


def _flat(line):
    return " ".join(v for _, v in _segments(line))


def _revision(lines):
    body = json.dumps(lines, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(body.encode()).hexdigest()[:12]


def _roles(lines):
    roles = collections.OrderedDict()
    for l in lines:
        if l["kind"] != "speech":
            continue
        r = roles.setdefault(l["role"], {"name": l["role"], "lines": 0, "words": 0})
        r["lines"] += 1
        r["words"] += sum(len(p["say"].split()) for p in l["parts"] if "say" in p)
    return list(roles.values())


def _new_id(line_id, taken):
    m = re.fullmatch(r"(L\d{4})[a-z]*", line_id)
    n = 1
    while f"{m.group(1)}{P._letters(n)}" in taken:
        n += 1
    return f"{m.group(1)}{P._letters(n)}"


def _speech(lid, role, segs, em=None):
    out = {"id": lid, "kind": "speech", "role": role, "parts": [{k: v} for k, v in segs]}
    if em:
        out["em"] = em
    return out


def _direction(lid, segs):
    return {"id": lid, "kind": "direction", "source": " ".join(v for _, v in segs).strip()}


def _pieces(line, c, taken):
    """The lines a `split` makes of `line`, the first with its id."""
    segs = _segments(line)
    flat = " ".join(v for _, v in segs)
    spans, at = [], 0
    for k, v in segs:
        spans.append((at, at + len(v)))
        at += len(v) + 1
    pieces = c.get("pieces")
    if not isinstance(pieces, list) or not pieces or len(pieces) == 1 and not pieces[0].get("cut"):
        raise Refused(f"{c['play']} {c['line']}: a split makes two pieces, or cuts one")
    starts = [0]
    for p in pieces[1:]:
        q = p.get("from")
        if not q or flat.count(q) != 1:
            raise Refused(f"{c['play']} {c['line']}: {q!r} is in the line {flat.count(q or '')} times, not once")
        starts.append(flat.index(q))
    if starts != sorted(set(starts)) or starts[0] != 0:
        raise Refused(f"{c['play']} {c['line']}: pieces are not in the order of the line")
    ends = starts[1:] + [len(flat)]
    em_old = set(line.get("em") or [])
    out, gone, ids = [], [], [line["id"]]
    for x, (p, a, b) in enumerate(zip(pieces, starts, ends)):
        cut = p.get("cut")
        if cut:
            if not flat[a:b].lstrip().startswith(cut):
                raise Refused(f"{c['play']} {c['line']}: the piece does not begin with the cut {cut!r}")
            at = flat.index(cut, a)
            gone.append((at, at + len(cut)))
            a = at + len(cut)
        sub, idx = [], []
        for j, ((k, v), (s, e)) in enumerate(zip(segs, spans)):
            lo, hi = max(a, s), min(b, e)
            if lo >= hi:
                continue
            text = v[lo - s:hi - s]
            if text.strip():
                sub.append((k, text.strip()))
                idx.append((j, lo - s == 0 and hi - s == len(v)))
        if not sub:
            raise Refused(f"{c['play']} {c['line']}: piece {x} has no words")
        if p.get("as") == "drop":
            gone.append((a, b))
            continue
        lid = line["id"] if not out else _new_id(line["id"], taken)
        taken.add(lid)
        ids.append(lid)
        if p.get("as") == "direction":
            out.append(_direction(lid, sub))
        elif p.get("as") == "speech" and p.get("role"):
            if line["kind"] == "direction":
                sub = [("say", " ".join(v for _, v in sub))]
            em = []
            for n, (j, whole) in enumerate(idx):
                if j in em_old:
                    if not whole:
                        raise Refused(f"{c['play']} {c['line']}: the cut falls inside an italic part")
                    em.append(n)
            out.append(_speech(lid, p["role"].strip(), sub, em))
        else:
            raise Refused(f"{c['play']} {c['line']}: piece {x} is neither a speech with a role nor a direction")
    kept = "".join(ch for i, ch in enumerate(flat) if not any(a <= i < b for a, b in gone))
    wrote = "".join(q for l in out for q in ([next(iter(p.values())) for p in l["parts"]] if l["kind"] == "speech" else [l["source"]]))
    if re.sub(r"\s+", "", kept) != re.sub(r"\s+", "", wrote):
        raise Refused(f"{c['play']} {c['line']}: the pieces are not the line's own letters, less what was cut: the split lost or added words")
    return out


def apply(entry, corrections=None):
    """The entry with its corrections made, or the entry itself when it has none. Raises Refused on any that does not apply."""
    if corrections is None:
        global _LOADED
        _LOADED = _LOADED or load()
        corrections = _LOADED
    mine = corrections.get(entry["id"])
    if not mine:
        return entry
    lines = [dict(l) for l in entry["lines"]]
    at = {l["id"]: i for i, l in enumerate(lines)}
    taken = set(at)
    whole = squash(" ".join((l["role"] + ". " if l["kind"] == "speech" else "") + _flat(l) for l in lines))
    seen, out = set(), {}
    for c in mine:
        where = f"{c['play']} {c['line']}"
        if c["revision"] != entry["revision"]:
            raise Refused(f"{where}: read against revision {c['revision']}, but the play is now {entry['revision']}; read it again")
        if c["line"] not in at:
            raise Refused(f"{where}: no such line")
        if c["line"] in seen:
            raise Refused(f"{where}: corrected twice")
        seen.add(c["line"])
        if squash(c["evidence"]) not in whole:
            raise Refused(f"{where}: the evidence {c['evidence']!r} is not in the play")
        line = lines[at[c["line"]]]
        op = c["op"]
        if op == "role":
            if line["kind"] != "speech" or not c.get("role") or c["role"] == line["role"]:
                raise Refused(f"{where}: a role correction names another role for a speech")
            out[c["line"]] = [{**line, "role": c["role"].strip()}]
        elif op == "direction":
            if line["kind"] != "speech":
                raise Refused(f"{where}: not a speech")
            out[c["line"]] = [_direction(line["id"], _segments(line))]
        elif op == "speech":
            if line["kind"] != "direction" or not c.get("role"):
                raise Refused(f"{where}: a direction made a speech needs a role")
            out[c["line"]] = [_speech(line["id"], c["role"].strip(), [("say", line["source"])])]
        elif op == "drop":
            out[c["line"]] = []
        else:
            out[c["line"]] = _pieces(line, c, taken)
    new = []
    for l in lines:
        new += out.get(l["id"], [l])
    ids = {l["id"] for l in new}
    for s in entry.get("sections") or []:
        if s["line"] not in ids:
            raise Refused(f"{entry['id']}: a correction took away {s['line']}, where a section opens")
    return {**entry, "revision": _revision(new), "lines": new, "roles": _roles(new)}
