#!/usr/bin/env python3
"""
test_pulse_collect.py — the dashboard's readers, held to the one property that
matters: a reader that cannot read must SAY SO, never report a confident zero.

Every case is a defect that happened once. No case touches the network: the
drop box is a local HTTP server, and main() runs against stubbed SOURCES.

  python3 tools/test_pulse_collect.py
"""
from __future__ import annotations

import base64
import contextlib
import gzip
import http.server
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

os.environ["PULSE_CONFIG"] = "/nonexistent/pulse.config.json"
os.environ["PULSE_NO_APP_CONFIG"] = "1"
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import pulse_collect as P  # noqa: E402

PASS = FAIL = 0


def check(name, got, want):
    global PASS, FAIL
    if got == want:
        PASS += 1
        print(f"  ok   {name}")
    else:
        FAIL += 1
        print(f"  FAIL {name}: got {got!r}, want {want!r}")


# An app to test against. Nothing here is a real product.
P.ID = P.identity({
    "product": {"name": "Sample App", "site": "https://sample.example", "repo": "o/r"},
    "mentions": {"strict": ["sample.example", "sampleapp"], "loose": "sample app",
                 "corroborate": ["apple tv", "roku", "app store"]},
}, use_app_config=False)


def run_main(argv, sources):
    saved = P.SOURCES
    P.SOURCES = sources
    try:
        sys.argv = ["pulse_collect.py", *argv]
        with contextlib.redirect_stdout(io.StringIO()) as buf:
            rc = P.main()
        return rc, buf.getvalue()
    finally:
        P.SOURCES = saved


# ── relevant(): the filter that makes a fuzzy web search usable ──────────────
# Reddit's search once answered a product query with a post titled "Vintage
# Tissot". A reader with no filter would have called that a mention.
print("relevant()")
for name, args, want in [
    ("strict domain", ("Neat find", "check sample.example for it", ""), True),
    ("strict one word", ("sampleapp on Apple TV", "", ""), True),
    ("strict in url", ("", "", "https://sample.example/item/x"), True),
    ("loose + corroborate", ("Sample App", "great on apple tv", ""), True),
    ("loose alone", ("a sample app for my class", "", ""), False),
    ("reddit false positive", ("Vintage Tissot", "watch collectors thread", ""), False),
    ("empty", ("", "", ""), False),
]:
    check(name, P.relevant(*args), want)
_saved = P.ID
P.ID = P.identity({}, use_app_config=False)
check("no mention terms configured -> nothing is relevant (never everything)",
      P.relevant("anything at all", "", ""), False)
P.ID = _saved


# ── WANT / LOVE: a request is a SENTENCE somebody wrote ─────────────────────
print("\nWANT / LOVE")
for name, text, want in [
    ("wish", "I wish it had a watchlist.", True),
    ("please add", "Please add support for Chromecast.", True),
    ("only complaint", "My only complaint is the search is slow.", True),
    ("would be great", "Would be great to have a watchlist.", True),
    ("beta testers", "Let us know if you need beta testers.", False),
    ("plain praise", "The interface is intuitive.", False),
]:
    check(f"want: {name}", bool(P.WANT.search(text)), want)
for name, text, want in [
    ("works well", "Works really well and I love it.", True),
    ("thanks", "Thank you for making this free.", True),
    ("complaint", "The search is slow and it crashes on launch.", False),
    ("a want is not praise", "Would be great to have a watchlist.", False),
]:
    check(f"love: {name}", bool(P.LOVE.search(text)), want)

print("\nasks()")
st = P.blank()
st["reviews"] = [{"store": "App Store", "rating": 4, "title": "Great but",
                  "body": "Works really well. I wish it had a watchlist. There is so much content.",
                  "author": "someone", "date": "2026-09-01", "url": "https://example/r"}]
st["mentions"] = [{"source": "Reddit", "author": "u/x", "url": "https://example/m",
                   "date": "2026-09-02", "excerpt": "Please add Chromecast support."}]
P.asks(st)
check("a request is quoted from the review", any("watchlist" in a["text"] for a in st["asks"]), True)
check("a request is quoted from the mention", any("Chromecast" in a["text"] for a in st["asks"]), True)
check("praise kept separately", any("Works really well" in lv["text"] for lv in st["loves"]), True)
check("a neutral sentence is dropped", any("so much content" in a["text"] for a in st["asks"] + st["loves"]), False)
check("every request carries its link", all(a.get("url") for a in st["asks"]), True)


# ── the Reddit parser against a fixture ─────────────────────────────────────
print("\nparsers")
REDDIT = """<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
 <entry><title>Sample App on Apple TV is great</title>
  <content type="html">&lt;p&gt;Found sample.example today&lt;/p&gt;</content>
  <link href="https://reddit.com/r/appletv/comments/a"/>
  <author><name>/u/someone</name></author><updated>2026-09-08T10:00:00+00:00</updated></entry>
 <entry><title>Vintage Tissot</title><content type="html">watch collectors</content>
  <link href="https://reddit.com/r/watches/comments/b"/>
  <author><name>/u/other</name></author><updated>2026-09-08T11:00:00+00:00</updated></entry>
</feed>"""
ns = {"a": "http://www.w3.org/2005/Atom"}
st = P.blank()
for e in ET.fromstring(REDDIT).findall("a:entry", ns):
    ln = e.find("a:link", ns)
    P._mention(st, "Reddit", e.findtext("a:title", "", ns), e.findtext("a:content", "", ns),
               ln.get("href") if ln is not None else "", e.findtext("a:author/a:name", "", ns),
               e.findtext("a:updated", "", ns))
check("reddit: the real one is kept", len(st["mentions"]), 1)
check("reddit: the watch thread is dropped", any("Tissot" in m["title"] for m in st["mentions"]), False)


# ── a missing cell is NULL, never zero ──────────────────────────────────────
print("\na missing column is null, never zero")
check("blank cell", P.num_or_none(""), None)
check("absent cell", P.num_or_none(None), None)
check("a real zero stays zero", P.num_or_none("0"), 0)
check("thousands and percent", P.num_or_none("1,204"), 1204)
check("total of nothing is None, not 0", P.total([None, None]), None)
check("total skips the missing", P.total([3, None, 4]), 7)


# ── Play's report CSVs: gzip + UTF-16 + CRLF, all three at once ─────────────
print("\nPlay report CSVs")
raw = gzip.compress(("Date,Daily Device Installs\r\n2026-09-01,29\r\n2026-09-02,31\r\n").encode("utf-16"))
rows = P.play_csv(raw)
check("gzipped UTF-16 CRLF parses to rows", [r["Daily Device Installs"] for r in rows], ["29", "31"])
check("the header is not mojibake", list(rows[0].keys()), ["Date", "Daily Device Installs"])


# ── Apple's sales report: vendor-wide, and two product-code families ────────
print("\nApple sales report")
TSV = "\t".join(["Apple Identifier", "Units", "Product Type Identifier", "Device", "Country Code", "Version"]) + "\n" + "\n".join([
    "\t".join(["111", "5", "1", "iPhone", "US", "1.0"]),
    "\t".join(["111", "2", "1T", "iPad", "GB", "1.0"]),
    "\t".join(["111", "3", "F1", "Desktop", "US", "1.0"]),       # Mac: a DIFFERENT family
    "\t".join(["111", "9", "7", "iPhone", "US", "1.0"]),         # an update: not a new person
    "\t".join(["111", "4", "ZZ9", "Apple TV", "US", "1.0"]),     # a code nobody has seen
    "\t".join(["999", "50", "1", "iPhone", "US", "3.0"]),        # ANOTHER app on the same vendor
])
units, by_dev, by_country, by_version, skipped, dc, dv = P.apple_sales_rows(TSV, "111")
check("another app in the vendor-wide report is not counted", units, 10)
check("Mac first downloads (F1) are counted", by_dev.get("Desktop"), 3)
check("updates are recorded as skipped, with units", skipped.get("7"), 9)
check("an UNKNOWN product code is recorded, never silently dropped", skipped.get("ZZ9"), 4)
check("per-device countries are that device's own", dc.get("Desktop"), {"US": 3})
check("a header without Units is unreadable, not zero",
      P.apple_sales_rows("Apple Identifier\tDevice\n111\tiPhone", "111"), None)


# ── Amazon: free installs are $0 Charge rows ────────────────────────────────
print("\nAmazon sales report")
daily, country, kinds = P.amazon_sales_rows([
    {"Transaction Type": "Charge", "Transaction Time": "2026-09-10T12:00:00Z", "Country/Region Code": "US"},
    {"Transaction Type": "Charge", "Transaction Time": "2026-09-10T15:00:00Z", "Country/Region Code": "GB"},
    {"Transaction Type": "Refund", "Transaction Time": "2026-09-11T10:00:00Z", "Country/Region Code": "US"},
])
check("each Charge row is an install", daily, {"2026-09-10": 2})
check("a refund is not an install", sum(daily.values()), 2)
check("the transaction-type histogram is kept", kinds, {"Charge": 2, "Refund": 1})


# ── a source that fails is RECORDED; one not configured is OFF ──────────────
print("\nnever a silent zero")


def broken(_state):
    raise RuntimeError("no credential in this environment")


def unset(_state):
    raise P.NotConfigured("set x.y in ops/pulse.config.json")


def fine(state):
    state["github"] = {"stars": 5}
    return "read"


def exits(_state):
    sys.exit("a helper that calls sys.exit must not end the run")


with tempfile.TemporaryDirectory() as tmp:
    out = Path(tmp) / "pulse.json"
    rc, text = run_main(["--apply", "--force", "--out", str(out)],
                        [("broken", broken), ("unset", unset), ("fine", fine), ("exits", exits)])
    got = json.loads(out.read_text())
    check("main() survives a broken source", rc, 0)
    check("a failed source is ok:false with its reason",
          (got["sources"]["broken"]["ok"], "credential" in got["sources"]["broken"]["note"]), (False, True))
    check("a sys.exit() inside a reader is caught and recorded", got["sources"]["exits"]["ok"], False)
    check("an unconfigured source is marked off, not failed", got["sources"]["unset"].get("off"), True)
    check("the run flags never reach the written reading",
          [k for k in got if k in ("_apply", "_prev", "_force")], [])
    check("the reading carries the app block the page reads", got["app"]["name"], "Sample App")


# ── the degraded-run guard ──────────────────────────────────────────────────
print("\na reading that cannot be trusted is refused")
check("a third dark refuses", P.degraded({"a": {"ok": True}, "b": {"ok": True}, "c": {"ok": False}},
                                         {"a", "b", "c"})[2], True)
check("a quarter dark writes", P.degraded({k: {"ok": k != "d"} for k in "abcd"}, set("abcd"))[2], False)
check("not-configured readers do not count as dark",
      P.degraded({"a": {"ok": True}, "b": {"ok": True}, "c": {"ok": False, "off": True},
                  "d": {"ok": False, "off": True}}, set("abcd")), (0, 2, False))
check("readers carried from an earlier reading do not count",
      P.degraded({"a": {"ok": True}, "old": {"ok": False}}, {"a"})[2], False)
with tempfile.TemporaryDirectory() as tmp:
    out = Path(tmp) / "pulse.json"
    rc, text = run_main(["--apply", "--out", str(out)], [("fine", fine), ("broken", broken)])
    check("--apply with half the readers dark writes NOTHING", out.exists(), False)
    check("...and says why", "REFUSING TO WRITE" in text, True)
    check("...and still exits 0 (a reporter never fails on its findings)", rc, 0)
    rc, text = run_main(["--apply", "--force", "--out", str(out)], [("fine", fine), ("broken", broken)])
    check("--force writes it anyway", out.exists(), True)


# ── history: one row per day, append-only, numbers only ─────────────────────
print("\nhistory")
st = P.blank()
st["ratings"] = [{"store": "App Store", "average": 4.4, "count": 5}]
st["social"] = {"totalPosts": 9, "byPlatform": {"bluesky": {"likes": 3}},
                "reach": {"bluesky": {"followers": 12}, "youtube": {"error": "403"}}}
st["github"] = {"stars": 0, "views14d": 20}
st["health"] = {"workflows": [{"severity": "BROKEN"}, {"severity": "STALE"}]}
row = P.history_row(st)
check("one date", row["date"], P.today())
check("likes summed", row["likes"], 3)
check("a reach that could not be read adds nothing, not zero", row["followers"], 12)
check("urgent counts BROKEN, not STALE", row["urgent"], 1)
check("the row holds only scalars", all(not isinstance(v, (list, dict)) for v in row.values()), True)
check("no social programme -> likes is None, not 0", P.history_row(P.blank())["likes"], None)


# ── a partial run must not delete what it did not collect ───────────────────
print("\npartial runs merge")
with tempfile.TemporaryDirectory() as tmp:
    f = Path(tmp) / "pulse.json"
    f.write_text(json.dumps({
        "reviews": [{"store": "App Store", "id": "r1", "rating": 5, "date": "2026-09-01"}],
        "mentions": [{"source": "Mastodon", "url": "u1", "excerpt": "someone said a thing"},
                     {"source": "Reddit", "url": "u2", "excerpt": "another"}],
        "github": {"stars": 3}, "social": {"totalPosts": 9},
        "stores": [{"store": "App Store", "platform": "Apple TV", "state": "READY_FOR_SALE"},
                   {"store": "Google Play", "platform": "Production", "state": "COMPLETED", "version": "old"},
                   {"store": "LG Content Store", "platform": "webOS", "manual": True}],
        "history": [{"date": "2026-01-01", "stars": 3}],
    }))
    r = subprocess.run([sys.executable, str(HERE / "pulse_collect.py"), "--only", "mentions_reddit",
                        "--apply", "--out", str(f)], capture_output=True, text=True, timeout=180,
                       env={**os.environ, "PULSE_CONFIG": "/nonexistent", "PULSE_NO_APP_CONFIG": "1"})
    got = json.loads(f.read_text())
    check("a source it did not run keeps its reviews", len(got["reviews"]), 1)
    check("...and its github reading", got["github"].get("stars"), 3)
    check("...and its social section", got["social"].get("totalPosts"), 9)
    check("a mention found once is not lost when a search does not repeat",
          {m["url"] for m in got["mentions"]} >= {"u1", "u2"}, True)
    check("yesterday's history row survives", any(h["date"] == "2026-01-01" for h in got["history"]), True)

    def play_stub(state):
        state["stores"].append({"store": "Google Play", "platform": "Production", "state": "COMPLETED", "version": "new"})
        return "1 track"
    rc, _ = run_main(["--only", "play_stores", "--apply", "--out", str(f)], [("play_stores", play_stub)])
    got = json.loads(f.read_text())
    stores = {(s["store"], s.get("version")) for s in got["stores"]}
    check("a play_stores re-read keeps the Apple rows", ("App Store", None) in stores, True)
    check("...and the declared rows", ("LG Content Store", None) in stores, True)
    check("...and replaces its own", (("Google Play", "new") in stores, ("Google Play", "old") in stores), (True, False))


# ── every credential the collector reads must reach it in CI ────────────────
# A reports key was set as a repo secret and NOT passed by the workflow: the run
# stayed green and the panel stayed empty. A secret that exists and never
# arrives is indistinguishable from one that was never made.
print("\nthe workflow passes what the collector reads")
_src = (HERE / "pulse_collect.py").read_text()
_wf = (HERE.parent / ".github" / "workflows" / "pulse.yml").read_text()
_names = set(re.findall(r'os\.environ(?:\.get)?[\(\[]"([A-Z][A-Z0-9_]{3,})"', _src))
_names |= set(re.findall(r'"((?:YOUTUBE|AMAZON|ASC|PLAY|BLUESKY|MASTODON|IG|THREADS)_[A-Z0-9_]+)"', _src))
# Written by the key step / set by Actions / local-only overrides of committed config.
_exempt = {"ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH", "PULSE_CONFIG", "PULSE_NO_APP_CONFIG",
           "PULSE_COUNTER", "PULSE_INGEST_ORIGIN", "GITHUB_REPOSITORY", "GITHUB_TOKEN", "MASTODON_BASE_URL"}
check("no credential the collector reads is missing from pulse.yml",
      sorted(n for n in _names - _exempt if n not in _wf), [])

print("\nthe workflow is a dormant reporter")
check("the schedule ships commented out (dormant until configured)",
      bool(re.search(r"^\s{2}schedule:", _wf, re.M)), False)
check("the one step that may fail says why", "# reporter-may-fail:" in _wf, True)
check("the summary step survives a refused (unwritten) reading", "[ -f ops/pulse.json ]" in _wf, True)
check("a release re-read of the stores is written, ready to enable", "workflow_run:" in _wf, True)


# ── every health section a reader writes must be PRESERVED when it fails ────
print("\nevery health section a reader writes is preserved when it fails")
_written = set(re.findall(r'state\["health"\]\["([A-Za-z0-9_]+)"\]\s*=', _src))
_written |= set(re.findall(r'state\["health"\]\.setdefault\("([A-Za-z0-9_]+)"', _src))
_owned = set(P.HEALTH_OWNS.values()) | {k for ks in P.HEALTH_ALSO.values() for k in ks}
check("no health key a reader writes is missing from HEALTH_OWNS", sorted(_written - _owned), [])
check("every HEALTH_OWNS reader exists", sorted(set(P.HEALTH_OWNS) - {n for n, _ in P.SOURCES}), [])
check("every SOURCES name is unique", len({n for n, _ in P.SOURCES}), len(P.SOURCES))


# ── the fleet auditor: 'nothing audited' is not 'no findings' ───────────────
print("\nthe fleet reader refuses a run that audited nothing")


class _Proc:
    def __init__(self, out, rc=0):
        self.stdout, self.stderr, self.returncode = out, "", rc


_real_run = P.subprocess.run
try:
    P.subprocess.run = lambda *a, **k: _Proc("set GITHUB_REPOSITORY=owner/repo (Actions sets it) — nothing audited\n")
    try:
        P.workflows(P.blank())
        check("'nothing audited' raises", False, True)
    except RuntimeError as e:
        check("'nothing audited' raises", "audited nothing" in str(e), True)
    P.subprocess.run = lambda *a, **k: _Proc("Checked 0 workflows, each against its OWN cadence\n")
    try:
        P.workflows(P.blank())
        check("'Checked 0 workflows' raises", False, True)
    except RuntimeError:
        check("'Checked 0 workflows' raises", True, True)
    P.subprocess.run = lambda *a, **k: _Proc("Checked 7 workflows, each against its OWN cadence\n"
                                             "  BROKEN   Deploy                                  red twice\n")
    st = P.blank()
    note = P.workflows(st)
    check("a real audit reports its findings", (st["health"]["workflows"][0]["severity"], "7 workflow" in note),
          ("BROKEN", True))
finally:
    P.subprocess.run = _real_run


# ── Roku: the three shapes of tile, from the REAL headers Looker sent ───────
print("\nRoku tiles: series, tables and empties all survive")


def _zipof(files):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        for n, text in files.items():
            z.writestr(f"dashboard-x/{n}", text)
    buf.seek(0)
    return buf.getvalue()


ROKU_ZIP = _zipof({
    "visits_and_streams.csv": ",date,Visits,Streams\n1,2026-09-12,29,14\n2,2026-09-11,33,16\n",
    "brightscript_crash_logs.csv":
        ",Date,Roku OS Release,App Version,Error Text,Total Count of Crashes\n"
        "1,2026-09-12,14.5.0,00071,&hf4 invalid component,3\n2,2026-09-11,13.0.0,00065,type mismatch,1\n",
    "viewership_details.csv": ",Hardware,Roku Model,Visits\n1,Streaming Stick,3820X,12\n2,Express,3930X,4\n",
    "rebuffers-tile.csv": "Rebuffers per Hours Streamed,Total Rebuffers\n0.13,4\n",
    "malone.csv": ",Date Key Date,Memory Closures Per 1K Hours\n",
})
_daily, _head, _tables, _tiles, _empty = P.roku_parse_zip(zipfile.ZipFile(io.BytesIO(ROKU_ZIP)))
check("a lowercase `date` column still makes a daily series", sorted(_daily), ["2026-09-11", "2026-09-12"])
check("...and its numbers are picked up", _daily.get("2026-09-12", {}).get("Visits"), 29.0)
check("a DATED tile with text is ALSO kept as a table", "brightscript_crash_logs" in _tables, True)
check("an undated multi-row tile is a table", len(_tables.get("viewership_details", [])), 2)
check("a single undated row is a headline", _head.get("Total Rebuffers"), 4.0)
check("a delivered-but-empty tile is RECORDED, not dropped", _empty, ["malone"])
check("a day from a crash-only report carries NO install column (absent, not 0)",
      "Channel Installs" in _daily["2026-09-11"], False)

_v = P.roku_versions_in({"logs": [
    {"Date": "2026-09-12", "App Version": "1.0.9"}, {"Date": "2026-09-10", "App Version": "1.0.75"},
    {"Date": "2026-09-11", "App Version": "1.0.75"}, {"Date": "2026-09-11", "Error Text": "no version"}]})
check("versions sort as numbers (1.0.75 after 1.0.9)", [x["version"] for x in _v], ["1.0.9", "1.0.75"])
check("...with the FIRST day each was seen", _v[1]["firstSeen"], "2026-09-10")


# ── the drop box: a dry run must not consume the delivery ───────────────────
print("\nthe drop box: dry runs leave it, real runs ack it, Cloudflare wants a UA")


class Box(http.server.BaseHTTPRequestHandler):
    rows, acks, uas = [], [], []

    def log_message(self, *a):
        pass

    def do_GET(self):
        Box.uas.append(self.headers.get("User-Agent", ""))
        if "Python-urllib" in Box.uas[-1]:           # what Cloudflare does to a bare client
            self.send_response(403)
            self.end_headers()
            return
        body = json.dumps({"rows": Box.rows}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        Box.acks.append(self.path)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"{}")


srv = http.server.HTTPServer(("127.0.0.1", 0), Box)
threading.Thread(target=srv.serve_forever, daemon=True).start()
P.ID["ingest"] = f"http://127.0.0.1:{srv.server_port}"
os.environ["PULSE_INGEST_TOKEN"] = "t0k"
good = {"id": 1, "body": json.dumps({"scheduled_plan": {"title": "App Health"},
                                     "attachment": {"data": base64.b64encode(ROKU_ZIP).decode()}})}
Box.rows = [good, {"id": 2, "body": "{not json"}]
st = {**P.blank(), "_apply": False}
try:
    note = P.roku_engagement(st)
except Exception as e:                                 # noqa: BLE001 — a 403 here is the UA case below
    note = f"raised: {e}"
check("a dry run acks NOTHING", Box.acks, [])
check("...and says the delivery was left in the box", "left in the box" in note, True)
check("the collector sends its own User-Agent, not Python-urllib",
      all("Pulse" in u and "Python-urllib" not in u for u in Box.uas), True)
check("reports are kept apart by their plan title",
      (st["health"].get("rokuEngagement") or {}).get("reportsSeen"), ["App Health"])
st = {**P.blank(), "_apply": True}
P.roku_engagement(st)
check("a real run acks what it read", [a for a in Box.acks if "id=1" in a] != [], True)
check("...and NEVER acks an unreadable payload (it is the evidence)", [a for a in Box.acks if "id=2" in a], [])
check("the unreadable payload is reported", len(st["health"]["rokuEngagement"]["unreadable"]), 1)

Box.rows, Box.acks = [], []
old = (P.dt.date.today() - P.dt.timedelta(days=10)).isoformat()
st = {**P.blank(), "_prev": {"health": {"rokuEngagement": {"daily": [{"date": old}]}}}}
try:
    P.roku_engagement(st)
    check("a feed quiet for 10 days raises (the schedule is the suspect)", False, True)
except RuntimeError as e:
    check("a feed quiet for 10 days raises (the schedule is the suspect)", "no Roku delivery for 10 days" in str(e), True)
st = {**P.blank(), "_prev": {"health": {"rokuEngagement": {"daily": [{"date": P.today()}]}}}}
check("an empty box one day after a delivery is normal", "normal" in P.roku_engagement(st), True)
srv.shutdown()

print("\nRoku merges across readings")
prev = {"health": {"rokuEngagement": {"daily": [{"date": "2026-09-01", "Channel Installs": 5.0}],
                                      "headline": {"Account Channel Installs": 112.0},
                                      "versionsSeen": [{"version": "1.0.65", "firstSeen": "2026-09-01", "lastSeen": "2026-09-05"}]}}}
st = P.blank()
st["health"]["rokuEngagement"] = {"daily": [{"date": "2026-09-10", "Total Count of Crashes": 3.0}],
                                  "headline": {"Rebuffers per Hours Streamed": 0.1}, "byReport": {},
                                  "versionsSeen": [{"version": "1.0.75", "firstSeen": "2026-09-10", "lastSeen": "2026-09-10"}]}
st["stores"] = [{"store": "Roku Channel Store", "platform": "Roku", "version": "1.0.51", "manual": True}]
P.merge_roku(st, prev)
rk = st["health"]["rokuEngagement"]
check("a day that fell out of Looker's window is kept", [r["date"] for r in rk["daily"]], ["2026-09-01", "2026-09-10"])
check("a headline tile nobody redelivered keeps its value", rk["headline"].get("Account Channel Installs"), 112.0)
check("versions accumulate", [v["version"] for v in rk["versionsSeen"]], ["1.0.65", "1.0.75"])
P.roku_store_version(st)
check("the declared Roku version loses to the newest one SEEN", st["stores"][0]["version"], "1.0.75")


print(f"\n{PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
