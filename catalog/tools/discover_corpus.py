"""Find archive.org audio that is old-time radio but outside the five harvest seeds.

    python3 tools/discover_corpus.py [--stage queries|fetch|classify|all] [--workers 4]

Stages (each resumable; a container restart loses at most one query or item):
  queries   build candidate queries from measured sources, record numFound for
            each and enumerate the ones narrow enough to read; one cache file
            per query under .cache/discover/q/.
  fetch     fetch /metadata for every candidate that passes the light gate
            (search fields only) into .cache/discover/meta/ (slimmed exactly as
            harvest_ia does, so harvest_ia can reuse the file).
  classify  judge every candidate; write editorial/extra_seeds.json (accepted
            ids + the queries that found each) and .cache/discover/report.json
            (every query's numFound/overlap, every rejection with its reason).

Query sources: subject/title/description terms (+ decade filters on the
radioprograms umbrella), the collections existing OTR items also belong to,
the uploaders of existing OTR items, every OTRR program title and RadioEchoes
series name (batched as OR'd title phrases), and OTRR's own archive ids.

collection:radioprograms (5 million items) is NEVER enumerated wholesale: a
query is enumerated only when its numFound is <= SCRAPE_CAP, and any query
naming radioprograms must carry another clause.
"""
import argparse
import concurrent.futures as cf
import glob
import hashlib
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
import ia_lib as ia
import otr_parse as P

DISC = os.path.join(ia.CACHE, "discover")
QDIR = os.path.join(DISC, "q")
MDIR = os.path.join(DISC, "meta")
EXTRA = os.path.join(ia.EDITORIAL, "extra_seeds.json")
SCRAPE_CAP = 30000
FIELDS = "identifier,mediatype,title,date,year,subject,collection,uploader,item_size,downloads"
AUDIO = "mediatype:audio"

TERMS = [
    'subject:"old time radio show"', 'subject:"old time radio shows"', 'subject:"oldtimeradio"',
    'subject:otr', 'title:otr', 'title:"old time radio"', 'title:"old-time radio"',
    'description:"old time radio"', 'subject:"golden age of radio"', 'description:"golden age of radio"',
    'subject:"radio drama"', 'title:"radio drama"', 'subject:"radio dramas"',
    'subject:"radio play"', 'subject:"radio plays"', 'title:"radio play"',
    'subject:"radio show"', 'subject:"radio shows"', 'title:"radio show"',
    'subject:"radio program"', 'subject:"radio programs"', 'subject:"radio programme"',
    'subject:"radio theater"', 'subject:"radio theatre"', 'subject:"audio theater"',
    'subject:"radio serial"', 'subject:"radio serials"', 'subject:"radio comedy"',
    'subject:"radio mystery"', 'subject:"radio western"', 'subject:"radio soap opera"',
    'subject:"radio broadcast"', 'subject:"radio broadcasts"', 'subject:"vintage radio"',
    'subject:"classic radio"', 'subject:"old radio"', 'subject:"nostalgia radio"',
    'subject:"radio history"', 'subject:"transcription disc"', 'subject:"transcription discs"',
    'subject:"electrical transcription"', 'subject:"radio transcription"', 'subject:transcriptions',
    'subject:afrs', 'title:afrs', 'subject:afrts', 'subject:"armed forces radio"',
    'subject:"armed forces radio service"', 'title:"armed forces radio"', 'subject:aircheck',
    'subject:airchecks', 'subject:"radio aircheck"', 'subject:"lux radio theatre"',
    'subject:"mercury theatre"', 'subject:"radio adventure"', 'subject:"radio detective"',
    'subject:"radio horror"', 'subject:"radio sci-fi"', 'subject:"radio science fiction"',
    'subject:"radio news" AND date:[1920-01-01 TO 1979-12-31]',
    'identifier:otr_*', 'identifier:*_otr', 'identifier:OTR*', 'identifier:*oldtimeradio*',
    'identifier:*OldTimeRadio*', 'identifier:*radiodrama*', 'identifier:*RadioDrama*',
]
# Phrases too broad to read whole (numFound > SCRAPE_CAP, measured 2026-10-19),
# read again narrowed to pre-1980 dates, decade subjects or OTR-ish genres.
BROAD = ['subject:"radio show"', 'title:"radio show"', 'subject:"radio program"', 'subject:radio']
NARROW = ['date:[1920-01-01 TO 1979-12-31]', 'year:[1920 TO 1979]',
          'subject:(1930s OR 1940s OR 1950s OR 1960s)',
          'subject:(drama OR mystery OR detective OR suspense OR western OR "science fiction" OR horror)',
          'subject:(comedy OR variety OR serial OR "soap opera" OR quiz)']
TERMS += [f"{b} AND {n}" for b in BROAD for n in NARROW]
# Radio collections too big to read whole (measured 2026-10-19), read narrowed.
BIG_RADIO_COLS = ["radioshowarchive", "radioshowinbox", "airchecks", "airchecks-misc", "hifidelity",
                  "hifidelity_potpourri", "podcasts_miscellaneous", "audio_news", "community_media"]
TERMS += [f'collection:{c} AND (subject:(otr OR "old time radio" OR "radio drama" OR "radio play" OR '
          f'"golden age of radio" OR afrs) OR title:(otr OR "old time radio") OR date:[1920-01-01 TO 1979-12-31])'
          for c in BIG_RADIO_COLS]
DECADES = [f"{d}s" for d in range(1920, 1980, 10)]
UMBRELLA_FILTERS = [f'collection:radioprograms AND subject:"{d}"' for d in DECADES] + [
    f'collection:radioprograms AND title:"{d}"' for d in DECADES] + [
    'collection:radioprograms AND date:[1920-01-01 TO 1979-12-31]',
    'collection:radioprograms AND year:[1920 TO 1979]',
    'collection:radioprograms AND subject:(drama OR mystery OR detective OR suspense OR western)',
    'collection:radioprograms AND subject:(comedy OR variety) AND subject:radio',
    'collection:radioprograms AND subject:"world war"',
    'collection:radioprograms AND title:(episode AND 194*)',
]
# Collections too broad to read, or that are user favourites lists: measured only.
NEVER_SCRAPE = {"radioprograms", "opensource_audio", "audio", "community", "opensource",
                "opensource_movies", "podcasts", "audio_music", "folksoundomy", "ourmedia",
                "opensource_image", "community_media", "audio_news", "folkscanomy"}

OTR_RX = re.compile(r"old[- ]?time[- ]?radio|\botrr?\b|golden age of radio|radio (drama|play|show|"
                    r"program|programme|serial|theat|broadcast|comedy|mystery|western|adventure|"
                    r"transcription|series)|transcription|\bafrts?\b|armed forces radio|aircheck|"
                    r"vintage radio|classic radio|old radio|nostalgia radio|lux radio|mercury theat", re.I)
STRONG_RX = re.compile(r"old[- ]?time[- ]?radio|oldtimeradio|\botrr?\b|golden age of radio|\bafrts?\b|"
                       r"armed forces radio|transcription disc|electrical transcription|vintage radio|"
                       r"classic radio|nostalgia radio", re.I)
PODCAST_RX = re.compile(r"podcast", re.I)
MUSIC_RX = re.compile(r"78 ?rpm|\bmusic\b|\bjazz\b|\borch\b|orchestra|\bpop\b|big band|\bsongs?\b|"
                      r"\balbum\b|\bconcert\b|\blive at\b|ragtime|dixieland|\bblues\b|\bfolk\b", re.I)
YEAR_IN_TEXT = re.compile(r"\b19[2-7]\d\b|\(\d{1,2}[-/.]\d{1,2}[-/.][2-7]\d\)|\b[2-7]\d[-.]\d\d[-.]\d\d\b")


def qkey(q):
    return hashlib.sha1(q.encode()).hexdigest()[:16]


def as_list(v):
    if v is None:
        return []
    if isinstance(v, (str, int, float)):
        return [str(v)]
    return [str(x) for x in v]


def existing_ids():
    """Items the five original seeds found (harvest_ia also records extra ids in seeds.json)."""
    import harvest_ia as H
    items = ia.read_json(os.path.join(ia.CACHE, "seeds.json"))["items"]
    return {i for i, v in items.items() if set(v.get("seeds", [])) & set(H.SEEDS)}


def meta_items():
    for f in glob.glob(os.path.join(ia.CACHE, "meta", "*.json.gz")):
        yield ia.read_json(f)


def build_queries():
    """Every candidate query, with the family that produced it. Returns [(family, label, q)]."""
    out = [("term", q, f"{AUDIO} AND ({q})") for q in TERMS]
    out += [("umbrella_filter", q, f"{AUDIO} AND {q}") for q in UMBRELLA_FILTERS]
    cols, ups = {}, {}
    for m in meta_items():
        it = m["item"]
        for c in as_list(it.get("collection")):
            if not c.startswith("fav-"):
                cols[c] = cols.get(c, 0) + 1
        u = it.get("uploader")
        if u:
            ups[u] = ups.get(u, 0) + 1
    for c, n in sorted(cols.items(), key=lambda x: -x[1]):
        if n >= 3 and c not in ("oldtimeradio", "lumedwards"):
            fam = "co_collection_measured" if c in NEVER_SCRAPE else "co_collection"
            out.append((fam, f"{c} ({n} existing)", f"collection:{c}"))
    for u, n in sorted(ups.items(), key=lambda x: -x[1]):
        if n >= 10:
            out.append(("uploader", f"{u} ({n} existing)", f'{AUDIO} AND uploader:"{u}"'))
    names = series_names()
    batch = []
    for i, n in enumerate(names):
        batch.append(n)
        if len(batch) == 40 or i == len(names) - 1:
            ors = " OR ".join(f'"{b}"' for b in batch)
            out.append(("series_title", f"series batch {i // 40:03d} ({batch[0]} .. {batch[-1]})",
                        f"{AUDIO} AND title:({ors})"))
            batch = []
    return out


def series_names():
    """OTRR program titles + RadioEchoes series, phrase-safe, deduplicated by norm."""
    raw = [p["ptitle"] for p in ia.read_json(os.path.join(ia.CACHE, "otrr", "otterlog.json"))]
    for f in glob.glob(os.path.join(ia.CACHE, "radioechoes", "series", "*.json")):
        raw.append(ia.read_json(f).get("series") or "")
    seen, out = set(), []
    for n in raw:
        n = re.sub(r'["\\():\[\]{}^~*?!+&|/-]', " ", n or "")
        n = re.sub(r"\s+", " ", n).strip()
        k = P.norm_series(n)
        # One-word names shorter than 8 letters ("Escape", "Suspense") match too
        # much modern audio to be worth a title query; the seeds already hold them.
        if len(k) < 6 or (" " not in n and len(k) < 8) or k in seen:
            continue
        seen.add(k)
        out.append(n)
    return sorted(out)


def run_query(family, label, q):
    measure_only = family.endswith("_measured")
    if q.strip() == "collection:radioprograms" and not measure_only:
        raise RuntimeError("refusing to enumerate collection:radioprograms wholesale")
    path = os.path.join(QDIR, qkey(q) + ".json.gz")
    if os.path.exists(path):
        return ia.read_json(path)
    nf = ia.num_found(q)
    rec = {"family": family, "label": label, "q": q, "numFound": nf, "items": None, "status": None}
    col = re.fullmatch(r"collection:(\S+)", q)
    if nf is None:
        rec["status"] = "failed"      # not cached: retried next run
        return rec
    if measure_only or nf > SCRAPE_CAP or (col and col.group(1) in NEVER_SCRAPE):
        rec["status"] = "measured_only"
    else:
        items = []
        try:
            for it in ia.scrape(q, FIELDS):
                items.append({k: it.get(k) for k in FIELDS.split(",") if it.get(k) is not None})
        except RuntimeError:
            rec["status"] = "failed"
            return rec
        if nf and len(items) < nf * 0.98:
            rec["status"] = "failed"      # scrape anomaly (07 §3): never trust a short read
            return rec
        rec["items"], rec["status"] = items, "scraped"
    ia.write_json(path, rec, gz=True)
    return rec


def stage_queries():
    qs = build_queries()
    have = existing_ids()
    results, fails = [], 0
    for i, (fam, label, q) in enumerate(qs, 1):
        r = run_query(fam, label, q)
        if r["status"] == "failed":
            fails += 1
        results.append(r)
        if i % 25 == 0:
            print(f"queries {i}/{len(qs)} failed={fails}", file=sys.stderr, flush=True)
    print(f"queries done {len(qs)} failed={fails}", file=sys.stderr)
    return results, have


def load_query_results():
    return [ia.read_json(f) for f in sorted(glob.glob(os.path.join(QDIR, "*.json.gz")))]


def candidates(results, have):
    cand = {}
    for r in results:
        for it in r.get("items") or []:
            i = it["identifier"]
            if i in have:
                continue
            c = cand.setdefault(i, dict(it, found_by=[]))
            c["found_by"].append({"family": r["family"], "label": r["label"]})
    for a in otrr_missing_ids(have):
        c = cand.setdefault(a, {"identifier": a, "found_by": []})
        c["found_by"].append({"family": "otrr_archive_id", "label": "OTRR log files[].archive_id"})
    return cand


def otrr_missing_ids(have):
    out = set()
    for f in glob.glob(os.path.join(ia.CACHE, "otrr", "programs", "*.json.gz")):
        for e in ia.read_json(f).get("episodes", []):
            for fl in e.get("files") or []:
                a = fl.get("archive_id")
                if a and a not in have:
                    out.add(a)
    return out


def light_text(c):
    return " ".join(as_list(c.get("subject")) + as_list(c.get("title")) + as_list(c.get("collection")))


def light_gate(c):
    """True when a candidate is worth a /metadata fetch, judged on its search fields alone.

    An old-time-radio term (STRONG_RX) earns a fetch whatever the item's year,
    because uploaders date items by upload; a weaker radio term ("radio play",
    "aircheck", "Radio Program") needs a pre-1980 year; a series-title or
    OTR-uploader hit with a pre-1980 year earns one so its file names can speak.
    """
    fams = {f["family"] for f in c["found_by"]}
    if "otrr_archive_id" in fams:
        return True
    if c.get("mediatype") != "audio":
        return False
    txt = light_text(c)
    yr = item_year(c)
    old = (yr is not None and yr <= 1979) or bool(YEAR_IN_TEXT.search(" ".join(as_list(c.get("title")))))
    if PODCAST_RX.search(txt) and not STRONG_RX.search(txt):
        return False
    if STRONG_RX.search(txt):
        return True
    if OTR_RX.search(txt) and old:
        return True
    if not old or MUSIC_RX.search(txt) or c["identifier"].startswith(("78_", "lp_")):
        return False
    return bool(fams & {"series_title", "uploader"})


def item_year(it):
    for k in ("year", "date"):
        v = it.get(k)
        if isinstance(v, list):
            v = v[0] if v else None
        m = re.match(r"\s*(\d{4})", str(v or ""))
        if m:
            return int(m.group(1))
    return None


def fetch_one(ident):
    import harvest_ia as H
    path = os.path.join(MDIR, ident + ".json.gz")
    if os.path.exists(path) or os.path.exists(os.path.join(ia.CACHE, "meta", ident + ".json.gz")):
        return ident, "cached"
    md = ia.get(ia.META + ident, timeout=120)
    if md is None:
        return ident, "failed"
    if not md:
        return ident, "empty"
    ia.write_json(path, H.slim(md), gz=True)
    return ident, "fetched"


def stage_fetch(cand, workers):
    todo = sorted(i for i, c in cand.items() if light_gate(c))
    status = {}
    t0 = time.time()
    with cf.ThreadPoolExecutor(workers) as ex:
        for n, (i, st) in enumerate(ex.map(fetch_one, todo), 1):
            status[i] = st
            if n % 250 == 0:
                print(f"fetch {n}/{len(todo)} {time.time() - t0:.0f}s", file=sys.stderr, flush=True)
    ia.write_json(os.path.join(DISC, "fetch_status.json"), status)
    return status


def load_meta(ident):
    for d in (MDIR, os.path.join(ia.CACHE, "meta")):
        p = os.path.join(d, ident + ".json.gz")
        if os.path.exists(p):
            return ia.read_json(p)
    return None


def file_dates(files):
    """(audio stems, dated stems, dated <=1979, dated >=1980) over distinct file stems."""
    stems = {}
    for f in files:
        if f.get("private") == "true":
            continue
        stems.setdefault(P.stem(f.get("name", "")).lower(), f.get("name", ""))
    dated = old = modern = 0
    for name in stems.values():
        d = P.parse(name)["date"]
        if d:
            dated += 1
            if int(d[:4]) <= 1979:
                old += 1
            else:
                modern += 1
    return len(stems), dated, old, modern


def classify(c, meta):
    """Return (accept: bool, reason). Pure: every input is passed in."""
    fams = {f["family"] for f in c["found_by"]}
    if meta is None:
        return False, "no metadata (fetch failed or light gate refused)"
    it = meta.get("item") or {}
    if meta.get("is_dark"):
        return False, "item is dark"
    mt = it.get("mediatype") or c.get("mediatype")
    if mt != "audio":
        return False, f"mediatype {mt}"
    if not meta.get("files"):
        return False, "no audio files"
    n, dated, old_f, mod_f = file_dates(meta["files"])
    desc = (it.get("description") or "")[:1500] if isinstance(it.get("description"), str) else ""
    text = " ".join(as_list(it.get("subject")) + [it.get("title") or ""] +
                    [x for x in as_list(it.get("collection")) if not x.startswith("fav-")])
    yr = item_year(it)
    old = (yr is not None and yr <= 1979) or old_f >= 1 or bool(YEAR_IN_TEXT.search(it.get("title") or ""))
    radio = bool(OTR_RX.search(text) or OTR_RX.search(desc))
    strong = bool(STRONG_RX.search(text) or STRONG_RX.search(desc))
    podcast = bool(PODCAST_RX.search(text))
    if "otrr_archive_id" in fams:
        return True, "OTRR log names this archive id"
    if dated >= 3 and mod_f >= 0.8 * dated:
        return False, f"files dated 1980+ ({mod_f}/{dated})"
    if old_f >= 2 and old_f >= 0.3 * max(dated, 1) and (radio or fams & {"series_title", "co_collection", "uploader"}):
        return True, f"files parse as pre-1980 broadcasts ({old_f}/{n})"
    if podcast and not old:
        return False, "podcast, no pre-1980 evidence"
    if strong:
        return True, "old-time-radio term" + (" + pre-1980 evidence" if old else "")
    if radio and old:
        return True, "radio term + pre-1980 evidence"
    if radio:
        return False, "radio term, no pre-1980 evidence (modern audio drama?)"
    if old:
        return False, "pre-1980 but nothing says radio (music/speech?)"
    return False, "no radio or pre-1980 evidence"


def stage_classify(results, cand, have):
    accepted, rejected = {}, {}
    for i, c in sorted(cand.items()):
        if light_gate(c):
            meta = load_meta(i)
            ok, why = classify(c, meta) if meta is not None else (False, "metadata fetch failed")
        else:
            meta = None
            ok, why = False, "light gate: " + ("not audio" if c.get("mediatype") != "audio"
                                               else "no radio term and no pre-1980 year")
        rec = {"found_by": sorted({f["label"] for f in c["found_by"]}),
               "families": sorted({f["family"] for f in c["found_by"]}), "reason": why}
        if ok:
            files = (meta or {}).get("files") or []
            rec["audio_files"] = len(files)
            accepted[i] = rec
        else:
            rec["title"] = (c.get("title") or ((meta or {}).get("item") or {}).get("title") or "")[:120]
            rejected[i] = rec
    qrep = []
    for r in results:
        ids = [it["identifier"] for it in r.get("items") or []]
        qrep.append({"family": r["family"], "label": r["label"], "q": r["q"], "numFound": r["numFound"],
                     "status": r["status"], "read": len(ids) if r.get("items") is not None else None,
                     "overlap_existing": sum(1 for x in ids if x in have),
                     "new": sum(1 for x in ids if x not in have),
                     "accepted": sum(1 for x in ids if x in accepted)})
    extra = {"about": "Archive.org items found by tools/discover_corpus.py outside harvest_ia's five seeds. "
                      "Each id carries the queries that found it and why it was accepted. harvest_ia "
                      "enumerates the original seeds plus these ids. Regenerated by discover_corpus.py.",
             "generated": time.strftime("%Y-%m-%d"),
             "queries": {}, "ids": accepted}
    ia.write_json(EXTRA, extra)
    ia.write_json(os.path.join(DISC, "report.json"),
                  {"queries": qrep, "candidates": len(cand), "accepted": len(accepted),
                   "rejected": len(rejected), "rejected_items": rejected})
    print(f"candidates {len(cand)} accepted {len(accepted)} rejected {len(rejected)}", file=sys.stderr)
    return accepted


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage", default="all", choices=["queries", "fetch", "classify", "all"])
    ap.add_argument("--workers", type=int, default=4)
    a = ap.parse_args()
    os.makedirs(QDIR, exist_ok=True)
    os.makedirs(MDIR, exist_ok=True)
    have = existing_ids()
    if a.stage in ("queries", "all"):
        stage_queries()
    results = load_query_results()
    if not results:
        print("no query results cached: nothing was read", file=sys.stderr)
        sys.exit(1)
    cand = candidates(results, have)
    if a.stage in ("fetch", "all"):
        st = stage_fetch(cand, a.workers)
        if st and not any(v in ("fetched", "cached") for v in st.values()):
            sys.exit(1)
    if a.stage in ("classify", "all"):
        stage_classify(results, cand, have)


if __name__ == "__main__":
    main()
