"""Which served episodes carry a script a person may record from (Decision 068).

    python3 tools/episode_scripts.py          # the counts, from out/radio-catalog.sqlite and the bundle

An episode's `script` is a castable script's id, and it is set only when all of
these hold, so a wrong match is never published:

    1. the research database matched the script to the episode (build_db: series + air date);
    2. the script's date is the episode's date, and its series is the episode's series
       (or, across a series name the two sources spell differently, the titles are equal);
    3. the titles agree (`title_agrees`): equal, or every content word of the shorter
       in the longer, with at least two of them. "Episode 170" never agrees with anything;
    4. the script is in the castable bundle (plays/castable-scripts.json, which only
       script_rights' castable rescues reach) and its bucket is still a castable one.

Nothing here judges rights: the bundle is the rights test's output. A script whose
source has not given permission (Generic Radio Workshop: "Assume Copyright", until
they answer the owner) is matched and counted as `awaiting_permission`, never linked.
When a source answers, its terms change in editorial/script_evidence.json, the
bundle is rebuilt, and the links follow with no change here.
"""
import json
import os
import re
import sqlite3
import sys
import unicodedata

sys.path.insert(0, os.path.dirname(__file__))
import script_rights as R

HERE = os.path.dirname(os.path.abspath(__file__))
BUNDLE = os.path.join(HERE, "..", "plays", "castable-scripts.json")
# The research database's `scripts.source` -> the id prefix the castable bundle gives that source's scripts.
BUNDLE_PREFIX = {"genericradio.com": "grw-"}
SOURCE_NAME = {"genericradio.com": "Generic Radio Workshop"}
STOP = {"the", "a", "an", "of", "and", "in", "on", "to", "at", "for", "with", "from", "by", "is"}


def _words(t):
    t = "".join(c for c in unicodedata.normalize("NFD", t or "") if unicodedata.category(c)[0] != "M").lower()
    t = re.sub(r"[\(\[][^\)\]]*[\)\]]", " ", t).replace("&", " and ")
    t = re.sub(r"[^a-z0-9 ]", "", re.sub(r"[-/:;,.!?\"']+", " ", t))
    return t.split()


def title_agrees(a, b):
    wa, wb = _words(a), _words(b)
    if not wa or not wb:
        return False
    if "".join(wa) == "".join(wb):
        return True
    ca, cb = [w for w in wa if w not in STOP], [w for w in wb if w not in STOP]
    small, large = (ca, cb) if len(ca) <= len(cb) else (cb, ca)
    return len(set(small)) >= 2 and set(small) <= set(large)


def load_bundle(path=BUNDLE):
    """id -> bundle entry; an absent file links nothing."""
    try:
        return {s["id"]: s for s in json.load(open(path, encoding="utf-8")).get("scripts", [])}
    except FileNotFoundError:
        return {}


def castable_entry(entry):
    return bool(entry) and R.STATE.get((entry.get("rights") or {}).get("bucket")) == "castable"


def source_terms(path=R.EDITORIAL):
    try:
        return json.load(open(path, encoding="utf-8")).get("source_terms", {})
    except FileNotFoundError:
        return {}


def links(s, served, bundle, terms=None):
    """`s`: the research database; `served`: the episode ids the projection writes.
    Returns ({episode id: script id}, report)."""
    terms = source_terms() if terms is None else terms
    report = {"scripts": 0, "matched_served": 0, "title_disagrees": 0, "linked": 0, "awaiting_permission": 0,
              "not_castable": 0}
    tables = {r[0] for r in s.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
    if "scripts" not in tables:
        return {}, report
    eps = {eid: (sk, air, title, aka) for eid, sk, air, title, aka in
           s.execute("SELECT id, series_key, air_date, title, aka FROM episodes")}
    out = {}
    for sid, source, sk, air, title, eid in s.execute(
            "SELECT id, source, series_key, air_date, title, episode_id FROM scripts ORDER BY id"):
        report["scripts"] += 1
        if not eid or eid not in served or eid not in eps:
            continue
        esk, eair, etitle, eaka = eps[eid]
        if not air or air != eair:
            continue
        agree = any(title_agrees(title, t) for t in (etitle, eaka) if t)
        if not agree or (sk != esk and "".join(_words(title)) != "".join(_words(etitle))):
            report["title_disagrees"] += 1
            continue
        report["matched_served"] += 1
        bid = BUNDLE_PREFIX.get(source, "") + sid
        if castable_entry(bundle.get(bid)):
            if eid not in out:
                out[eid] = bid
                report["linked"] += 1
        elif (terms.get(SOURCE_NAME.get(source, source)) or {}).get("reuse") == "ask":
            report["awaiting_permission"] += 1
        else:
            report["not_castable"] += 1
    return out, report


def check(projection, bundle):
    """The guard: every published link names a script in the bundle whose bucket is castable.
    Returns the offending (episode id, script id) pairs."""
    cols = {r[1] for r in projection.execute("PRAGMA table_info(episodes)")}
    if "script" not in cols:
        return []
    return [(e, sc) for e, sc in projection.execute("SELECT id, script FROM episodes WHERE script IS NOT NULL")
            if not castable_entry(bundle.get(sc))]


def main():
    import ia_lib as ia
    s = sqlite3.connect(f"file:{os.path.join(ia.OUT, 'radio-catalog.sqlite')}?mode=ro", uri=True)
    served = {r[0] for r in s.execute("SELECT id FROM episodes WHERE state IN ('keep_clean', 'keep_unclaimed')")}
    bundle = load_bundle()
    _, report = links(s, served, bundle)
    report["bundle_radio_castable"] = sum(1 for b in bundle.values() if b.get("kind") == "radio" and castable_entry(b))
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
