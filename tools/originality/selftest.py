"""The planted-copy gate (R4-9 section 5.4). From a few plays that are in the index, build verbatim, renamed, OCR 3%,
21%-synonym, one-act and 150-in-2,000 copies; every one must hold and name its source. One control, a play's
words shuffled, must not hold. A failed self-test judges nothing: judge() refuses a gate that did not pass, or
one made against another index.

It runs the same judge.content() a real script goes through, so a changed threshold, k, or an emptied index fails
here first.
"""
import random

from originality import judge as J
from originality import plant as PL


class Gate:
    def __init__(self, index_id, results):
        self.index_id = index_id
        self.results = results
        self.passed = bool(results) and all(ok for _, _, ok in results)

    def failures(self):
        return [(w, c) for w, c, ok in self.results if not ok]


def run(index, plays, seed=20261125):
    """plays: {document name in the index: raw text}; at least three, and one more is the control and the filler."""
    names = sorted(plays)
    if len(names) < 4:
        return Gate(index.id, [])
    results = []
    plant_names, control = names[:-1], names[-1]
    filler = plays[control]
    for n, name in enumerate(plant_names):
        for cls, text in PL.plants(plays[name], filler, seed + n):
            r = J.content(index, text)
            # another edition of the same play may rank first; the source must be among the works found
            named = any(w["work"] == name and w["copied"] >= J.RUN_WORDS for w in r["works"])
            results.append((name, cls, bool(r["held"] and named)))
    ctrl = J.content(index, PL.shuffled(plays[control], random.Random(seed)))
    results.append((control, "shuffled_control", not ctrl["held"]))
    return Gate(index.id, results)
