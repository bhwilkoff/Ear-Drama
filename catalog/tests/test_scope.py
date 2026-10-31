"""Scope (drama and spoken story only) and the P-7 merges in build_db (DECISIONS 026; owner, 2026-10-31).

    python3 tests/test_scope.py

Fixtures only; tests never pin catalog contents. Every case was seen failing before its rule was written
(enrich_scope.py, merge_disc_series and merge_near_names did not exist); each control is a refusal.
"""
import collections
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import build_db as B
import enrich_scope as S

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


def cls(name, items=1, kinds=None, drama=0, music=0, lecture=0, mcoll=0, performers=None):
    got = S.classify(name, items, collections.Counter(kinds or {"radio": 3}), drama, music, lecture, mcoll, performers)
    return got[:2] if got else None


# Concert, lecture and music set, each from evidence a reader can open.
check("a concert named", cls("Illini Faculty Concert series"), ("concert", "name_names_a_concert"))
check("a recital named", cls("Organ Recital"), ("concert", "name_names_a_concert"))
check("a lecture named", cls("Edmund J. James Lectures on Government"), ("lecture", "name_names_a_lecture"))
check("a symposium named", cls("Faculty Symposium"), ("lecture", "name_names_a_lecture"))
check("episodes the build kinds as lectures", cls("Care of the Garden", kinds={"lecture": 4}), ("lecture", "episodes_are_lectures"))
check("music in the items' own keywords", cls("Fiddlin Favorites", items=3, music=3), ("music", "music_in_its_own_keywords"))
check("a band name and a music collection", cls("Jimmy Carroll and his Orchestra", items=2, mcoll=2), ("music", "music_in_its_own_keywords"))
check("a live set by one performer", cls("Tom Waits Live Coffe Break", performers={"Tom Waits"}), ("concert", "live_set_by_one_performer"))
# Controls: what stays.
check("control: live with several artists on the files", cls("Live From The Palace", performers={"A", "B"}), None)
check("control: live, files not tagged", cls("Live From The Palace", performers=None), None)
check("control: one performer, no live in the name", cls("Coffee Break Radio Show", performers={"Tom Waits"}), None)
check("control: a dramatic reading named Symposium", cls("Symposium (version 2) (dramatic reading)"), None)
check("control: Sherlock Holmes's band", cls("Speckled Band: An Adventure of Sherlock Holmes"), None)
check("control: a band name with no music evidence", cls("Band Remotes"), None)
check("control: music keywords on under 60% of the items", cls("Radio Roundup", items=5, music=2), None)
check("control: half the items name a spoken genre", cls("Gospel Hour", items=4, music=4, drama=2), None)
check("control: a reading of poems is not a lecture", cls("Reading from the poets", kinds={"lecture": 1}), None)
check("control: lecture kind on under 60% of the episodes", cls("Campus Hour", kinds={"lecture": 1, "radio": 3}), None)
check("control: no items read, no keywords", cls("Fiddlin Favorites", items=0), None)

# build_db.merge_near_names and merge_disc_series on fixture files.
K2C = {"topsecret": "topsecret", "proudlywehail": "proudlywehail"}


class Reg:
    k2c = K2C
    name = {"topsecret": "Top Secret", "proudlywehail": "Proudly We Hail"}

    def display(self, canon, fallback=None):
        return self.name.get(canon) or fallback


def rec(key, name, date=None, title="x", stem="x", num=None, how="item"):
    return {"key": key, "sname": name, "raw": name, "how": how, "orow": None, "date": date, "title": title, "stem": stem,
            "num": num, "idt": {}}


TD = {"topsecret": {"1950-01-01", "1950-02-01", "1951-03-01"}}
recs = ([rec("topsecret", "Top Secret", "1950-01-01", "a"), rec("topsecret", "Top Secret", "1950-02-01", "b"),
         rec("topsecret", "Top Secret", "1951-03-01", "c")]
        + [rec("topsercet", "Top Sercet", "1950-04-04")])
stats = collections.Counter()
B.merge_near_names(recs, Reg(), TD, {}, stats)
check("near: a misspelled series joins its program", sorted({r["key"] for r in recs}), ["topsecret"])
check("near: and is named for it", {r["sname"] for r in recs}, {"Top Secret"})
check("near: the move is recorded", recs[-1]["idt"]["reattributed"]["from"], "topsercet")
check("near: with its gate", recs[-1]["idt"]["reattributed"]["gate"], "date")
check("near: one series moved", stats["near_series_merged"], 1)

recs = [rec("topsecret", "Top Secret", "1950-01-01"), rec("topsecret", "Top Secret", "1950-02-01"), rec("topsecret", "Top Secret", "1951-03-01"),
        rec("topsecrex", "Top Secrex", "1950-01-01"), rec("topsecrex", "Top Secrex", "1950-02-01"), rec("topsecrex", "Top Secrex", "1950-02-02"),
        rec("topsecrdt", "Top Secrdt", "1950-04-04")]
B.merge_near_names(recs, Reg(), TD, {}, collections.Counter())
check("control: two programs this near, nothing moves", recs[-1]["key"], "topsecrdt")

recs = [rec("topsecret", "Top Secret", "1950-01-01"), rec("topsecret", "Top Secret", "1950-02-01"), rec("topsecret", "Top Secret", "1951-03-01"),
        rec("topsercet", "Top Sercet", "1962-04-04")]
B.merge_near_names(recs, Reg(), TD, {}, collections.Counter())
check("control: a date outside the run leaves the series alone", recs[-1]["key"], "topsercet")

recs = [rec("topsecret", "Top Secret", "1950-01-01"), rec("topsecret", "Top Secret", "1950-02-01"), rec("topsecret", "Top Secret", "1951-03-01"),
        rec("topsercet", "Top Sercet", "1950-04-04", how="album")]
recs[-1]["orow"] = {"eid": "1"}
B.merge_near_names(recs, Reg(), TD, {}, collections.Counter())
check("control: a file the logs placed is never moved", recs[-1]["key"], "topsercet")

# Volumes of one program merge, and a bare number stops naming an undated episode.
recs = [rec("cbsfantasyselection1", "CBS Mystery Theater Fantasy Selection 1", None, "One", num=1),
        rec("cbsfantasyselection2", "CBS Mystery Theater Fantasy Selection 2", None, "Two", num=1),
        rec("cbsfantasyselection2", "CBS Mystery Theater Fantasy Selection 2", "1976-01-01", "Three", num=2)]
holds = {}
B.merge_disc_series(recs, Reg(), {}, {}, collections.Counter(), holds)
check("disc: volumes become one series", {r["key"] for r in recs}, {"cbsmysterytheaterfantasy"})
check("disc: named for the base", {r["sname"] for r in recs}, {"CBS Mystery Theater Fantasy"})
check("disc: an undated file's number is dropped", [r["num"] for r in recs], [None, None, 2])
check("disc: nothing held", holds, {})

# A disc of many programs: each file to the program its name begins with, the rest held back.
recs = [rec("americanarmedforcesradiono62", "American Armed Forces Radio No 62", None, stem="AFRS-Proudly-We-Hail-311-This-Mans-Army"),
        rec("americanarmedforcesradiono62", "American Armed Forces Radio No 62", None, stem="USAF Wolfman Jack s13 Sep72"),
        rec("americanarmedforcesradiono63", "American Armed Forces Radio No 63", None, stem="USAF Wolfman Jack s14 Oct72")]
holds = {}
B.merge_disc_series(recs, Reg(), {}, {}, collections.Counter(), holds)
check("service disc: a named program moves", recs[0]["key"], "proudlywehail")
check("service disc: the rest stays, held back",
      (recs[1]["key"], holds), ("americanarmedforcesradiono62", {"americanarmedforcesradiono62": "series_is_a_numbered_disc",
                                                                  "americanarmedforcesradiono63": "series_is_a_numbered_disc"}))
check("service disc: never merged into a catch-all", {r["key"] for r in recs} & {"americanarmedforcesradio"}, set())
check("service disc: the move says why", recs[0]["idt"]["reattributed"]["gate"], "named")

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
