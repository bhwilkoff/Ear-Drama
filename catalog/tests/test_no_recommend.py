"""The never-recommend rules (catalog DECISIONS 013, after Archive Watch Decisions 149 and 174).

Broken control (2026-10-19): with a bare-name pattern (no speech word required), the US
program ABOUT Hitler is flagged, which is the over-reach this rule exists to avoid.
Broken controls (2026-10-28): a speaker-led alternative that takes any title opening with
a name flags "Hitler's Secret Army in America" and "Adolph Hitler and the Nazi Movement";
skipping `not`, or ignoring the deemphasize collection, fails here too.
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import build_db as B

TABLE = json.load(open(os.path.join(os.path.dirname(__file__), "..", "editorial", "racist_caricature.json")))
RULES = B.caricature_rules(TABLE)
ITEMS = {"hidden1": {"collections": ["fringe", "deemphasize"]}, "plain1": {"collections": ["oldtimeradio"]}}

# (series name, title, item, expected reason prefix or None)
CASES = [
    ("", "Adolf Hitler - Reichstagsrede 1939-09-01", "plain1", "Nazi"),
    ("", "Goebbels Sportpalastrede", "plain1", "Nazi"),
    ("", "Rede Hermann Göring 1942", "plain1", "Nazi"),
    ("Adolf Hitler", "Adolf Hitler - Kulturtagung (21m 20s)", "plain1", "Nazi"),
    ("", "Adolf Hitler vor dem Reichstag ueber von Fritsch", "plain1", "Nazi"),
    ("", "Adolf Hitler - Wahlkampfrede in Goettingen (20m 11s)", "plain1", "Nazi"),
    ("", "DRF Adolf Hitler - First Public Appearance As Chancellor", "plain1", "Nazi"),
    ("", "The Shadow 1938-10-09 Death Stalks the Shadow", "plain1", None),
    ("Words at War", "The Hitler Gang", "plain1", None),
    ("Founder's Day Speech", "Adolph Hitler and the Nazi Movement", "plain1", None),
    ("Theta Sigma Phi Lecture", "Hitler's Secret Army in America", "plain1", None),
    ("European History Class", "History leading to the invasion of Austria by Hitler, Mar. 1938", "plain1", None),
    ("Some Upload", "Untitled", "hidden1", "archive.org de-emphasizes"),
    ("Amos and Andy Show", "The Kingfish's Secret", "plain1", "racist caricature"),
    ("Christmas Shows", "NBC The Amos n Andy Show - Mr 1943", "plain1", "racist caricature"),
    ("Easter Classics", "AmosAndyEasterHat1945", "plain1", "racist caricature"),
    ("Beulah", "Beulah's Birthday", "plain1", "racist caricature"),
    ("Aunt Jemima", "1930s program", "plain1", "racist caricature"),
    ("Jack Benny Program", "Doc Benny's Minstrel Show (OTR)", "plain1", "racist caricature"),
    ("The Shadow Of Fu Manchu", "Episode 12", "plain1", "racist caricature"),
    ("The Railroad Hour", "Minstrel Boy", "plain1", None),
    ("Authors Playhouse", "Minstrels of the Mist", "plain1", None),
    ("AFRS Vietnam", "Land of Giants - The New Christy Minstrels", "plain1", None),
    ("Gunsmoke", "Beulah", "plain1", None),  # a series-only pattern never reads titles
    ("Famous Finales", "Famous Andy Devine", "plain1", None),
]
NOT_ID = "jeanshepherdshow|tamosandandy"


def verdict(sname, title, item, eid="x|1"):
    ep = {"id": eid, "series_name": sname, "title": title, "recordings": [{"archive_id": item}]}
    return B.no_recommend_reason(ep, ITEMS, RULES, TABLE)


def main():
    failed = 0
    for sname, title, item, want in CASES:
        got = verdict(sname, title, item)
        ok = (got is None) if want is None else (got is not None and got.startswith(want))
        if not ok:
            failed += 1
            print(f"FAIL {sname!r} / {title!r}: want {want}, got {got}")
    if verdict("The Jean Shepherd Show", "Amos and Andy", "plain1", NOT_ID) is not None:
        failed += 1
        print("FAIL an exempt id (`not`) was flagged")
    for k, v in TABLE["series"].items():
        if not v.get("source", "").startswith("https://") or not v.get("why"):
            failed += 1
            print(f"FAIL {k}: a pattern needs a source a reader can open and its reason")
    total = len(CASES) + 1 + len(TABLE["series"])
    print(f"{total - failed}/{total} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
