"""Harvest the Generic Radio Workshop script library (genericradio.com):
206 series, 1,374 scripts (its own count, 2026-10-17), each a broadcast script
with series, title and air date, plus a downloadable text file.

GRW states the scripts "remain, as they should, the copyright of their
respective owners" and advises "Assume Copyright". So the text is cached for
SEARCH and matching only; a client links to the GRW page (which GRW hosts and
funds with ads) and never re-publishes the script. robots.txt blocks only
/eklipse/ and /common/; a 3-second delay is used anyway.
"""
import html
import os
import re
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
import ia_lib as ia

BASE = "https://www.genericradio.com"
UA = "Mozilla/5.0 (Macintosh) ArchiveWatch-RadioCatalog (catalog build; links back to every script)"
DELAY = 3
SERIES = re.compile(r"<a href=series/([A-Za-z0-9_-]+)>([^<]+)")
ROW = re.compile(r"<tr><td>([^<]*)</td><td><a href='/show/([0-9A-Za-z]+)'>([^<]*)</a>")
EXTERNAL_ID = re.compile(r"[0-9a-f]{16}")
MONTHS = {m: i for i, m in enumerate("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split(), 1)}


def fetch(path):
    body = ia.get(BASE + path, ua=UA, raw=True, timeout=90)
    time.sleep(DELAY)
    return None if body is None else body.decode("utf-8", "replace")


def iso(d):
    m = re.match(r"([A-Z][a-z]{2})\s+(\d{1,2})\s+(\d{4})", d.strip())
    if m and m.group(1) in MONTHS:
        return f"{m.group(3)}-{MONTHS[m.group(1)]:02d}-{int(m.group(2)):02d}"
    return None


def main():
    out = os.path.join(ia.CACHE, "grw")
    os.makedirs(os.path.join(out, "text"), exist_ok=True)
    index = os.path.join(out, "scripts.json")
    if os.path.exists(index) and "--refresh" not in sys.argv:
        # Reuse the saved index: re-crawling 206 series pages (~10 min) on every
        # restart meant a run never reached the text pass (2026-10-18).
        saved = ia.read_json(index)
        fetch_texts(out, {s["id"]: s for s in saved["scripts"]}, saved["series"], [])
        return
    lib = fetch("/library.php")
    if not lib:
        raise SystemExit("GRW library unreadable")
    series = [(slug, html.unescape(name).strip()) for slug, name in SERIES.findall(lib)]
    if len(series) < 150:
        raise SystemExit(f"GRW library parsed only {len(series)} series")
    scripts, failed = {}, []
    for slug, name in series:
        page = fetch(f"/series/{slug}")
        if page is None:
            failed.append("series:" + slug)
            continue
        for date, sid, title in ROW.findall(page):
            scripts.setdefault(sid, {"id": sid, "series": name, "series_slug": slug, "title": html.unescape(title).strip(),
                                     "date_text": date.strip(), "date": iso(date), "url": f"{BASE}/show/{sid}"})
    fetch_texts(out, scripts, len(series), failed)


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def redirect_target(url):
    """Where a GRW /show/ page redirects, without following it (None if it does not)."""
    opener = urllib.request.build_opener(_NoRedirect)
    try:
        opener.open(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=30)
        return None
    except urllib.error.HTTPError as e:
        return e.headers.get("Location") if 300 <= e.code < 400 else None
    except Exception:
        return None
    finally:
        time.sleep(1)


def fetch_texts(out, scripts, n_series, failed):
    # Save the index before the long text pass: a run stopped mid-way (a session
    # restart killed one on 2026-10-17) must not lose what it already read.
    ia.write_json(os.path.join(out, "scripts.json"), {"series": n_series, "scripts": list(scripts.values()),
                                                       "failed": failed, "complete": False})
    for sid, s in scripts.items():
        path = os.path.join(out, "text", sid + ".txt")
        if os.path.exists(path):
            continue
        if EXTERNAL_ID.fullmatch(sid) or s.get("external"):
            # GRW's link to a script hosted elsewhere (its /show/ page 302s to
            # another site, MEASURED 2026-10-18); GRW holds no text for it.
            s["external"] = True
            continue
        where = redirect_target(f"{BASE}/show/{sid}")
        if where and not where.startswith(BASE) and not where.startswith("/"):
            s["external"] = True
            s["external_url"] = where
            continue
        body = ia.get(f"{BASE}/files/generic_radio_workshop_radio_script_{sid}.txt", ua=UA, raw=True, timeout=90)
        time.sleep(DELAY)
        if body is None:
            # Some scripts have no text download (404 on ~20%, 2026-10-17); the
            # show page carries the same script in its scriptbody block.
            page = fetch(f"/show/{sid}")
            m = re.search(r"class=.scriptbody[^>]*>(.*?)(?:<div class=.aboutblock|</body>)", page or "", re.S)
            if not m:
                failed.append("text:" + sid)
                continue
            body = m.group(1).encode("utf-8")
        with open(path, "wb") as f:
            f.write(body)
    ia.write_json(os.path.join(out, "scripts.json"), {"series": n_series, "scripts": list(scripts.values()),
                                                       "failed": failed, "complete": True})
    print(f"{n_series} series, {len(scripts)} scripts, {len(failed)} failed", file=sys.stderr)
    if not scripts:
        sys.exit(1)


if __name__ == "__main__":
    main()
