"""Polite client for Wikimedia APIs (Wikidata SPARQL + Action API, enwiki, Commons).

Wikimedia answers bursts with 429 + Retry-After (measured 2026-10-19 on enwiki:
retry-after 22). Every call waits PAUSE seconds, honours Retry-After, and caches
the body on disk keyed by the request so a rerun resumes. A call that fails after
its retries returns None; the caller records it as a failure, never as empty.
"""
import gzip
import hashlib
import http.client
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ia_lib import CACHE  # noqa: E402

UA = ("ArchiveWatch-RadioCatalog/0.1 (https://archivewatch.org; "
      "radio catalog enrichment, read-only, low rate)")
SPARQL = "https://query.wikidata.org/sparql"
WD_API = "https://www.wikidata.org/w/api.php"
EN_API = "https://en.wikipedia.org/w/api.php"
COMMONS_API = "https://commons.wikimedia.org/w/api.php"
PAUSE = {"query.wikidata.org": 2.0, "www.wikidata.org": 1.0,
         "en.wikipedia.org": 1.5, "commons.wikimedia.org": 3.0}
_last = {}
FAILED = []


def _key(url, data):
    return hashlib.sha1((url + "\n" + (data or "")).encode()).hexdigest()


def call(url, params, *, cache_dir, post=False, tries=7, use_cache=True):
    # A body cut off mid-stream (seen on 450-550 KB SPARQL answers through this
    # proxy, 2026-10-19) is retried at most 3 times: the same request is cut the
    # same way, and a series of 120 s backoffs stalls the harvest.
    """GET/POST a JSON API; cached under .cache/<cache_dir>/<sha1>.json.gz."""
    qs = urllib.parse.urlencode(params, doseq=True)
    d = os.path.join(CACHE, cache_dir)
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, _key(url, qs) + ".json.gz")
    if use_cache and os.path.exists(path):
        with gzip.open(path, "rt", encoding="utf-8") as f:
            return json.load(f)
    host = urllib.parse.urlparse(url).netloc
    delay = 5.0
    cut = 0
    for attempt in range(tries):
        wait = PAUSE.get(host, 2.0) - (time.time() - _last.get(host, 0))
        if wait > 0:
            time.sleep(wait)
        _last[host] = time.time()
        if post:
            req = urllib.request.Request(url, data=qs.encode(), headers={
                "User-Agent": UA, "Content-Type": "application/x-www-form-urlencoded",
                "Accept": "application/sparql-results+json, application/json"})
        else:
            req = urllib.request.Request(url + "?" + qs, headers={
                "User-Agent": UA, "Accept": "application/sparql-results+json, application/json"})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                body = r.read()
            obj = json.loads(body)
            if isinstance(obj, dict) and obj.get("error", {}).get("code") == "maxlag":
                time.sleep(delay)
                delay *= 2
                continue
            tmp = path + ".tmp"
            with gzip.open(tmp, "wt", encoding="utf-8") as f:
                json.dump(obj, f)
            os.replace(tmp, path)
            return obj
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504):
                ra = e.headers.get("Retry-After")
                time.sleep(max(delay, float(ra) if ra and ra.isdigit() else 0))
                delay = min(delay * 2, 120)
                continue
            print(f"HTTP {e.code} {url} {qs[:200]}", file=sys.stderr)
            break
        except Exception as e:  # noqa: BLE001 - retried, then recorded
            print(f"retry {attempt}: {e} {url}", file=sys.stderr)
            if isinstance(e, (json.JSONDecodeError, http.client.IncompleteRead)):
                cut += 1
                if cut >= 3:
                    break
            time.sleep(delay)
            delay = min(delay * 2, 120)
    FAILED.append({"url": url, "params": qs[:500]})
    return None


def sparql(query, cache_dir="wikidata/sparql"):
    d = call(SPARQL, {"query": query, "format": "json"}, cache_dir=cache_dir, post=True)
    if d is None:
        return None
    out = []
    for b in d["results"]["bindings"]:
        out.append({k: v["value"] for k, v in b.items()})
    return out


def qid(uri):
    return uri.rsplit("/", 1)[-1] if uri else None


def raw_page(host, title, cache_dir):
    """Wikitext of one page via index.php?action=raw, cached. The Action and REST
    APIs answered this egress IP 429 throughout 2026-10-19 (shared with other
    sessions); action=raw (a documented, cache-served read) answered 200. One
    request per page, 1.5 s apart. Returns (text, status): text None + "missing"
    for a page that does not exist, None + "failed" for a read that failed."""
    d = os.path.join(CACHE, cache_dir)
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, hashlib.sha1((host + "|" + title).encode()).hexdigest() + ".json.gz")
    if os.path.exists(path):
        with gzip.open(path, "rt", encoding="utf-8") as f:
            o = json.load(f)
        return o["text"], o["status"]
    url = f"https://{host}/w/index.php?" + urllib.parse.urlencode({"title": title, "action": "raw"})
    delay = 5.0
    for attempt in range(6):
        wait = 1.5 - (time.time() - _last.get(host + "/raw", 0))
        if wait > 0:
            time.sleep(wait)
        _last[host + "/raw"] = time.time()
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as r:
                text, status = r.read().decode("utf-8", "replace"), "ok"
            break
        except urllib.error.HTTPError as e:
            if e.code == 404:
                text, status = None, "missing"
                break
            if e.code in (429, 500, 502, 503, 504):
                ra = e.headers.get("Retry-After")
                time.sleep(max(delay, float(ra) if ra and ra.isdigit() else 0))
                delay = min(delay * 2, 120)
                continue
            text, status = None, "failed"
            break
        except Exception as e:  # noqa: BLE001
            print(f"retry {attempt}: {e} {url}", file=sys.stderr)
            time.sleep(delay)
            delay = min(delay * 2, 120)
    else:
        text, status = None, "failed"
    if status == "failed":
        FAILED.append({"url": url})
        return None, status
    tmp = path + ".tmp"
    with gzip.open(tmp, "wt", encoding="utf-8") as f:
        json.dump({"title": title, "text": text, "status": status, "fetched": time.strftime("%Y-%m-%d")}, f)
    os.replace(tmp, path)
    return text, status


def entity_data(host, eid, cache_dir):
    """Special:EntityData/<id>.json (Commons M-ids for Structured Data), cached."""
    d = os.path.join(CACHE, cache_dir)
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, eid + ".json.gz")
    if os.path.exists(path):
        with gzip.open(path, "rt", encoding="utf-8") as f:
            return json.load(f)
    delay = 5.0
    for attempt in range(6):
        wait = 1.5 - (time.time() - _last.get(host + "/ed", 0))
        if wait > 0:
            time.sleep(wait)
        _last[host + "/ed"] = time.time()
        try:
            req = urllib.request.Request(f"https://{host}/wiki/Special:EntityData/{eid}.json",
                                         headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as r:
                obj = json.loads(r.read())
            break
        except urllib.error.HTTPError as e:
            if e.code == 404:
                obj = {"missing": True}
                break
            time.sleep(delay)
            delay = min(delay * 2, 120)
        except Exception:  # noqa: BLE001
            time.sleep(delay)
            delay = min(delay * 2, 120)
    else:
        FAILED.append({"entity": eid})
        return None
    tmp = path + ".tmp"
    with gzip.open(tmp, "wt", encoding="utf-8") as f:
        json.dump(obj, f)
    os.replace(tmp, path)
    return obj


def mwapi(endpoint, params, outputs, cache_dir, limit=None):
    """A MediaWiki Generator call made BY the query service (SERVICE wikibase:mwapi),
    which reaches enwiki/Commons when their APIs refuse this IP. `outputs` maps a
    variable name to an apiOutput path ("@title", "imageinfo/ii/@url")."""
    ps = " ".join(f'mwapi:{k} "{v}" ;' for k, v in params.items())
    outs = " ".join(f'?{k} wikibase:apiOutput "{p}" .' for k, p in outputs.items())
    lim = f' wikibase:limit "{limit}" ;' if limit else ""
    q = f"""SELECT * WHERE {{ SERVICE wikibase:mwapi {{
        bd:serviceParam wikibase:endpoint "{endpoint}" ; wikibase:api "Generator" ;{lim} {ps[:-1]} .
        {outs} }} }}"""
    return sparql(q, cache_dir=cache_dir)
