"""Tonight in 19xx: a real network evening rebuilt from a period newspaper's radio
grid, each slot matched to the served episode of THAT program on THAT date, every
other slot a stated gap (05-design-research §4.3, rules R9 and R10; DECISIONS 058).

Source: JJ's Newspaper Radio Logs (docs/research/evenings.md), the Washington Post's
daily grid: one column per Washington station, one row per quarter hour, times as
printed in Eastern time. A Washington station stands for its network (WRC = NBC,
WJSV/WTOP = CBS, ...), so an evening is "the network's evening as Washington heard it",
and the witness names the paper, the station and the page.

    python3 tools/build_evenings.py index                      # month pages -> PDF list
    python3 tools/build_evenings.py evening 1947-10-16 CBS     # one evening, printed
    python3 tools/build_evenings.py measure --sample N         # coverage over many evenings
    python3 tools/build_evenings.py measure --window --max-fetch 120   # the window's logs, politely
    python3 tools/build_evenings.py tonight --previous live/tonight.json --out tonight.json
    python3 tools/build_evenings.py web --src tonight.json --web out/web --out out/web/tonight.json
    python3 tools/build_evenings.py kept --old live/tonight.json --new tonight.json

stdlib only, plus poppler's `pdftotext` for the PDF's own OCR text layer.
Caches: <cache>/radiologs/{index,pdf}; never committed.
"""
import argparse
import collections
import datetime as dt
import difflib
import json
import os
import random
import re
import sqlite3
import subprocess
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
from forwarding import episode_forwards  # noqa: E402
from otr_parse import norm_series  # noqa: E402

UA = "EarDrama/0.1 (+https://eardrama.org)"
JJ = "https://www.jjonz.us/RadioLogs/pagesnfiles/"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.environ.get("EARDRAMA_CACHE", os.path.join(ROOT, ".cache"))
PROJECTION = os.environ.get("EARDRAMA_PROJECTION", os.path.join(ROOT, "out", "publish", "ear-drama.sqlite"))
REGISTRY = os.environ.get("EARDRAMA_REGISTRY", os.path.join(ROOT, "out", "next", "radio-catalog.sqlite"))
MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
PAPERS = {"w": "Washington Post", "n": "New York Times", "c": "Chicago Daily Tribune", "L": "Los Angeles Times"}

PRIME = (19 * 60, 23 * 60)  # 7-11 PM Eastern, the measured window
ZONE = "America/New_York"   # the printed times are Eastern; tonight replays on the same Eastern clock
# Decision 067 (the owner, 2026-10-23): an evening shows when ANY program survives, so
# Decision 058's 0.25 coverage floor is gone; an evening whose every slot is a gap is
# never offered.
# The published window, by calendar date: yesterday through 13 days ahead of the build's
# UTC date, so every time zone finds its own today (contract §8).
WINDOW_BACK, WINDOW_AHEAD = 1, 13
YEARS = (1935, 1955)        # the anniversary years read for each calendar date

# Washington stations and their networks, by date. A grid header that prints the
# network ("WRC (NBC)") wins over this table; the table is the fallback and its
# edges are from station histories (docs/research/evenings.md, UNVERIFIED to the month).
DC_STATIONS = {
    "WRC": [("1923-01-01", "NBC")],
    "WMAL": [("1933-01-01", "NBC Blue"), ("1942-01-01", "Blue"), ("1945-06-15", "ABC")],
    "WJSV": [("1932-01-01", "CBS")],
    "WTOP": [("1943-01-01", "CBS")],
    "WOL": [("1937-01-01", "Mutual"), ("1950-01-01", None)],
    "WWDC": [("1941-01-01", None), ("1950-01-01", "Mutual")],
    "WINX": [("1940-01-01", None)],
}
NETWORK_ALIASES = {"NBC": "NBC", "CBS": "CBS", "ABC": "ABC", "MBS": "Mutual", "M85": "Mutual", "MEM": "Mutual",
                   "MUTUAL": "Mutual", "BLUE": "Blue"}


DIAL = {950: [("1920-01-01", "WRC")], 980: [("1941-03-29", "WRC")], 630: [("1925-01-01", "WMAL")],
        1310: [("1928-01-01", "WOL")], 1260: [("1941-03-29", "WOL"), ("1950-01-01", "WWDC")],
        1460: [("1932-01-01", "WJSV")], 1500: [("1941-03-29", "WJSV"), ("1943-01-01", "WTOP")],
        1340: [("1941-03-29", "WINX")], 1450: [("1941-03-29", "WWDC"), ("1950-01-01", "WOL")]}


def dial_station(kc, date):
    """Washington dial positions by date (the 1941 NARBA move shifted most of them)."""
    call = None
    for since, c in DIAL.get(kc, []):
        if date >= since:
            call = c
    return call


def station_network(call, date):
    net = None
    for since, n in DC_STATIONS.get(call, []):
        if date >= since:
            net = n
    return net


# ---------------------------------------------------------------- fetching (polite)

def _get(url, tries=4):
    delay = 5.0
    for _ in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=90) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            time.sleep(delay)
            delay *= 2
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            time.sleep(delay)
            delay *= 2
    raise RuntimeError(f"could not read {url}")


def index_path(year, month):
    return os.path.join(CACHE, "radiologs", "index", f"{year}_{month:02d}{MON[month - 1]}.htm")


def fetch_month(y, m, pause=2.0):
    """One month page from JJ's into the cache; False when JJ's has none."""
    path = index_path(y, m)
    if os.path.exists(path):
        return True
    os.makedirs(os.path.dirname(path), exist_ok=True)
    name = f"{y}_{m:02d}{MON[m - 1]}"
    body = None
    for variant in (name, f"{y} _{m:02d}{MON[m - 1]}"):
        body = _get(f"{JJ}logs_pages_months/{y // 10 * 10}s/{y}/{urllib.request.quote(variant)}.htm")
        time.sleep(pause)
        if body:
            break
    if body is None:
        return False
    with open(path, "wb") as f:
        f.write(body)
    return True


def fetch_index(y0, y1, pause=2.0):
    missing = []
    for y in range(y0, y1 + 1):
        for m in range(1, 13):
            if not fetch_month(y, m, pause):
                missing.append(f"{y}_{m:02d}{MON[m - 1]}")
    return missing


def url_map_path():
    return os.path.join(CACHE, "radiologs", "log-urls.json")


_URLS = None


def url_map():
    """{'YYYY-MM': {'pYYYY-MM-DD': pdf url}}: the month pages reduced to their links, the
    form the publish run keeps between runs (a link is a fact; the page is JJ's)."""
    global _URLS
    if _URLS is None:
        p = url_map_path()
        _URLS = json.load(open(p)) if os.path.exists(p) else {}
    return _URLS


def save_url_map():
    if _URLS is not None:
        os.makedirs(os.path.dirname(url_map_path()), exist_ok=True)
        with open(url_map_path(), "w") as f:
            json.dump(_URLS, f, sort_keys=True)


def log_urls(year, month, fetch=False):
    """{(paper, 'YYYY-MM-DD'): absolute PDF url}, from the kept link map, else a cached month
    page, else (fetch=True) the month page fetched once."""
    key = f"{year}-{month:02d}"
    kept = url_map().get(key)
    if kept is not None:
        return {(k[0], k[1:]): v for k, v in kept.items()}
    path = index_path(year, month)
    if not os.path.exists(path) and not (fetch and fetch_month(year, month)):
        return {}
    html = open(path, encoding="latin-1").read()
    out = {}
    base = f"{JJ}logs_pages_months/{year // 10 * 10}s/{year}/"
    for href in re.findall(r'href="([^"]+\.pdf)"', html):
        m = re.search(r"\[(\w)\](\d\d)-(\d\d)-(\d\d)", href)
        if not m:
            continue
        paper, yy, mm, dd = m.groups()
        date = f"{year // 100}{yy}-{mm}-{dd}"
        url = urllib.request.urljoin(base, href)
        out[(paper, date)] = url
    url_map()[key] = {p + d: u for (p, d), u in out.items()}
    return out


# PDFs a run may still download (None = no limit): a publish run reads only what its window
# needs, and at most this many, so a first run without the kept cache spreads over days.
FETCH_BUDGET = None


def pdf_for(paper, date, fetch=True):
    global FETCH_BUDGET
    y, m, _ = (int(x) for x in date.split("-"))
    url = log_urls(y, m, fetch=fetch).get((paper, date))
    if not url:
        return None, None
    path = os.path.join(CACHE, "radiologs", "pdf", f"{paper}{date}.pdf")
    if not os.path.exists(path):
        if not fetch or FETCH_BUDGET == 0:
            return None, url
        if FETCH_BUDGET is not None:
            FETCH_BUDGET -= 1
        body = _get(url.replace("[", "%5B").replace("]", "%5D"))
        if body is None:
            return None, url
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(body)
        time.sleep(3.0)
    return path, url


# ---------------------------------------------------------------- the grid parser

WORD = re.compile(r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">([^<]*)</word>')
LABEL_BARE = re.compile(r"^[|!'\"`.,\-=]*(00|15|30|45|13|43)(?:[1lI|!/]?$|[1lI|!/]?([A-Z\"'(].*)$)")
LABEL = re.compile(r"^[|!'\"`.,\-=]*(\d{1,2}|[IlZz]\d?|\d[IlZz])?\s*[:;]\s*([0-9OoDIl(][0-9OoDIl()\]]?)[1lI|!'.,:;)\]]?(.*)$")
HOURLAB = re.compile(r"^(\d{1,2}|[IlZ][0-9IlZ]?)$")


def words_of(pdf):
    xml = subprocess.run(["pdftotext", "-bbox", pdf, "-"], capture_output=True, text=True, check=True).stdout
    out = []
    for x0, y0, x1, y1, t in WORD.findall(xml):
        t = t.replace("&apos;", "'").replace("&quot;", '"').replace("&amp;", "&")
        out.append([float(x0), float(y0), float(x1), float(y1), t])
    return out


def glue_labels(words):
    """OCR splits "10: 00Bing" into two words; a label is one word again."""
    out = []
    for w in words:
        if out and re.fullmatch(r"\d{0,2}\s*[:;]", out[-1][4]) and abs(w[1] - out[-1][1]) < 4 and 0 <= w[0] - out[-1][2] < 8:
            prev = out.pop()
            w = [prev[0], min(prev[1], w[1]), w[2], max(prev[3], w[3]), prev[4] + w[4]]
        out.append(w)
    return out


def _digit(c):
    return {"O": "0", "o": "0", "D": "0", "(": "0", "I": "1", "l": "1", "Z": "2", "z": "2"}.get(c, c)


def _call(t):
    t = re.sub(r"[^A-Z0-9]", "", t.upper().replace("1", "I"))
    t = t.replace("WJSY", "WJSV").replace("WJSR", "WJSV").replace("WMAI", "WMAL").replace("VVRC", "WRC")
    return t


def find_header(words, date):
    """The y band where three or more Washington call letters sit side by side. A Sunday
    page prints the day as two grids side by side, so the band can hold each call twice:
    every repeat starts a new panel."""
    hits = []
    for i, w in enumerate(words):
        # call letters are often glued to the dial numbers beside them ("6301WRC", "WT0P")
        raw = w[4].upper().replace("0", "O").replace("1", "I")
        for bad, good in (("WJSY", "WJSV"), ("WJSR", "WJSV"), ("WISV", "WJSV"), ("WMAI", "WMAL"), ("VVRC", "WRC")):
            raw = raw.replace(bad, good)
        if len(raw) > 14:
            continue
        raw = re.sub(r"^WDC", "WWDC", raw)
        for m in re.finditer(r"W(?:MAL|RC|OL|JSV|TOP|WDC|INX)", raw):
            if "TV" in raw[m.end():m.end() + 3]:  # the television grid beside the radio one
                continue
            frac = (m.start() + m.end()) / 2 / max(1, len(raw))
            hits.append((w[1], w[0] + frac * (w[2] - w[0]), m.group(0), 0))
        # the dial position printed under the call letters ("316M-950KC") names the station
        # when the OCR has mangled its letters ("WFIC", "1VM AL")
        if "KC" in w[4].upper() or re.search(r"\d{3}M", w[4]):
            for m in re.finditer(r"(\d,?\d{3}|\d{3})\s*K", w[4].upper().replace("O", "0").replace("I", "1")):
                call = dial_station(int(m.group(1).replace(",", "")), date)
                if call:
                    frac = (m.start() + m.end()) / 2 / max(1, len(w[4]))
                    hits.append((w[1] - 8, w[0] + frac * (w[2] - w[0]), call, 1))
    best = None
    for y, _, _, _ in hits:
        band = [h for h in hits if 0 <= h[0] - y < 24]
        if len({h[2] for h in band}) >= 3 and (best is None or len(band) > len(best[1]) or
                                               (len(band) == len(best[1]) and y < best[0])):
            best = (y, band)
    if not best:
        return None
    y, band = best
    # one station per column: a dial number under its own call letters is the same column
    marks = []
    for h in sorted(band, key=lambda h: (h[3], h[1])):
        if any(m[2] == h[2] and abs(m[1] - h[1]) < 45 for m in marks):
            continue
        marks.append(h)
    marks.sort(key=lambda h: h[1])
    panels, cur = [], []
    for h in marks:
        if any(c[1] == h[2] for c in cur):
            panels.append(cur)
            cur = []
        cur.append((h[1], h[2]))
    panels.append(cur)
    panels = [p for p in panels if len(p) >= 3]
    if not panels:
        return None
    out = []
    for cols in panels:
        # a column whose call letters the OCR lost leaves a double-wide gap; keep its place
        # (unnamed) so its programs are not read into a neighbor's column
        diffs = [b[0] - a[0] for a, b in zip(cols, cols[1:])]
        unit = min(diffs)
        filled = [cols[0]]
        for (xa, _), (xb, cb) in zip(cols, cols[1:]):
            k = round((xb - xa) / unit)
            for j in range(1, k if k >= 2 and (xb - xa) > 1.6 * unit else 1):
                filled.append((xa + j * (xb - xa) / k, f"?{len(filled)}"))
            filled.append((xb, cb))
        out.append({"cols": filled, "pitch": (filled[-1][0] - filled[0][0]) / max(1, len(filled) - 1)})
    for i, p in enumerate(out):
        p["left"] = p["cols"][0][0] - 0.75 * p["pitch"]
        p["right"] = p["cols"][-1][0] + 0.75 * p["pitch"]
        p["gutter"] = (out[i - 1]["cols"][-1][0] + 0.4 * out[i - 1]["pitch"]) if i else p["left"] - 40
        if i + 1 < len(out):
            p["right"] = min(p["right"], out[i + 1]["cols"][0][0] - 0.6 * out[i + 1]["pitch"])
    nets = {}
    allcols = [c for p in out for c in p["cols"]]
    for w in words:  # "WRC (NBC)" / "(CBS)" printed beside the call letters
        if abs(w[1] - y) < 8:
            m = re.match(r"^\(?([A-Z0-9]{3,6})\)?$", w[4].strip(".,"))
            if m and m.group(1) in NETWORK_ALIASES and "(" in w[4]:
                cx = (w[0] + w[2]) / 2
                near = min(allcols, key=lambda c: abs(c[0] - cx))
                if abs(near[0] - cx) < 60:
                    nets[near[1]] = NETWORK_ALIASES[m.group(1)]
    return {"y": y, "panels": out, "nets": nets, "cols": out[0]["cols"]}


def clock_breaks(a, b):
    """Two labels that both print their hour and are more than two hours apart, or run
    backward, are not one block: another list starts here (or a misread hour, which the
    re-chaining of blocks repairs)."""
    if a[2] is None or b[2] is None:
        return False
    k = (((b[2] % 12) * 4 + b[1] // 15) - ((a[2] % 12) * 4 + a[1] // 15)) % 48
    return not 1 <= k <= 8


def quarter_step(a, b, med):
    """Quarters from label a to label b: congruent to their minutes, nearest their spacing
    (an OCR-dropped label leaves a taller gap, not a lost hour)."""
    diff = ((b[1] - a[1]) // 15) % 4
    est = (b[0] - a[0]) / med if med else 1
    if a[2] is not None and b[2] is not None:  # both print their hour: the clock says how far
        k = (((b[2] % 12) * 4 + b[1] // 15) - ((a[2] % 12) * 4 + a[1] // 15)) % 48
        if 1 <= k <= 8 and abs(k - est) <= 3:
            return k
    ks = [diff + 4 * j for j in range(4) if diff + 4 * j >= 1]
    k = min(ks, key=lambda k: (abs(k - est), k))
    if abs(k - est) > 2.5:  # the minutes disagree with the spacing: a misread label, trust the spacing
        k = max(1, round(est))
    return k


def _minute(s):
    d = _digit(s[0]) if s else ""
    return {"0": 0, "1": 15, "3": 30, "4": 45}.get(d)


def _labels(words, panel, y_head):
    """A panel's time labels (the gutter tokens that read as [h]:mm) and its other words."""
    centers = [c[0] for c in panel["cols"]]
    pitch = panel["pitch"]
    labels, rest = [], []
    for w in words:
        if w[1] <= y_head + 4 or w[0] < panel["gutter"] or w[0] > panel["right"]:
            continue
        in_gutter = w[0] < centers[0] - 0.1 * pitch
        m = LABEL.match(w[4])
        if not m and in_gutter:
            b = LABEL_BARE.match(w[4])  # "45IGunnar": the colon lost, the rule bar read as I
            if b:
                m = LABEL.match(":" + b.group(1) + "|" + (b.group(2) or ""))
        if m and in_gutter:
            minute = _minute(m.group(2))
            if minute is not None:
                hour = None
                if m.group(1):
                    h = "".join(_digit(c) for c in m.group(1))
                    if h.isdigit() and 1 <= int(h) <= 12:
                        hour = int(h)
                labels.append([(w[1] + w[3]) / 2, minute, hour])
                tail = m.group(3).strip()
                if tail:
                    width = (w[2] - w[0]) / max(1, len(w[4]))
                    rest.append([w[2] - len(tail) * width, w[1], w[2], w[3], tail])
                continue
        rest.append(w)
    # bare hour numerals in the gutter ("9", "10", "12") anchor the hour of the label beside them
    for w in rest:
        if w[2] < centers[0] - 0.2 * pitch and HOURLAB.match(w[4]) and labels:
            h = "".join(_digit(c) for c in w[4])
            if h.isdigit() and 1 <= int(h) <= 12:
                yc = (w[1] + w[3]) / 2
                near = min(labels, key=lambda lab: abs(lab[0] - yc))
                if abs(near[0] - yc) < 7 and near[2] is None:
                    near[2] = int(h)
    labels.sort()
    rows = []
    for lab in labels:  # one row per band; a time printed on both sides of the grid is one row
        if rows and abs(lab[0] - rows[-1][0]) < 3.5 and (lab[1] == rows[-1][1] or lab[0] - rows[-1][0] < 1.5):
            if lab[2] is not None and rows[-1][2] is None:  # two labels on one line: keep the one with its hour
                rows[-1] = lab
                continue
            if rows[-1][2] is None:
                rows[-1][2] = lab[2]
            continue
        rows.append(lab)
    return rows, rest


def parse_grid(words, date):
    """Rows (Eastern minutes since midnight) x station columns -> slots per station."""
    head = find_header(words, date)
    if not head:
        return None, "no station header"
    words = glue_labels(words)
    panels = head["panels"]
    per = [_labels(words, p, head["y"]) for p in panels]
    if sum(len(r) for r, _ in per) < 12:
        return None, f"only {sum(len(r) for r, _ in per)} time labels"
    # the grid is the runs of evenly spaced labels (a page may print the day in two blocks,
    # "AFTERNOON" / "EVENING", or two panels); times printed elsewhere (highlights, FM
    # notes) fall outside them
    runs = []  # (panel, rows)
    meds = []
    for pi, (rows, _) in enumerate(per):
        gaps = sorted(b[0] - a[0] for a, b in zip(rows, rows[1:]))
        med = gaps[len(gaps) // 2] if gaps else 9
        meds.append(med)
        cur = rows[:1]
        for a, b in zip(rows, rows[1:]):
            if b[0] - a[0] > 2.6 * med or clock_breaks(a, b):
                runs.append((pi, cur))
                cur = []
            cur.append(b)
        if cur:
            runs.append((pi, cur))
    runs = [r for r in runs if len(r[1]) >= 3]
    if not runs or sum(len(r[1]) for r in runs) < 12:
        return None, "too few grid rows"
    placed = []  # (panel, rows, quarters-from-run-start, start quarter on a 12-hour clock)
    for pi, run in runs:
        q = [0]
        for a, b in zip(run, run[1:]):
            q.append(q[-1] + quarter_step(a, b, meds[pi]))
        offsets = collections.Counter()
        for (y, minute, hour), qi in zip(run, q):
            if hour is not None:
                offsets[((hour % 12) * 4 + minute // 15 - qi) % 48] += 1
        if offsets:
            placed.append((pi, run, q, offsets.most_common(1)[0][0]))
    if not placed:
        return None, "no printed hour"

    def continues(a, b):  # block b picks up the clock where block a stops (below it, or the next panel)
        pa, run, q, s12 = a
        end12 = (s12 + q[-1] + 1) * 15 % 720
        step = (b[3] * 15 - end12 + 360) % 720 - 360
        near = b[0] != pa or b[1][0][0] - run[-1][0] <= 12 * meds[pa]
        return near and -60 <= step <= 120

    core = max(range(len(placed)), key=lambda i: len(placed[i][1]))  # the grid's main block
    lo = hi = core
    while hi + 1 < len(placed) and continues(placed[hi], placed[hi + 1]):
        hi += 1
    while lo > 0 and continues(placed[lo - 1], placed[lo]):
        lo -= 1
    placed = placed[lo:hi + 1]
    if os.environ.get("EVENINGS_DEBUG"):
        print("RUNS", [(pi, round(r[0][0]), len(r)) for pi, r in runs],
              "CHAIN", [(pi, round(r[0][0]), s) for pi, r, _, s in placed], file=sys.stderr)
    # a day's grid ends late at night: the last block ends between 10 PM and 3 AM, and
    # each earlier block is the latest placing that still ends before the next one starts
    starts = [None] * len(placed)
    nxt = None
    for i in range(len(placed) - 1, -1, -1):
        pi, run, q, s12 = placed[i]
        span = q[-1] * 15 + 15
        opts = [s12 * 15 + k * 720 for k in (0, 1, 2)]
        if nxt is None:
            ok = [o for o in opts if 22 * 60 <= o + span <= 27 * 60]
        else:
            ok = [o for o in opts if o + span <= nxt + 30 and o >= 4 * 60]
        if not ok:
            ok = [opts[1] if nxt is None else opts[0]]
        starts[i] = max(ok)
        nxt = starts[i]
    rows = []  # (panel, y, minute, hour, time)
    for (pi, run, q, s12), st in zip(placed, starts):
        rows += [(pi, r[0], r[1], r[2], st + qi * 15) for r, qi in zip(run, q)]
    if os.environ.get("EVENINGS_DEBUG"):
        for r in rows:
            print("ROW", r[0], round(r[1]), r[2], r[3], hhmm(r[4]), file=sys.stderr)
    times = [r[4] for r in rows]
    # anomalies: a printed hour that disagrees with its row means the sequence slipped
    def wrong(r):  # a printed "1" may be 10, 11 or 12 with a digit lost
        h = (r[4] // 60) % 12 or 12
        return r[3] is not None and h != r[3] and not (r[3] == 1 and h in (10, 11, 12))
    disagree = sum(1 for r in rows if wrong(r))
    # the evening is what is offered: its own rows (5 PM to 1 AM) must agree with their printed hours
    disagree_evening = sum(1 for r in rows if wrong(r) and 17 * 60 <= r[4] < 25 * 60)
    grid = {}  # (row index, call) -> printed text
    for pi, p in enumerate(panels):
        mine = [i for i, r in enumerate(rows) if r[0] == pi]
        if not mine:
            continue
        spans = [(run[0][0] - meds[pi] * 0.6, run[-1][0] + meds[pi] * 0.9) for qp, run, _, _ in placed if qp == pi]
        centers = [c[0] for c in p["cols"]]
        bounds = [(c1 + c2) / 2 for c1, c2 in zip(centers, centers[1:])]
        cells = collections.defaultdict(list)
        for w in per[pi][1]:
            yc = (w[1] + w[3]) / 2
            xc = (w[0] + w[2]) / 2
            if not any(a <= yc <= b for a, b in spans) or xc < p["left"] or xc > p["right"]:
                continue
            ri = min(mine, key=lambda i: abs(rows[i][1] - yc))
            cells[(ri, p["cols"][sum(1 for b in bounds if xc > b)][1])].append(w)
        for key, ws in cells.items():
            ws.sort(key=lambda w: (round(w[1] / 4), w[0]))
            grid[key] = " ".join(w[4] for w in ws)
    calls = []
    for p in panels:
        for _, c in p["cols"]:
            if c not in calls:
                calls.append(c)
    stations = []
    for call in calls:
        net = head["nets"].get(call) or station_network(call, date)
        has = {pi for pi, p in enumerate(panels) if any(c == call for _, c in p["cols"])}
        slots = []
        for ri, r in enumerate(rows):
            if r[0] not in has:  # this panel has no column for the station: nothing is known here
                continue
            t = r[4]
            text = clean_cell(grid.get((ri, call), ""))
            if text is None:  # ditto marks or nothing: the program above continues
                if slots and slots[-1]["end"] >= t:
                    slots[-1]["end"] = t + 15
                continue
            if slots and slots[-1]["end"] >= t and similar(slots[-1]["printed"], text):
                slots[-1]["end"] = t + 15
                continue
            slots.append({"start": t, "end": t + 15, "printed": text})
        for a, b in zip(slots, slots[1:]):
            a["end"] = min(a["end"], b["start"]) if a["end"] > b["start"] else b["start"]
        stations.append({"call": call, "network": net,
                         "network_from": "header" if call in head["nets"] else "station table", "slots": slots})
    zone = "ET"
    full = " ".join(w[4] for w in words[:400]).lower()
    if "war time" in full:
        zone = "EWT"
    elif "daylight" in full:
        zone = "EDT"
    elif "standard" in full:
        zone = "EST"
    # prime-time quarters the grid's blocks span (a dropped label inside a block is still
    # placed by its neighbors; a quarter outside every block is unknown)
    covered = set()
    for (pi, run, q, s12), st in zip(placed, starts):
        covered |= set(range(st, st + q[-1] * 15 + 15, 15))
    prime_rows = len({t for t in covered if PRIME[0] <= t < PRIME[1]})
    readable = prime_rows >= 13 and disagree_evening <= 1 and 22 * 60 + 45 <= max(times) <= 26 * 60
    return {"stations": stations, "rows": len(rows), "hour_disagreements": disagree,
            "evening_disagreements": disagree_evening, "printed_zone": zone,
            "prime_rows": prime_rows, "last_row": hhmm(max(times)), "readable": readable,
            "panels": len(panels)}, None


TIME_TOKEN = re.compile(r"(?:^|\s)[\dIl]{0,2}\s?[:;]\s?[\dOIl]{2}\S*|(?:^|\s)\d{1,2}(?=\s|$)")


def clean_cell(t):
    t = TIME_TOKEN.sub(" ", t)
    t = re.sub(r"\s+", " ", t).strip(" .,;:-_'\"`|!~*")
    letters = re.sub(r"[^A-Za-z]", "", t)
    if len(letters) < 3:
        return None
    if re.fullmatch(r"[\"'`.,\s\-wW0-9]+", t):
        return None
    return t


def _norm(s):
    s = s.lower().replace("&", " and ").replace("'n'", " and ").replace(" n ", " and ")
    s = re.sub(r"\bthe\b", " ", s)
    return re.sub(r"[^a-z0-9]", "", s)


def similar(a, b):
    na, nb = _norm(a), _norm(b)
    if not na or not nb:
        return False
    if na in nb or nb in na:
        return min(len(na), len(nb)) >= 5
    return difflib.SequenceMatcher(None, na, nb).ratio() >= 0.72


def name_score(name, text, allow_short=True):
    """How much of a series name appears, in order, in the printed cell (0..1). A short
    name ("Clock", "Blondie") must appear whole: a few letters in order prove nothing."""
    n, t = _norm(name), _norm(text)
    if len(n) < 5 or not t:
        return 0.0
    if n in t:
        return 1.0
    if len(n) < 9:
        return 0.0
    blocks = [b for b in difflib.SequenceMatcher(None, n, t, autojunk=False).get_matching_blocks() if b.size >= 3]
    if not blocks:
        return 0.0
    span = blocks[-1].b + blocks[-1].size - blocks[0].b
    if span > len(n) * 1.5 + 3:  # scattered letters across a long cell are not the name
        return 0.0
    sm_blocks = difflib.SequenceMatcher(None, n, t, autojunk=False).get_matching_blocks()
    got = sum(b.size for b in blocks)
    loose = sum(b.size for b in sm_blocks if b.size >= 2)
    # the paper often prints a shortened name ("Readers Digest" for Radio Reader's Digest):
    # a cell of eight or more letters read almost whole inside the name counts as the name
    short = loose / len(t) if got >= 8 and len(n) * 0.5 <= len(t) <= len(n) else 0.0
    return max(got / len(n), short if allow_short else 0.0)


# ---------------------------------------------------------------- the catalog side

class Catalog:
    """Served episodes by date, with each series' names (the served projection is what
    a listener can play; the registry adds the names a series was printed under)."""

    def __init__(self, projection=PROJECTION, registry=REGISTRY):
        self.db = sqlite3.connect(f"file:{projection}?mode=ro", uri=True)
        self.names = collections.defaultdict(set)
        for key, name in self.db.execute("SELECT key, name FROM series"):
            self.names[key].add(name)
        if registry and os.path.exists(registry):
            reg = sqlite3.connect(f"file:{registry}?mode=ro", uri=True)
            for key, alias in reg.execute("SELECT series_key, alias FROM series_aliases"):
                if key in self.names and alias and not re.search(r"\d", alias) and len(alias) <= 40:
                    self.names[key].add(alias)
        self._by_date = {}

    def episodes_on(self, date):
        if date not in self._by_date:
            rows = self.db.execute(
                "SELECT e.id, e.series_key, s.name, e.network, e.length_s, e.title, e.rights, e.no_recommend "
                "FROM episodes e JOIN series s ON s.key = e.series_key WHERE e.air_date = ?", (date,)).fetchall()
            self._by_date[date] = [dict(zip(("id", "series_key", "series", "network", "length_s", "title", "rights",
                                              "no_recommend"), r)) for r in rows]
        return self._by_date[date]

    def identify(self, text, date):
        """A gap's printed text read as a known series active that year (for the station
        card: "Mr. District Attorney aired here"); None when nothing reads clearly."""
        if not hasattr(self, "_tok"):
            self._tok = collections.defaultdict(set)
            self._span = {}
            for key, name, first, last in self.db.execute("SELECT key, name, first_date, last_date FROM series"):
                self._span[key] = (first or "0000", last or "9999", name)
                for n in self.names.get(key, {name}):
                    for w in re.findall(r"[a-z]{5,}", n.lower()):
                        self._tok[w].add(key)
        keys = set()
        for w in re.findall(r"[a-z]{5,}", text.lower()):
            if len(self._tok.get(w, ())) <= 60:
                keys |= self._tok.get(w, set())
        best, who = 0.0, None
        for key in keys:
            first, last, name = self._span[key]
            if not (first[:4] <= date[:4] <= last[:4]):
                continue
            # a one-word name ("Edward", "Beulah") inside a cell names nothing for certain
            sc = max((name_score(n, text) for n in self.names.get(key, {name}) if len(_norm(n)) >= 9), default=0.0)
            if sc > best:
                best, who = sc, name
        return who if best >= 0.92 else None

    def episode_network(self, eid):
        r = self.db.execute("SELECT network FROM episodes WHERE id = ?", (eid,)).fetchone()
        return r[0] if r else None

    def series_name(self, key):
        r = self.db.execute("SELECT name FROM series WHERE key = ?", (key,)).fetchone()
        return r[0] if r else key

    def served(self, eid):
        """May this episode fill a slot tonight? Only a row the served projection holds, and
        never a never-recommended one (contract §9.4). A row hidden by rights is not here."""
        r = self.db.execute("SELECT no_recommend FROM episodes WHERE id = ?", (eid,)).fetchone()
        return bool(r) and not r[0]


def net_family(n):
    n = (n or "").lower()
    for fam in ("nbc blue", "blue", "cbs", "nbc", "mutual", "abc"):
        if fam in n:
            return {"nbc blue": "blue", "blue": "blue"}.get(fam, fam)
    return None


def match_slots(slots, date, network, cat, threshold=0.84):
    """Give each slot the served episode of its own program on its own date, or a gap.
    Only episodes whose air_date == date are candidates (R9): no other date can fill a
    slot. A name the grid wrapped over two or three rows is read across them, and those
    rows become one slot."""
    cands = [ep for ep in cat.episodes_on(date)
             if not ep["no_recommend"]  # contract §9.4: never in an evening
             and not (net_family(ep["network"]) and net_family(network)
                     and net_family(ep["network"]) != net_family(network))]
    scored = []
    for i in range(len(slots)):
        for k in (1, 2, 3):
            if i + k > len(slots):
                break
            text = " ".join(s["printed"] for s in slots[i:i + k])
            for ep in cands:
                best = max((name_score(n, text) for n in cat.names.get(ep["series_key"], {ep["series"]})),
                           default=0.0)
                if best >= threshold:
                    # ties go to the window that holds more of the series' own name ("Abbott
                    # S / Costello" over "Costello"), then to the shorter window
                    cover = name_score(ep["series"], text, allow_short=False)  # of the series' own name
                    scored.append((best, cover, k, i, ep))
    scored.sort(key=lambda t: (-t[0], -t[1], t[2], t[3]))
    taken, used, busy = {}, set(), set()
    for score, _, k, i, ep in scored:
        span = set(range(i, i + k))
        if span & busy or ep["series_key"] in used:
            continue
        taken[i] = (k, dict(ep, score=round(score, 3)))
        busy |= span
        used.add(ep["series_key"])
    out = []
    i = 0
    while i < len(slots):
        if i in taken:
            k, ep = taken[i]
            s = {"start": slots[i]["start"], "end": slots[i + k - 1]["end"],
                 "printed": " / ".join(x["printed"] for x in slots[i:i + k])}
            assert ep_date(ep["id"], cat) == date  # R9, at the point of use
            s["episode"] = {"id": ep["id"], "series": ep["series"], "title": ep["title"], "rights": ep["rights"],
                            "length_s": ep["length_s"], "match": ep["score"]}
            i += k
        else:
            s = dict(slots[i], gap=True)
            known = cat.identify(s["printed"], date)
            if known:
                s["known_series"] = known
            i += 1
        out.append(s)
    # the recording says how long the program ran: a 29-minute episode filled its half hour,
    # so a stray fragment the grid read in its second quarter is part of it, not a program
    merged = []
    for s in out:
        prev = merged[-1] if merged else None
        if (prev and prev.get("episode") and s.get("gap") and prev["episode"]["length_s"]
                and s["start"] == prev["end"]):
            need = max(15, int(round(prev["episode"]["length_s"] / 60 / 15)) * 15)
            if s["end"] - prev["start"] <= need:
                prev["end"] = s["end"]
                prev["printed"] += " / " + s["printed"]
                continue
        merged.append(s)
    return merged


def refuse_bleed(slots, station, stations, network, cat):
    """A name the OCR read into two columns at once: the station whose cell reads it better
    keeps it; on a tie only a station of the episode's recorded network does. Otherwise the
    slot is a gap, not a guess."""
    out = []
    for s in slots:
        ep = s.get("episode")
        if ep:
            key = ep["id"].split("|")[0]
            names = cat.names.get(key, {ep["series"]})
            mine = max(name_score(n, s["printed"]) for n in names)
            rival = 0.0
            for other in stations:
                if other is station:
                    continue
                for o in other["slots"]:
                    if o["start"] < s["end"] and o["end"] > s["start"]:
                        rival = max(rival, max(name_score(n, o["printed"]) for n in names))
            own_net = net_family(cat.episode_network(ep["id"])) == net_family(network)
            if rival > mine or (rival == mine and rival > 0 and not own_net):
                s = {k: v for k, v in s.items() if k != "episode"}
                s["gap"] = True
                s["refused"] = "the name is printed in another station's column at this hour"
        out.append(s)
    return out


def ep_date(eid, cat):
    r = cat.db.execute("SELECT air_date FROM episodes WHERE id = ?", (eid,)).fetchone()
    return r[0] if r else None


def coverage(slots, window=PRIME):
    lo, hi = window
    total = hi - lo
    have = 0
    for s in slots:
        if s.get("episode"):
            a, b = max(lo, s["start"]), min(hi, s["end"])
            if b > a:
                have += b - a
    return have / total


def hhmm(m):
    return f"{m // 60 % 24:02d}:{m % 60:02d}"


def build_evening(date, network, cat, fetch=True, paper="w"):
    """One network's evening on one date, or (None, reason)."""
    pdf, url = pdf_for(paper, date, fetch=fetch)
    if not pdf:
        return None, "no log" if not url else "log not fetched"
    try:
        words = words_of(pdf)
    except subprocess.CalledProcessError:  # a page JJ's serves that poppler cannot open: a finding
        return None, "pdf unreadable"
    grid, err = parse_grid(words, date)
    if err:
        return None, err
    st = [s for s in grid["stations"] if net_family(s["network"]) == net_family(network)]
    if not st:
        return None, f"no {network} station in the grid"
    station = st[0]
    prime = [s for s in station["slots"] if s["end"] > PRIME[0] - 60 and s["start"] < PRIME[1] + 60]
    slots = refuse_bleed(match_slots(prime, date, network, cat), station, grid["stations"], network, cat)
    witness = {"paper": PAPERS[paper], "station": station["call"], "network_from": station["network_from"],
               "url": url, "via": "JJ's Newspaper Radio Logs (jjonz.us)", "printed_zone": grid["printed_zone"]}
    return {
        "date": date, "weekday": dt.date.fromisoformat(date).strftime("%A"), "network": network,
        "station": station["call"], "zone": "ET", "witness": witness,
        "grid_rows": grid["rows"], "hour_disagreements": grid["hour_disagreements"],
        "evening_disagreements": grid["evening_disagreements"],
        "prime_rows": grid["prime_rows"], "last_row": grid["last_row"], "readable": grid["readable"],
        "coverage": round(coverage(slots), 3),
        "slots": [{"et_start": hhmm(s["start"]), "et_end": hhmm(s["end"]), "length_min": s["end"] - s["start"],
                   "printed": s["printed"], **({"episode": s["episode"]} if s.get("episode") else
                      {"gap": True, **{k: s[k] for k in ("known_series", "refused") if s.get(k)}})}
                  for s in slots],
    }, None


# ---------------------------------------------------------------- measuring and publishing

def evenings_cache():
    return os.path.join(CACHE, "radiologs", "evenings.jsonl")


def load_measured():
    out = {}
    p = evenings_cache()
    if os.path.exists(p):
        for line in open(p):
            r = json.loads(line)
            out[(r["date"], r["network"])] = r
    return out


def measure(dates, networks, cat, fetch=True):
    done = load_measured()
    with open(evenings_cache(), "a") as f:
        for d in dates:
            for net in networks:
                if (d, net) in done:
                    continue
                try:
                    ev, err = build_evening(d, net, cat, fetch=fetch)
                except RuntimeError as e:
                    print(f"FETCH {d}: {e}", file=sys.stderr, flush=True)
                    continue
                if err == "log not fetched":  # not measured yet, not a finding
                    continue
                rec = ev if ev else {"date": d, "network": net, "error": err}
                done[(d, net)] = rec
                f.write(json.dumps(rec) + "\n")
                f.flush()
                print(d, net, rec.get("coverage", rec.get("error")), flush=True)
    return done


def sample_dates(n, y0=1935, y1=1955, seed=1947):
    rnd = random.Random(seed)
    span = (dt.date(y1, 12, 31) - dt.date(y0, 1, 1)).days
    return sorted({(dt.date(y0, 1, 1) + dt.timedelta(days=rnd.randrange(span + 1))).isoformat() for _ in range(n)})


def anniversary_dates(start, days, y0=1935, y1=1955):
    out = []
    for i in range(days):
        d = start + dt.timedelta(days=i)
        for y in range(y0, y1 + 1):
            try:
                out.append(dt.date(y, d.month, d.day).isoformat())
            except ValueError:
                pass
    return out


def anniversaries(day, measured):
    """Every readable evening on this calendar date in which a program survives, one per
    year (that year's best network), oldest year first."""
    best = {}
    for r in measured.values():
        if "coverage" in r and r.get("readable") and r["coverage"] > 0 and r["date"][5:] == day.strftime("%m-%d"):
            y = r["date"][:4]
            if y not in best or (r["coverage"], r["network"]) > (best[y]["coverage"], best[y]["network"]):
                best[y] = r
    return [best[y] for y in sorted(best)]


def pick_tonight(day, measured):
    """Decisions 058 and 067: this calendar date in its best-surviving year when any program
    of that evening survives; else the best evening for this weekday. Never a stitched
    evening, and never one with nothing to play."""
    best = max(anniversaries(day, measured), key=lambda r: (r["coverage"], r["date"]), default=None)
    if best:
        return best, "anniversary"
    ok = [r for r in measured.values() if "coverage" in r and r.get("readable") and r["coverage"] > 0]
    wk = [r for r in ok if dt.date.fromisoformat(r["date"]).weekday() == day.weekday()]
    alt = max(wk, key=lambda r: (r["coverage"], r["date"]), default=None)
    return alt, "weekday"


def _mins(et):
    """Minutes after the evening's midnight; the small hours belong to the night before."""
    h, m = (int(x) for x in et.split(":"))
    return (h + (24 if h < 4 else 0)) * 60 + m


def to_utc(day, et):
    """Tonight's replay: the printed Eastern wall clock on today's date, as UTC."""
    from zoneinfo import ZoneInfo
    h, m = (int(x) for x in et.split(":"))
    if h < 4:
        day = day + dt.timedelta(days=1)
    local = dt.datetime(day.year, day.month, day.day, h, m, tzinfo=ZoneInfo(ZONE))
    return local.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def window(today):
    """The published window for a build on `today` (its UTC date): (first day, number of days)."""
    return today - dt.timedelta(days=WINDOW_BACK), WINDOW_BACK + 1 + WINDOW_AHEAD


def slot_coverage(slots, window=PRIME):
    lo, hi = window
    have = 0
    for s in slots:
        if s.get("episode"):
            a, b = max(lo, _mins(s["et_start"])), min(hi, _mins(s["et_start"]) + s["length_min"])
            have += max(0, b - a)
    return round(have / (hi - lo), 3)


def withhold(slots, served, forward=None):
    """Each slot whose episode `served` refuses becomes a gap marked `withheld` (a recording
    that exists but this projection does not serve: hidden by rights, taken down, never
    recommended), so no unserved episode ever fills a slot. An id that moved (`forward`,
    contract §3.5) follows its alias instead; a tombstoned id is a gap. Returns (slots, changed)."""
    out, changed = [], False
    for s in slots:
        ep = s.get("episode")
        if ep and not served(ep["id"]):
            to = (forward or {}).get(ep["id"])
            if to:
                s = dict(s, episode=dict(to))
            else:
                s = {k: v for k, v in s.items() if k != "episode"}
                s.update(gap=True, withheld=True, **({"known_series": ep["series"]} if ep.get("series") else {}))
            changed = True
        out.append(s)
    return out, changed


def served_evening(rec, served):
    """A measured evening as the served projection can play it now: coverage counts only
    served episodes, so the pick sees what a listener would hear."""
    if not served or "slots" not in rec:
        return rec
    slots, changed = withhold(rec["slots"], served)
    return dict(rec, slots=slots, coverage=slot_coverage(slots)) if changed else rec


# What a published slot carries. The paper's OCR text (`printed`) is not among them: a gap
# shows its time and, when the listing matched a series, that series' name (`known_series`),
# never the newspaper's text (Decision 067). The measured cache keeps it as witness.
SLOT_KEYS = ("et_start", "et_end", "length_min", "episode", "gap", "known_series", "withheld", "refused")


def published_slots(day, slots):
    return [dict({k: json.loads(json.dumps(s[k])) for k in SLOT_KEYS if k in s},
                 utc_start=to_utc(day, s["et_start"]), utc_end=to_utc_end(day, s))
            for s in slots if _mins(s["et_end"]) > PRIME[0] and _mins(s["et_start"]) < PRIME[1]]


def published_evening(day, ev):
    return {"evening": ev["date"], "network": ev["network"], "station": ev["station"],
            "coverage": ev["coverage"], "witness": ev["witness"], "slots": published_slots(day, ev["slots"])}


def other_years(day, measured, picked):
    """Decision 067: a listener may pick another published year for the same date. Each is
    a whole evening of its own (never stitched), served only, replayed on today's clock."""
    return [published_evening(day, r) for r in anniversaries(day, measured) if r["date"] != picked]


def tonight(start, days, measured, served=None):
    out = {"schemaVersion": 1, "zone": ZONE, "window_et": [hhmm(PRIME[0]), hhmm(PRIME[1])],
           "rule": "Decisions 058 and 067: the anniversary in its best-surviving year when any program survives, "
                   "else the best evening for the weekday; gaps are gaps (R9); years are the date's other "
                   "published years", "days": {}}
    measured = {k: served_evening(r, served) for k, r in measured.items()}
    for i in range(days):
        day = start + dt.timedelta(days=i)
        ev, why = pick_tonight(day, measured)
        if not ev:
            continue
        out["days"][day.isoformat()] = dict(published_evening(day, ev), picked=why,
                                            years=other_years(day, measured, ev["date"]))
    return out


def to_utc_end(day, s):
    start = dt.datetime.strptime(to_utc(day, s["et_start"]), "%Y-%m-%dT%H:%M:%SZ")
    return (start + dt.timedelta(minutes=s["length_min"])).strftime("%Y-%m-%dT%H:%M:%SZ")


DAYCODE = {"M": 0, "Tu": 1, "W": 2, "Th": 3, "F": 4, "Sa": 5, "Su": 6}


def otrr_times(registry=REGISTRY):
    """OTRR's logged regular slot per series: {(series_key, family): [(start, end, weekdays, minutes)]}."""
    out = collections.defaultdict(list)
    if not registry or not os.path.exists(registry):
        return out
    reg = sqlite3.connect(f"file:{registry}?mode=ro", uri=True)
    for key, net, start, end, day, tm in reg.execute(
            "SELECT series_key, network, start, end, day, time FROM program_runs WHERE time != ''"):
        m = re.match(r"(\d{1,2}):(\d\d)\s*([AP])M", tm or "")
        if not m:
            continue
        h = int(m.group(1)) % 12 + (12 if m.group(3) == "P" else 0)
        days = {DAYCODE[d] for d in (day or "").split(",") if d in DAYCODE} or set(range(7))  # no day logged: any
        out[(key, net_family(net))].append((start or "0000", end or "9999", days, h * 60 + int(m.group(2))))
    return out


def report(measured, floors=(0.1, 0.15, 0.2, 0.25, 1 / 3, 0.4, 0.5, 0.6)):
    """The numbers the floor is chosen from (printed; the caller writes them into the docs)."""
    recs = list(measured.values())
    ok = [r for r in recs if "coverage" in r]
    readable = [r for r in ok if r.get("readable")]
    lines = [f"evenings attempted {len(recs)}; parsed {len(ok)}; readable {len(readable)}"]
    errs = collections.Counter(r.get("error") for r in recs if "error" in r)
    lines.append(f"not parsed: {dict(errs)}")
    unread = collections.Counter((r["date"][:4]) for r in ok if not r.get("readable"))
    lines.append(f"parsed but unreadable, by year: {dict(sorted(unread.items()))}")

    def dist(rs, label):
        cs = sorted(r["coverage"] for r in rs)
        if not cs:
            return f"{label}: none"
        pct = lambda p: cs[min(len(cs) - 1, int(p * len(cs)))]
        zero = sum(1 for c in cs if c == 0)
        above = " ".join(f">={f:.2f}:{sum(1 for c in cs if c >= f - 1e-9)}" for f in floors)
        return (f"{label}: n={len(cs)} zero={zero} median={pct(0.5):.3f} p75={pct(0.75):.3f} p90={pct(0.9):.3f} "
                f"max={cs[-1]:.3f} mean={sum(cs) / len(cs):.3f} | {above}")
    lines.append(dist(readable, "all readable"))
    for net in ("CBS", "NBC"):
        lines.append(dist([r for r in readable if r["network"] == net], net))
    for y0 in range(1935, 1956, 3):
        lines.append(dist([r for r in readable if y0 <= int(r["date"][:4]) < y0 + 3], f"{y0}-{y0 + 2}"))
    for wd in range(7):
        lines.append(dist([r for r in readable if dt.date.fromisoformat(r["date"]).weekday() == wd],
                          dt.date(2024, 1, 1 + wd).strftime("%A")))
    # anniversaries: for each calendar date measured in many years, its best evening
    by_md = collections.defaultdict(list)
    for r in readable:
        by_md[r["date"][5:]].append(r)
    full = {md: rs for md, rs in by_md.items() if len({r["date"] for r in rs}) >= 10}
    if full:
        best = {md: max(rs, key=lambda r: r["coverage"]) for md, rs in sorted(full.items())}
        lines.append("best anniversary evening per calendar date (dates measured in 10+ years): " +
                     ", ".join(f"{md} {b['date'][:4]} {b['network']} {b['coverage']:.2f}" for md, b in best.items()))
        lines.append("calendar dates whose best anniversary clears the floor: " +
                     " ".join(f">={f:.2f}:{sum(1 for b in best.values() if b['coverage'] >= f - 1e-9)}/{len(best)}"
                              for f in floors))
    hist = collections.Counter(min(9, int(r["coverage"] * 10)) for r in readable)
    lines.append("histogram (tenths): " + " ".join(f"{k / 10:.1f}-:{hist.get(k, 0)}" for k in range(10)))
    # time check: each matched slot against OTRR's logged regular time for that series
    runs = otrr_times()
    agree = differ = none = 0
    off = collections.Counter()
    for r in readable:
        wd = dt.date.fromisoformat(r["date"]).weekday()
        for s in r["slots"]:
            if not s.get("episode"):
                continue
            key = s["episode"]["id"].split("|")[0]
            cands = [t for (a, b, days, t) in runs.get((key, net_family(r["network"])), [])
                     if a <= r["date"] <= b and wd in days]
            if not cands:
                none += 1
                continue
            h, m = (int(x) for x in s["et_start"].split(":"))
            got = h * 60 + m
            if got in cands:
                agree += 1
            else:
                differ += 1
                off[min((got - c for c in cands), key=abs)] += 1
    lines.append(f"matched slots vs OTRR logged time: agree {agree}, differ {differ}, no OTRR time {none}; "
                 f"differences in minutes (most common): {dict(off.most_common(8))}")
    return "\n".join(lines)


EVENING_KEYS = ("evening", "network", "station", "coverage", "witness", "slots")


def withhold_day(v, served, forward=None):
    """A published day with each episode `served` refuses withheld, in its evening and in
    every other year it offers (a year left with nothing to play is no longer offered)."""
    slots, changed = withhold(v["slots"], served, forward)
    out = dict(v, slots=slots, coverage=slot_coverage(slots)) if changed else v
    if v.get("years"):
        years = []
        for y in v["years"]:
            ys, yc = withhold(y["slots"], served, forward)
            years.append(dict(y, slots=ys, coverage=slot_coverage(ys)) if yc else y)
        out = dict(out, years=[y for y in years if y["coverage"] > 0])
    return out


def keep_published(new, old, start, served=None, forward=None):
    """Contract §8: a day once published keeps its evening and slots; days before the window
    drop off. A kept day takes the new build's other years (an offer beside the evening,
    never the evening itself), and the paper's text leaves it. The one change its evening
    can take is a withdrawal: an episode the served projection no longer serves becomes a
    withheld gap (unclaimed recordings are removed on request), or follows its id's alias."""
    days = dict(new["days"])
    for d, v in old.get("days", {}).items():
        if d >= start:
            kept = dict(v, slots=[{k: x for k, x in s.items() if k != "printed"} for s in v.get("slots", [])])
            w = new["days"].get(d)
            if w is not None:
                offer = list(w.get("years") or [])
                if w.get("picked") == "anniversary":
                    offer.append({k: w[k] for k in EVENING_KEYS})
                kept["years"] = sorted((y for y in offer if y["evening"] != v["evening"]), key=lambda y: y["evening"])
            days[d] = kept
    if served:
        days = {d: withhold_day(v, served, forward) for d, v in days.items()}
    return dict(new, days=dict(sorted(days.items())))


def changed_days(old, new, start, forward=None):
    """The published days (on or after `start`) the new file would change, beyond a
    withdrawal. Empty is the never-change rule holding."""
    def plain(day):
        return [(s["et_start"], s["et_end"], (s.get("episode") or {}).get("id"))
                for s in day["slots"]]
    bad = []
    for d, v in old.get("days", {}).items():
        if d < start:
            continue
        w = new.get("days", {}).get(d)
        if w is None or w["evening"] != v["evening"] or w["network"] != v["network"]:
            bad.append(d)
            continue
        a, b = plain(v), plain(w)
        if len(a) != len(b) or any(x[:2] != y[:2] or (y[2] and y[2] != x[2] and y[2] != ((forward or {}).get(x[2]) or {}).get("id"))
                             for x, y in zip(a, b)):
            bad.append(d)
    return bad


def for_web(doc, web_dir):
    """The web's tonight.json: the same evenings (one clock on every platform), each slot
    whose episode the web projection does not serve withheld. The web projection's own
    episode shards decide, so the public-web gate is applied once, upstream."""
    sys.path.insert(0, os.path.dirname(__file__))
    from build_web_projection import shard_of
    shards = {}

    def served(eid):
        k = shard_of(eid)
        if k not in shards:
            p = os.path.join(web_dir, "episodes", f"{k}.json")
            shards[k] = json.load(open(p)) if os.path.exists(p) else {}
        return eid in shards[k]
    return dict(doc, days={d: withhold_day(v, served) for d, v in doc["days"].items()})


def _today(s):
    return dt.date.fromisoformat(s) if s else dt.datetime.now(dt.timezone.utc).date()


def main():
    global FETCH_BUDGET
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("index")
    a.add_argument("--years", default="1935-1955")
    a = sub.add_parser("evening")
    a.add_argument("date")
    a.add_argument("network")
    a = sub.add_parser("measure")
    a.add_argument("--sample", type=int, default=0)
    a.add_argument("--anniversaries", default="")
    a.add_argument("--days", type=int, default=14)
    a.add_argument("--networks", default="CBS,NBC")
    a.add_argument("--offline", action="store_true")
    a.add_argument("--window", action="store_true", help="the anniversaries of the published window (--today)")
    a.add_argument("--today", default="")
    a.add_argument("--max-fetch", type=int, default=None, help="PDFs this run may download")
    a = sub.add_parser("fetch")
    a.add_argument("--sample", type=int, default=0)
    a.add_argument("--anniversaries", default="")
    a.add_argument("--days", type=int, default=14)
    a = sub.add_parser("report")
    a = sub.add_parser("tonight")
    a.add_argument("--today", default="", help="the build's UTC date (default: now)")
    a.add_argument("--previous", default="", help="the tonight.json published now (missing = first publish)")
    a.add_argument("--out", required=True)
    a = sub.add_parser("web")
    a.add_argument("--src", required=True, help="the native tonight.json")
    a.add_argument("--web", required=True, help="the web projection's directory")
    a.add_argument("--out", required=True)
    a = sub.add_parser("kept")
    a.add_argument("--old", required=True)
    a.add_argument("--new", required=True)
    a.add_argument("--today", default="")
    a.add_argument("--projection", default=PROJECTION, help="the projection whose aliases a slot may follow")
    args = ap.parse_args()
    if args.cmd == "index":
        y0, y1 = (int(x) for x in args.years.split("-"))
        missing = fetch_index(y0, y1)
        print("missing month pages:", missing)
        return 0
    if args.cmd == "web":
        doc = for_web(json.load(open(args.src)), args.web)
        with open(args.out, "w") as f:
            json.dump(doc, f, indent=1)
        filled = sum(1 for v in doc["days"].values() for s in v["slots"] if s.get("episode"))
        print("wrote", args.out, len(doc["days"]), "days,", filled, "slots the web serves")
        return 0
    if args.cmd == "kept":
        start, _ = window(_today(args.today))
        old = json.load(open(args.old)) if os.path.exists(args.old) else {}
        bad = changed_days(old, json.load(open(args.new)), start.isoformat(), episode_forwards(args.projection))
        kept = sum(1 for d in old.get("days", {}) if d >= start.isoformat())
        print(f"published days kept: {kept - len(bad)} of {kept}" + (f"; changed: {bad}" if bad else ""))
        return 1 if bad else 0
    if args.cmd not in ("fetch",):
        cat = Catalog()
    if args.cmd == "evening":
        ev, err = build_evening(args.date, args.network, cat)
        if err:
            print("no evening:", err)
            return 1
        print(json.dumps({k: v for k, v in ev.items() if k != "slots"}, indent=1))
        for s in ev["slots"]:
            tag = f"{s['episode']['series']} -- {s['episode']['title']} ({s['episode']['match']})" if s.get("episode") else "GAP"
            print(f"  {s['et_start']}-{s['et_end']} ET  {s['printed'][:44]:44}  {tag}")
        return 0
    if args.cmd == "fetch":
        dates = sample_dates(args.sample) if args.sample else []
        if args.anniversaries:
            dates += anniversary_dates(dt.date.fromisoformat(args.anniversaries), args.days)
        got = miss = 0
        for d in sorted(set(dates)):
            try:
                path, url = pdf_for("w", d)
            except RuntimeError as e:
                print("FAIL", d, e, flush=True)
                miss += 1
                continue
            got += bool(path)
            miss += not path
            print(d, "ok" if path else ("no log" if not url else "missing"), flush=True)
        print("fetched", got, "missing", miss)
        return 0 if got else 1
    if args.cmd == "measure":
        FETCH_BUDGET = args.max_fetch
        nets = args.networks.split(",")
        dates = sample_dates(args.sample) if args.sample else []
        if args.anniversaries:
            dates += anniversary_dates(dt.date.fromisoformat(args.anniversaries), args.days)
        if args.window:  # nearest day first, so a capped run fills the days listeners reach soonest
            dates += anniversary_dates(*window(_today(args.today)), *YEARS)
        before = len(load_measured())
        done = measure(list(dict.fromkeys(dates)), nets, cat, fetch=not args.offline)
        save_url_map()
        left = "" if FETCH_BUDGET is None else f"; fetch budget left {FETCH_BUDGET} of {args.max_fetch}"
        print(f"measured {len(done)} (+{len(done) - before}){left}")
        return 0
    if args.cmd == "report":
        print(report(load_measured()))
        return 0
    if args.cmd == "tonight":
        start, days = window(_today(args.today))
        doc = tonight(start, days, load_measured(), served=cat.served)
        new_days = set(doc["days"])
        old = json.load(open(args.previous)) if args.previous and os.path.exists(args.previous) else {}
        doc = keep_published(doc, old, start.isoformat(), served=cat.served, forward=episode_forwards(PROJECTION))
        with open(args.out, "w") as f:
            json.dump(doc, f, indent=1)
        kept = [d for d in doc["days"] if d in old.get("days", {})]
        print(f"wrote {args.out}: {len(doc['days'])} days ({len(kept)} kept as published, "
              f"{len(new_days - set(kept))} new) for {start} + {days} days; "
              f"{sum(len(v.get('years') or []) for v in doc['days'].values())} other years offered")
        return 0 if doc["days"] else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
