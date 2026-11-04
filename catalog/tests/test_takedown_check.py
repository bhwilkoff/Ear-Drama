"""The rule that reads a take-down request (DECISIONS 029), and the privacy of
everything the public workflow writes: its log, its issues, its public list.

    python3 tests/test_takedown_check.py

Fixtures only. The planted requester below must reach none of the three outputs,
and the same run with a leak put in place must be caught (a test is not a test
until seen to fail).
"""
import contextlib
import datetime
import io
import json
import os
import sys
import tempfile
import types

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import takedown_cases as K
import takedown_check as C

ran = failed = 0


def check(name, got, want=True):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


DAY = datetime.date(2026, 11, 4)
NOTICE = {"kind": "copyright", "complete": True}
FIELDS = ["id", "date", "season", "num", "title", "rights", "length", "url", "li", "ltp"]
PAGES = {
    "series/a-long-show-name.json": {"key": "a-long-show-name", "name": "A Long Show Name", "fields": FIELDS,
        "episodes": [["a-long-show-name|n1", "1948-03-02", None, 1, "The Pilot", "clean", 1800,
                      "https://archive.org/download/itemA/a.mp3", None, None]]},
    "series/old-show.json": {"key": "old-show", "name": "Old Show", "fields": FIELDS,
        "episodes": [["old-show|n1", "1925-05-01", None, 1, "First", "clean", 900,
                      "https://archive.org/download/itemB/b.mp3", None, None]]},
    "index/aliases.json": {"a-long-show-name|old": "a-long-show-name|n1"},
    "index/series-aliases.json": {"long-show": "a-long-show-name"},
}
cat = C.Catalog(fetch=lambda p: PAGES.get(p))
CLEAN = {"read": True, "layer": False, "modernDate": False}


def v(work, item, ev, **case):
    return C.verdict({**NOTICE, "work": work, **case}, item, ev, DAY)


show = cat.find("series", "a-long-show-name")
old = cat.find("series", "old-show")
r = v("A Long Show Name", show, CLEAN)
check("a complete notice removes", (r["action"], r["reason"]) == ("remove", "complete_notice"))
r = v("Show", show, CLEAN)
check("a word of a longer title is held", (r["action"], r["reason"]) == ("hold", "title_word_only"))
r = v("Show", show, {"read": True, "layer": True, "modernDate": False})
check("a modern restoration removes even then", (r["action"], r["reason"]) == ("remove", "modern_layer"))
r = v("Show", show, {"read": True, "layer": False, "modernDate": True})
check("a post-1971 date removes", r["reason"] == "modern_layer")
r = v("Old Show", old, CLEAN)
check("a 1925 recording with a clean record is held", (r["action"], r["reason"]) == ("hold", "old_recording"))
r = v("Old Show", old, {"read": False})
check("an unreadable record contradicts nothing", r["action"] == "remove")
r = v("Show", show, {"read": False})
check("nor does it excuse a word-only claim", r["reason"] == "title_word_only")
r = v("Zebra Hour", show, CLEAN)
check("an unrelated name proves nothing", r["action"] == "remove")
check("what we do not serve closes", v("X", None, {})["action"] == "none")
check("a privacy request is the owner's", v("", show, CLEAN, kind="other")["reason"] == "not_copyright")
check("an incomplete notice is the owner's", v("X", show, CLEAN, complete=False)["reason"] == "incomplete_notice")
check("1925 is free in 2026", C.old_enough("1925-12-31", DAY))
check("1926 is not", not C.old_enough("1926-01-01", DAY))
ep = cat.find("episode", "a-long-show-name|n1")
check("an episode may be named by its own title", C.best_fit("The Pilot", ep["names"]) == "same")
check("a forwarded episode id resolves", cat.find("episode", "a-long-show-name|old")["key"] == "a-long-show-name|n1")
check("a forwarded series key resolves", cat.find("series", "long-show")["key"] == "a-long-show-name")

rec = C.read_record({"title": "Show", "description": "Digitally remastered with new narration", "date": "1948"})
check("a remaster is a modern layer", rec["layer"] and not rec["modernDate"])
check("a plain record is not", not C.read_record({"title": "Show", "description": "Broadcast of 1948"})["layer"])
check("a 1980 date is modern", C.read_record({"title": "x", "date": "1980-01-01"})["modernDate"])
check("no record reads nothing", C.read_record(None) == {"read": False})

t = C.targets("https://eardrama.org/series/a%20b\nhttps://eardrama.org/episode/x%7Cn1 "
              "https://eardrama.org/series/a%20b https://archive.org/details/zz nonsense")
check("links resolve, repeats count once, strangers are kept unread",
      [x.get("id") for x in t] == ["a b", "x|n1", None, None] and len(t) == 4 and "unread" in t[3])

# ---- privacy: the planted requester reaches no public output ----
PLANT = ["Jane Requester", "jane@example.com", "555-0100", "12 Private Lane", "Secret Work Title"]
CASES = [
    {"ref": "TD-AAAAAAAA", "status": "open", "kind": "copyright", "complete": 1, "source": "form",
     "links": "https://eardrama.org/series/a-long-show-name Jane Requester jane@example.com",
     "work": "A Long Show Name, Secret Work Title"},
    {"ref": "TD-BBBBBBBB", "status": "open", "kind": "copyright", "complete": 1, "source": "form",
     "links": "https://eardrama.org/series/old-show https://eardrama.org/series/zzz-Jane-Requester-12-Private-Lane",
     "work": "Old Show"},
]


def run(leak=False):
    """One judge + report run on the planted cases. Returns everything it made public."""
    sent, issues = [], []
    real_call, real_gh, real_issue_body = K.call, K.gh, K.issue_body
    with tempfile.TemporaryDirectory() as d:
        C.EDITORIAL = os.path.join(d, "takedowns.json")
        out = os.path.join(d, "updates.json")
        K.call = lambda path, body=None: {"cases": CASES} if body is None else sent.append((path, body)) or {}
        K.gh = lambda *a: issues.append(a) or "[]"
        if leak:
            K.issue_body = lambda u: real_issue_body(u) + "\n" + CASES[0]["work"]
        buf = io.StringIO()
        try:
            with contextlib.redirect_stdout(buf):
                K.cmd_judge(types.SimpleNamespace(out=out), cat=cat, read=lambda url: CLEAN, today="2026-11-04")
                K.cmd_report(types.SimpleNamespace(updates=out))
        finally:
            K.call, K.gh, K.issue_body = real_call, real_gh, real_issue_body
        listing = open(C.EDITORIAL).read() if os.path.exists(C.EDITORIAL) else ""
    return buf.getvalue(), json.dumps(issues), listing


def leaked(*outputs):
    blob = "\n".join(outputs)
    return [p for p in PLANT if p in blob] + [p for p in ("Jane", "Private") if p in blob]


log, issues, listing = run()
check("the run read both cases", "TD-AAAAAAAA" in log and "TD-BBBBBBBB" in log)
check("the public list gained the removal", '"case": "TD-AAAAAAAA"' in listing and '"scope": "series"' in listing)
check("the held case opened an issue naming a fixed reason", "old recording" in issues or "no recording right" in issues)
check("PLANTED DATA reaches no log, issue or list", leaked(log, issues, listing), [])
check("the list holds a date and a case number only",
      all(set(e) == {"date", "case", "scope", "key"} for e in json.loads(listing)["requests"].values()))
log2, issues2, listing2 = run(leak=True)
check("CONTROL: a leak in the issue body is caught", leaked(log2, issues2, listing2) != [])

# the cap
many = [{"ref": f"TD-CCCCCCC{i}", "status": "open", "kind": "copyright", "complete": 1, "source": "form",
         "links": "https://eardrama.org/series/a-long-show-name", "work": "A Long Show Name"} for i in range(8)]
real_call = K.call
K.call = lambda path, body=None: {"cases": many}
with tempfile.TemporaryDirectory() as d:
    C.EDITORIAL = os.path.join(d, "t.json")
    out = os.path.join(d, "u.json")
    with contextlib.redirect_stdout(io.StringIO()):
        K.cmd_judge(types.SimpleNamespace(out=out), cat=cat, read=lambda url: CLEAN, today="2026-11-04")
    ups = json.load(open(out))
K.call = real_call
check("a run removes at most its cap on its own",
      sum(1 for u in ups if u["status"] == "removed") == K.MAX_REMOVALS and
      sum(1 for u in ups if u["status"] == "held") == len(many) - K.MAX_REMOVALS)

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
