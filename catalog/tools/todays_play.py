"""Today's play (Decision 075, WEB-DESIGN §4.2): the reference copy of the date rotation every
client mirrors (js/plays-core.js `todaysPlay`, Apple `PlayScript.todaysPlay`, Android
`todaysPlay`). The script whose FNV-1a 64 of "play:{YYYY-MM-DD}:{id}" (UTF-8) is smallest,
ties by id. Order-independent, never a seeded shuffle (cross-platform-determinism).

    python3 tools/todays_play.py --write   # regenerate tests/golden/todays_play.json
"""
import json
import os
import sys

MASK = 0xFFFFFFFFFFFFFFFF


def fnv1a64(s):
    h = 0xCBF29CE484222325
    for b in s.encode("utf-8"):
        h ^= b
        h = (h * 0x100000001B3) & MASK
    return h


def todays_play(ids, date_key):
    return min(ids, key=lambda i: (fnv1a64(f"play:{date_key}:{i}"), i)) if ids else None


# Today's scene (Decision 079, WEB-DESIGN 4.2 item 7): the same hash over a pool, the first non-empty of
# two voices and at most 20 minutes, two or three voices and at most 30, every play.
SCENE_POOLS = [(2, 2, 20), (2, 3, 30)]


def scene_pool(rows):
    for lo, hi, most in SCENE_POOLS:
        pool = [r for r in rows if lo <= r["voices"] <= hi and max(1, r["minutes"]) <= most]
        if pool:
            return pool
    return rows


def todays_scene(rows, date_key):
    return todays_play([r["id"] for r in scene_pool(rows)], date_key)


GOLDEN = os.path.join(os.path.dirname(__file__), "..", "tests", "golden", "todays_play.json")
# Fixed ids, not the bundled library: a test never pins catalog contents. One id is non-ASCII
# so a stack that hashes UTF-16 or sign-extends bytes fails.
IDS = ["gut-28051", "gut-2265", "gut-49295", "gut-7364", "gut-5071", "gut-12039", "lib-café-1", "usda-0001"]
# Each pool's edge: 20 and 21 minutes, three voices, one voice, twelve.
SCENE_ROWS = [
    {"id": "gut-28051", "voices": 2, "minutes": 17}, {"id": "gut-2265", "voices": 2, "minutes": 20},
    {"id": "gut-49295", "voices": 2, "minutes": 21}, {"id": "gut-7364", "voices": 3, "minutes": 12},
    {"id": "gut-5071", "voices": 1, "minutes": 5}, {"id": "gut-12039", "voices": 12, "minutes": 175},
    {"id": "lib-café-1", "voices": 2, "minutes": 9}, {"id": "usda-0001", "voices": 4, "minutes": 15},
]
SCENE_SUBSETS = [
    ["gut-49295", "gut-7364", "gut-12039", "usda-0001"],  # no two-voice play of 20 min: the 2-3 voices, 30 min pool
    ["gut-5071", "gut-12039"],  # neither pool: every play
]
DATES = ["2026-01-01", "2026-02-28", "2026-02-29", "2026-11-14", "2026-11-15", "2026-12-31", "2027-06-01", "2030-07-04"]


def golden():
    return {
        "rule": "the id whose FNV-1a 64 of 'play:{date}:{id}' (UTF-8) is smallest, ties by id",
        "hashes": [{"text": t, "fnv1a64": format(fnv1a64(t), "016x")} for t in ("", "a", "play:2026-11-14:gut-2265", "lib-café-1")],
        "ids": IDS,
        "cases": [{"date": d, "want": todays_play(IDS, d)} for d in DATES]
                 + [{"date": "2026-11-14", "ids": IDS[:1], "want": IDS[0]}, {"date": "2026-11-14", "ids": [], "want": None}],
        "scene": {
            "rule": "todays play over the first non-empty pool: voices == 2 and minutes <= 20; 2 <= voices <= 3 and minutes <= 30; every play",
            "rows": SCENE_ROWS,
            "cases": [{"date": d, "want": todays_scene(SCENE_ROWS, d)} for d in DATES]
                     + [{"date": d, "ids": ids, "want": todays_scene([r for r in SCENE_ROWS if r["id"] in ids], d)}
                        for ids in SCENE_SUBSETS for d in DATES[:4]]
                     + [{"date": "2026-11-15", "ids": [], "want": None}],
        },
    }


if __name__ == "__main__":
    g = golden()
    if "--write" in sys.argv:
        with open(GOLDEN, "w", encoding="utf-8") as f:
            json.dump(g, f, indent=1, ensure_ascii=False)
            f.write("\n")
    with open(GOLDEN, encoding="utf-8") as f:
        ok = json.load(f) == g
    print("todays_play golden", "matches" if ok else "DIFFERS")
    sys.exit(0 if ok else 1)
