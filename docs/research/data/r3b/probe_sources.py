#!/usr/bin/env python3
"""R3b: measure which public image sources cover Ear Drama's content kinds.

Research only (docs/research/design/R3b-image-sources.md). Stdlib only. Every
response is cached under cache/ next to this file (gitignored), so a rerun is
offline. One User-Agent ("EarDramaResearch/1.0"), a pause per host, and a 429
honors Retry-After; loc.gov's 429 stops that phase (its block restarts on any
request made during it).

    python3 probe_sources.py sample          # live projection -> sample.json
    python3 probe_sources.py wikidata        # series + news subjects -> wd.json
    python3 probe_sources.py wikipedia       # enwiki summary images -> wp.json
    python3 probe_sources.py commons         # Commons file search -> commons.json
    python3 probe_sources.py loc             # loc.gov photos -> loc.json
    python3 probe_sources.py openverse       # Openverse -> openverse.json
    python3 probe_sources.py europeana       # Europeana (public demo key) -> europeana.json
    python3 probe_sources.py plays           # plays: Wikidata, enwiki, IA scans, Gutenberg covers -> plays_probe.json
    python3 probe_sources.py orgs            # networks + sponsors logos -> orgs.json
    python3 probe_sources.py licenses        # classify every file seen -> files.json
    python3 probe_sources.py report          # coverage tables -> report.json (+ stdout)
"""
import hashlib
import json
import os
import random
import re
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "cache")
UA = "EarDramaResearch/1.0"
PAUSE = {"www.wikidata.org": 1.5, "en.wikipedia.org": 1.5, "commons.wikimedia.org": 1.5,
         "www.loc.gov": 6.5, "api.openverse.org": 4.0, "api.europeana.eu": 1.0,
         "archive.org": 1.0, "www.gutenberg.org": 1.0, "eardrama.org": 0.2}
_last = {}
SEED = 20261119
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
sys.path.insert(0, os.path.join(REPO, "catalog", "tools"))


class Blocked(Exception):
    pass


def fetch(url, *, method="GET", binary=False, tries=6, data=None):
    host = urllib.parse.urlparse(url).netloc
    key = hashlib.sha1((method + " " + url + ("\n" + data if data else "")).encode()).hexdigest()
    path = os.path.join(CACHE, host, key + (".bin" if binary else ".json"))
    if os.path.exists(path):
        with open(path, "rb") as f:
            body = f.read()
        return body if binary else json.loads(body)
    for attempt in range(tries):
        wait = PAUSE.get(host, 1.0) - (time.time() - _last.get(host, 0))
        if wait > 0:
            time.sleep(wait)
        _last[host] = time.time()
        hdr = {"User-Agent": UA, "Accept": "application/json"}
        if data:
            hdr["Content-Type"] = "application/x-www-form-urlencoded"
        req = urllib.request.Request(url, method=method, headers=hdr, data=data.encode() if data else None)
        try:
            with urllib.request.urlopen(req, timeout=40) as r:
                status, body = r.status, (r.read() if method in ("GET", "POST") else b"")
        except urllib.error.HTTPError as e:
            if e.code == 429:
                if host == "www.loc.gov":
                    raise Blocked(url)
                ra = int(e.headers.get("Retry-After") or 10)
                print(f"429 {host} retry-after {ra}", file=sys.stderr, flush=True)
                time.sleep(min(ra, 1300) + 2)
                continue
            if e.code in (404, 410, 400):
                status, body = e.code, b""
            elif attempt < tries - 1:
                time.sleep(3 * (attempt + 1))
                continue
            else:
                return None
        except Exception:
            if attempt < tries - 1:
                time.sleep(3 * (attempt + 1))
                continue
            return None
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if method == "HEAD":
            out = {"status": status}
            with open(path, "w") as f:
                json.dump(out, f)
            return out
        if binary:
            with open(path, "wb") as f:
                f.write(body)
            return body
        try:
            out = json.loads(body) if body else {"_status": status}
        except ValueError:
            if b"captcha" in body[:4000].lower():
                raise Blocked(url)
            out = {"_status": status, "_nonjson": True}
        with open(path, "w") as f:
            json.dump(out, f)
        return out
    return None


def q(base, **params):
    return base + "?" + urllib.parse.urlencode(params)


def load(name, default=None):
    p = os.path.join(HERE, name)
    if not os.path.exists(p):
        return default
    with open(p) as f:
        return json.load(f)


def save(name, obj):
    with open(os.path.join(HERE, name), "w") as f:
        json.dump(obj, f, indent=1, ensure_ascii=False, sort_keys=True)


def norm(s):
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode().lower()
    s = re.sub(r"&", " and ", s)
    s = re.sub(r"[^a-z0-9 ]+", " ", s)
    s = re.sub(r"^(the|a|an) ", "", s.strip())
    return re.sub(r"\s+", " ", s).strip()


def years_of(text):
    return [int(y) for y in re.findall(r"\b(19[0-9]{2}|18[5-9][0-9]|20[0-2][0-9])\b", text or "")]


# ---------------------------------------------------------------- sample

def cmd_sample():
    s = fetch("https://eardrama.org/data/index/series.json")
    F = s["fields"]
    rows = [dict(zip(F, r)) for r in s["rows"]]
    for r in rows:
        y = r.get("years")
        r["y0"] = int(r["first"][:4]) if r.get("first") else (y[0] if y else None)
        r["y1"] = int(r["last"][:4]) if r.get("last") else ((y[0] + len(y) - 2) if y else None)
    rows.sort(key=lambda r: (-(r.get("downloads") or 0), r["key"]))
    top = rows[:300]
    rest = sorted(rows[300:], key=lambda r: r["key"])
    rnd = random.Random(SEED).sample(rest, 100)
    news = [r for r in rows if r.get("genre") in ("news", "documentary")][:40]
    keep = ("key", "name", "genre", "y0", "y1", "episodes", "networks", "star", "downloads", "pictureKind")
    p = fetch("https://eardrama.org/data/plays/library/index.json")
    plays = sorted(p["plays"], key=lambda x: x["id"])
    psamp = random.Random(SEED).sample(plays, 50)
    save("sample.json", {
        "generated": time.strftime("%Y-%m-%d"),
        "series_total": len(rows), "plays_total": len(plays),
        "live_art": sum(1 for r in rows if r.get("art")),
        "top": [{k: r.get(k) for k in keep} for r in top],
        "random": [{k: r.get(k) for k in keep} for r in rnd],
        "news": [{k: r.get(k) for k in keep} for r in news],
        "plays": [{"id": x["id"], "title": x["title"], "authors": x["authors"], "kind": x["kind"],
                   "source": x["source"]["url"]} for x in psamp],
    })
    print("top", len(top), "random", len(rnd), "news", len(news), "plays", len(psamp))


def all_series(S):
    seen, out = set(), []
    for grp in ("top", "random", "news"):
        for r in S[grp]:
            if r["key"] not in seen:
                seen.add(r["key"])
                out.append(r)
    return out


# ---------------------------------------------------------------- Wikidata via SPARQL
# The Action API (wbsearchentities) answered this UA 429 at one request per 1.5 s
# on 2026-11-19; the query service batches 40 names a request instead.

SPARQL = "https://query.wikidata.org/sparql"
PAUSE["query.wikidata.org"] = 75.0  # "Aggressively rate-limiting to 1 req / min" (WDQS outage rule, 2026-11-19)


def sparql(query):
    return fetch(SPARQL, method="POST", data=urllib.parse.urlencode({"query": query, "format": "json"}))


def _lit(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"@en'


def name_variants(name):
    v = {name}
    if name.startswith("The "):
        v.add(name[4:])
    else:
        v.add("The " + name)
    for a, b in ((" and ", " & "), (" & ", " and ")):
        if a in name:
            v |= {x.replace(a, b) for x in list(v)}
    return sorted(v)


def wd_lookup(names, extra=""):
    """{name: [qid]} for items whose en label or alias is exactly a name (``extra`` adds a triple filter)."""
    out = {}
    names = sorted(set(names))
    for i in range(0, len(names), 250):
        chunk = names[i:i + 250]
        query = ("SELECT DISTINCT ?name ?item WHERE { VALUES ?name { " + " ".join(_lit(n) for n in chunk) +
                 " } { ?item rdfs:label ?name } UNION { ?item skos:altLabel ?name } " + extra + " }")
        r = sparql(query)
        if r is None:
            print("sparql lookup failed", i, file=sys.stderr)
            continue
        for b in r.get("results", {}).get("bindings", []):
            out.setdefault(b["name"]["value"], []).append(b["item"]["value"].rsplit("/", 1)[-1])
    return out


def wd_items(qids):
    """slim() records for items, from the query service."""
    qids = sorted(set(qids))
    out = {x: {"label": None, "desc": "", "p31": [], "p449": [], "p50": [], "start": [], "end": [], "born": [],
               "died": [], "p373": [], "imgs": {}, "enwiki": None, "vlabels": {}} for x in qids}
    for i in range(0, len(qids), 60):
        chunk = qids[i:i + 60]
        vals = " ".join("wd:" + x for x in chunk)
        q1 = ("SELECT ?item ?label ?desc ?wp WHERE { VALUES ?item { " + vals + " } "
              "OPTIONAL { ?item rdfs:label ?label FILTER(lang(?label)='en') } "
              "OPTIONAL { ?item schema:description ?desc FILTER(lang(?desc)='en') } "
              "OPTIONAL { ?wp schema:about ?item ; schema:isPartOf <https://en.wikipedia.org/> } }")
        q2 = ("SELECT ?item ?p ?v ?vl WHERE { VALUES ?item { " + vals + " } "
              "VALUES ?p { wdt:P31 wdt:P449 wdt:P50 wdt:P580 wdt:P582 wdt:P571 wdt:P577 wdt:P569 wdt:P570 wdt:P373 "
              "wdt:P18 wdt:P3383 wdt:P2716 wdt:P6802 wdt:P996 } ?item ?p ?v . "
              "OPTIONAL { ?v rdfs:label ?vl FILTER(lang(?vl)='en') } }")
        q3 = ("SELECT ?item ?v ?s ?e WHERE { VALUES ?item { " + vals + " } ?item p:P154 ?st . ?st ps:P154 ?v . "
              "OPTIONAL { ?st pq:P580 ?s } OPTIONAL { ?st pq:P582 ?e } }")
        r1, r2, r3 = sparql(q1), sparql(q2), sparql(q3)
        for b in (r1 or {}).get("results", {}).get("bindings", []):
            o = out[b["item"]["value"].rsplit("/", 1)[-1]]
            o["label"] = o["label"] or b.get("label", {}).get("value")
            o["desc"] = o["desc"] or b.get("desc", {}).get("value", "")
            if b.get("wp"):
                o["enwiki"] = urllib.parse.unquote(b["wp"]["value"].rsplit("/wiki/", 1)[-1]).replace("_", " ")
        for b in (r2 or {}).get("results", {}).get("bindings", []):
            o = out[b["item"]["value"].rsplit("/", 1)[-1]]
            p = b["p"]["value"].rsplit("/", 1)[-1]
            v = b["v"]["value"]
            if v.startswith("http://www.wikidata.org/entity/"):
                v = v.rsplit("/", 1)[-1]
                if b.get("vl"):
                    o["vlabels"][v] = b["vl"]["value"]
            if p in ("P18", "P3383", "P2716", "P6802", "P996"):
                o["imgs"].setdefault(p, []).append({"file": urllib.parse.unquote(v.rsplit("/", 1)[-1]).replace("_", " ")})
            elif p in ("P580", "P571", "P577"):
                o["start"].append(v[:4])
            elif p == "P582":
                o["end"].append(v[:4])
            elif p == "P569":
                o["born"].append(v[:4])
            elif p == "P570":
                o["died"].append(v[:4])
            else:
                o[p.lower()].append(v)
        for b in (r3 or {}).get("results", {}).get("bindings", []):
            o = out[b["item"]["value"].rsplit("/", 1)[-1]]
            d = {"file": urllib.parse.unquote(b["v"]["value"].rsplit("/", 1)[-1]).replace("_", " ")}
            if b.get("s"):
                d["P580"] = b["s"]["value"][:4]
            if b.get("e"):
                d["P582"] = b["e"]["value"][:4]
            o["imgs"].setdefault("P154", []).append(d)
    for o in out.values():
        o["start"] = sorted(set(o["start"]))[:1]
        o["end"] = sorted(set(o["end"]))[-1:]
    return out


# ---------------------------------------------------------------- Wikidata (Action API, orgs only)

WD = "https://www.wikidata.org/w/api.php"
IMG_PROPS = {"P18": "image", "P154": "logo", "P3383": "poster", "P2716": "collage", "P6802": "related",
             "P4291": "panorama", "P5775": "interior", "P1442": "grave", "P996": "scan"}
NOT_RADIO = re.compile(r"\b(television|tv series|tv program|film|novel|song|album|single|comic|video game|"
                       r"musical|book|magazine|newspaper|band|play by|opera|painting|episode of)\b", re.I)
RADIO = re.compile(r"\bradio\b|\bbroadcast", re.I)


def wd_search(text, limit=7):
    r = fetch(q(WD, action="wbsearchentities", search=text, language="en", type="item",
                limit=limit, format="json"))
    return [h["id"] for h in (r or {}).get("search", [])]


def wd_entities(ids):
    out = {}
    ids = list(dict.fromkeys(ids))
    for i in range(0, len(ids), 50):
        chunk = ids[i:i + 50]
        r = fetch(q(WD, action="wbgetentities", ids="|".join(chunk), props="labels|descriptions|claims|sitelinks",
                    languages="en", sitefilter="enwiki", format="json"))
        for qid, e in ((r or {}).get("entities") or {}).items():
            out[qid] = slim(e)
    return out


def _val(c):
    dv = c.get("mainsnak", {}).get("datavalue", {}).get("value")
    if isinstance(dv, dict):
        if "id" in dv:
            return dv["id"]
        if "time" in dv:
            return dv["time"][1:5]
    return dv


def _quals(c):
    out = {}
    for p, snaks in (c.get("qualifiers") or {}).items():
        for s in snaks:
            v = s.get("datavalue", {}).get("value")
            if isinstance(v, dict) and "time" in v:
                out[p] = v["time"][1:5]
    return out


def slim(e):
    cl = e.get("claims") or {}
    def vals(p):
        return [_val(c) for c in cl.get(p, []) if _val(c)]
    imgs = {}
    for p in IMG_PROPS:
        if cl.get(p):
            imgs[p] = [{"file": _val(c), **_quals(c)} for c in cl[p] if _val(c)]
    return {
        "label": e.get("labels", {}).get("en", {}).get("value"),
        "desc": e.get("descriptions", {}).get("en", {}).get("value") or "",
        "p31": vals("P31"), "p449": vals("P449"), "p50": vals("P50"),
        "start": (vals("P580") + vals("P571") + vals("P577"))[:1],
        "end": vals("P582")[:1], "born": vals("P569")[:1], "died": vals("P570")[:1],
        "p373": vals("P373")[:1], "imgs": imgs,
        "enwiki": e.get("sitelinks", {}).get("enwiki", {}).get("title"),
    }


RADIO_CLASSES = {"Q1555508", "Q2635894", "Q15416", "Q7889", "Q1047113", "Q211025", "Q24634210", "Q7216866",
                 "Q15709879", "Q1144661", "Q105543609", "Q24862"}
NETWORK_QIDS = {}


def network_match(item, networks, labels):
    nets = norm(networks or "")
    for b in item["p449"]:
        lab = norm(labels.get(b, ""))
        for tok in ("nbc", "cbs", "mutual", "abc", "blue", "don lee", "afrs", "armed forces", "cbc", "bbc",
                    "columbia", "national broadcasting", "american broadcasting"):
            if tok in lab and (tok in nets or {"columbia": "cbs", "national broadcasting": "nbc",
                                               "american broadcasting": "abc", "armed forces": "afrs"}.get(tok, "#") in nets):
                return True
    return False


def identity(item, r, labels):
    """How a Wikidata item is tied to our series, mirroring art_policy.series_identity's spirit."""
    if NOT_RADIO.search(item["desc"]) and not RADIO.search(item["desc"]):
        return None
    radioish = RADIO.search(item["desc"]) or (set(item["p31"]) & RADIO_CLASSES)
    if not radioish:
        return None
    ys = [int(x) for x in item["start"] + item["end"] if str(x).isdigit()] + years_of(item["desc"])
    if r.get("y0") and ys:
        lo, hi = r["y0"] - 2, (r.get("y1") or r["y0"]) + 2
        if any(lo <= y <= hi for y in ys):
            return "years"
        return "years-contradict"
    if network_match(item, r.get("networks"), labels):
        return "network"
    return "title-only"


def title_ok(item, name):
    a, b = norm(item["label"] or ""), norm(name)
    b2 = re.sub(r" (program|show|hour|theater|theatre)$", "", b)
    return a == b or a == b2 or re.sub(r" (program|show|hour)$", "", a) == b2


def cmd_lookup():
    S = load("sample.json")
    names = {v for r in all_series(S) for v in name_variants(r["name"])}
    for p in S["plays"]:
        t = re.sub(r"\s*[:;,]\s.*$", "", p["title"]).strip()
        names |= set(name_variants(t)) | set(p["authors"][:1])
    names |= set(NETWORKS) | set(SPONSORS)
    save("lookup.json", wd_lookup(sorted(names)))
    print("names", len(names))


def cmd_wikidata():
    S = load("sample.json")
    series = all_series(S)
    hits = load("lookup.json")
    cands = {r["key"]: sorted({x for v in name_variants(r["name"]) for x in hits.get(v, [])}) for r in series}
    ents = wd_entities([i for v in cands.values() for i in v])
    labels = {k: (v["label"] or "") for k, v in wd_entities(sorted({b for e in ents.values() for b in e["p449"]})).items()}
    out = {}
    for r in series:
        best = None
        for qid in cands[r["key"]]:
            e = ents.get(qid)
            if not e:
                continue
            idt = identity(e, r, labels)
            if idt in (None, "years-contradict"):
                continue
            rank = {"years": 0, "network": 1, "title-only": 2}[idt]
            if best is None or rank < best[0]:
                best = (rank, qid, idt)
        # news / documentary: the subject may be a person ("Franklin D Roosevelt", "H V Kaltenborn")
        subject = None
        if r.get("genre") in ("news", "documentary"):
            for qid in cands[r["key"]]:
                e = ents.get(qid)
                if e and "Q5" in e["p31"]:
                    subject = qid
                    break
        out[r["key"]] = {"match": best and {"qid": best[1], "identity": best[2], **ents[best[1]]},
                         "subject": subject and {"qid": subject, **ents[subject]}}
    save("wd.json", out)
    n = sum(1 for v in out.values() if v["match"])
    print("series", len(series), "matched", n)


# ---------------------------------------------------------------- Wikipedia

EN = "https://en.wikipedia.org/w/api.php"


def summary(title):
    return fetch("https://en.wikipedia.org/api/rest_v1/page/summary/" + urllib.parse.quote(title.replace(" ", "_"), safe=""))


def enwiki_pages(titles):
    """{asked title: page record} for up to many titles, 50 a request, following redirects."""
    out = {}
    titles = sorted(set(titles))
    for i in range(0, len(titles), 50):
        chunk = titles[i:i + 50]
        r = fetch(q(EN, action="query", format="json", redirects=1, titles="|".join(chunk),
                    prop="pageprops|description|pageimages", piprop="original|name",
                    ppprop="wikibase_item|page_image_free|disambiguation")) or {}
        qq = r.get("query", {})
        hop = {}
        for n in qq.get("normalized", []) + qq.get("redirects", []):
            hop[n["from"]] = n["to"]
        pages = {pg["title"]: pg for pg in (qq.get("pages") or {}).values()}
        for t in chunk:
            u = t
            for _ in range(3):
                u = hop.get(u, u)
            pg = pages.get(u)
            if pg and "missing" not in pg:
                pp = pg.get("pageprops", {})
                out[t] = {"title": pg["title"], "desc": pg.get("description") or "", "qid": pp.get("wikibase_item"),
                          "disambig": "disambiguation" in pp, "free": pp.get("page_image_free"),
                          "pageimage": pg.get("pageimage"), "image": (pg.get("original") or {}).get("source"),
                          "w": (pg.get("original") or {}).get("width"), "h": (pg.get("original") or {}).get("height")}
    return out


SUFFIXES = ("", " (radio program)", " (radio series)", " (radio show)", " (radio drama)", " (radio)")


def cmd_wikipedia():
    S = load("sample.json")
    W = load("wd.json")
    want = {}
    for r in all_series(S):
        m = (W.get(r["key"]) or {}).get("match")
        if m and m.get("enwiki"):
            want[r["key"]] = [m["enwiki"]]
        else:
            want[r["key"]] = [r["name"] + sfx for sfx in SUFFIXES]
    pages = enwiki_pages([t for v in want.values() for t in v])
    out = {}
    for r in all_series(S):
        m = (W.get(r["key"]) or {}).get("match")
        hit = None
        for t in want[r["key"]]:
            pg = pages.get(t)
            if not pg or pg["disambig"]:
                continue
            if m and m.get("enwiki") == t:
                hit = (pg, "wikidata-sitelink", m["identity"])
                break
            d = pg["desc"]
            if not RADIO.search(d + " " + pg["title"]) or re.search(r"\btelevision\b", d, re.I) and not RADIO.search(d):
                continue
            ys = years_of(d)
            if r.get("y0") and ys:
                lo, hi = r["y0"] - 2, (r.get("y1") or r["y0"]) + 2
                if not any(lo <= y <= hi for y in ys):
                    continue
                hit = (pg, "enwiki-title", "years")
            else:
                hit = (pg, "enwiki-title", "title-only")
            break
        if not hit:
            out[r["key"]] = None
            continue
        pg, via, idt = hit
        out[r["key"]] = {**pg, "via": via, "identity": idt}
    save("wp.json", out)
    print("with page", sum(1 for v in out.values() if v), "with image",
          sum(1 for v in out.values() if v and v["image"]))


def cmd_wp_any():
    """The same articles' lead image with pilicense=any: how many leads are non-free (PageImages hides them by default)."""
    WP = load("wp.json")
    titles = sorted({v["title"] for v in WP.values() if v})
    out = {}
    for i in range(0, len(titles), 50):
        chunk = titles[i:i + 50]
        r = fetch(q(EN, action="query", format="json", titles="|".join(chunk), prop="pageimages",
                    piprop="original|name", pilicense="any")) or {}
        for pg in (r.get("query", {}).get("pages") or {}).values():
            out[pg["title"]] = {"pageimage": pg.get("pageimage"), "image": (pg.get("original") or {}).get("source")}
    save("wp_any.json", out)
    print("articles", len(titles), "with any lead image", sum(1 for v in out.values() if v["image"]))


# ---------------------------------------------------------------- Commons search

CM = "https://commons.wikimedia.org/w/api.php"


def cmd_commons():
    S = load("sample.json")
    out = load("commons.json", {})
    # Commons answered 429 (Retry-After 30-45 s) to this UA on 2026-11-19, so the search route is
    # measured on a sub-sample: the top 100 and the first 50 of the random 100.
    for r in S["top"][:100] + S["random"][:50]:
        if r["key"] in out:
            continue
        res = fetch(q(CM, action="query", list="search", srnamespace=6, srlimit=20, format="json",
                      srsearch=f'"{r["name"]}" radio'))
        if res is None:
            continue
        out[r["key"]] = [h["title"] for h in res.get("query", {}).get("search", [])]
        save("commons.json", out)
    print("series with any hit", sum(1 for v in out.values() if v))


PUBLICITY = ["Category:CBS Radio publicity photos", "Category:NBC Radio publicity photos",
             "Category:ABC Radio publicity photos", "Category:Mutual Broadcasting System publicity photos",
             "Category:Blue Network publicity photos", "Category:Radio programs of the United States",
             "Category:Old-time radio", "Category:Radio drama", "Category:PD US no notice advertisement",
             "Category:Radio Guide (magazine)", "Category:Radio Mirror", "Category:Radio Digest"]


def cmd_commons_cats():
    """Category route: what the network publicity-photo categories hold today (members 500 a request)."""
    info = fetch(q(CM, action="query", format="json", prop="categoryinfo", titles="|".join(PUBLICITY))) or {}
    counts = {pg["title"]: pg.get("categoryinfo", {}) for pg in (info.get("query", {}).get("pages") or {}).values()}
    members = {}
    for cat in PUBLICITY[:5]:
        todo, seen = [(cat, 0)], set()
        while todo:
            c, depth = todo.pop(0)
            if c in seen:
                continue
            seen.add(c)
            cont = {}
            while True:
                r = fetch(q(CM, action="query", format="json", list="categorymembers", cmtitle=c, cmlimit=500,
                            cmtype="file|subcat", **cont)) or {}
                for m in r.get("query", {}).get("categorymembers", []):
                    if m["ns"] == 14 and depth < 1:
                        todo.append((m["title"], depth + 1))
                    elif m["ns"] == 6:
                        members.setdefault(m["title"], []).append(c)
                if "continue" not in r:
                    break
                cont = {"cmcontinue": r["continue"]["cmcontinue"]}
    save("commons_cats.json", {"counts": counts, "members": members})
    print("files in publicity categories (depth 1):", len(members))


# ---------------------------------------------------------------- loc.gov

def _loc_rights(x):
    it = x.get("item") or {}
    r = it.get("rights_advisory") or it.get("rights_information") or x.get("rights_advisory") or ""
    return " ".join(map(str, r)) if isinstance(r, list) else str(r)


def cmd_loc():
    S = load("sample.json")
    series = S["top"][:60] + S["random"][:30] + S["news"][:20]
    out = load("loc.json", {})
    try:
        for r in series:
            if r["key"] in out and "--reparse" not in sys.argv:
                continue
            if "--reparse" in sys.argv and r["key"] not in out:
                continue
            res = fetch(q("https://www.loc.gov/photos/", q=f'"{r["name"]}" radio', fo="json", c=25,
                          at="results,pagination"))
            recs = []
            for x in (res or {}).get("results", []):
                recs.append({"id": x.get("id"), "title": x.get("title"), "date": x.get("date"),
                             "rights": _loc_rights(x),
                             "partof": x.get("partof") or [], "contributor": x.get("contributor") or [],
                             "image": (x.get("image_url") or [None])[-1]})
            out[r["key"]] = recs
            save("loc.json", out)
    except Blocked as b:
        print("loc.gov blocked; stopping:", b)
    print("queried", len(out))


# ---------------------------------------------------------------- Openverse / Europeana

def cmd_openverse():
    S = load("sample.json")
    out = load("openverse.json", {})
    for r in S["top"][:60]:
        if r["key"] in out:
            continue
        res = fetch(q("https://api.openverse.org/v1/images/", q=f'{r["name"]} radio', page_size=20))
        if res is None:
            print("openverse failed at", r["name"])
            break
        out[r["key"]] = [{"title": x.get("title"), "license": x.get("license"), "source": x.get("source"),
                          "provider": x.get("provider"), "url": x.get("foreign_landing_url"),
                          "w": x.get("width"), "h": x.get("height")} for x in res.get("results", [])]
        save("openverse.json", out)
    print("queried", len(out))


def cmd_europeana():
    S = load("sample.json")
    out = {}
    for r in S["top"][:60]:
        res = fetch(q("https://api.europeana.eu/record/v2/search.json", wskey="api2demo", query=f'"{r["name"]}"',
                      qf="TYPE:IMAGE", reusability="open", rows=20))
        out[r["key"]] = [{"title": (x.get("title") or [""])[0], "rights": (x.get("rights") or [""])[0],
                          "provider": (x.get("dataProvider") or [""])[0], "year": x.get("year")}
                         for x in (res or {}).get("items", [])]
    save("europeana.json", out)
    print("queried", len(out))


# ---------------------------------------------------------------- plays

def surname(a):
    a = re.sub(r"\(.*?\)", "", a).strip()
    return norm(a.split()[-1]) if a.split() else ""


def cmd_plays():
    S = load("sample.json")
    out = {}
    per = {}
    for p in S["plays"]:
        title = re.sub(r"\s*[:;,]\s.*$", "", p["title"]).strip()
        per[p["id"]] = title
    th = ah = load("lookup.json")
    for p in S["plays"]:
        t = per[p["id"]]
        per[p["id"]] = (t, sorted({x for v in name_variants(t) for x in th.get(v, [])}),
                        ah.get(p["authors"][0], []) if p["authors"] else [])
    ents = wd_entities([x for v in per.values() for x in v[1] + v[2]])
    for p in S["plays"]:
        title, w, a = per[p["id"]]
        sn = {surname(x) for x in p["authors"]}
        work = None
        auth_ids = set()
        for qid in a:
            e = ents.get(qid)
            if e and "Q5" in e["p31"] and surname(e["label"] or "") in sn:
                auth_ids.add(qid)
                break
        for qid in w:
            e = ents.get(qid)
            if not e:
                continue
            if (set(e["p50"]) & auth_ids) or any(s and s in norm(e["desc"]) for s in sn):
                work = qid
                break
        author = next(iter(auth_ids), None)
        wp = None
        if work and ents[work].get("enwiki"):
            sm = summary(ents[work]["enwiki"]) or {}
            wp = {"title": ents[work]["enwiki"], "image": (sm.get("originalimage") or {}).get("source"),
                  "w": (sm.get("originalimage") or {}).get("width"), "h": (sm.get("originalimage") or {}).get("height")}
        # archive.org: a scanned edition whose own record dates it
        qs = f'title:("{title}") AND mediatype:texts'
        if sn:
            qs += " AND creator:(" + " OR ".join(sorted(s for s in sn if s)) + ")"
        ia = fetch(q("https://archive.org/advancedsearch.php", q=qs, fl="identifier,title,date,year,creator,"
                     "possible-copyright-status,licenseurl", rows=25, output="json")) or {}
        docs = ia.get("response", {}).get("docs", [])
        def yr(d):
            v = str(d.get("year") or d.get("date") or "")[:4]
            return int(v) if v.isdigit() else None
        pre = [d for d in docs if yr(d) and yr(d) <= 1930]
        gid = p["id"].split("-", 1)[1] if p["id"].startswith("gut-") else None
        cover = None  # gutenberg.org answered 503 "down for maintenance" (Retry-After 21600) on 2026-11-19
        out[p["id"]] = {"title": p["title"], "authors": p["authors"],
                        "work": work and {"qid": work, **ents[work]},
                        "author": author and {"qid": author, **ents[author]},
                        "wp": wp, "ia_docs": len(docs), "ia_pre1931": [
                            {"id": d["identifier"], "year": yr(d), "pcs": d.get("possible-copyright-status")} for d in pre[:5]],
                        "gutenberg_cover": (cover or {}).get("status")}
    save("plays_probe.json", out)
    print("plays", len(out), "work", sum(1 for v in out.values() if v["work"]),
          "author", sum(1 for v in out.values() if v["author"]))


# ---------------------------------------------------------------- networks + sponsors

NETWORKS = ["National Broadcasting Company", "CBS Radio", "Columbia Broadcasting System", "Mutual Broadcasting System",
            "American Broadcasting Company", "Blue Network", "NBC Radio Network", "Armed Forces Radio Service",
            "Don Lee Broadcasting System", "Canadian Broadcasting Corporation", "BBC", "NPR", "WOR (AM)",
            "Australian Broadcasting Corporation", "CBS"]
SPONSORS = ["Philip Morris USA", "General Foods", "Camel (cigarette)", "Old Gold (cigarette)", "Ford Motor Company",
            "Gulf Oil", "General Mills", "Campbell Soup Company", "Procter & Gamble", "Lucky Strike", "Kellogg's",
            "Quaker Oats Company", "Pabst Brewing Company", "Kraft Foods", "Colgate-Palmolive", "The Coca-Cola Company",
            "Chevrolet", "Wrigley Company", "Lever Brothers", "Pepsodent", "Maxwell House", "Chase & Sanborn Coffee",
            "AT&T", "Wildroot", "Alka-Seltzer", "Lux (soap)", "Jell-O", "S. C. Johnson & Son", "Ovaltine",
            "Ralston Purina", "Lady Esther", "Woodbury Soap Company", "RCA", "Texaco", "Johnson & Johnson"]


def cmd_orgs():
    out = {"networks": {}, "sponsors": {}}
    for kind, names in (("networks", NETWORKS), ("sponsors", SPONSORS)):
        lk = load("lookup.json")
        ents = wd_entities([i for n in names for i in lk.get(n, [])])
        fit = re.compile(r"broadcast|network|radio|television|company|corporation|manufacturer|brand|"
                         r"cigarette|soap|cereal|beverage|coffee|food|toothpaste|drink|gelatin|dessert|oil", re.I)
        for n in names:
            ids = [i for i in lk.get(n, []) if fit.search(ents[i]["desc"] or "")]
            ids.sort(key=lambda i: (0 if ents[i]["imgs"].get("P154") else 1, int(i[1:])))
            out[kind][n] = {"qid": ids[0], **ents[ids[0]]} if ids else None
        # period advertisements on Commons whose own page carries the ad-level PD route
        if kind == "sponsors":
            for n in names:
                base = re.sub(r"\s*\(.*\)", "", n)
                res = fetch(q(CM, action="query", list="search", srnamespace=6, srlimit=50, format="json",
                              srsearch=f'"{base}" incategory:"PD US no notice advertisement"'))
                tot = (res or {}).get("query", {}).get("searchinfo", {}).get("totalhits", 0)
                if out[kind][n] is not None:
                    out[kind][n]["ads_no_notice"] = tot
                else:
                    out[kind][n] = {"ads_no_notice": tot}
    save("orgs.json", out)
    print("orgs saved")


# ---------------------------------------------------------------- license classes

def classify_meta(md, nonfree_repo=False):
    """A license class from a file's own page (Commons extmetadata, incl. hidden license categories)."""
    if md is None:
        return "missing"
    def g(k):
        return ((md.get(k) or {}).get("value") or "")
    cats = g("Categories")
    lic = g("License").lower()
    if g("NonFree").lower() == "true" or "non-free" in cats.lower() or "fair use" in cats.lower():
        return "non_free"
    if re.search(r"PD[ -]US[ -]?no notice|PD-US-no notice|PD US not renewed|PD-US-not renewed|PD US expired|"
                 r"PD-US-expired|PD-US-1978-89|PD US 1978|PD-US-defective|PD US defective|PD-1996|PD US\b|"
                 r"PD-US\b|Public domain in the United States", cats):
        return "pd_us"
    if re.search(r"PD-old-auto-expired|PD-old-100|PD-US-expired|PD US expired", cats):
        return "pd_us"
    if re.search(r"PD[ -]self|PD-author|PD-user|PD[ -]release", cats):
        return "pd_release"
    if re.search(r"Library of Congress-no known copyright restrictions", cats):
        return "loc_nkr"
    if re.search(r"PD[ -]USGov|PD US Government|PD-USGov", cats):
        return "pd_us_gov"
    if lic.startswith("cc0") or "CC-Zero" in cats:
        return "cc0"
    if lic.startswith("cc-by-sa"):
        return "cc_by_sa"
    if lic.startswith("cc-by"):
        return "cc_by"
    if re.search(r"PD[ -]textlogo|PD textlogo|PD-shape", cats):
        return "pd_textlogo"
    if re.search(r"PD[ -]old|PD-Art|PD-old|PD[ -]70", cats) or lic == "pd":
        return "pd_other"
    return "other"


EVIDENCE = {"pd_us", "pd_us_gov", "cc0", "pd_release", "cc_by", "cc_by_sa"}


def cmd_licenses():
    files = load("files.json", {})
    want = set()
    W = load("wd.json", {})
    for v in W.values():
        for k in ("match", "subject"):
            if v.get(k):
                for p, lst in v[k]["imgs"].items():
                    want |= {"File:" + x["file"] for x in lst}
    for v in (load("wp.json", {}) or {}).values():
        if v and v.get("image"):
            want.add(("EN " if "/wikipedia/en/" in v["image"] else "") + "File:" + urllib.parse.unquote(v["image"].split("?")[0].rsplit("/", 1)[-1]))
    for lst in (load("commons.json", {}) or {}).values():
        want |= set(lst)
    P = load("plays_probe.json", {}) or {}
    for v in P.values():
        for k in ("work", "author"):
            if v.get(k):
                for p, lst in v[k]["imgs"].items():
                    want |= {"File:" + x["file"] for x in lst}
        if v.get("wp") and v["wp"].get("image"):
            u = v["wp"]["image"]
            want.add(("EN " if "/wikipedia/en/" in u else "") + "File:" + urllib.parse.unquote(u.split("?")[0].rsplit("/", 1)[-1]))
    O = load("orgs.json", {}) or {}
    for kind in O.values():
        for v in kind.values():
            if v and v.get("imgs"):
                for p, lst in v["imgs"].items():
                    want |= {"File:" + x["file"] for x in lst}
    files = {k: v for k, v in files.items() if v.get("class") != "missing" and "?" not in k}
    todo = sorted(w for w in want if w not in files)
    for repo in ("commons", "en"):
        batch = [t for t in todo if (t.startswith("EN ") == (repo == "en"))]
        api = CM if repo == "commons" else EN
        for i in range(0, len(batch), 40):
            chunk = batch[i:i + 40]
            titles = [t[3:] if t.startswith("EN ") else t for t in chunk]
            r = fetch(q(api, action="query", format="json", prop="imageinfo", iiprop="size|extmetadata|mime",
                        iiextmetadatafilter="LicenseShortName|License|UsageTerms|Copyrighted|Artist|DateTimeOriginal|"
                                            "Categories|NonFree|Restrictions|AttributionRequired",
                        titles="|".join(titles))) or {}
            qn = {n["from"]: n["to"] for n in r.get("query", {}).get("normalized", [])}
            pages = {p["title"]: p for p in (r.get("query", {}).get("pages") or {}).values()}
            for orig, t in zip(chunk, titles):
                pg = pages.get(qn.get(t, t))
                ii = (pg or {}).get("imageinfo", [{}])[0] if pg and pg.get("imageinfo") else None
                md = ii.get("extmetadata") if ii else None
                files[orig] = {"class": classify_meta(md), "w": ii and ii.get("width"), "h": ii and ii.get("height"),
                               "mime": ii and ii.get("mime"),
                               "date": md and (md.get("DateTimeOriginal") or {}).get("value", "")[:60],
                               "artist": md and re.sub(r"<[^>]+>", "", (md.get("Artist") or {}).get("value", ""))[:80],
                               "cats": md and (md.get("Categories") or {}).get("value", "")[:400],
                               "restrictions": md and (md.get("Restrictions") or {}).get("value", "")}
            save("files.json", files)
    print("files classified", len(files))


# ---------------------------------------------------------------- report

def shape(w, h):
    if not w or not h:
        return "unknown"
    a = w / h
    return "portrait" if a < 0.9 else ("landscape" if a > 1.1 else "square")


def cmd_report():
    import photo_match as M
    S, W, WP, C, F = load("sample.json"), load("wd.json", {}), load("wp.json", {}), load("commons.json", {}), load("files.json", {})
    L, OV, EU, P, O = load("loc.json", {}), load("openverse.json", {}), load("europeana.json", {}), load("plays_probe.json", {}), load("orgs.json", {})
    rep = {"groups": {}, "matches": [], "shapes": {}}

    def wd_files(item, props=IMG_PROPS):
        out = []
        for p, lst in (item or {}).get("imgs", {}).items():
            if p in ("P1442",):
                continue
            for x in lst:
                f = F.get("File:" + x["file"], {})
                out.append({"file": x["file"], "prop": p, **f})
        return out

    def series_hits(r):
        k = r["key"]
        h = {}
        m = (W.get(k) or {}).get("match")
        strong = m and m["identity"] in ("years", "network")
        wf = [f for f in wd_files(m) if f.get("class") in EVIDENCE]
        h["wikidata_any"] = bool(wf)
        h["wikidata_strong"] = bool(wf) and strong
        wp = WP.get(k)
        if wp and wp.get("image") and wp.get("identity") in ("years", "network"):
            key = ("EN " if "/wikipedia/en/" in wp["image"] else "") + "File:" + urllib.parse.unquote(wp["image"].split("?")[0].rsplit("/", 1)[-1])
            cls = F.get(key, {}).get("class")
            h["wikipedia_strong"] = cls in EVIDENCE
            h["wikipedia_nonfree"] = cls == "non_free" or key.startswith("EN ") and cls not in EVIDENCE
        else:
            h["wikipedia_strong"] = False
            h["wikipedia_nonfree"] = False
        # Commons search: a file whose title or categories carry the series name and whose own date fits
        nm = norm(r["name"])
        cm_ok, cm_dated = [], []
        for t in C.get(k, []):
            f = F.get(t, {})
            if f.get("class") not in EVIDENCE:
                continue
            hay = norm(t) + " " + norm(f.get("cats") or "")
            if len(nm) < 4 or nm not in hay:
                continue
            cm_ok.append(t)
            ys = years_of(f.get("date") or "") or years_of(t)
            if r.get("y0") and ys and any(r["y0"] - 2 <= y <= (r.get("y1") or r["y0"]) + 2 for y in ys):
                cm_dated.append(t)
        h["commons_named"] = bool(cm_ok)
        h["commons_named_dated"] = bool(cm_dated)
        h["_commons_files"] = cm_dated[:3]
        lrecs = L.get(k)
        if lrecs is not None:
            usable = [x for x in lrecs if M.rights_class(x["rights"], " ".join(x["contributor"] + x["partof"])) in M.USABLE]
            named = [x for x in usable if nm in norm(x["title"])]
            h["loc_usable_any"] = bool(usable)
            h["loc_named"] = bool(named)
            h["loc_restricted_named"] = any(nm in norm(x["title"]) for x in lrecs) and not named
        if k in OV:
            h["openverse_named"] = any(nm in norm(x["title"] or "") for x in OV[k])
        if k in EU:
            h["europeana_named"] = any(nm in norm(x["title"] or "") for x in EU[k])
        subj = (W.get(k) or {}).get("subject")
        h["subject_person"] = bool([f for f in wd_files(subj) if f.get("class") in EVIDENCE])
        h["live_art"] = r.get("pictureKind") is not None
        h["live_show"] = r.get("pictureKind") == "show"
        h["any_new_show_image"] = h["wikidata_strong"] or h["wikipedia_strong"] or h["commons_named_dated"] or h.get("loc_named", False)
        return h, m, wf

    for grp in ("top", "random", "news"):
        rows = S[grp]
        agg = {}
        for r in rows:
            h, m, wf = series_hits(r)
            for kk, v in h.items():
                if kk.startswith("_"):
                    continue
                agg.setdefault(kk, [0, 0])
                agg[kk][1] += 1
                agg[kk][0] += 1 if v else 0
            if h["wikidata_any"] or h["wikipedia_strong"] or h["commons_named_dated"]:
                rep["matches"].append({"grp": grp, "key": r["key"], "name": r["name"], "y": [r.get("y0"), r.get("y1")],
                                       "net": r.get("networks"), "qid": m and m["qid"], "label": m and m["label"],
                                       "desc": m and m["desc"], "identity": m and m["identity"],
                                       "wd_files": [(f["prop"], f["file"], f.get("class"), f.get("date")) for f in wf][:4],
                                       "wp": WP.get(r["key"]) and (WP[r["key"]]["image"] or "")[-80:],
                                       "commons": h["_commons_files"]})
            for f in wf:
                s = shape(f.get("w"), f.get("h"))
                rep["shapes"].setdefault("series:" + f["prop"], {}).setdefault(s, 0)
                rep["shapes"]["series:" + f["prop"]][s] += 1
            for t in h["_commons_files"]:
                s = shape(F[t].get("w"), F[t].get("h"))
                rep["shapes"].setdefault("series:commons", {}).setdefault(s, 0)
                rep["shapes"]["series:commons"][s] += 1
        rep["groups"][grp] = {k2: {"n": v[0], "of": v[1], "pct": round(100 * v[0] / v[1], 1)} for k2, v in sorted(agg.items())}
        # matching statistics
        ids = [W.get(r["key"], {}).get("match") for r in rows]
        rep["groups"][grp]["_wd_identity"] = {i: sum(1 for m in ids if m and m["identity"] == i) for i in ("years", "network", "title-only")}
        cls = {}
        for m in ids:
            for f in wd_files(m):
                cls[f.get("class")] = cls.get(f.get("class"), 0) + 1
        rep["groups"][grp]["_wd_file_classes"] = cls
        wpc = {}
        for r in rows:
            wp = WP.get(r["key"])
            if wp and wp.get("image"):
                key = ("EN " if "/wikipedia/en/" in wp["image"] else "") + "File:" + urllib.parse.unquote(wp["image"].split("?")[0].rsplit("/", 1)[-1])
                c = ("en-local:" if key.startswith("EN ") else "commons:") + str(F.get(key, {}).get("class"))
                wpc[c] = wpc.get(c, 0) + 1
        rep["groups"][grp]["_wp_image_classes"] = wpc
        rep["groups"][grp]["_wp_pages"] = sum(1 for r in rows if WP.get(r["key"]))
    # plays
    pa = {"n": len(P)}
    def ev(item):
        return [f for f in wd_files(item) if f.get("class") in EVIDENCE]
    pa["work_matched"] = sum(1 for v in P.values() if v["work"])
    pa["work_image"] = sum(1 for v in P.values() if ev(v["work"]))
    pa["author_matched"] = sum(1 for v in P.values() if v["author"])
    pa["author_portrait"] = sum(1 for v in P.values() if [f for f in ev(v["author"]) if f["prop"] == "P18"])
    def wpimg(v):
        if not v.get("wp") or not v["wp"].get("image"):
            return None
        u = v["wp"]["image"]
        return F.get(("EN " if "/wikipedia/en/" in u else "") + "File:" + urllib.parse.unquote(u.split("?")[0].rsplit("/", 1)[-1]), {}).get("class")
    pa["wikipedia_image_evidence"] = sum(1 for v in P.values() if wpimg(v) in EVIDENCE)
    pa["wikipedia_image_any"] = sum(1 for v in P.values() if wpimg(v))
    pa["ia_scan_any"] = sum(1 for v in P.values() if v["ia_docs"])
    pa["ia_scan_pre1931"] = sum(1 for v in P.values() if v["ia_pre1931"])
    pa["gutenberg_cover_200"] = sum(1 for v in P.values() if v["gutenberg_cover"] == 200)
    pa["any_work_image"] = sum(1 for v in P.values() if ev(v["work"]) or wpimg(v) in EVIDENCE or v["ia_pre1931"])
    pa["any_image_incl_author"] = sum(1 for v in P.values() if ev(v["work"]) or wpimg(v) in EVIDENCE or v["ia_pre1931"] or ev(v["author"]))
    for v in P.values():
        for f in ev(v["work"]) + ev(v["author"]):
            s = shape(f.get("w"), f.get("h"))
            kk = "plays:work" if v["work"] and f in ev(v["work"]) else "plays:author"
            rep["shapes"].setdefault(kk, {}).setdefault(s, 0)
            rep["shapes"][kk][s] += 1
    rep["plays"] = pa
    # orgs
    orgs = {}
    for kind, d in O.items():
        rows = []
        for n, v in d.items():
            logos = [f for f in wd_files(v, {"P154": 1}) if f["prop"] == "P154"] if v and v.get("imgs") else []
            rows.append({"name": n, "qid": v and v.get("qid"), "label": v and v.get("label"),
                         "logos": [(f["file"], f.get("class"), f.get("start") if False else None) for f in logos],
                         "logo_classes": sorted({str(f.get("class")) for f in logos}),
                         "dated_logos": sum(1 for x in (v or {}).get("imgs", {}).get("P154", []) if x.get("P580") or x.get("P582")),
                         "ads_no_notice": (v or {}).get("ads_no_notice")})
        orgs[kind] = rows
    rep["orgs"] = orgs
    save("report.json", rep)
    for grp, d in rep["groups"].items():
        print("==", grp)
        for k2, v in d.items():
            print("  ", k2, v)
    print("== plays", pa)
    print("== shapes", rep["shapes"])


if __name__ == "__main__":
    {"sample": cmd_sample, "lookup": cmd_lookup, "wikidata": cmd_wikidata, "wikipedia": cmd_wikipedia, "commons": cmd_commons, "commons_cats": cmd_commons_cats, "wp_any": cmd_wp_any,
     "loc": cmd_loc, "openverse": cmd_openverse, "europeana": cmd_europeana, "plays": cmd_plays,
     "orgs": cmd_orgs, "licenses": cmd_licenses, "report": cmd_report}[sys.argv[1]]()
