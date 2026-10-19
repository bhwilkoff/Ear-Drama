"""discover_corpus's classifier and guards, on item shapes seen 2026-10-19.

Accept cases sit beside REJECT controls that differ in the one signal the rule
reads. Control seen failing: with classify() replaced by `return True, "x", None`
this test reported 9 failures (every reject case); with the 1980+ file rule
deleted it reported 1 (the modern-dated twin).

    python3 tests/test_discover_corpus.py
"""
import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import discover_corpus as D
import harvest_ia as H


def cand(family="term", **kw):
    return dict({"identifier": "x", "mediatype": "audio", "found_by": [{"family": family, "label": "t"}]}, **kw)


def meta(files, **item):
    return {"item": dict({"mediatype": "audio"}, **item), "files": [{"name": f} for f in files]}


OTR_FILES = ["Gunsmoke 52-04-26 (001) Billy the Kid.mp3", "Gunsmoke 52-05-03 (002) Ben Thompson.mp3",
             "Gunsmoke 52-05-10 (003) Jayhawkers.mp3"]
MODERN_FILES = ["Show 85-04-26 (001) A.mp3", "Show 86-05-03 (002) B.mp3", "Show 87-05-10 (003) C.mp3"]

CASES = [
    # (label, candidate, meta, expect_accept)
    ("dated pre-1980 broadcasts, found by series title", cand("series_title"),
     meta(OTR_FILES, title="Gunsmoke"), True),
    ("control: same series hit, files dated 1985-87", cand("series_title"),
     meta(MODERN_FILES, title="Gunsmoke", subject=["old time radio"]), False),
    ("old-time radio subject, undated files", cand(),
     meta(["ep1.mp3"], title="Box 13", subject=["old time radio"], year="2015"), True),
    ("control: old-time radio subject on a podcast", cand(),
     meta(["ep1.mp3"], title="Filthy '47 - Part 1", subject=["podcast", "old-time radio"],
          collection=["podcasts"], year="2020"), False),
    ("radio drama + pre-1980 year", cand(),
     meta(["a.mp3"], title="Saturday Night Theatre", subject=["radio drama"], year="1962"), True),
    ("control: radio drama, no pre-1980 evidence", cand(),
     meta(["a.mp3"], title="Northern Lights Part 1", subject=["radio drama"], year="2003"), False),
    ("control: pre-1980 music album, nothing says radio", cand("uploader"),
     meta(["01 Moonlight Serenade.mp3"], title="Glenn Miller 78s", year="1941"), False),
    ("control: not audio", cand(), {"item": {"mediatype": "movies", "subject": ["old time radio"]},
                                    "files": [{"name": "a.mp3"}]}, False),
    ("control: audio item with no audio files", cand(),
     {"item": {"mediatype": "audio", "subject": ["old time radio"]}, "files": []}, False),
    ("OTR episode in a podcast feed, found by series title", cand("series_title"),
     meta(["u0ch8hzqvyrhcfm-Thriller832.mp3"], title="Phone Call From Death by The Whistler",
          subject=["Podcast", "otr"], year="2024"), True),
    ("a broadcast's air date says radio", cand(),
     meta(["AV_475.mp3"], title="Hasidic Protests / Elie Wiesel. Air date: 1972-02-27."), True),
    ("control: the same talk with no air date", cand(),
     meta(["AV_475.mp3"], title="Hasidic Protests / Elie Wiesel. 1972-02-27."), False),
    ("OTRR's own log names the item", cand("otrr_archive_id"), meta(["x.mp3"]), True),
    ("control: dark item", cand("otrr_archive_id"), dict(meta(["x.mp3"]), is_dark=True), False),
    ("control: no metadata", cand(), None, False),
]


def main():
    failed = 0
    for label, c, m, want in CASES:
        got, why, _ = D.classify(c, m)
        if got != want:
            failed += 1
            print(f"FAIL {label}: got {got} ({why})")
    # Light gate: a non-audio hit is never fetched; an OTR subject is.
    if D.light_gate(cand(mediatype="texts", subject=["old time radio"])):
        failed += 1
        print("FAIL light gate fetched a texts item")
    if not D.light_gate(cand(subject=["old time radio"])):
        failed += 1
        print("FAIL light gate refused an OTR subject")
    # Never enumerate the 5-million-item umbrella.
    try:
        D.run_query("term", "umbrella", "collection:radioprograms")
        failed += 1
        print("FAIL run_query accepted collection:radioprograms wholesale")
    except RuntimeError:
        pass
    # harvest_ia reads extra_seeds.json ids and an --ids file.
    with tempfile.TemporaryDirectory() as tmp:
        old = H.ia.EDITORIAL
        H.ia.EDITORIAL = tmp
        try:
            with open(os.path.join(tmp, "extra_seeds.json"), "w") as f:
                json.dump({"queries": {"q1": "collection:foo"}, "ids": {"a": {}, "b": {}}}, f)
            idf = os.path.join(tmp, "ids.txt")
            with open(idf, "w") as f:
                f.write("# comment\nb\nc\n")
            q, ids = H.load_extra(idf)
        finally:
            H.ia.EDITORIAL = old
        if q != {"q1": "collection:foo"} or ids != {"a": "extra_seeds", "b": "extra_seeds", "c": "ids_file"}:
            failed += 1
            print(f"FAIL load_extra {q} {ids}")
    print(f"{len(CASES) + 4 - failed}/{len(CASES) + 4} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
