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
# A library built since B31 C1 carries `pictures` (play_art.summary); at least this share of its plays must wear one
# (measured 2026-11-26: 49%). A build on a machine without the picture caches stops in play_art.attach; this catches
# a cache that is there but serves nothing. An index with no summary predates the rule and is read as it is.
MIN_PICTURE_SHARE = 0.25


def check_library(root, min_plays=1, min_phoneme_share=0.0, min_picture_share=0.0):
    """Shape and consistency of a built library; returns the index. Raises AssertionError. With
    min_phoneme_share > 0 the library must carry phonemes for at least that share of its plays; with
    min_picture_share > 0, a library that carries the pictures summary must have pictures on that share."""
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
        assert p["voices"] == sum(1 for r in s["roles"] if r["lines"] >= 1), (p["id"], "voices is the parts with a spoken line")
        # A role's stand-in register (catalog DECISIONS 049): "high" or "low" or absent, and the index's letters say the same
        # in the order of `cast` (largest first). A library built before 2026-11-26 has neither, and still deploys.
        assert all(r.get("register", "high") in ("high", "low") for r in s["roles"]), (p["id"], "a register is high or low")
        assert p["cast"] == sorted((r["lines"] for r in s["roles"]), reverse=True), (p["id"], "cast is each role's speeches")
        if "registers" in p or any("register" in r for r in s["roles"]):
            order = sorted(s["roles"], key=lambda r: -r["lines"])
            assert p.get("registers") == "".join({"high": "h", "low": "l"}.get(r.get("register"), "-") for r in order), \
                (p["id"], "registers is each role's register, in the order of cast")
        speech = [l for l in s["lines"] if l["kind"] == "speech"]
        assert len(speech) == p["lines"]
        assert all(l["role"] and l["parts"] for l in speech)
        if "phonemes" in p:
            assert p["phonemes"] == f"phonemes/{p['id']}.json", (p["id"], p["phonemes"])
            PH.check_phoneme_file(json.load(open(os.path.join(root, p["phonemes"]), encoding="utf-8")), s)
    check_phonemes(root, idx, min_phoneme_share)
    check_pictures(idx, min_picture_share)
    check_finding(root, idx)
    return idx


def check_pictures(idx, min_share):
    """The pictures summary (play_art.summary) agrees with the rows, and enough rows wear a picture."""
    s = idx.get("pictures")
    if s is None:
        return
    rows = idx["plays"]
    kinds = {}
    for p in rows:
        if p.get("picture"):
            assert p["picture"].get("url") and p["picture"].get("kind") in ("work", "production", "book", "titlePage", "author"), p["id"]
            kinds[p["picture"]["kind"]] = kinds.get(p["picture"]["kind"], 0) + 1
    assert s["plays"] == len(rows) and s["picture"] == sum(kinds.values()) and s["kinds"] == dict(sorted(kinds.items())), s
    share = s["picture"] / max(1, len(rows))
    assert share >= min_share, f"pictures on {s['picture']} of {len(rows)} plays ({share:.0%}), need {min_share:.0%}: are the picture caches restored?"


FORM_HUES = {"comedy": "comedy", "farce": "comedy", "tragedy": "drama", "tragicomedy": "drama", "history": "documentary",
             "fantasy": "scifi", "religious": "serial", "melodrama": "mystery", "libretto": "news"}
ERAS = ("Antiquity", "Medieval", "1500s", "1600s", "1700s", "1800s", "1900-1930")


def check_finding(root, idx):
    """The finding facets on each row (contract 4.1, B31 C3) and the files beside the index: collections.json,
    characters.json, search/said/ and search/lines/. A library built before them carries none and passes."""
    rows = idx["plays"]
    n = len(rows)
    ids = {p["id"] for p in rows}
    for p in rows:
        if "form" in p:
            assert FORM_HUES.get(p["form"]) == p["hue"] and p["formSource"] in ("subject", "title"), (p["id"], p["form"])
        assert "era" not in p or p["era"] in ERAS, (p["id"], p.get("era"))
        assert "balance" not in p or p["balance"] in ("ensemble", "mixed", "lead"), p["id"]
        assert "locc" not in p or re.fullmatch(r"[A-Z]{1,2}", p["locc"]), p["id"]
        assert "subjects" not in p or (p["subjects"] and all(isinstance(t, str) and t for t in p["subjects"])), p["id"]
        for k in ("oneAct", "translated", "attributed"):
            assert p.get(k, True) is True, (p["id"], k)
        for sc in p.get("scenes") or []:
            assert 2 <= sc["voices"] <= 4 and len(sc["parts"]) == sc["voices"] and 1 <= sc["minutes"] <= 12, (p["id"], sc)
            assert sc["heading"] and re.fullmatch(r"L\d{4}[a-z]?", sc["line"]), (p["id"], sc)
        assert len(p.get("scenes") or []) <= 6, p["id"]
    path = os.path.join(root, "collections.json")
    if os.path.exists(path):
        doc = json.load(open(path, encoding="utf-8"))
        assert doc["format"] == FORMAT
        for c in doc["data"] + doc["editor"]:
            assert c["id"] and c["title"] and c["count"] == len(c["plays"]) >= 1, c.get("id")
            missing = [x for x in c["plays"] if x not in ids]
            assert not missing, (c["id"], "names plays not in the index", missing[:3])
            assert len(set(c["plays"])) == len(c["plays"]), (c["id"], "a play twice")
        for c in doc["data"]:
            assert c["rule"], c["id"]
        for c in doc["editor"]:
            assert c["by"] and c["added"] and c["count"] >= 3, c["id"]
    path = os.path.join(root, "characters.json")
    if os.path.exists(path):
        doc = json.load(open(path, encoding="utf-8"))
        assert doc["format"] == FORMAT
        for name, plays in doc["names"].items():
            assert name and name == name.upper(), name
            assert all(0 <= k < n and lines >= 1 for k, lines in plays), name
    folder = os.path.join(root, "search", "said")
    if os.path.isdir(folder):
        for f in sorted(os.listdir(folder)):
            assert re.fullmatch(r"([a-z0-9]{2}|x[0-9a-f]+)\.json", f), f
            for w, deltas in json.load(open(os.path.join(folder, f), encoding="utf-8")).items():
                k = -1
                for i, d in enumerate(deltas):
                    assert (d >= 0 if i == 0 else d >= 1), (f, w)
                    k = d if i == 0 else k + d
                assert 0 <= k < n, (f, w, "a play number past the index")
    folder = os.path.join(root, "search", "lines")
    if os.path.isdir(folder):
        sizes = {p["id"]: None for p in rows}
        for f in sorted(os.listdir(folder)):
            assert re.fullmatch(r"([a-z0-9]{2}|x[0-9a-f]+)\.json", f), f
            for w, flat in json.load(open(os.path.join(folder, f), encoding="utf-8")).items():
                i, k = 0, 0
                while i < len(flat):
                    assert flat[i] >= (0 if i == 0 else 1) and flat[i + 1] >= 1, (f, w, "a play out of order or with no line")
                    k += flat[i]
                    assert 0 <= k < n, (f, w, "a play number past the index")
                    ds = flat[i + 2:i + 2 + flat[i + 1]]
                    assert len(ds) == flat[i + 1] and all(d >= (0 if j == 0 else 1) for j, d in enumerate(ds)), (f, w, "lines out of order")
                    pid = rows[k]["id"]
                    if sizes[pid] is None:
                        sp = os.path.join(root, rows[k].get("path") or f"scripts/{pid}.json")
                        sizes[pid] = len(json.load(open(sp, encoding="utf-8"))["scripts"][0]["lines"]) if os.path.exists(sp) else 10 ** 9
                    assert sum(ds) < sizes[pid], (f, w, pid, "a line place past the script")
                    i += 2 + flat[i + 1]


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
        idx = check_library(root, MIN_PLAYS, MIN_PHONEME_SHARE, MIN_PICTURE_SHARE)
    except (AssertionError, OSError, ValueError, KeyError) as e:
        sys.exit(f"play library at {root} failed its shape check: {e!r}")
    pics = idx.get("pictures")
    print(f"play library ok: {idx['count']} plays, {idx['phonemes']['plays']} with phonemes, "
          f"{pics['picture'] if pics else 'no summary of'} pictures, at {root}")


if __name__ == "__main__":
    main()
