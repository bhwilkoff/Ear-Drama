"""English Wikipedia episode tables as an independent date + title witness.

    python3 tools/harvest_ext_wikipedia.py      # after harvest_ext_wikidata.py

Pages read: every article in an enwiki radio-PROGRAM category that
harvest_ext_wikidata.py crawled (.cache/wikidata/enwiki_radio.json; franchise
film/TV categories excluded), every "List of" page in a radio list category,
and every "List of <article> episodes" page that exists for one of them. Wikitext is read
one page a request (action=raw), and two shapes are parsed:
{{Episode list}} templates and wikitables with a date column and a title column.

Only facts are kept (air date, episode title, episode number) with the page URL
and fetch date (in the raw cache) as provenance; synopsis and notes columns (CC BY-SA prose) are
not stored. Writes .cache/wikipedia/witnesses.json.gz and pages.json.
Exits non-zero when no page could be read.
"""
import datetime
import json
import os
import re
import sys
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ia_lib import CACHE, write_json  # noqa: E402
import harvest_ext_wm as wm  # noqa: E402

DIR = os.path.join(CACHE, "wikipedia")
MONTHS = {m: i for i, m in enumerate(
    ["january", "february", "march", "april", "may", "june", "july", "august",
     "september", "october", "november", "december"], 1)}
MONTHS.update({k[:3]: v for k, v in list(MONTHS.items())})
MONTHS["sept"] = 9


def _mk(y, m, d):
    try:
        y, m, d = int(y), int(m), int(d)
        if not 1920 <= y <= 2030:
            return None
        return datetime.date(y, m, d).isoformat()
    except (ValueError, TypeError):
        return None


def parse_date(s, year=None):
    """A full date from wikitext or plain text; None when the day is not stated.
    `year` is the single year a section heading or caption gives a table whose
    cells say only "April 22" (List of X Minus One episodes)."""
    if not s:
        return None
    m = re.search(r"\{\{\s*(?:start date|film date|dts|date|air date)[^|}]*\|\s*(\d{4})\s*\|\s*(\d{1,2})\s*\|\s*(\d{1,2})",
                  s, re.I)
    if m:
        return _mk(*m.groups())
    m = re.search(r"\b(\d{4})-(\d{2})-(\d{2})\b", s)
    if m:
        return _mk(*m.groups())
    m = re.search(r"\b([A-Za-z]{3,9})\.?\s+(\d{1,2}),?\s+(\d{4})\b", s)
    if m and m.group(1).lower() in MONTHS:
        return _mk(m.group(3), MONTHS[m.group(1).lower()], m.group(2))
    m = re.search(r"\b(\d{1,2})\s+([A-Za-z]{3,9})\.?,?\s+(\d{4})\b", s)
    if m and m.group(2).lower() in MONTHS:
        return _mk(m.group(3), MONTHS[m.group(2).lower()], m.group(1))
    m = re.search(r"(?<![\d/-])(\d{1,2})[-/](\d{1,2})[-/](\d{2})(?![\d/-])", s)
    if m:
        return _mk(1900 + int(m.group(3)), m.group(1), m.group(2))
    if year:
        t = plain(s)
        m = re.fullmatch(r"([A-Za-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?", t)
        if m and m.group(1).lower() in MONTHS:
            return _mk(year, MONTHS[m.group(1).lower()], m.group(2))
        m = re.fullmatch(r"(\d{1,2})\s+([A-Za-z]{3,9})\.?", t)
        if m and m.group(2).lower() in MONTHS:
            return _mk(year, MONTHS[m.group(2).lower()], m.group(1))
    return None


def context_year(text, pos):
    """The one year named by the nearest heading (or caption) above `pos`."""
    heads = list(re.finditer(r"^(=+)\s*(.*?)\s*\1\s*$", text[:pos], re.M))
    for h in reversed(heads[-1:]):
        ys = re.findall(r"\b(19[2-9]\d|20[0-2]\d)\b", h.group(2))
        if len(ys) == 1 and not re.search(r"\d{4}\s*[-–]\s*\d{2}", h.group(2)):
            return int(ys[0])
    return None


def plain(s):
    s = re.sub(r"<ref[^>]*/>", "", s)
    s = re.sub(r"<ref.*?</ref>", "", s, flags=re.S)
    s = re.sub(r"<!--.*?-->", "", s, flags=re.S)
    s = re.sub(r"\{\{\s*(?:sortname)\s*\|([^|}]*)\|([^|}]*)[^}]*\}\}", r"\1 \2", s, flags=re.I)
    for _ in range(3):
        s = re.sub(r"\{\{[^{}]*\}\}", "", s)
    s = re.sub(r"\[\[(?:[^|\]]*\|)?([^\]]*)\]\]", r"\1", s)
    s = re.sub(r"\[https?://\S+\s*([^\]]*)\]", r"\1", s)
    s = re.sub(r"<[^>]+>", "", s)
    s = s.replace("'''", "").replace("''", "")
    return re.sub(r"\s+", " ", s).strip().strip('"').strip()


def _templates(text, name):
    """Yield the bodies of {{name ...}} with nested braces balanced."""
    for m in re.finditer(r"\{\{\s*" + name + r"\b", text, re.I):
        i, depth = m.start(), 0
        j = i
        while j < len(text) - 1:
            two = text[j:j + 2]
            if two == "{{":
                depth += 1
                j += 2
                continue
            if two == "}}":
                depth -= 1
                j += 2
                if depth == 0:
                    break
                continue
            j += 1
        yield text[m.end():j - 2]


def _params(body):
    out, depth, cur, parts = {}, 0, "", []
    i = 0
    while i < len(body):
        two = body[i:i + 2]
        if two in ("{{", "[["):
            depth += 1
            cur += two
            i += 2
            continue
        if two in ("}}", "]]"):
            depth -= 1
            cur += two
            i += 2
            continue
        if body[i] == "|" and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += body[i]
        i += 1
    parts.append(cur)
    for p in parts:
        if "=" in p:
            k, v = p.split("=", 1)
            out[k.strip().lower()] = v.strip()
    return out


def episode_list_rows(text):
    rows = []
    for body in _templates(text, "Episode list"):
        p = _params(body)
        date = parse_date(p.get("originalairdate") or p.get("airdate") or "")
        title = plain(p.get("title", ""))
        if date and title:
            rows.append({"date": date, "title": title,
                         "num": plain(p.get("episodenumber", "")) or None, "shape": "episode_list"})
    return rows


DATE_H = re.compile(r"date|air|broadcast", re.I)
TITLE_H = re.compile(r"title|episode|story|play|program", re.I)
NUM_H = re.compile(r"^(no\.?|#|number|ep\.?|episode\s*(no\.?|#))$", re.I)


def _cells(line, sep):
    line = line[1:]
    parts = re.split(r"\s*" + re.escape(sep * 2) + r"\s*", line)
    out = []
    for c in parts:
        # strip a leading attribute block: 'style="..." | text'
        if "|" in c and not c.lstrip().startswith(("[[", "{{")):
            a, b = c.split("|", 1)
            if "=" in a and "[[" not in a and "{{" not in a:
                c = b
        out.append(c.strip())
    return out


def table_rows(text):
    rows = []
    for t in re.finditer(r"^\{\|(.*?)^\|\}", text, re.S | re.M):
        body = t.group(1)
        year = context_year(text, t.start())
        cap = re.search(r"^\|\+(.*)$", body, re.M)
        if cap:
            ys = re.findall(r"\b(19[2-9]\d|20[0-2]\d)\b", cap.group(1))
            if len(ys) == 1:
                year = int(ys[0])
        header, cur, data = None, [], []
        for raw in re.split(r"^\|-.*$", body, flags=re.M):
            cells = []
            for ln in raw.split("\n"):
                if ln.startswith("!"):
                    cells.extend(("h", c) for c in _cells(ln, "!"))
                elif ln.startswith("|") and not ln.startswith("|+"):
                    cells.extend(("d", c) for c in _cells(ln, "|"))
                elif cells and ln.strip() and not ln.startswith(("{|", "|}")):
                    k, v = cells[-1]
                    cells[-1] = (k, v + " " + ln.strip())
            if not cells:
                continue
            if header is None and all(k == "h" for k, _ in cells):
                header = [plain(c) for _, c in cells]
                continue
            data.append([c for _, c in cells])
        if not header:
            continue
        di = next((i for i, h in enumerate(header) if DATE_H.search(h)), None)
        ti = next((i for i, h in enumerate(header) if TITLE_H.search(h) and i != di
                   and not NUM_H.match(h)), None)
        ni = next((i for i, h in enumerate(header) if NUM_H.match(h)), None)
        if di is None or ti is None:
            continue
        for r in data:
            # rows with fewer cells than the header (rowspans) are aligned from the right
            off = len(header) - len(r)
            if off < 0 or off > 1:
                continue
            g = lambda i: r[i - off] if i is not None and 0 <= i - off < len(r) else ""  # noqa: E731
            date = parse_date(g(di), year)
            title = re.sub(r"^\d+[.)]\s*", "", plain(g(ti))).strip().strip('"').strip()
            if date and title and len(title) < 200:
                rows.append({"date": date, "title": title, "num": plain(g(ni)) or None,
                             "shape": "wikitable"})
    return rows


def page_series(title):
    m = re.match(r"List of (.+?) (?:radio )?(?:episodes|programs|broadcasts|shows)\b", title, re.I)
    s = m.group(1) if m else title
    return re.sub(r"\s*\([^)]*\)\s*$", "", s).strip()


def fetch_wikitext(titles):
    """{title: text} by action=raw, one page per request (the Action API answered
    this IP 429 throughout 2026-10-19). Missing pages are skipped; failed reads
    are in wm.FAILED and the caller's count."""
    pages = {}
    titles = sorted(set(titles))
    for i, t in enumerate(titles):
        text, status = wm.raw_page("en.wikipedia.org", t, "wikipedia/raw")
        if status == "ok" and text and not re.match(r"\s*#REDIRECT", text, re.I):
            pages[t] = {"text": text}
        elif status == "ok" and text:
            m = re.search(r"\[\[([^\]|#]+)", text)
            if m:
                t2 = m.group(1).strip()
                text2, st2 = wm.raw_page("en.wikipedia.org", t2, "wikipedia/raw")
                if st2 == "ok" and text2:
                    pages[t2] = {"text": text2}
        if i % 200 == 0:
            print(f"  wikitext {i}/{len(titles)}", flush=True)
    return pages


def main():
    src = os.path.join(CACHE, "wikidata", "enwiki_radio.json")
    if not os.path.exists(src):
        print("run harvest_ext_wikidata.py first", file=sys.stderr)
        sys.exit(2)
    arts = json.load(open(src))
    import sqlite3
    from enrich_external import SeriesIndex, radio_program_category, strip_qualifier
    from ia_lib import OUT
    idx = SeriesIndex(sqlite3.connect(os.path.join(OUT, "radio-catalog.sqlite")))
    qids = {t: v["qid"] for t, v in arts.items()}
    lists = [t for t, v in arts.items() if t.startswith("List of") and any("radio" in c.lower() for c in v["cats"])]
    series_arts = [t for t, v in arts.items() if not t.startswith("List of")
                   and any(radio_program_category(c) for c in v["cats"]) and idx.lookup(t)]
    guesses = set()
    for t in series_arts:
        guesses.add(f"List of {strip_qualifier(t)} episodes")
        guesses.add(f"List of {t} episodes")
    ask = set(lists) | set(series_arts) | guesses
    print(f"{len(series_arts)} series articles that name a series we hold, {len(lists)} list pages, "
          f"{len(guesses)} list-page guesses", flush=True)
    pages = fetch_wikitext(ask)
    print(f"{len(pages)} pages read of {len(ask)} asked", flush=True)
    rows, used = [], {}
    for title, pg in pages.items():
        found = episode_list_rows(pg["text"]) + table_rows(pg["text"])
        seen = set()
        uniq = []
        for r in found:
            k = (r["date"], r["title"].lower())
            if k not in seen:
                seen.add(k)
                uniq.append(r)
        if len(uniq) < 3:   # a lone dated row in an article is not an episode list
            continue
        url = "https://en.wikipedia.org/wiki/" + urllib.parse.quote(title.replace(" ", "_"))
        series = page_series(title)
        qid = qids.get(title) or qids.get(series)
        used[title] = {"series": series, "qid": qid, "rows": len(uniq)}
        for r in uniq:
            rows.append({"page": title, "series": series, "page_qid": qid, "url": url, **r})
    write_json(os.path.join(DIR, "witnesses.json.gz"), rows, gz=True)
    write_json(os.path.join(DIR, "pages.json"), used)
    write_json(os.path.join(DIR, "failed.json"), wm.FAILED)
    print(f"{len(used)} pages with episode tables, {len(rows)} dated rows, failed reads {len(wm.FAILED)}")
    if not pages:
        sys.exit(1)


if __name__ == "__main__":
    main()
