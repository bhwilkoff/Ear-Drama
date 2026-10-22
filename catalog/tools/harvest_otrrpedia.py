"""Harvest OTRRpedia, the Old Time Radio Researchers' encyclopedia, through the
same keyless JSON endpoint as harvest_otrr.py (`www.otrr.org/php/jqSelectM7.php`,
qids found in OTRRPedia/js/pedia7.js; robots.txt `Disallow:` allows all).

    progPedia            10,783 programs: genres, run histories (network, days,
                         time, length), sponsors (undated), titles   - 1 request
    peoplePedia          51,130 people: id + name                    - 1 request
    programData&idp=N    one program in full: DATED sponsors, histories,
                         program-level people with roles, codes, print
                         sources, links, infos/synopses (prose)      - 1 per program
    personData&idp=N     one person: birth/death dates, birth name/place,
                         credited episodes with role, programs, and a link
                         to the person's RadioGOLDINdex artist page (idtype 102)

MEASURED 2026-10-19 (Suspense, idp 8654): programData = 926 episodes, 118
people, 21 histories, 11 dated sponsors, 250 prints, 116 links, 2 infos.

Phases run in that order; programs with logs (otterlog) first, then the rest;
people in descending order of how many episode credits they carry in the OTRR
logs cached by harvest_otrr.py. Each response is cached as it arrives, so a
killed run resumes. A request that fails is listed in failed_<phase>.json and
the run exits non-zero; it is never cached as empty.

`infos` and `synopses` are contributors' prose: cached, and stored by
enrich_db.py only with provenance and display_allowed = 0.

    python3 tools/harvest_otrrpedia.py                    # all phases
    python3 tools/harvest_otrrpedia.py --phase programs
    python3 tools/harvest_otrrpedia.py --phase people --max-people 15000
"""
import argparse
import collections
import glob
import gzip
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
import ia_lib as ia

OT = "https://www.otrr.org/php/jqSelectM7.php"
UA = "Mozilla/5.0 EarDrama-Catalog (catalog build; credits OTRR)"
OUT = os.path.join(ia.CACHE, "otrrpedia")
DELAY = 1.5


def q(**params):
    d = ia.get(OT, params, ua=UA, timeout=180)
    time.sleep(DELAY)
    return d


def bulk():
    for name in ("progPedia", "peoplePedia", "otterlog"):
        path = os.path.join(OUT, name + ".json.gz")
        if os.path.exists(path):
            continue
        d = q(qid=name)
        if not d:
            raise SystemExit(f"{name} unreadable")
        ia.write_json(path, d, gz=True)
        print(f"{name}: {len(d)}", file=sys.stderr, flush=True)


def load(name):
    with gzip.open(os.path.join(OUT, name + ".json.gz"), "rt") as f:
        return json.load(f)


def slim_program(d):
    eps = d.get("episodes") or []
    d["episodes"] = [{"ide": e.get("ide"), "date": e.get("date"), "epnum": e.get("epnum"),
                      "exists": e.get("exists")} for e in eps]
    return d


def programs(limit=None):
    d = os.path.join(OUT, "programs")
    os.makedirs(d, exist_ok=True)
    logged = [p["idp"] for p in load("otterlog")]
    rest = sorted({p["idp"] for p in load("progPedia")} - set(logged), key=int)
    order = logged + rest
    if limit:
        order = order[:limit]
    failed, done = [], 0
    for i, idp in enumerate(order):
        path = os.path.join(d, f"{idp}.json.gz")
        if os.path.exists(path):
            continue
        r = q(qid="programData", idp=idp)
        if not isinstance(r, dict):
            failed.append(idp)
            continue
        ia.write_json(path, slim_program(r), gz=True)
        done += 1
        if i % 250 == 0:
            print(f"programs {i}/{len(order)}", file=sys.stderr, flush=True)
    ia.write_json(os.path.join(OUT, "failed_programs.json"), failed)
    print(f"programs: fetched {done}, failed {len(failed)}", file=sys.stderr)
    return failed


def person_order():
    n = collections.Counter()
    for p in glob.glob(os.path.join(ia.CACHE, "otrr", "programs", "*.json.gz")):
        with gzip.open(p, "rt") as f:
            for e in json.load(f)["episodes"]:
                for x in e.get("people") or []:
                    n[x["id"]] += 1
    everyone = [p["idp"] for p in load("peoplePedia")]
    rest = sorted(set(everyone) - set(n), key=int)
    return [k for k, _ in n.most_common()] + rest


def people(limit=None):
    d = os.path.join(OUT, "people")
    os.makedirs(d, exist_ok=True)
    order = person_order()
    if limit:
        order = order[:limit]
    failed, done = [], 0
    for i, idp in enumerate(order):
        path = os.path.join(d, f"{idp}.json.gz")
        if os.path.exists(path):
            continue
        r = q(qid="personData", idp=idp)
        if not isinstance(r, dict):
            failed.append(idp)
            continue
        ia.write_json(path, r, gz=True)
        done += 1
        if i % 500 == 0:
            print(f"people {i}/{len(order)}", file=sys.stderr, flush=True)
    ia.write_json(os.path.join(OUT, "failed_people.json"), failed)
    print(f"people: fetched {done}, failed {len(failed)}", file=sys.stderr)
    return failed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase", choices=("bulk", "programs", "people", "all"), default="all")
    ap.add_argument("--max-programs", type=int)
    ap.add_argument("--max-people", type=int)
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    bulk()
    failed = []
    if a.phase in ("programs", "all"):
        failed += programs(a.max_programs)
    if a.phase in ("people", "all"):
        failed += people(a.max_people)
    have = len(glob.glob(os.path.join(OUT, "programs", "*.json.gz"))) + \
        len(glob.glob(os.path.join(OUT, "people", "*.json.gz")))
    if a.phase != "bulk" and not have:
        raise SystemExit("read nothing")
    if failed:
        raise SystemExit(f"{len(failed)} requests failed")


if __name__ == "__main__":
    main()
