"""Planted data for the tests: a made-up corpus, a small index of it, and the recorded service answers.

No real play is used. Words are made of syllables, so none is in any title list, and a test can plant a
marker word and prove it never leaves.
"""
import collections
import gzip
import json
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from originality import index as I  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SYL = ["ba", "ke", "lo", "mi", "nu", "pra", "ste", "tor", "vin", "wex", "zo", "dra", "fel", "gor", "hu", "jan", "kri", "lum"]


def vocab(rng, n=3000):
    seen, out = set(), []
    while len(out) < n:
        w = "".join(rng.choice(SYL) for _ in range(rng.randint(1, 3)))
        if w not in seen:
            seen.add(w)
            out.append(w)
    return out


def doc(rng, words, weights, n):
    ws = rng.choices(words, weights, k=n)
    return "\n".join(" ".join(ws[i:i + 9]).capitalize() + "." for i in range(0, n, 9))


def corpus(seed=7, gut=24, tr=12, grw=5, n=4000):
    rng = random.Random(seed)
    words = vocab(rng)
    weights = [1 / (i + 4) for i in range(len(words))]
    return {"gut": {f"gut-{i}": doc(rng, words, weights, n) for i in range(gut)},
            "tr": {f"tr-{i}|x|1940-01-{i + 1:02d}": doc(rng, words, weights, n) for i in range(tr)},
            "grw": {f"grw-{i}": doc(rng, words, weights, n) for i in range(grw)}}


def build_index(out, c, date="2026-11-25", without=()):
    os.makedirs(out, exist_ok=True)
    freq, sources = collections.Counter(), {}
    for src in I.REQUIRED + I.OPTIONAL:
        if src in without:
            continue
        sources[src] = I.build_source(src, sorted(c[src].items()), out, freq=freq if src == "tr" else None)
    for src in c["gut"], c["tr"]:
        for t in src.values():
            freq.update(I.N.words(t))
    I.write_freq(out, freq)
    for s in ("gut", "grw", "cce"):
        t = {}
        if s == "gut":
            t = {"firstplay": [["gut-1", "First Play", "Ada Quill"]], "hamlet": [["gut-2", "Hamlet", "W Shakespeare"]],
                 "fences": [["gut-3", "Fences", "August Wilson"]]}
        with gzip.open(os.path.join(out, f"titles-{s}.json.gz"), "wt") as f:
            json.dump(t, f)
    return I.write_manifest(out, date, 5, 12, sources)


def fixture(name):
    return I.jload(os.path.join(HERE, "fixtures", name))


def play_raw(c, name):
    return c["gut"][name]
