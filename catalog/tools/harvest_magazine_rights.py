#!/usr/bin/env python3
"""Period radio magazines as art: which issues are scanned where, and the
evidence for each title's copyright by year. reports/F-photo-archives.md §3.

Four sources, each cached under .cache/magazines/ (resumable; a failed fetch
is recorded, never read as "nothing there"):

  obp   The Online Books Page "First copyright renewals for periodicals"
        (onlinebooks.library.upenn.edu/cce/firstperiod.html, John Mark
        Ockerbloom, Penn Libraries), which states for each listed periodical
        the first issue (and first contribution) whose copyright was renewed,
        from the CCE and the Copyright Office's online records (CPRS). Its own
        scope note: it "should include all of the periodicals with renewed
        issue or contribution copyrights (for 1931-1950 issues) between 1958
        and 1977, that were filed in the CCE". Every radio entry is kept, with
        its sentence verbatim, plus the per-title detail page (cinfo).
  cce   Our own reading of the RENEWAL entries in the Catalog of Copyright
        Entries, Third Series, Part 2: Periodicals, 1958-1977 (archive.org OCR),
        which renew 1930-1950 issues: for each target title, every heading block
        that carries an R-number, with the issue's original (c) date. This is an
        independent check of the OBP sentence (and the only check for titles OBP
        does not list). OCR loss causes misses, never false renewals.
  wrh   worldradiohistory.com master pages: the issue PDFs it links, by title
        and year (URLs only; the PDFs are not downloaded). The site's own terms:
        "the operator of this web site does not claim copyright ... The content
        of this site appears under the 'fair use' doctrine", with a take-down
        notice — so it is a scan source, never rights evidence.
  mhdl  archive.org's Media History Digital Library volumes (collection
        mediahistory): title, dates, and the item's own `possible-copyright-
        status` / `licenseurl` / `rights` fields verbatim.

Output: .cache/magazines/evidence.json. Run:
    python3 tools/harvest_magazine_rights.py [--only obp,cce,wrh,mhdl]
"""
import argparse
import html
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ia_lib as L

DIR = os.path.join(L.CACHE, "magazines")
OUT = os.path.join(DIR, "evidence.json")
OBP = "https://onlinebooks.library.upenn.edu/cce/firstperiod.html"
WRH = "https://www.worldradiohistory.com/"

# canonical title -> heading spellings as the CCE prints them (upper case)
TITLES = {
    "Radio Mirror": ["RADIO MIRROR", "RADIO AND TELEVISION MIRROR", "RADIO ROMANCES", "RADIO-TV MIRROR",
                     "RADIO TV MIRROR", "TV RADIO MIRROR", "TV-RADIO MIRROR"],
    "Radio Guide": ["RADIO GUIDE", "MOVIE AND RADIO GUIDE", "MOVIE-RADIO GUIDE", "MOVIE RADIO GUIDE"],
    "Radio Digest": ["RADIO DIGEST"],
    "Radio Stars": ["RADIO STARS"],
    "Tune In": ["TUNE IN"],
    "Radio Varieties": ["RADIO VARIETIES"],
    "Radio Life": ["RADIO LIFE"],
    "Radio Album": ["RADIO ALBUM", "RADIO-TV ALBUM", "TV RADIO ALBUM"],
    "Radio Best": ["RADIO BEST", "RADIO AND TELEVISION BEST", "RADIO & TELEVISION BEST"],
    "Radio Showmanship": ["RADIO SHOWMANSHIP"],
    "Radio Daily": ["RADIO DAILY", "RADIO DAILY-TELEVISION DAILY"],
    "Broadcasting": ["BROADCASTING", "BROADCASTING-TELECASTING", "BROADCASTING TELECASTING"],
    "Radioland": ["RADIOLAND"],
    "Radioland and Television": ["RADIOLAND AND TELEVISION"],
    "Stand By": ["STAND BY"],
    "Screen and Radio Weekly": ["SCREEN AND RADIO WEEKLY", "SCREEN & RADIO WEEKLY"],
    "Variety": ["VARIETY"],
    # controls: film fan magazines OBP lists as renewed from 1944 (Macfadden)
    "Photoplay": ["PHOTOPLAY", "PHOTOPLAY MOVIE MIRROR"],
    "Motion Picture Magazine": ["MOTION PICTURE", "MOTION PICTURE MAGAZINE"],
}
WRH_PAGES = {
    "Radio Guide": "Radio_Guide_Master_Page.htm",
    "Radio Mirror": "Mirror-Page-Range-Guide.htm",
    "Radio Digest": "Radio_Digest_Master_Page_Guide.htm",
    "Radio Stars": "Radio_Stars.htm",
    "Tune In": "Tune-In.htm",
    "Radio Varieties": "Radio_Varieties.htm",
}
OBP_ALIASES = {  # OBP entry title -> our canonical title
    "radio mirror": "Radio Mirror", "radio guide": "Radio Guide", "radio digest": "Radio Digest",
    "radio stars": "Radio Stars", "radioland and television": "Radioland and Television", "stand by": "Stand By",
    "sponsor": "Sponsor", "variety": "Variety", "what's on the air": "What's On the Air",
    "radio news": "Radio News", "broadcasting": "Broadcasting", "photoplay": "Photoplay",
    "motion picture magazine": "Motion Picture Magazine", "song hits": "Song Hits",
}


def cached_get(url, name, raw=True, pause=2.0):
    path = os.path.join(DIR, "raw", name)
    if os.path.exists(path):
        with open(path, "rb") as f:
            return f.read()
    body = L.get(url, raw=True, pause=pause, timeout=300)
    if body is None:
        return None
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".tmp", "wb") as f:
        f.write(body)
    os.replace(path + ".tmp", path)
    return body


def text_of(h):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", h))).strip()


def harvest_obp(fails):
    body = cached_get(OBP, "obp_firstperiod.html")
    if body is None:
        fails.append(OBP)
        return []
    t = body.decode("utf-8", "replace")
    rows = []
    for li in re.findall(r"<li>(.*?)(?=<li>|</ul>)", t, re.S):
        tx = text_of(li)
        m = re.match(r"(.+?)\s*(?:\(([^)]*)\))?\s*:\s*(.*)$", tx)
        if not m:
            continue
        name, qual, stmt = m.group(1).strip(), m.group(2), m.group(3)
        low = name.lower().lstrip("the ").strip() if name.lower().startswith("the ") else name.lower()
        radioish = re.search(r"\bradio|broadcast|tune in|stand by\b", (name + " " + (qual or "")).lower())
        canon = OBP_ALIASES.get(low)
        if not (radioish or canon):
            continue
        if re.search(r"radiolog|radiograph|radium|radiolog", low):
            continue
        hrefs = re.findall(r'href="([^"]+)"', li)
        rows.append({"obp_title": name, "qualifier": qual, "statement": stmt, "canonical": canon,
                     "detail": hrefs[0] if hrefs else None, "source": OBP})
    # detail pages for the titles we hold a canonical name for
    for r in rows:
        if r["canonical"] and r["detail"] and "cinfo" in r["detail"]:
            slug = r["detail"].rstrip("/").split("/")[-1]
            b = cached_get(r["detail"], f"obp_cinfo_{slug}.html")
            if b is None:
                fails.append(r["detail"])
                continue
            r["detail_text"] = text_of(re.sub(r"<script.*?</script>|<style.*?</style>", "", b.decode("utf-8", "replace"),
                                              flags=re.S))[:4000]
    return rows


MON = {m: i + 1 for i, m in enumerate("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split())}
CDATE = re.compile(r"[©@]\s*(\d{1,2})\s?([A-Z][a-z]{2})[a-z]*\s?(\d{2})\b")
RNUM = re.compile(r"\bR\s?(\d{5,6})\b")
# 1975-77 print titles in mixed case on a line of their own: "Photoplay."
BARE = re.compile(r"^[A-Z][A-Za-z0-9 '&,:/!-]{2,80}\.\s*$")
HEAD = re.compile(r"^([A-Z0-9][A-Z0-9 '&.,:/!-]{2,80}?)\.\s*(?:\(R\)|©|$)")


def cce_volumes():
    rows = list(L.scrape('title:("catalog of copyright entries") AND title:(periodicals)', "identifier,title,year"))
    vols = []
    for r in rows:
        y = int(str(r.get("year") or "0")[:4] or 0)
        if 1958 <= y <= 1977 and "Third Series" in (r.get("title") or ""):
            vols.append((y, r["identifier"], r["title"]))
    return sorted(vols)


def parse_cce(txt, vol_year, ident):
    """Heading blocks for target titles that carry renewal numbers."""
    lines = txt.split("\n")
    want = {}
    for canon, heads in TITLES.items():
        for h in heads:
            want[h] = canon
    found = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i].strip()
        m = HEAD.match(line.upper()) if len(line) < 90 else None
        if m and m.group(1).strip() in want and (line[:len(m.group(1))].isupper() or (vol_year >= 1975 and BARE.match(line))):
            head = m.group(1).strip()
            block = [line]
            j = i + 1
            while j < n and j < i + 60:
                nxt = lines[j].strip()
                hm = HEAD.match(nxt)
                if hm and hm.group(1).strip() != head and len(hm.group(1)) > 3 and hm.group(1).upper() == hm.group(1) \
                        and not re.match(r"^(V\.|NO\.|\d)", hm.group(1)):
                    break
                if vol_year >= 1975 and BARE.match(nxt) and nxt.upper().rstrip(". ") != head:
                    break
                block.append(nxt)
                j += 1
            btxt = " ".join(block)
            rs = RNUM.findall(btxt)
            if rs:
                dates = []
                for d, mo, yy in CDATE.findall(btxt):
                    if mo in MON:
                        yr = 1900 + int(yy)
                        if vol_year - 30 <= yr <= vol_year - 26:
                            dates.append(f"{yr}-{MON[mo]:02d}-{int(d):02d}")
                found.append({"canonical": want[head], "heading": head, "vol_year": vol_year, "vol": ident,
                              "line": i + 1, "renewals": sorted(set("R" + r for r in rs)),
                              "orig_dates": sorted(set(dates)), "text": btxt[:600],
                              "src": f"https://archive.org/details/{ident}?q=%22{head.replace(' ', '+')}%22"})
            i = j
            continue
        i += 1
    return found


def harvest_cce(fails):
    vols = cce_volumes()
    out = []
    for y, ident, title in vols:
        body = cached_get(f"https://archive.org/download/{ident}/{ident}_djvu.txt", f"cce_{ident}.txt")
        if body is None:
            fails.append(ident)
            continue
        out.extend(parse_cce(body.decode("utf-8", "replace"), y, ident))
    return {"volumes": [{"year": y, "id": i, "title": t} for y, i, t in vols], "hits": out}


def harvest_wrh(fails):
    out = []
    for canon, page in WRH_PAGES.items():
        body = cached_get(WRH + page, "wrh_" + page, pause=3.0)
        if body is None:
            fails.append(WRH + page)
            continue
        t = body.decode("utf-8", "replace")
        pdfs = sorted(set(re.findall(r'href="([^"]+\.pdf)"', t, re.I)))
        for p in pdfs:
            fn = p.rsplit("/", 1)[-1]
            m = re.search(r"/(1[89]\d\d)/", p) or re.search(r"(1[89]\d\d)", fn) or re.search(r"/(\d\d)/", p)
            yr = None
            if m:
                yr = int(m.group(1)) if len(m.group(1)) == 4 else 1900 + int(m.group(1))
            out.append({"canonical": canon, "year": yr, "url": urljoin(page, p), "file": fn})
    return out


def urljoin(page, href):
    import urllib.parse
    return urllib.parse.urljoin(WRH + page, href)


def harvest_mhdl(fails):
    q = 'collection:mediahistory AND (title:radio OR title:"tune in" OR title:"stand by")'
    try:
        rows = list(L.scrape(q, "identifier,title,date,year,licenseurl,rights,possible-copyright-status"))
    except RuntimeError as e:
        fails.append(str(e))
        return []
    out = []
    for r in rows:
        t = (r.get("title") or "")
        canon = None
        low = t.lower()
        for c, heads in TITLES.items():
            if any(low.startswith(h.lower()) for h in heads):
                canon = c
                break
        if not canon:
            continue
        out.append({"canonical": canon, "id": r["identifier"], "title": t, "date": r.get("date"),
                    "year": r.get("year"), "licenseurl": r.get("licenseurl"), "rights": r.get("rights"),
                    "possible_copyright_status": r.get("possible-copyright-status"),
                    "url": "https://archive.org/details/" + r["identifier"]})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="obp,cce,wrh,mhdl")
    a = ap.parse_args()
    os.makedirs(DIR, exist_ok=True)
    ev = L.read_json(OUT) if os.path.exists(OUT) else {}
    fails = []
    for part in a.only.split(","):
        f = {"obp": harvest_obp, "cce": harvest_cce, "wrh": harvest_wrh, "mhdl": harvest_mhdl}[part]
        ev[part] = f(fails)
        print(part, "done", file=sys.stderr)
    ev["failures"] = fails
    ev["fetched"] = time.strftime("%Y-%m-%d")
    L.write_json(OUT, ev)
    print({k: (len(v) if isinstance(v, list) else len(v.get("hits", []))) for k, v in ev.items()
           if k in ("obp", "cce", "wrh", "mhdl")}, "failures", len(fails), file=sys.stderr)
    if not any(ev.get(k) for k in ("obp", "cce", "wrh", "mhdl")):
        sys.exit(1)


if __name__ == "__main__":
    main()
