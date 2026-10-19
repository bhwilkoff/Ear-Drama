"""Jerry Haendiges Vintage Radio Logs (otrsite.com) as an independent date witness.

    python3 tools/harvest_ext_haendiges.py            # fetch (resumable, 3 s apart) then parse
    python3 tools/harvest_ext_haendiges.py --parse    # re-parse the cache only

The logs are (c) Jerry Haendiges Productions; only FACTS are kept (series,
date, episode number, title, length) with the log's URL as provenance. The
comments column (cast, notes) is not stored. robots.txt (2026-10-19) disallows
only /cgi-bin/ and /wusage; no crawl-delay is given, 3 s is used.

Writes .cache/haendiges/witnesses.json.gz: one row per dated log line.
A page that could not be fetched is listed in .cache/haendiges/failed.json,
never treated as an empty log. Exits non-zero when nothing was read.
"""
import gzip
import html
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ia_lib import CACHE, UA, write_json  # noqa: E402

BASE = "https://otrsite.com"
INDEX = BASE + "/radiolog/index.html"
DIR = os.path.join(CACHE, "haendiges")
LOGS = os.path.join(DIR, "logs")
PAUSE = 3.0


def fetch(url, tries=4):
    delay = 5.0
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            print(f"HTTP {e.code} {url}", file=sys.stderr)
        except Exception as e:  # noqa: BLE001 - recorded, retried
            print(f"retry {attempt}: {e} {url}", file=sys.stderr)
        time.sleep(delay)
        delay *= 2
    return None


def index_links(raw):
    text = raw.decode("latin-1")
    out = {}
    for m in re.finditer(r'<A\s+HREF="\.\./logs/([^"#]+)"[^>]*>(.*?)</A>', text, re.I | re.S):
        name = m.group(1)
        label = html.unescape(re.sub(r"<[^>]+>", "", m.group(2))).strip().strip('"').strip()
        out.setdefault(name, label)
    return out


def crawl():
    os.makedirs(LOGS, exist_ok=True)
    ipath = os.path.join(DIR, "index.html.gz")
    if not os.path.exists(ipath):
        raw = fetch(INDEX)
        if raw is None:
            print("could not read the index", file=sys.stderr)
            sys.exit(2)
        with gzip.open(ipath, "wb") as f:
            f.write(raw)
    links = index_links(gzip.open(ipath).read())
    write_json(os.path.join(DIR, "index.json"), links)
    fpath = os.path.join(DIR, "failed.json")
    failed = {}
    todo = [n for n in sorted(links) if not os.path.exists(os.path.join(LOGS, n + ".gz"))]
    print(f"{len(links)} logs, {len(todo)} to fetch", flush=True)
    for i, name in enumerate(todo):
        raw = fetch(f"{BASE}/logs/{name}")
        if raw is None:
            failed[name] = "fetch failed or 404"
        else:
            tmp = os.path.join(LOGS, name + ".gz.tmp")
            with gzip.open(tmp, "wb") as f:
                f.write(raw)
            os.replace(tmp, os.path.join(LOGS, name + ".gz"))
        if i % 50 == 0:
            write_json(fpath, failed)
            print(f"{i}/{len(todo)} failed={len(failed)}", flush=True)
        time.sleep(PAUSE)
    write_json(fpath, failed)
    return links


SERIES = re.compile(r'Series:\s*"?([^"<]+?)"?\s*$', re.I)


def year4(y):
    y = int(y)
    if y >= 100:
        return y
    return 1900 + y if y >= 20 else 2000 + y


def parse_date(s):
    m = re.fullmatch(r"(\d{1,2})-(\d{1,2})-(\d{2,4})", s)
    if not m:
        return None
    mo, d, y = int(m.group(1)), int(m.group(2)), year4(m.group(3))
    if not (1 <= mo <= 12 and 1 <= d <= 31 and 1920 <= y <= 2030):
        return None
    import datetime
    try:
        return datetime.date(y, mo, d).isoformat()
    except ValueError:
        return None


def to_text(raw):
    t = raw.decode("latin-1")
    t = re.sub(r"<[^>]+>", "", t)
    return html.unescape(t)


DATE_AT = re.compile(r"\s(\d{1,2}-\d{1,2}-\d{2,4})(?=[\s*]|$)")


def parse_line(ln):
    """(title, ep, date, length) for a log line, or None. A line is a log line
    when it starts in column 0 (the catalog field: a number, '*na*', '8862 C5')
    and carries a mm-dd-yy date past the title column. '?? Title Unknown ??'
    and blank titles still witness the date; their title is None."""
    if not ln or ln[0].isspace() or ln.startswith(("=", "_", "Catalog")):
        return None
    dm = DATE_AT.search(ln)
    if not dm or dm.start() < 20:
        return None
    date = parse_date(dm.group(1))
    if not date:
        return None
    pre = ln[:dm.start()]
    title, ep, open_quote = None, None, False
    q = pre.find('"')
    if q >= 0:
        rest = pre[q + 1:]
        e = rest.find('"')
        if e >= 0:
            title, tail = rest[:e], rest[e + 1:]
        else:
            open_quote = True
            mm = re.match(r"(.*?)(\s{2,}|$)(.*)", rest)
            title, tail = mm.group(1), mm.group(3)
        toks = tail.split()
        ep = toks[-1] if toks and len(toks[-1]) <= 6 else None
    else:
        toks = pre[35:].split()
        ep = toks[-1] if toks and len(toks[-1]) <= 6 else None
    lm = re.match(r"\s*(:?[\d:]+)", ln[dm.end():])
    title = re.sub(r"\s+", " ", title).strip() if title else None
    return title, ep, date, (lm.group(1) if lm else None), open_quote


def parse_log(raw, label, name):
    """Return dated rows. A title wrapped onto the next line is joined."""
    lines = to_text(raw).splitlines()
    series = None
    rows = []
    pending = None
    for ln in lines:
        s = SERIES.search(ln)
        if s:
            series = s.group(1).strip().strip('"').strip()
            pending = None
            continue
        if pending is not None:
            m2 = re.match(r'^\s{5,}([^"]*)"', ln)
            if m2:
                pending["title"] = re.sub(r"\s+", " ", pending["title"] + " " + m2.group(1)).strip()
            pending = None
        p = parse_line(ln)
        if not p:
            continue
        title, ep, date, length, open_quote = p
        row = {"series": series or label, "date": date, "ep": ep, "title": title,
               "length": length, "url": f"{BASE}/logs/{name}"}
        rows.append(row)
        if open_quote and title:
            pending = row
    return rows


def parse_all(links):
    rows = []
    pages = 0
    for name in sorted(links):
        p = os.path.join(LOGS, name + ".gz")
        if not os.path.exists(p):
            continue
        pages += 1
        rows.extend(parse_log(gzip.open(p).read(), links[name], name))
    write_json(os.path.join(DIR, "witnesses.json.gz"), rows, gz=True)
    print(f"parsed {pages} pages -> {len(rows)} dated rows, "
          f"{len({(r['series']) for r in rows})} series headers")
    return pages, rows


def main():
    if "--parse" in sys.argv:
        links = json.load(open(os.path.join(DIR, "index.json")))
    else:
        links = crawl()
    pages, rows = parse_all(links)
    if not pages or not rows:
        sys.exit(1)


if __name__ == "__main__":
    main()
