#!/usr/bin/env python3
"""POST-BUILD step: photographs and graphics from archives beyond Wikimedia
Commons, rights-classed from each record's own statement and matched to our
series and people; and the period radio magazines' copyright by title and year.
reports/F-photo-archives.md.

Reads only caches (no network): .cache/loc/records.json.gz
(harvest_loc_photos.py), .cache/smithsonian/*/*.json.gz (harvest_smithsonian.py),
.cache/magazines/evidence.json (harvest_magazine_rights.py). Adds ONLY its own
tables to out/radio-catalog.sqlite, dropping and rebuilding them each run:

  archive_photos       one row per record (source, record_id), with the rights
                       statement verbatim, its class (photo_match.rights_class),
                       `usable`, and the largest image URL the record lists
  archive_photo_links  record -> series key or person id, with the match basis
  magazine_rights      (title, year) -> status with evidence and caveats
  magazine_scans       issue scans by title and year: worldradiohistory PDFs and
                       archive.org Media History Digital Library volumes

and writes out/enrich_photo_archives_report.json.

Owner rule for images (2026-10): no human review queue. A row is `usable` when
its OWN record carries public-domain or free-licence evidence a reader can open
(`evidence_url`), and it is removed on request (take-down model).

Run: python3 tools/enrich_photo_archives.py
"""
import collections
import glob
import json
import os
import re
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ia_lib as L
import photo_match as M

DB = os.path.join(L.OUT, "radio-catalog.sqlite")
REPORT = os.path.join(L.OUT, "enrich_photo_archives_report.json")
LOC = os.path.join(L.CACHE, "loc", "records.json.gz")
SI = os.path.join(L.CACHE, "smithsonian")
MAG = os.path.join(L.CACHE, "magazines", "evidence.json")

TABLES = """
DROP TABLE IF EXISTS archive_photos;
CREATE TABLE archive_photos (
  source TEXT, record_id TEXT, title TEXT, date TEXT, year INTEGER, collection TEXT,
  creators TEXT,            -- JSON list as the record gives them
  rights_statement TEXT,    -- verbatim from the record
  rights_class TEXT,        -- no_known_restrictions | government | cc0 | restricted | unknown
  rights_why TEXT, usable INTEGER,
  evidence_url TEXT,        -- the record page that carries the statement
  image_url TEXT,           -- largest JPEG the record lists
  image_master TEXT,        -- TIFF master when listed
  width INTEGER, height INTEGER,
  subjects TEXT, found_via TEXT,
  PRIMARY KEY (source, record_id)
);
DROP TABLE IF EXISTS archive_photo_links;
CREATE TABLE archive_photo_links (
  source TEXT, record_id TEXT, target_kind TEXT, target_id TEXT, basis TEXT,
  strength TEXT             -- title: the name is in the record's own title and the record names
                            -- at most 3 matched people (a portrait or a cast photo);
                            -- heading: an LoC name heading; mentioned: named elsewhere in the record
);
DROP TABLE IF EXISTS magazine_rights;
CREATE TABLE magazine_rights (
  title TEXT, year INTEGER,
  status TEXT,              -- pd_by_age | not_renewed | renewed | renewed_from_month | in_copyright | unchecked
  usable INTEGER,           -- 1 for pd_by_age and not_renewed
  detail TEXT, evidence TEXT, caveats TEXT,
  PRIMARY KEY (title, year)
);
DROP TABLE IF EXISTS magazine_scans;
CREATE TABLE magazine_scans (
  title TEXT, year INTEGER, source TEXT, url TEXT, label TEXT, holder_statement TEXT
);
"""

AGE_LINE = 1930          # published 1930 or earlier is public domain in 2026 (calendar rule)
AUTO_RENEW = 1964        # issues from 1964 on were renewed automatically (1992 Act)
CAVEATS = [
    "a contribution (story, photo, drawing) can carry its own registration and renewal, independent of the issue",
    "an advertisement may carry its own notice and is judged separately from the issue",
    "wire-service, studio or syndicated photos reprinted in an issue may be under the originator's copyright",
]
MONTHS = {m: i + 1 for i, m in enumerate("january february march april may june july august september october november december".split())}


# ---------------------------------------------------------------- matching inputs
def load_targets(c):
    # a series is looked for only when it has a known run and at least 10
    # episodes: the spine also holds one-off rows named "History", "Various",
    # "Looking" that would match any caption
    series = []
    for key, name, fd, ld, n in c.execute(
            "select key, name, first_date, last_date, episodes from series "
            "where name is not null and first_date is not null and episodes >= 10"):
        if len(M.fold(name).split()) == 1 and n < 100:
            continue
        series.append((key, name, M.year_of(fd), M.year_of(ld)))
    credits = dict(c.execute("select person_id, count(distinct episode_id) from episode_credits "
                             "where person_id is not null group by person_id"))
    name_index = collections.defaultdict(set)
    years = {}
    for pid, name, names, b, d in c.execute("select id, name, names, birth, death from people"):
        allnames = {name or ""}
        try:
            allnames |= set(json.loads(names or "[]"))
        except json.JSONDecodeError:
            pass
        # a person is looked for when we know them: 3+ credited episodes or a
        # birth/death date (OTRR also files groups — "Black and White" — as people)
        if credits.get(pid, 0) < 3 and not (b or d):
            continue
        for n in allnames:
            f = M.fold(n)
            if M.name_ok(f) and "'" not in f and " and " not in f:
                name_index[f].add(pid)
        years[pid] = (M.year_of(b), M.year_of(d))
    # two people rows that are one person filed twice (OTRR + Goldin) share a
    # folded name; only when both carry the SAME known birth and death years are
    # they treated as one — otherwise the name stays ambiguous and is refused
    for n, ids in list(name_index.items()):
        if len(ids) > 1:
            ys = {years[i] for i in ids}
            if len(ys) == 1 and ys != {(None, None)}:
                name_index[n] = set(sorted(ids)[:1])
    # a series named for a person ("Bing Crosby", "Winston Churchill") is found
    # through the person; matching it as a series would tie every caption that
    # names the man to his program
    series = [row for row in series if re.sub(r"^the ", "", M.fold(row[1])) not in name_index]
    return series, dict(name_index), years


# ---------------------------------------------------------------- sources
def loc_rows():
    if not os.path.exists(LOC):
        return []
    recs = L.read_json(LOC)
    out = []
    for r in recs.values():
        jpg = [f for f in (r.get("files") or []) if f.get("mimetype") == "image/jpeg" and f.get("width")]
        big = max(jpg, key=lambda f: f["width"]) if jpg else None
        text = " ".join(filter(None, [r.get("title"), r.get("description"), " ".join(r.get("summary") or []) if isinstance(r.get("summary"), list) else r.get("summary"),
                                      " ".join(r.get("notes") or []), " ".join(r.get("subjects") or [])]))
        out.append({
            "source": "loc", "record_id": r["id"], "title": r.get("title"), "date": r.get("date"),
            "year": M.year_of(r.get("date") or (r.get("dates") or [""])[0]),
            "collection": "; ".join(p for p in r.get("partof") or [] if p not in ("catalog", "prints and photographs division")),
            "creators": r.get("contributors") or [], "rights_statement": r.get("rights"),
            "rights_class": r.get("rights_class"), "rights_why": r.get("rights_why"),
            "online": r.get("online"), "evidence_url": r.get("url"),
            "image_url": (big or {}).get("url") or r.get("image_largest"), "image_master": r.get("image_master"),
            "width": (big or {}).get("width"), "height": (big or {}).get("height"),
            "subjects": r.get("subject_headings") or r.get("subjects") or [], "found_via": r.get("queries"),
            "text": text, "headings": r.get("subject_headings") or [],
        })
    return out


def si_rows():
    out = []
    for f in sorted(glob.glob(os.path.join(SI, "*", "*.json.gz"))):
        for r in L.read_json(f):
            media = r.get("media") or []
            cc0 = [m for m in media if m.get("usage") == "CC0" and m.get("largest")]
            usage = sorted({m.get("usage") or "none" for m in media})
            if cc0:
                cls, why = "cc0", "the image file is marked CC0 by the Smithsonian"
            elif media:
                cls, why = "restricted", "the image file says: " + ", ".join(usage)
            else:
                cls, why = "unknown", "no image online in the record"
            pick = cc0[0] if cc0 else (media[0] if media else {})
            text = " ".join(filter(None, [r.get("title"), " ".join(r.get("names") or []), " ".join(r.get("topics") or []),
                                          " ".join(r.get("object_type") or []), " ".join(r.get("notes") or [])]))
            out.append({
                "source": "smithsonian", "record_id": r["id"], "title": r.get("title"),
                "date": "; ".join(r.get("dates") or []), "year": M.year_of(" ".join(r.get("dates") or [])),
                "collection": r.get("unit") + (": " + "; ".join(r.get("set") or []) if r.get("set") else ""),
                "creators": r.get("names") or [], "rights_statement": "media usage: " + ", ".join(usage) +
                "; metadata usage: " + str(r.get("metadata_usage")), "rights_class": cls, "rights_why": why,
                "online": bool(pick.get("largest")), "evidence_url": r.get("record_link") or r.get("guid"),
                "image_url": pick.get("largest"), "image_master": None,
                "width": pick.get("width"), "height": pick.get("height"),
                "subjects": r.get("topics") or [], "found_via": ["bulk:" + (r.get("unit") or "")],
                "text": text, "headings": [], "sitters": M.sitters(r.get("names")),
            })
    return out


def link(row, series, name_index, years):
    links, refused = [], []
    for key, basis in M.match_series(row["text"], row["year"], series):
        links.append(("series", key, basis))
    found, ref = M.match_people(row["text"], row["headings"], row["year"], name_index, years)
    links += [("person", pid, basis) for pid, basis in found]
    refused += ref
    if row.get("sitters"):
        have = {pid for k, pid, _ in links if k == "person"}
        pf, pr = M.match_portrait(row["title"], row["sitters"], name_index, years)
        links += [("person", pid, basis) for pid, basis in pf if pid not in have]
        refused += pr
    return links, refused


def loc_targets(records):
    """Record ids the LoC harvester should fetch item JSON for: usable and matched."""
    c = sqlite3.connect(DB)
    series, name_index, years = load_targets(c)
    out = []
    for r in records:
        if r.get("rights_class") not in M.USABLE or not r.get("online"):
            continue
        text = " ".join(filter(None, [r.get("title"), r.get("description"), " ".join(r.get("notes") or []),
                                      " ".join(r.get("subjects") or [])]))
        row = {"text": text, "year": M.year_of(r.get("date") or ""), "headings": r.get("subject_headings") or []}
        if link(row, series, name_index, years)[0]:
            out.append(r["id"])
    return out


# ---------------------------------------------------------------- magazines
def obp_rule(stmt):
    """Parse an OBP sentence -> (issue_from (year, month) | None, issue_checked, contrib_from year | None)."""
    s = stmt or ""
    issue_from = None
    m = re.search(r"issues (?:actively )?renewed from (?:©\s*)?([A-Z][a-z]+)?\s*(?:\d{1,2},\s*)?(\d{4})", s)
    if m:
        issue_from = (int(m.group(2)), MONTHS.get((m.group(1) or "").lower(), 1))
    checked = "CCE or CPRS" if re.search(r"no (?:active )?issue renewals found in CCE or CPRS", s) else \
        ("CCE" if "no issue renewals found in CCE" in s else ("CPRS" if "no issue renewals found in CPRS" in s else None))
    cm = re.search(r"contributions (?:actively )?renewed from (?:©\s*)?(?:[A-Z][a-z]+\s*)?(?:\d{1,2},\s*)?(\d{4})", s)
    return issue_from, checked, (int(cm.group(1)) if cm else None)


def magazine_status(title, year, obp, cce_years, cce_scanned):
    """(status, detail, evidence[]) for one title-year. `obp` is the OBP row or None;
    `cce_years` {year: [hit]} from our CCE reading; `cce_scanned` whether that
    reading covered the renewal window for this year (1958-1977 volumes renew
    1930-1950 issues)."""
    ev = []
    if obp:
        ev.append({"source": "Online Books Page, first periodical renewals", "url": obp.get("detail") or obp["source"],
                   "statement": obp["statement"]})
    hits = cce_years.get(year) or []
    for h in hits[:3]:
        ev.append({"source": "CCE renewal (our reading)", "url": h["src"], "renewals": h["renewals"][:6],
                   "orig_dates": h["orig_dates"][:6], "vol_year": h["vol_year"]})
    if year <= AGE_LINE:
        return "pd_by_age", f"published {year}; works published {AGE_LINE} or earlier are public domain in 2026", ev
    if year >= AUTO_RENEW:
        return "in_copyright", "issues from 1964 on were renewed automatically", ev
    if hits:
        return "renewed", f"{len(hits)} renewal block(s) in the CCE for issues of {year}", ev
    if obp:
        issue_from, checked, _ = obp_rule(obp["statement"])
        if issue_from:
            fy, fm = issue_from
            if year > fy:
                return "renewed", f"OBP: issues renewed from {fy}-{fm:02d}", ev
            if year == fy:
                return ("renewed" if fm == 1 else "renewed_from_month"), f"OBP: issues renewed from {fy}-{fm:02d}", ev
            return "not_renewed", f"OBP: first renewed issue is {fy}-{fm:02d}; this year precedes it", ev
        if checked == "CCE or CPRS":
            return "not_renewed", "OBP: no issue renewals found in CCE or CPRS", ev
        if checked == "CCE":
            if year <= 1950:
                return "not_renewed", "OBP: no issue renewals found in CCE (which holds every renewal of a 1931-1950 issue)", ev
            return "unchecked", "OBP checked the CCE only; a 1951-1963 issue renews in 1979-1991, in the online records", ev
        if checked == "CPRS" and year >= 1950:
            return "not_renewed", "OBP: no issue renewals found in CPRS", ev
    if year <= 1950 and cce_scanned:
        ev.append({"source": "Online Books Page scope note", "url": "https://onlinebooks.library.upenn.edu/cce/firstperiod.html",
                   "statement": "should include all of the periodicals with renewed issue or contribution copyrights "
                                "(for 1931-1950 issues) between 1958 and 1977, that were filed in the CCE"})
        return "not_renewed", "absent from OBP's inventory, and no renewal block found in our reading of the 1958-1977 CCE", ev
    return "unchecked", "no renewal source read for this year", ev


def magazines(c, rep):
    if not os.path.exists(MAG):
        rep["magazines"] = "no evidence cache"
        return
    ev = L.read_json(MAG)
    obp = {r["canonical"]: r for r in ev.get("obp") or [] if r.get("canonical")}
    cce = ev.get("cce") or {}
    cce_hits = collections.defaultdict(lambda: collections.defaultdict(list))
    for h in cce.get("hits") or []:
        for d in h["orig_dates"]:
            # a monthly is registered on its on-sale date, a month or more before
            # its cover date: the Jan 1944 Radio Mirror is (c) 10Dec43 (R519469).
            # A November or December (c) date is the next cover year's issue.
            y, mo = int(d[:4]), int(d[5:7])
            cce_hits[h["canonical"]][y + 1 if mo >= 11 else y].append(h)
    scanned_years = {v["year"] for v in cce.get("volumes") or []}
    cce_scanned = bool(scanned_years) and scanned_years >= set(range(1958, 1978))
    years = collections.defaultdict(set)
    scans = []
    for r in ev.get("wrh") or []:
        if r.get("year"):
            years[r["canonical"]].add(r["year"])
            scans.append((r["canonical"], r["year"], "worldradiohistory", r["url"], r["file"],
                          "site disclaims copyright ownership; fair-use claim; take-down notice"))
    for r in ev.get("mhdl") or []:
        y = M.year_of(str(r.get("year") or r.get("date") or ""))
        if y:
            years[r["canonical"]].add(y)
            scans.append((r["canonical"], y, "archive.org mediahistory", r["url"], r["title"],
                          "; ".join(f"{k}={r[k]}" for k in ("possible_copyright_status", "licenseurl", "rights") if r.get(k))))
    for t, row in obp.items():  # OBP-listed titles with no scan still get their statement on record
        years.setdefault(t, set())
    rows = []
    for t, ys in years.items():
        for y in sorted(ys):
            st, detail, evid = magazine_status(t, y, obp.get(t), cce_hits.get(t, {}), cce_scanned)
            cav = list(CAVEATS)
            if obp.get(t):
                _, _, contrib = obp_rule(obp[t]["statement"])
                if contrib and y >= contrib:
                    cav.insert(0, f"OBP: contributions to this title were renewed from {contrib}; check a photo's own credit")
            rows.append((t, y, st, int(st in ("pd_by_age", "not_renewed")), detail, json.dumps(evid), json.dumps(cav)))
    c.executemany("insert into magazine_rights values (?,?,?,?,?,?,?)", rows)
    c.executemany("insert into magazine_scans values (?,?,?,?,?,?)", scans)
    # disagreements between the holder's own statement (MHDL) and the renewal record
    status = {(r[0], r[1]): r[2] for r in rows}
    dis = collections.Counter()
    for r in ev.get("mhdl") or []:
        y = M.year_of(str(r.get("year") or ""))
        if y and r.get("possible_copyright_status") and "NOT_IN_COPYRIGHT" in str(r["possible_copyright_status"]).upper() \
                and status.get((r["canonical"], y)) in ("renewed", "renewed_from_month"):
            dis[r["canonical"]] += 1
    rep["magazines"] = {
        "titles": len(years), "title_years": len(rows), "scans": len(scans),
        "status": dict(collections.Counter(r[2] for r in rows)),
        "by_title": {t: dict(collections.Counter(r[2] for r in rows if r[0] == t)) for t in sorted(years)},
        "mhdl_says_not_in_copyright_but_renewed": dict(dis),
        "cce_volumes_read": sorted(scanned_years), "cce_hits": len(cce.get("hits") or []),
        "cce_hits_by_title": dict(collections.Counter(h["canonical"] for h in cce.get("hits") or [])),
    }


# ---------------------------------------------------------------- main
def main():
    c = sqlite3.connect(DB)
    c.executescript(TABLES)
    series, name_index, years = load_targets(c)
    rep = {"sources": {}, "links": {}, "refused": collections.Counter()}
    all_rows = loc_rows() + si_rows()
    if not all_rows:
        print("no photo records in the caches", file=sys.stderr)
    nlinks = collections.Counter()
    linked_usable = collections.Counter()
    targets = collections.defaultdict(set)
    for row in all_rows:
        usable = int(row["rights_class"] in M.USABLE and bool(row["online"]) and bool(row["image_url"]))
        c.execute("insert or replace into archive_photos values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (
            row["source"], row["record_id"], row["title"], row["date"], row["year"], row["collection"],
            json.dumps(row["creators"]), row["rights_statement"], row["rights_class"], row["rights_why"], usable,
            row["evidence_url"], row["image_url"], row["image_master"], row["width"], row["height"],
            json.dumps(row["subjects"][:30]), json.dumps(row["found_via"])))
        links, refused = link(row, series, name_index, years)
        for n, why in refused:
            rep["refused"][re.sub(r"\d+", "N", why)[:70]] += 1
        npeople = sum(1 for k, _, _ in links if k == "person")
        ftitle = M.fold(row["title"] or "")
        for kind, tid, basis in links:
            name = re.search(r"'([^']+)'", basis).group(1) if "'" in basis else ""
            if "subject heading" in basis:
                strength = "heading"
            elif basis.startswith("portrait:"):
                strength = "title"
            elif M.phrase_in(name, ftitle) and (kind == "series" or npeople <= 3):
                strength = "title"
            else:
                strength = "mentioned"
            c.execute("insert into archive_photo_links values (?,?,?,?,?,?)",
                      (row["source"], row["record_id"], kind, tid, basis, strength))
            nlinks[(row["source"], kind, strength)] += 1
            if usable:
                linked_usable[(row["source"], kind, strength)] += 1
                if strength != "mentioned":
                    targets[kind].add(tid)
        s = rep["sources"].setdefault(row["source"], {"records": 0, "by_class": collections.Counter(), "usable": 0})
        s["records"] += 1
        s["by_class"][row["rights_class"]] += 1
        s["usable"] += usable
    rep["links"] = {f"{s}:{k}:{st}": {"all": n, "usable": linked_usable[(s, k, st)]} for (s, k, st), n in nlinks.items()}
    rep["targets_with_usable_photo_title_or_heading"] = {k: len(v) for k, v in targets.items()}
    magazines(c, rep)
    c.commit()
    rep["refused"] = dict(rep["refused"])
    for s in rep["sources"].values():
        s["by_class"] = dict(s["by_class"])
    L.write_json(REPORT, rep)
    print(json.dumps(rep, indent=1)[:4000])


if __name__ == "__main__":
    main()
