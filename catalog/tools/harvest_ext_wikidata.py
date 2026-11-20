"""Wikidata (CC0) series and episode items for radio, harvested whole, matched later.

    python3 tools/harvest_ext_wikidata.py
    python3 tools/harvest_ext_wikidata.py --names [--db out/radio-catalog.sqlite]   # H1, after a build

Rather than ask Wikidata one name at a time for ~9,000 names, this pulls every
item whose class (P31) is radio program Q1555508 or a subclass and that has an
English label (~9,700 measured 2026-10-19), plus every article in enwiki's
American radio categories (some US radio shows are typed only "television
series" or not typed at all), and fetches their full entities. Matching to our
series keys happens in enrich_external.py, where our years are known.

Writes, under .cache/wikidata/:
  items.json.gz     {qid: slim entity}  (series candidates)
  episodes.json.gz  {qid: slim entity}  (radio series episode items, Q57608327)
  enwiki_radio.json {enwiki title: {qid, cats}}  (category evidence)
  labels.json.gz    {qid: en label} for values (networks, people, genres)
  failed.json       requests that could not be read
  names.json.gz     --names (H1, R3b section 5.1): {hits: {qid: [names that reached it]},
                    items: {qid: slim entity} for radio items the class harvest missed,
                    shortdesc: {enwiki title: its own short description}, labels}
Exits non-zero when nothing was read (--names: when any request failed).
"""
import json
import os
import re
import sys
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ia_lib import CACHE, write_json  # noqa: E402
import harvest_ext_wm as wm  # noqa: E402

DIR = os.path.join(CACHE, "wikidata")
RADIO_PROGRAM = "Q1555508"
EPISODE = "Q57608327"
# Categories whose members are radio programs; crawled to DEPTH subcategories.
ENWIKI_ROOTS = ["Category:American radio programs", "Category:American radio dramas",
                "Category:Old-time radio", "Category:Lists of radio series episodes"]
DEPTH = 3

ITEM_PROPS = {
    "P31": "instance_of", "P449": "broadcaster", "P272": "production_company",
    "P136": "genre", "P1113": "episodes", "P161": "cast", "P725": "voice_actor",
    "P170": "creator", "P50": "author", "P57": "director", "P58": "screenwriter",
    "P162": "producer", "P86": "composer", "P371": "presenter", "P859": "sponsor",
    "P580": "start", "P582": "end", "P571": "inception", "P576": "dissolved",
    "P577": "published", "P495": "country", "P364": "language", "P18": "image",
    "P154": "logo", "P373": "commons_category", "P179": "series", "P1545": "ordinal",
    "P155": "follows", "P156": "followed_by", "P4969": "derivative", "P144": "based_on",
    "P6216": "copyright_status", "P275": "license",
}


def _v(b):
    """A SPARQL binding as the value slim() used to produce."""
    v = b["value"]
    if b["type"] == "uri":
        if v.startswith("http://www.wikidata.org/entity/"):
            return v.rsplit("/", 1)[-1]
        if "Special:FilePath/" in v:
            return urllib.parse.unquote(v.split("Special:FilePath/", 1)[1])
        return v
    if b.get("datatype", "").endswith("#dateTime"):
        return v[:10]
    return v


def _sparql_raw(query):
    d = wm.call(wm.SPARQL, {"query": query, "format": "json"}, cache_dir="wikidata/sparql", post=True)
    return None if d is None else d["results"]["bindings"]


PROP_FILTER = " ".join(f"wdt:{p}" for p in ITEM_PROPS)


def get_items(ids, batch=250):
    """Slim entities for `ids` by SPARQL. The Action API (wbgetentities) answers
    this egress IP with 429 for minutes at a time (measured 2026-10-19, shared
    with other sessions); the query service does not."""
    ids = sorted(set(ids))
    out = {}
    for i in range(0, len(ids), batch):
        chunk = ids[i:i + batch]
        vals = " ".join("wd:" + q for q in chunk)
        claims = _sparql_raw(f"""SELECT ?x ?p ?v ?t WHERE {{ VALUES ?x {{ {vals} }}
          ?x ?p ?v . ?prop wikibase:directClaim ?p ; wikibase:propertyType ?t .
          FILTER(?t = wikibase:ExternalId || ?p IN ({PROP_FILTER.replace(' ', ', ')})) }}""")
        names = _sparql_raw(f"""SELECT ?x ?l ?a ?d ?en WHERE {{ VALUES ?x {{ {vals} }}
          OPTIONAL {{ ?x rdfs:label ?l FILTER(lang(?l)="en") }}
          OPTIONAL {{ ?x skos:altLabel ?a FILTER(lang(?a)="en") }}
          OPTIONAL {{ ?x schema:description ?d FILTER(lang(?d)="en") }}
          OPTIONAL {{ ?en schema:about ?x ; schema:isPartOf <https://en.wikipedia.org/> }} }}""")
        if claims is None or names is None:
            print(f"  batch {i}: FAILED", file=sys.stderr)
            continue
        for b in names:
            q = _v(b["x"])
            e = out.setdefault(q, {"qid": q, "label": None, "aliases": [], "description": None,
                                   "enwiki": None, "props": {}, "external_ids": {}})
            if "l" in b:
                e["label"] = b["l"]["value"]
            if "a" in b and b["a"]["value"] not in e["aliases"]:
                e["aliases"].append(b["a"]["value"])
            if "d" in b:
                e["description"] = b["d"]["value"]
            if "en" in b:
                e["enwiki"] = urllib.parse.unquote(b["en"]["value"].rsplit("/wiki/", 1)[1]).replace("_", " ")
        for b in claims:
            q = _v(b["x"])
            e = out[q]
            pid = b["p"]["value"].rsplit("/", 1)[1]
            v = _v(b["v"])
            if b["t"]["value"].endswith("ExternalId"):
                lst = e["external_ids"].setdefault(pid, [])
            else:
                lst = e["props"].setdefault(ITEM_PROPS[pid], [])
            if v not in lst:
                lst.append(v)
        print(f"  items {i + len(chunk)}/{len(ids)}", flush=True)
    return out


def get_labels(ids, batch=400):
    ids = sorted(set(ids))
    out = {}
    for i in range(0, len(ids), batch):
        vals = " ".join("wd:" + q for q in ids[i:i + batch])
        rows = _sparql_raw(f'SELECT ?x ?l WHERE {{ VALUES ?x {{ {vals} }} ?x rdfs:label ?l FILTER(lang(?l)="en") }}')
        for b in rows or []:
            out[_v(b["x"])] = b["l"]["value"]
    return out


def get_episodes():
    """Episode-level items: typed radio series episode, or part of (P179) a radio series."""
    rows = _sparql_raw(f"""SELECT ?e ?l ?s ?date ?prec ?ord WHERE {{
      {{ ?e wdt:P31 wd:{EPISODE} }} UNION {{ ?e wdt:P179 ?s0 . ?s0 wdt:P31/wdt:P279* wd:{RADIO_PROGRAM} }}
      OPTIONAL {{ ?e wdt:P179 ?s }}
      OPTIONAL {{ ?e p:P577/psv:P577 [ wikibase:timeValue ?date ; wikibase:timePrecision ?prec ] }}
      OPTIONAL {{ ?e wdt:P1545 ?ord }}
      OPTIONAL {{ ?e rdfs:label ?l FILTER(lang(?l)="en") }} }}""")
    if rows is None:
        return None
    out = {}
    for b in rows:
        q = _v(b["e"])
        e = out.setdefault(q, {"qid": q, "label": None, "props": {"series": [], "published": [], "ordinal": []},
                               "external_ids": {}})
        if "l" in b:
            e["label"] = b["l"]["value"]
        if "s" in b and _v(b["s"]) not in e["props"]["series"]:
            e["props"]["series"].append(_v(b["s"]))
        if "date" in b and int(b.get("prec", {}).get("value", 0)) >= 11:
            d = b["date"]["value"][:10]
            if d not in e["props"]["published"]:
                e["props"]["published"].append(d)
        if "ord" in b and b["ord"]["value"] not in e["props"]["ordinal"]:
            e["props"]["ordinal"].append(b["ord"]["value"])
    return out


def radio_classes():
    rows = wm.sparql(f"SELECT DISTINCT ?c WHERE {{ ?c wdt:P279* wd:{RADIO_PROGRAM} }}")
    if rows is None:
        return None
    return sorted({wm.qid(r["c"]) for r in rows})


def items_of_class(c):
    rows = wm.sparql(
        f'SELECT DISTINCT ?x WHERE {{ ?x wdt:P31 wd:{c} . ?x rdfs:label ?l FILTER(lang(?l)="en") }}')
    return None if rows is None else [wm.qid(r["x"]) for r in rows]


def enwiki_crawl():
    """Every article under ENWIKI_ROOTS (to DEPTH), with its Wikidata id. Read
    through the query service's MWAPI bridge, since en.wikipedia.org's own API
    rate-limits this egress IP (429, retry-after 22-35 s, 2026-10-19)."""
    pages = {}
    seen = set()
    frontier = [(c, 0) for c in ENWIKI_ROOTS]
    while frontier:
        cat, depth = frontier.pop(0)
        if cat in seen:
            continue
        seen.add(cat)
        title = cat.replace('"', '\\"')
        rows = _sparql_raw(f"""SELECT ?title ?ns ?item WHERE {{ SERVICE wikibase:mwapi {{
            bd:serviceParam wikibase:endpoint "en.wikipedia.org" ; wikibase:api "Generator" ;
              mwapi:generator "categorymembers" ; mwapi:gcmtitle "{title}" ; mwapi:gcmlimit "max" ;
              mwapi:gcmnamespace "0|14" .
            ?title wikibase:apiOutput mwapi:title . ?ns wikibase:apiOutput "@ns" .
            OPTIONAL {{ ?item wikibase:apiOutputItem mwapi:item . }} }} }}""")
        if rows is None:
            print(f"  category {cat}: FAILED", file=sys.stderr)
            continue
        for b in rows:
            t = b["title"]["value"]
            if b["ns"]["value"] == "14":
                if depth < DEPTH:
                    frontier.append((t, depth + 1))
            else:
                e = pages.setdefault(t, {"qid": _v(b["item"]) if "item" in b else None, "cats": []})
                e["cats"].append(cat)
    # MWAPI drops apiOutputItem under OPTIONAL (measured: 2,616 articles, 0 ids),
    # so the ids come from Wikidata's own sitelinks, by title.
    titles = sorted(pages)
    for i in range(0, len(titles), 200):
        vals = " ".join(json.dumps(t) + "@en" for t in titles[i:i + 200])
        rows = _sparql_raw(f"""SELECT ?item ?name WHERE {{ VALUES ?name {{ {vals} }}
            ?a schema:name ?name ; schema:isPartOf <https://en.wikipedia.org/> ; schema:about ?item }}""")
        for b in rows or []:
            pages[b["name"]["value"]]["qid"] = _v(b["item"])
    print(f"enwiki: {len(seen)} categories, {len(pages)} articles, "
          f"{sum(1 for v in pages.values() if v['qid'])} with a Wikidata id", flush=True)
    return pages


# ---------------------------------------------------------------- H1: wider identity (R3b section 5.1)

SMALL = {"a", "an", "and", "as", "at", "but", "by", "for", "from", "in", "into", "of", "on", "or", "the", "to",
         "with"}
QUALIFIERS = ("", " (radio program)", " (radio series)", " (radio drama)", " (radio show)", " (radio)",
              " (radio serial)", " (radio play)")
HUMAN, DISAMBIGUATION = "Q5", "Q4167410"


def smart_title(name):
    """'The Adventures Of Paul Temple' as a label is written: 'The Adventures of Paul Temple'."""
    words = (name or "").split()
    return " ".join(w if i == 0 or w.lower() not in SMALL else w.lower() for i, w in enumerate(words))


def label_variants(name):
    """The exact English labels a series may carry on Wikidata: its name as we hold it and as a label
    is cased, with and without a leading The (and OTRR's trailing ', The' moved to the front), with &
    and 'and' each way. Nothing that drops a content word."""
    n = re.sub(r"\s+", " ", name or "").strip()
    m = re.match(r"^(.*),\s*(The|A|An)$", n, re.I)
    bases = {n} | ({f"{m.group(2).title()} {m.group(1)}"} if m else set())
    out = set()
    for b in list(bases):
        for v in (b, smart_title(b)):
            for w in (v, re.sub(r"\s*&\s*", " and ", v), re.sub(r"\s+and\s+", " & ", v, flags=re.I)):
                out.add(w)
                out.add(w[4:] if w.lower().startswith("the ") else "The " + w)
    return sorted(v for v in out if 3 <= len(v) <= 150 and not v.isdigit())


def title_variants(name):
    """English Wikipedia article titles a series may have: its cased name, alone and with the
    radio qualifiers enwiki disambiguates with ('Suspense (radio drama)')."""
    out = set()
    for b in {smart_title(name), smart_title(re.sub(r"^(.*),\s*(The|A|An)$", r"\2 \1", name or "", flags=re.I))}:
        b = re.sub(r"\s+", " ", b).strip()
        if len(b) >= 3:
            out |= {b[0].upper() + b[1:] + q for q in QUALIFIERS}
    return sorted(out)


def _lit(s):
    return json.dumps(s, ensure_ascii=False) + "@en"


def label_hits(strings, batch=300):
    """{qid: [strings]}: items whose English label or alias is one of `strings`, in VALUES batches."""
    out = {}
    strings = sorted(set(strings))
    for i in range(0, len(strings), batch):
        vals = " ".join(_lit(s) for s in strings[i:i + batch])
        rows = _sparql_raw(f"""SELECT ?x ?name WHERE {{ VALUES ?name {{ {vals} }}
          {{ ?x rdfs:label ?name }} UNION {{ ?x skos:altLabel ?name }} }}""")
        if rows is None:
            print(f"  labels {i}: FAILED", file=sys.stderr)
            continue
        for b in rows:
            q = _v(b["x"])
            if q[:1] == "Q":
                out.setdefault(q, set()).add(b["name"]["value"])
        print(f"  labels {i + batch}/{len(strings)}: {len(out)} items", flush=True)
    return {q: sorted(v) for q, v in out.items()}


def sitelink_hits(titles, batch=300):
    """{enwiki title: qid}: the Wikidata item each existing English article is about (sitelinks)."""
    out = {}
    titles = sorted(set(titles))
    for i in range(0, len(titles), batch):
        vals = " ".join(_lit(t) for t in titles[i:i + batch])
        rows = _sparql_raw(f"""SELECT ?item ?name WHERE {{ VALUES ?name {{ {vals} }}
            ?a schema:name ?name ; schema:isPartOf <https://en.wikipedia.org/> ; schema:about ?item }}""")
        if rows is None:
            print(f"  titles {i}: FAILED", file=sys.stderr)
            continue
        for b in rows:
            out[b["name"]["value"]] = _v(b["item"])
        print(f"  titles {i + batch}/{len(titles)}: {len(out)} articles", flush=True)
    return out


def light_facts(qids, batch=300):
    """{qid: {"classes": [P31], "description", "enwiki"}} for the items a name reached."""
    out = {}
    qids = sorted(set(qids))
    for i in range(0, len(qids), batch):
        vals = " ".join("wd:" + q for q in qids[i:i + batch])
        rows = _sparql_raw(f"""SELECT ?x ?c ?d ?en WHERE {{ VALUES ?x {{ {vals} }}
          OPTIONAL {{ ?x wdt:P31 ?c }}
          OPTIONAL {{ ?x schema:description ?d FILTER(lang(?d)="en") }}
          OPTIONAL {{ ?en schema:about ?x ; schema:isPartOf <https://en.wikipedia.org/> }} }}""")
        if rows is None:
            print(f"  facts {i}: FAILED", file=sys.stderr)
            continue
        for b in rows:
            q = _v(b["x"])
            e = out.setdefault(q, {"classes": [], "description": None, "enwiki": None})
            if "c" in b and _v(b["c"]) not in e["classes"]:
                e["classes"].append(_v(b["c"]))
            if "d" in b:
                e["description"] = b["d"]["value"]
            if "en" in b:
                e["enwiki"] = urllib.parse.unquote(b["en"]["value"].rsplit("/wiki/", 1)[1]).replace("_", " ")
    return out


def shortdescs(titles, batch=50):
    """{enwiki title: its own short description, or None}: the article's wikibase-shortdesc page
    property, read through the Action API 50 titles a call (redirects followed back to the asked title)."""
    out = {}
    titles = sorted(set(titles))
    for i in range(0, len(titles), batch):
        chunk = titles[i:i + batch]
        d = wm.call(wm.EN_API, {"action": "query", "prop": "pageprops", "ppprop": "wikibase-shortdesc",
                                "titles": "|".join(chunk), "redirects": 1, "format": "json", "formatversion": 2},
                    cache_dir="wikidata/enwiki_shortdesc")
        if d is None:
            print(f"  shortdesc {i}: FAILED", file=sys.stderr)
            continue
        back = {t: t for t in chunk}
        for k in ("normalized", "redirects"):
            for r in d.get("query", {}).get(k, []):
                back[r["to"]] = back.get(r["from"], r["from"])
        for p in d.get("query", {}).get("pages", []):
            asked = back.get(p.get("title"), p.get("title"))
            out[asked] = (p.get("pageprops") or {}).get("wikibase-shortdesc")
        if i % 1000 == 0:
            print(f"  shortdesc {i + len(chunk)}/{len(titles)}", flush=True)
    return out


def names_phase(db_path):
    """H1: every served series name looked up on Wikidata in VALUES batches (labels and aliases, and
    English article titles with the radio qualifiers), the items found classed, their articles'
    short descriptions read, and the radio ones (a radio-program class, or a short description that
    names radio and years) fetched whole. Writes .cache/wikidata/names.json.gz; enrich_external.py
    matches them under the same rules as the radio-class harvest."""
    import sqlite3
    import art_policy as AP
    import enrich_external as EX
    db = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    idx = EX.SeriesIndex(db)
    keys = sorted(idx.known & idx.in_db)
    names = sorted({idx.name[k] for k in keys if idx.name.get(k)})
    print(f"H1: {len(names)} series names", flush=True)
    by_label = label_hits({v for n in names for v in label_variants(n)})
    by_title = sitelink_hits({t for n in names for t in title_variants(n)})
    hits = {q: set(v) for q, v in by_label.items()}
    for t, q in by_title.items():
        hits.setdefault(q, set()).add(t)
    have = EX.load(os.path.join(DIR, "items.json.gz"), {}) or {}
    classes = set(radio_classes() or [])
    if not classes:
        print("could not read the class tree", file=sys.stderr)
        sys.exit(2)
    facts = light_facts(hits)
    # Our names reach these: read the short description of each one's article that is not a person
    # or a disambiguation page, and of every radio-class item that reaches a name with no dates (V10).
    ask = set()
    for q, f in facts.items():
        if f["enwiki"] and not ({HUMAN, DISAMBIGUATION} & set(f["classes"])):
            ask.add(f["enwiki"])
    for q, it in have.items():
        dated = any(it["props"].get(k) for k in ("start", "end", "inception", "dissolved", "published"))
        nm = [it.get("label"), it.get("enwiki")] + list(it.get("aliases") or [])
        if it.get("enwiki") and not dated and any(idx.routes(n) for n in nm if n):
            ask.add(it["enwiki"])
    sd = shortdescs(ask)
    keep = set()
    for q, f in facts.items():
        rc = classes & set(f["classes"])
        if q in have:
            continue
        if HUMAN in f["classes"] or (rc and rc <= {EPISODE}):
            continue   # a person, or one broadcast's item
        if rc or AP.radio_shortdesc(sd.get(f["enwiki"])):
            keep.add(q)
    print(f"H1: {len(hits)} items reached by name, {len(keep)} new radio items, {len(sd)} short descriptions",
          flush=True)
    items = get_items(keep)
    for q, it in items.items():
        it["radio_class"] = sorted(classes & set(it["props"].get("instance_of", [])))
        it["found_by"] = sorted(hits.get(q, ()))
    refs = {v for it in items.values() for vs in it["props"].values() for v in vs
            if isinstance(v, str) and v[:1] == "Q" and v[1:].isdigit()}
    old = EX.load(os.path.join(DIR, "labels.json.gz"), {}) or {}
    labels = get_labels(refs - set(old))
    write_json(os.path.join(DIR, "names.json.gz"), {
        "names": len(names), "hits": {q: sorted(v) for q, v in sorted(hits.items())},
        "items": items, "shortdesc": sd, "labels": labels, "failed": wm.FAILED}, gz=True)
    print(f"H1: wrote {len(items)} items, {len(labels)} labels, failed {len(wm.FAILED)}")
    if wm.FAILED:
        sys.exit(1)


def main():
    if "--names" in sys.argv:
        from ia_lib import OUT
        db = sys.argv[sys.argv.index("--db") + 1] if "--db" in sys.argv else os.path.join(OUT, "radio-catalog.sqlite")
        return names_phase(db)
    os.makedirs(DIR, exist_ok=True)
    classes = radio_classes()
    if not classes:
        print("could not read the class tree", file=sys.stderr)
        sys.exit(2)
    print(f"{len(classes)} radio-program classes", flush=True)
    cand, eps = set(), set()
    class_of = {}
    for c in classes:
        xs = items_of_class(c)
        if xs is None:
            print(f"class {c}: FAILED", file=sys.stderr)
            continue
        for x in xs:
            class_of.setdefault(x, []).append(c)
            (eps if c == EPISODE else cand).add(x)
    print(f"{len(cand)} series candidates, {len(eps)} episode items", flush=True)
    enwiki = enwiki_crawl()
    write_json(os.path.join(DIR, "enwiki_radio.json"), enwiki)
    cand |= {v["qid"] for v in enwiki.values() if v["qid"]}
    cand -= eps
    items = get_items(cand)
    for q, it in items.items():
        it["radio_class"] = class_of.get(q, [])
    episodes = get_episodes() or {}
    write_json(os.path.join(DIR, "items.json.gz"), items, gz=True)
    write_json(os.path.join(DIR, "episodes.json.gz"), episodes, gz=True)
    # labels for entity-valued properties
    refs = set()
    for it in list(items.values()) + list(episodes.values()):
        for k, vs in it["props"].items():
            refs |= {v for v in vs if isinstance(v, str) and v[:1] == "Q" and v[1:].isdigit()}
    labels = get_labels(refs)
    write_json(os.path.join(DIR, "labels.json.gz"), labels, gz=True)
    write_json(os.path.join(DIR, "failed.json"), wm.FAILED)
    print(f"items {len(items)}, episodes {len(episodes)}, labels {len(labels)}, failed {len(wm.FAILED)}")
    if not items:
        sys.exit(1)


if __name__ == "__main__":
    main()
