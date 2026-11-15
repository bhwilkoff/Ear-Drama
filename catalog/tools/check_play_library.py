"""The shape check for a built play library (docs/CATALOG-CONTRACT.md 4.1): one function the build's
test, the Release packer, and the site assembly all call, so a library that fails it never ships.

    python3 tools/check_play_library.py [DIR]       # default catalog/out/plays-library; exits 1 on a defect

It reads shape and cross-file consistency, never which plays exist. `MIN_PLAYS` is a floor against an
empty or truncated library, not a pin on the catalog: it is far below any real build.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import play_phonemes as PH

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT = os.path.join(HERE, "..", "out", "plays-library")
FORMAT = 1
MIN_PLAYS = 100
# A shipped library carries phonemes (Decision 078) for at least this share of its plays; the rest are
# held for an editor (play_phonemes.HOLD_GUESSED_SHARE) and read by the system voice.
MIN_PHONEME_SHARE = 0.8


def check_library(root, min_plays=1, min_phoneme_share=0.0):
    """Shape and consistency of a built library; returns the index. Raises AssertionError. With
    min_phoneme_share > 0 the library must carry phonemes for at least that share of its plays."""
    idx = json.load(open(os.path.join(root, "index.json")))
    assert idx["format"] == FORMAT and isinstance(idx["plays"], list)
    assert idx["count"] == len(idx["plays"]) >= min_plays, f"{len(idx['plays'])} plays, need at least {min_plays}"
    names = sorted(os.listdir(os.path.join(root, "scripts")))
    assert names == sorted(f"{p['id']}.json" for p in idx["plays"]), "scripts/ and the index name different plays"
    ids = [p["id"] for p in idx["plays"]]
    assert len(ids) == len(set(ids)), "duplicate id"
    keys = [(p["sort_name"], p["id"]) for p in idx["plays"]]
    assert keys == sorted(keys), "index is not in sort order"
    for p in idx["plays"]:
        assert re.fullmatch(r"gut-\d+(-\d+)?", p["id"]), p["id"]
        assert ("collection" in p) or re.fullmatch(r"gut-\d+", p["id"]), (p["id"], "a split play names its volume")
        assert p["kind"] in ("stage", "radio"), p
        for k in ("title", "revision", "path"):
            assert isinstance(p[k], str) and p[k], (p["id"], k)
        assert p["path"] == f"scripts/{p['id']}.json"
        assert isinstance(p["authors"], list) and all(isinstance(a, str) for a in p["authors"])
        assert isinstance(p["voices"], int) and p["voices"] >= 2, p
        assert p["roles"] >= p["voices"] and p["words"] > 0 and p["minutes"] >= 1 and p["lines"] > 0
        assert "year" not in p or isinstance(p["year"], int)
        assert p["rights"]["bucket"] and p["rights"]["evidence"], (p["id"], "no rights evidence")
        for ev in p["rights"]["evidence"]:
            assert ev["claim"] and ev["src"].startswith("http"), p["id"]
        assert p["source"]["url"].startswith("http")
        doc = json.load(open(os.path.join(root, p["path"])))
        assert doc["format"] == FORMAT and len(doc["scripts"]) == 1
        s = doc["scripts"][0]
        assert s["id"] == p["id"] and s["revision"] == p["revision"] and s["title"] == p["title"]
        assert len(s["roles"]) == p["roles"] and s["rights"] == p["rights"]
        speech = [l for l in s["lines"] if l["kind"] == "speech"]
        assert len(speech) == p["lines"]
        assert all(l["role"] and l["parts"] for l in speech)
        if "phonemes" in p:
            assert p["phonemes"] == f"phonemes/{p['id']}.json", (p["id"], p["phonemes"])
            PH.check_phoneme_file(json.load(open(os.path.join(root, p["phonemes"]), encoding="utf-8")), s)
    check_phonemes(root, idx, min_phoneme_share)
    return idx


def check_phonemes(root, idx, min_share):
    """The phoneme files (docs/CATALOG-CONTRACT.md 4.1) agree with the index; each was checked against its
    script in check_library."""
    with_ps = sorted(f"{p['id']}.json" for p in idx["plays"] if "phonemes" in p)
    folder = os.path.join(root, "phonemes")
    files = sorted(os.listdir(folder)) if os.path.isdir(folder) else []
    assert files == with_ps, "phonemes/ and the index name different plays"
    meta = idx.get("phonemes")
    if with_ps or meta:
        assert meta and meta["format"] == PH.FORMAT and meta["dialects"] == list(PH.DIALECTS), meta
        assert meta["plays"] == len(with_ps), (meta["plays"], len(with_ps))
        assert meta["plays"] + meta["held_for_review"] == len(idx["plays"]), meta
        assert os.path.exists(os.path.join(root, meta["report"])), "no phoneme report"
    share = len(with_ps) / max(1, len(idx["plays"]))
    assert share >= min_share, f"phonemes for {len(with_ps)} of {len(idx['plays'])} plays, need {min_share:.0%}"


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    try:
        idx = check_library(root, MIN_PLAYS, MIN_PHONEME_SHARE)
    except (AssertionError, OSError, ValueError, KeyError) as e:
        sys.exit(f"play library at {root} failed its shape check: {e!r}")
    print(f"play library ok: {idx['count']} plays, {idx['phonemes']['plays']} with phonemes, at {root}")


if __name__ == "__main__":
    main()
