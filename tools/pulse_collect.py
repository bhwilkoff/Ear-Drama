#!/usr/bin/env python3
"""
pulse_collect.py — one place that knows how the product is doing.

Reads every channel the project actually has a route to — the Apple platforms,
Play, Amazon, Roku, the website, Search, the social program, the open web,
GitHub and the CI fleet — and writes ONE file, `ops/pulse.json`, that the
/pulse page renders. Run from CI (.github/workflows/pulse.yml).

What the app IS comes from ops/pulse.config.json (copy the .example), falling
back to tools/app_config.py for the identity it already carries. Credentials
come from the environment only.

The rules the whole tool is built on:

* **A source that will not answer costs one line, never the run.** Every
  reader is wrapped; a failure is recorded as a note IN the output, so the page
  can say "Play: no credential in this environment" instead of a confident
  zero. A dashboard that silently reports 0 for a broken reader is worse than
  no dashboard, because it reads as good news.

* **Not configured is not broken, and neither is zero.** A reader this app has
  not set up (no App Store id, no counter) records `off: true` and the page
  says "not configured". It is excluded from the degraded-run guard below,
  because config is the same on every machine and credentials are not.

* **Numbers are kept; text is capped.** `history` holds one compact row per
  day forever. Reviews and mentions are a window, newest first.

* **A request is QUOTED, never summarized.** `asks` extracts the sentence a
  person actually wrote and links to it. No model, no sentiment score.

* **A reading that cannot be trusted is refused, not written.** If a third or
  more of the configured readers were dark, `--apply` refuses: a laptop with a
  few credentials would otherwise replace CI's fresher reading with a mostly
  carried-forward one.

* **Usage is counted from what servers and vendors already see.** No reader
  here asks an app to send a new count (see web_usage, counter_tallies,
  cloud_usage).

Run:
  python3 tools/pulse_collect.py                 # collect, print, write nothing
  python3 tools/pulse_collect.py --apply         # write ops/pulse.json
  python3 tools/pulse_collect.py --only apple_reviews,mentions_hn
"""
from __future__ import annotations

import argparse
import base64
import csv
import datetime as dt
import io
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "ops" / "pulse.json"
CONFIG_PATH = Path(os.environ.get("PULSE_CONFIG") or (REPO / "ops" / "pulse.config.json"))

MAX_REVIEWS = 200
MAX_MENTIONS = 150
MAX_HISTORY = 800          # ~2 years of daily rows


class NotConfigured(RuntimeError):
    """This app has not set the reader up. Not a failure and never a zero:
    the page says 'not configured', and the degraded-run guard ignores it."""


# ─────────────────────────────────────────────────────────────── identity

def _placeholder(v) -> bool:
    """app_config.py ships placeholders; a placeholder is not an identity."""
    s = str(v or "").strip().lower()
    return (not s) or "example" in s or s in ("appname", "app name", "app")


def load_config(path: Path | None = None) -> dict:
    p = Path(path or CONFIG_PATH)
    try:
        return json.loads(p.read_text())
    except (OSError, ValueError):
        return {}


def identity(conf: dict, use_app_config: bool = True) -> dict:
    """Everything the readers need to know about THIS app, from one config.
    Blank means the reader is off. tools/app_config.py fills identity the
    template already asks for, so nothing is typed twice."""
    app = None
    if use_app_config and not os.environ.get("PULSE_NO_APP_CONFIG"):
        sys.path.insert(0, str(REPO / "tools"))
        try:
            import app_config as app                  # noqa: F811
        except Exception:                             # noqa: BLE001
            app = None

    def g(path, default=None):
        cur = conf
        for part in path.split("."):
            if not isinstance(cur, dict):
                return default
            cur = cur.get(part)
        return default if cur in (None, "", [], {}) else cur

    def fb(path, attr, default=""):
        v = g(path)
        if v not in (None, ""):
            return v
        v = getattr(app, attr, "") if app else ""
        if isinstance(v, (list, tuple)):
            v = [x for x in v if not _placeholder(x)]
            return v or default
        return default if _placeholder(v) else v

    site = str(fb("product.site", "PRODUCT_SITE") or "").rstrip("/")
    pkg = fb("play.package", "ANDROID_PACKAGE")
    return {
        "name": fb("product.name", "PRODUCT_NAME", "") or "",
        "site": site,
        "timezone": g("product.timezone", "UTC"),
        "repo": fb("product.repo", "GITHUB_REPO"),
        "ownerLogins": list(g("product.ownerLogins", [])) + ["github-actions[bot]"],
        "deployWorkflow": g("product.deployWorkflow", ""),
        "appleAppId": str(fb("apple.appStoreId", "APPLE_APP_STORE_ID") or ""),
        "applePlatforms": list(g("apple.platforms", ["TV_OS", "IOS", "MAC_OS"])),
        "playPackage": pkg,
        "stackMarker": g("play.stackMarker", "") or pkg,
        "amazonPackage": g("amazon.package", ""),
        "rokuConsole": g("roku.consoleUrl", ""),
        "strict": tuple(t.lower() for t in (fb("mentions.strict", "MENTION_STRICT", []) or [])),
        "loose": str(fb("mentions.loose", "MENTION_LOOSE") or "").lower(),
        "corroborate": tuple(g("mentions.corroborate", ())),
        "query": g("mentions.query", ""),
        "ledger": g("social.ledger", "social/posted.json"),
        "metrics": g("social.metrics", "social/metrics.json"),
        "profiles": {k: v for k, v in (g("social.profiles", {}) or {}).items() if v},
        "counter": (os.environ.get("PULSE_COUNTER") or g("web.counterOrigin", "")).rstrip("/"),
        "ingest": (os.environ.get("PULSE_INGEST_ORIGIN") or g("web.ingestOrigin", "")
                   or g("web.counterOrigin", "")).rstrip("/"),
        "tallies": list(g("web.tallies", [])),
        "searchSite": g("search.site", ""),
        "pagePattern": g("search.pagePattern", ""),
        "sampleSize": int(g("search.sampleSize", 150)),
        "cloud": g("cloudUsage", {}) or {},
        "playBucket": (os.environ.get("PLAY_REPORTS_BUCKET") or fb("play.reportsBucket", "PLAY_REPORTS_BUCKET")
                       or "").strip().replace("gs://", "").strip("/").split("/")[0],
    }


CONF = load_config()
ID = identity(CONF)


def need(key: str, what: str):
    """The identity value a reader cannot run without, or NotConfigured."""
    v = ID.get(key)
    if not v:
        raise NotConfigured(f"set {what} in ops/pulse.config.json")
    return v


def ua() -> str:
    slug = re.sub(r"[^A-Za-z0-9]", "", ID.get("name") or "") or "Product"
    return f"{slug}Pulse/1.0" + (f" (+{ID['site']})" if ID.get("site") else "")


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def today() -> str:
    return dt.datetime.now(dt.timezone.utc).date().isoformat()


def get(url, headers=None, timeout=25):
    # EVERY request carries the collector's UA. Cloudflare answers a bare
    # `Python-urllib` request with 403 — which reads exactly like an auth
    # failure and is not one.
    req = urllib.request.Request(url, headers={"User-Agent": ua(), **(headers or {})})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def get_json(url, headers=None, timeout=25):
    return json.loads(get(url, headers, timeout).decode("utf-8", "replace"))


def clamp(s, n):
    s = re.sub(r"\s+", " ", (s or "")).strip()
    return s if len(s) <= n else s[: n - 1].rstrip() + "…"


def relevant(*fields) -> bool:
    """Does this text plausibly talk about US? Deliberately narrow: a product
    name is usually also two ordinary words, so a hit must carry a STRICT term,
    or the loose term AND a corroborating word."""
    blob = " ".join(f for f in fields if f).lower()
    if any(t and t in blob for t in ID["strict"]):
        return True
    if ID["loose"] and ID["loose"] in blob and any(c in blob for c in ID["corroborate"]):
        return True
    return False


def num_or_none(v, cast=int):
    """A missing or blank cell is NULL, never zero. A reader that defaults a
    missing column to 0 reports a platform with 112 installs as having none."""
    if v is None or str(v).strip() == "":
        return None
    try:
        return cast(float(str(v).replace(",", "").replace("%", "")))
    except (TypeError, ValueError):
        return None


def total(vals):
    """Sum what exists; None when nothing did."""
    xs = [v for v in vals if v is not None]
    return sum(xs) if xs else None


# ─────────────────────────────────────────────────────────────── Apple

def _asc_key():
    kid, iss = os.environ.get("ASC_KEY_ID", "").strip(), os.environ.get("ASC_ISSUER_ID", "").strip()
    if not (kid and iss):
        raise RuntimeError("no App Store Connect key in this environment (ASC_KEY_ID / ASC_ISSUER_ID)")
    # The key is read OFF DISK, which is how every Apple tool here is fed.
    # Passing the key material as an env var looked right and read zero reviews.
    path = os.environ.get("ASC_KEY_PATH") or os.path.expanduser(
        f"~/.appstoreconnect/private_keys/AuthKey_{kid}.p8")
    if not os.path.exists(path):
        raise RuntimeError(f"ASC key {kid} is not on disk at {path}")
    return kid, iss, Path(path).read_text()


def _jwt(kid, iss, key):
    import jwt                                        # PyJWT + cryptography
    t = int(time.time())
    return jwt.encode({"iss": iss, "iat": t, "exp": t + 900, "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": kid, "typ": "JWT"})


def _asc_token():
    return _jwt(*_asc_key())


def _reports_token():
    """A SEPARATE key for reports, when one exists. App Store Connect says a key
    "can't be modified to access more services once created" (Edit offers only
    Revoke), and the release key is App Manager, which is not a reporting role.
    So ASC_REPORTS_KEY_ID + ASC_REPORTS_KEY_P8 (base64, same issuer) hold a key
    whose ONLY role is Sales and Reports; the ordinary key otherwise, which
    fails honestly with "the API key in use does not allow this request"."""
    kid = os.environ.get("ASC_REPORTS_KEY_ID", "").strip()
    p8 = os.environ.get("ASC_REPORTS_KEY_P8", "").strip()
    if not (kid and p8):
        return _asc_token()
    iss = os.environ.get("ASC_ISSUER_ID", "").strip()
    if not iss:
        raise RuntimeError("ASC_REPORTS_KEY_ID is set but ASC_ISSUER_ID is not")
    return _jwt(kid, iss, base64.b64decode(p8).decode())


def _asc_call(ep):
    req = urllib.request.Request("https://api.appstoreconnect.apple.com/" + ep,
                                 headers={"Authorization": "Bearer " + _asc_token(),
                                          "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        raw = r.read().decode()
        return json.loads(raw) if raw.strip() else {}


def _asc_raw(ep, accept, reports=False):
    """ASC endpoints that do not speak JSON. `salesReports` wants
    application/a-gzip and `perfPowerMetrics` wants
    application/vnd.apple.xcode-metrics+json; through a client that sets
    Accept: application/json both answer 406, which reads exactly like a
    permission problem and is not one."""
    tok = _reports_token() if reports else _asc_token()
    req = urllib.request.Request("https://api.appstoreconnect.apple.com/" + ep,
                                 headers={"Authorization": "Bearer " + tok, "Accept": accept})
    with urllib.request.urlopen(req, timeout=45) as r:
        return r.read()


APPLE_LABELS = {"TV_OS": "Apple TV", "IOS": "iPhone & iPad", "MAC_OS": "Mac", "VISION_OS": "Vision"}


def apple_stores(state):
    """Where each Apple platform stands right now: live, and anything in flight."""
    aid = need("appleAppId", "apple.appStoreId")
    rows = []
    for platform in ID["applePlatforms"]:
        vs = _asc_call(f"v1/apps/{aid}/appStoreVersions?limit=20&filter[platform]={platform}"
                       "&fields[appStoreVersions]=versionString,appStoreState").get("data") or []
        if not vs:
            continue
        live = next((v for v in vs if v["attributes"]["appStoreState"] == "READY_FOR_SALE"), None)
        flight = next((v for v in vs if v["attributes"]["appStoreState"] != "READY_FOR_SALE"), None)
        cur = flight or live
        rows.append({
            "store": "App Store",
            "platform": APPLE_LABELS.get(platform, platform),
            "state": cur["attributes"]["appStoreState"] if cur else "NONE",
            "version": cur["attributes"]["versionString"] if cur else None,
            "live": live["attributes"]["versionString"] if live else None,
            # A newer build is waiting ONLY when the store says so. Never
            # compare against AppVersion.xcconfig, which moves on every commit
            # and would call every store "behind" every day.
            **({"inFlight": {"version": flight["attributes"]["versionString"],
                             "state": flight["attributes"]["appStoreState"]}}
               if flight and live else {}),
            "route": "App Store Connect API",
            "url": f"https://appstoreconnect.apple.com/apps/{aid}/distribution",
        })
    state["stores"] += rows
    return f"{len(rows)} Apple platform(s)"


def apple_reviews(state):
    """Every customer review, all territories, newest first."""
    aid = need("appleAppId", "apple.appStoreId")
    out, cursor, pages = [], None, 0
    while pages < 6:
        ep = f"v1/apps/{aid}/customerReviews?limit=200&sort=-createdDate&include=response"
        if cursor:
            ep += f"&cursor={urllib.parse.quote(cursor)}"
        d = _asc_call(ep)
        replies = {i["id"]: i for i in d.get("included", []) if i["type"] == "customerReviewResponses"}
        for r in d.get("data", []):
            a = r["attributes"]
            rid = ((r.get("relationships") or {}).get("response") or {}).get("data") or {}
            out.append({
                "store": "App Store", "id": r["id"], "rating": a.get("rating"),
                "title": clamp(a.get("title"), 120), "body": clamp(a.get("body"), 1200),
                "author": a.get("reviewerNickname"), "territory": a.get("territory"),
                "date": a.get("createdDate"), "responded": bool(replies.get(rid.get("id"))),
                "url": f"https://appstoreconnect.apple.com/apps/{aid}/distribution/reviews",
            })
        cursor = ((d.get("links") or {}).get("next") or "")
        cursor = urllib.parse.parse_qs(urllib.parse.urlparse(cursor).query).get("cursor", [None])[0]
        pages += 1
        if not cursor:
            break
    state["reviews"] += out
    return f"{len(out)} review(s)"


def apple_rating(state):
    """The public ratings summary — no auth, so it works anywhere."""
    aid = need("appleAppId", "apple.appStoreId")
    d = get_json(f"https://itunes.apple.com/lookup?id={aid}&country=us")
    if not d.get("resultCount"):
        raise RuntimeError("iTunes lookup returned no result")
    r = d["results"][0]
    state["ratings"].append({
        "store": "App Store", "average": r.get("averageUserRating"),
        "count": r.get("userRatingCount"), "version": r.get("version"),
        "releasedAt": r.get("currentVersionReleaseDate"), "url": r.get("trackViewUrl"),
    })
    return f"{r.get('averageUserRating')} from {r.get('userRatingCount')}"


def apple_performance(state):
    """Launch time, hang rate, memory, disk — Apple's own aggregated field
    metrics, the one Apple-side signal that says something needs fixing before
    a user writes a review about it."""
    aid = need("appleAppId", "apple.appStoreId")
    d = json.loads(_asc_raw(f"v1/apps/{aid}/perfPowerMetrics",
                            "application/vnd.apple.xcode-metrics+json"))
    ins = d.get("insights") or {}
    rows = []
    for p in d.get("productData") or []:
        for m in p.get("metricCategories", []):
            for metric in m.get("metrics", []):
                pts = metric.get("datasets", [{}])[0].get("points", [])
                if pts:
                    rows.append({"platform": p.get("platform"), "category": m.get("identifier"),
                                 "metric": metric.get("identifier"), "value": pts[-1].get("value"),
                                 "unit": metric.get("unit")})
    state["health"]["applePerf"] = {
        "metrics": rows[:20],
        "regressions": [clamp(i.get("summaryString") or i.get("metric"), 160)
                        for i in (ins.get("regressions") or [])][:8],
        "improving": [clamp(i.get("summaryString") or i.get("metric"), 160)
                      for i in (ins.get("trendingUp") or [])][:8],
    }
    if not rows and not ins.get("regressions"):
        return "Apple has not aggregated enough device data yet"
    return f"{len(rows)} metric(s), {len(ins.get('regressions') or [])} regression(s)"


# Apple's Product Type Identifiers for a FIRST download. The Mac codes are a
# DIFFERENT family: iOS/tvOS codes are digit-led (1, 1T, 1E…), Mac apps are
# F-led (F1 free, FI1 in-app), and nothing about the first family hints that a
# second exists — macOS read ZERO for weeks while App Store Connect showed
# installs.
APPLE_FIRST_DOWNLOAD = {"1", "1T", "1E", "1EP", "1EU", "IA1",     # iPhone / iPad / Apple TV
                        "F1", "FI1"}                              # Mac


def apple_sales_rows(tsv_text, app_id, days_rows=None):
    """Parse one day's SUMMARY sales TSV. Pure, so it is tested.

    * The report covers the whole VENDOR account, not one app: filter on
      `Apple Identifier`, or another title's units are counted as yours.
    * Every Product Type Identifier NOT counted is RECORDED with its units. A
      code we do not recognise is the only way this reader under-reports, and
      it does so silently — the number just comes out smaller.
    Returns (units, byDevice, byCountry, byVersion, skipped, perDeviceCountry,
    perDeviceVersion) or None when the header lacks a column we need."""
    lines = tsv_text.splitlines()
    if len(lines) < 2:
        return None
    idx = {n: i for i, n in enumerate(lines[0].split("\t"))}
    if any(n not in idx for n in ("Units", "Product Type Identifier", "Apple Identifier")):
        return None
    units, by_dev, by_country, by_version, skipped = 0, {}, {}, {}, {}
    dev_country, dev_version = {}, {}
    for ln in lines[1:]:
        f = ln.split("\t")
        if len(f) <= max(idx.values()):
            continue
        if app_id and f[idx["Apple Identifier"]].strip() != str(app_id):
            continue                                   # another app in the same report
        pt = f[idx["Product Type Identifier"]].strip()
        u = num_or_none(f[idx["Units"]])
        if pt not in APPLE_FIRST_DOWNLOAD:
            skipped[pt] = skipped.get(pt, 0) + (u or 0)
            continue                                   # an update is not a new person
        if u is None:
            continue
        units += u
        d = (f[idx["Device"]].strip() if "Device" in idx else "") or "Unknown"
        by_dev[d] = by_dev.get(d, 0) + u
        if "Country Code" in idx:
            c = f[idx["Country Code"]].strip() or "??"
            by_country[c] = by_country.get(c, 0) + u
            dev_country.setdefault(d, {})[c] = dev_country.setdefault(d, {}).get(c, 0) + u
        if "Version" in idx:
            v = f[idx["Version"]].strip() or "?"
            by_version[v] = by_version.get(v, 0) + u
            dev_version.setdefault(d, {})[v] = dev_version.setdefault(d, {}).get(v, 0) + u
    return units, by_dev, by_country, by_version, skipped, dev_country, dev_version


def apple_downloads(state):
    """Daily first-time installs, split by DEVICE (iPhone, iPad, Apple TV,
    Desktop — the only per-platform install number on the Apple side), country
    and version. Needs the VENDOR NUMBER and a Sales-and-Reports key."""
    aid = need("appleAppId", "apple.appStoreId")
    vendor = os.environ.get("ASC_VENDOR_NUMBER", "").strip()
    if not vendor:
        raise RuntimeError("set ASC_VENDOR_NUMBER (App Store Connect -> Payments and "
                           "Financial Reports) to read downloads")
    import gzip
    days, by_dev, by_country, by_version, skipped = [], {}, {}, {}, {}
    dev_country, dev_version = {}, {}
    for back in range(1, 32):
        day = (dt.date.today() - dt.timedelta(days=back)).isoformat()
        ep = ("v1/salesReports?filter[frequency]=DAILY&filter[reportType]=SALES"
              f"&filter[reportSubType]=SUMMARY&filter[vendorNumber]={vendor}"
              f"&filter[reportDate]={day}")
        try:
            raw = gzip.decompress(_asc_raw(ep, "application/a-gzip", reports=True))
        except urllib.error.HTTPError as e:
            if e.code == 404:                          # no report for that day
                continue
            if e.code == 403:
                raise RuntimeError(
                    "the API key in use has no Sales and Reports access, and a key "
                    "cannot be widened after it is created — generate one with ONLY "
                    "that role and set ASC_REPORTS_KEY_ID / ASC_REPORTS_KEY_P8") from None
            raise
        except OSError:
            continue
        got = apple_sales_rows(raw.decode("utf-8", "replace"), aid)
        if got is None:
            continue
        u, bd, bc, bv, sk, dc, dvv = got
        for src, dst in ((bd, by_dev), (bc, by_country), (bv, by_version), (sk, skipped)):
            for k, v in src.items():
                dst[k] = dst.get(k, 0) + v
        for src, dst in ((dc, dev_country), (dvv, dev_version)):
            for dev, m in src.items():
                slot = dst.setdefault(dev, {})
                for k, v in m.items():
                    slot[k] = slot.get(k, 0) + v
        days.append({"date": day, "units": u, "byDevice": bd})
    if not days:
        raise RuntimeError("no sales report available yet for this vendor number")
    days.sort(key=lambda r: r["date"])
    top = lambda d: dict(sorted(d.items(), key=lambda kv: -kv[1])[:14])  # noqa: E731
    state["health"]["appleDownloads"] = {
        "daily": days,
        "total14d": sum(r["units"] for r in days[-14:]),
        "total28d": sum(r["units"] for r in days[-28:]),
        "byDevice": top(by_dev), "byCountry": top(by_country), "byVersion": top(by_version),
        # THIS device's countries and versions, never the account's.
        "perDevice": {k: {"byCountry": top(v), "byVersion": top(dev_version.get(k, {})),
                          "units": by_dev.get(k, 0)} for k, v in dev_country.items()},
        "skippedProductTypes": dict(sorted(skipped.items(), key=lambda kv: -kv[1])[:12]),
    }
    return (f"{sum(r['units'] for r in days)} first-time download(s) over {len(days)} day(s), "
            f"{len(by_dev)} device type(s)"
            + (f"; skipped {sum(skipped.values())} unit(s) across {len(skipped)} other "
               f"product type(s) {sorted(skipped)}" if skipped else ""))


# ─────────────────────────────────────────────────────────────── Google

def _google_creds(scopes):
    from google.oauth2 import service_account
    key = os.environ.get("PLAY_SERVICE_ACCOUNT_JSON", "").strip()
    if not key:
        raise RuntimeError("no Google service-account key in this environment "
                           "(PLAY_SERVICE_ACCOUNT_JSON: the JSON itself or a path)")
    if key.startswith("{"):                            # the secret may arrive as JSON itself
        return service_account.Credentials.from_service_account_info(json.loads(key), scopes=scopes)
    path = os.path.expanduser(key)
    if not os.path.exists(path):
        raise RuntimeError(f"PLAY_SERVICE_ACCOUNT_JSON points at {path}, which does not exist")
    return service_account.Credentials.from_service_account_file(path, scopes=scopes)


def _play():
    from googleapiclient.discovery import build
    return build("androidpublisher", "v3", cache_discovery=False,
                 credentials=_google_creds(["https://www.googleapis.com/auth/androidpublisher"]))


def _reporting():
    from googleapiclient.discovery import build
    return build("playdeveloperreporting", "v1beta1", cache_discovery=False,
                 credentials=_google_creds(["https://www.googleapis.com/auth/playdeveloperreporting"]))


def _google(scopes):
    """A bearer token for any Google API, as the same read-only robot."""
    from google.auth.transport.requests import Request
    creds = _google_creds(scopes)
    creds.refresh(Request())
    return creds.token


def play_stores(state):
    pkg = need("playPackage", "play.package")
    svc = _play()
    ed = svc.edits().insert(packageName=pkg, body={}).execute()
    try:
        tracks = svc.edits().tracks().list(packageName=pkg, editId=ed["id"]).execute()
    finally:
        try:
            svc.edits().delete(packageName=pkg, editId=ed["id"]).execute()
        except Exception:                              # noqa: BLE001
            pass
    rows = []
    for t in tracks.get("tracks", []):
        # A track can hold a COMPLETED release and a newer one in progress at
        # once. Reading only releases[0] showed whichever Google listed first,
        # so the morning after a promotion the row said the old build. Live is
        # the completed release; the other is in flight.
        rels = [r for r in (t.get("releases") or []) if r.get("status")]
        if not rels:
            continue
        done = next((r for r in rels if r.get("status") == "completed"), None)
        flight = next((r for r in rels if r.get("status") != "completed"), None)
        cur = flight or done
        row = {
            "store": "Google Play", "platform": t["track"].title(),
            "state": (cur.get("status") or "").upper(), "version": cur.get("name"),
            "live": done.get("name") if done else None,
            "build": ", ".join((done or cur).get("versionCodes") or []),
            "route": "Play Developer API",
            "url": f"https://play.google.com/console/developers/app/{pkg}",
        }
        if flight and done:
            row["inFlight"] = {"version": flight.get("name"),
                               "build": ", ".join(flight.get("versionCodes") or []),
                               "state": (flight.get("status") or "").upper()}
        rows.append(row)
    state["stores"] += rows
    return f"{len(rows)} track(s)"


def play_reviews(state):
    """Play only serves reviews from roughly the last week — an empty answer is
    normal, and is NOT the same as 'no reviews exist'."""
    pkg = need("playPackage", "play.package")
    r = _play().reviews().list(packageName=pkg, maxResults=100).execute()
    out = []
    for v in r.get("reviews", []):
        c = (v.get("comments") or [{}])[0].get("userComment", {}) or {}
        ts = c.get("lastModified", {}).get("seconds")
        out.append({
            "store": "Google Play", "id": v.get("reviewId"), "rating": c.get("starRating"),
            "title": "", "body": clamp(c.get("text"), 1200), "author": v.get("authorName"),
            "territory": (c.get("reviewerLanguage") or "").upper(),
            "date": dt.datetime.fromtimestamp(int(ts), dt.timezone.utc).isoformat() if ts else None,
            "responded": any("developerComment" in c2 for c2 in v.get("comments", [])),
            "device": c.get("device"), "appVersion": c.get("appVersionName"),
            "url": f"https://play.google.com/console/developers/app/{pkg}/user-feedback",
        })
    state["reviews"] += out
    return f"{len(out)} review(s) in Play's 7-day window"


def _freshest_day(api, name):
    """A metric set ADVERTISES the window it holds; querying past it is a 400
    that reads like a malformed request. Ask, then query to that date."""
    fresh = api.get(name=name).execute()
    daily = next((f for f in (fresh.get("freshnessInfo") or {}).get("freshnesses", [])
                  if f.get("aggregationPeriod") == "DAILY"), None)
    if not daily:
        return None
    le = daily["latestEndTime"]
    return dt.date(le["year"], le["month"], le["day"])


def _timeline(begin, end):
    return {"aggregationPeriod": "DAILY",
            "startTime": {"year": begin.year, "month": begin.month, "day": begin.day},
            "endTime": {"year": end.year, "month": end.month, "day": end.day}}


def play_vitals(state):
    """Crash and ANR rate. Play withholds a rate below a minimum audience —
    a real answer about the app's size, reported as one."""
    pkg = need("playPackage", "play.package")
    svc = _reporting()
    got, errs, notes = {}, [], []
    for res, metric, mset in (("crashrate", "crashRate", "crashRateMetricSet"),
                              ("anrrate", "anrRate", "anrRateMetricSet")):
        api = getattr(svc.vitals(), res)()
        name = f"apps/{pkg}/{mset}"
        try:
            end = _freshest_day(api, name)
        except Exception as e:                         # noqa: BLE001
            errs.append(f"{metric}: {str(e)[:90]}")
            continue
        if not end:
            notes.append(f"{metric}: Play reports no daily window yet")
            continue
        body = {"timelineSpec": _timeline(end - dt.timedelta(days=27), end), "metrics": [metric]}
        try:
            d = api.query(name=name, body=body).execute()
            vals = [float(m["decimalValue"]["value"])
                    for r in d.get("rows", []) for m in r.get("metrics", [])
                    if m.get("metric") == metric and m.get("decimalValue")]
            if vals:
                got[metric] = round(sum(vals) / len(vals), 5)
                got[metric + "Days"] = len(vals)
            else:
                notes.append(f"{metric}: too few users for Play to publish a rate")
        except Exception as e:                         # noqa: BLE001
            errs.append(f"{metric}: {str(e)[:90]}")
    state["health"]["playVitals"] = got
    if notes:
        state["health"]["playVitalsNote"] = "; ".join(notes)
    if errs and not got:
        raise RuntimeError("; ".join(errs))
    return (", ".join(f"{k}={v}" for k, v in got.items() if not k.endswith("Days"))
            or "; ".join(notes) or "no data yet")


_FIXED: dict | None = None


def _fixed_in(issue_uri):
    """Has this cluster's CAUSE already been fixed in the repo? A crash with a
    fix in hand asks to be SHIPPED, not fixed again. `ops/fixed-in.json` names
    the Android versionCode carrying the fix; the page compares it to Play's
    live and in-flight builds (never to an Apple build number)."""
    global _FIXED
    if _FIXED is None:
        try:
            _FIXED = json.loads((REPO / "ops" / "fixed-in.json").read_text()).get("clusters", {})
        except (OSError, ValueError):
            _FIXED = {}
    uri = issue_uri or ""
    cid = uri.rstrip("/").split("/")[-2] if "/details" in uri else uri.rstrip("/").split("/")[-1]
    return _FIXED.get(cid)


def _our_frame(svc, issue, iv, pkg):
    """The first line of the stack that is OUR code — the difference between
    'Compose threw' and 'this list has a duplicate key'."""
    marker = ID.get("stackMarker") or pkg
    try:
        rep = svc.vitals().errors().reports().search(
            parent=f"apps/{pkg}", pageSize=1,
            filter=f'errorIssueId = "{issue["name"].split("/")[-1]}"', **iv).execute()
    except Exception:                                  # noqa: BLE001
        return None
    for r in rep.get("errorReports", [])[:1]:
        text = r.get("reportText") or ""
        head = next((ln.strip() for ln in text.splitlines() if ln.strip().startswith("Exception ")), None)
        mine = next((ln.strip() for ln in text.splitlines() if marker and marker in ln), None)
        return clamp(" · ".join(x for x in (head, mine) if x), 300) or None
    return None


def play_crashes(state):
    """The crash clusters, worst first — a named stack beats a rate. Each one
    carries `stale` (last seen on a build older than production): a list where
    most clusters are two releases old is a list nobody reads."""
    pkg = need("playPackage", "play.package")
    svc = _reporting()
    end = dt.date.today()
    start = end - dt.timedelta(days=28)
    iv = {"interval_startTime_year": start.year, "interval_startTime_month": start.month,
          "interval_startTime_day": start.day, "interval_endTime_year": end.year,
          "interval_endTime_month": end.month, "interval_endTime_day": end.day}
    d = svc.vitals().errors().issues().search(
        parent=f"apps/{pkg}", pageSize=20, orderBy="distinctUsers desc",
        sampleErrorReportLimit=1, **iv).execute()   # sampleErrorReportLimit accepts only 0 or 1
    live_vc = None
    for row in state.get("stores", []):
        if row.get("store") == "Google Play" and (row.get("platform") or "").lower() == "production":
            live_vc = num_or_none((row.get("build") or "").split(",")[0])
    rows = []
    for i in d.get("errorIssues", []):
        last_vc = num_or_none(i.get("lastAppVersion", {}).get("versionCode"))
        rows.append({
            "type": i.get("type"), "cause": clamp(i.get("cause"), 160),
            "location": clamp(i.get("location"), 160),
            "users": num_or_none(i.get("distinctUsers")), "reports": num_or_none(i.get("errorReportCount")),
            "lastSeen": i.get("lastErrorReportTime"),
            "firstBuild": i.get("firstAppVersion", {}).get("versionCode"),
            "lastBuild": str(last_vc) if last_vc is not None else None,
            "api": f"{i.get('firstOsVersion', {}).get('apiLevel')}-{i.get('lastOsVersion', {}).get('apiLevel')}",
            "stale": bool(live_vc and last_vc and last_vc < live_vc),
            "url": i.get("issueUri"), "fixedIn": _fixed_in(i.get("issueUri")),
            "ours": _our_frame(svc, i, iv, pkg),
        })
    state["health"]["playCrashes"] = rows
    state["health"]["playLiveBuild"] = live_vc
    fresh = [r for r in rows if not r["stale"]]
    return (f"{len(rows)} cluster(s), {len(fresh)} still on build {live_vc}"
            if live_vc else f"{len(rows)} cluster(s)")


# Every one of these is ACCEPTED by the API and may return nothing: Play
# withholds a per-dimension figure below a minimum audience. The reader is
# proven; the audience is not there yet. Those are different sentences.
PLAY_DIMENSIONS = ("countryCode", "deviceModel", "deviceBrand", "versionCode",
                   "apiLevel", "deviceType", "deviceRamBucket")


def play_users(state):
    """Distinct users per day, off the crash-rate metric set (`distinctUsers`
    is a metric there, not a separate API)."""
    pkg = need("playPackage", "play.package")
    api = _reporting().vitals().crashrate()
    name = f"apps/{pkg}/crashRateMetricSet"
    end = _freshest_day(api, name)
    if not end:
        raise RuntimeError("Play reports no daily window yet")
    begin = end - dt.timedelta(days=27)

    def q(dims=None):
        body = {"timelineSpec": _timeline(begin, end), "metrics": ["distinctUsers"]}
        if dims:
            body["dimensions"] = list(dims)
        return api.query(name=name, body=body).execute()

    def val(row):
        m = (row.get("metrics") or [{}])[0]
        return num_or_none((m.get("decimalValue") or {}).get("value"), float)

    series = []
    for r in q().get("rows", []):
        t, v = r.get("startTime", {}), val(r)
        if v is not None:
            series.append({"date": f"{t.get('year')}-{t.get('month'):02d}-{t.get('day'):02d}",
                           "users": round(v, 1)})
    breakdown = {}
    for dim in PLAY_DIMENSIONS:
        try:
            agg = {}
            for r in q([dim]).get("rows", []):
                d0 = (r.get("dimensions") or [{}])[0]
                k, v = d0.get("stringValue") or d0.get("int64Value") or d0.get("valueLabel"), val(r)
                if k is not None and v is not None:
                    agg[str(k)] = round(agg.get(str(k), 0) + v, 1)
            if agg:
                breakdown[dim] = dict(sorted(agg.items(), key=lambda kv: -kv[1])[:12])
        except Exception:                              # noqa: BLE001 — one dimension, never the run
            continue
    state["health"]["playUsers"] = {"daily": series, "byDimension": breakdown,
                                    "window": f"{begin.isoformat()}..{end.isoformat()}"}
    if not series and not breakdown:
        return ("every query was accepted and returned nothing — Play withholds "
                "per-user figures below a minimum audience")
    return f"{len(series)} day(s) of users, {len(breakdown)} dimension(s)"


PLAY_REPORT_FILES = ("overview", "country", "device", "os_version", "app_version", "language", "carrier")


def _gcs(bucket):
    from googleapiclient.discovery import build as _build
    return _build("storage", "v1", cache_discovery=False,
                  credentials=_google_creds(["https://www.googleapis.com/auth/devstorage.read_only"]))


def _gcs_bytes(bucket, obj):
    """One object as the service account, falling back to the owner's gcloud.
    A Console grant takes HOURS to reach the bucket's ACLs, so a freshly
    permitted service account reads 403 while `gcloud` reads fine. The fallback
    is local-only by nature and simply does not fire in CI."""
    try:
        return _gcs(bucket).objects().get_media(bucket=bucket, object=obj).execute(), "service account"
    except Exception:                                  # noqa: BLE001
        pass
    try:
        out = subprocess.run(["gcloud", "storage", "cat", f"gs://{bucket}/{obj}"],
                             capture_output=True, timeout=120)
        if out.returncode == 0 and out.stdout:
            return out.stdout, "gcloud"
    except Exception:                                  # noqa: BLE001
        pass
    return None, None


def _gcs_written(bucket, obj):
    """When the object was last WRITTEN. The newest ROW in a CSV cannot tell a
    file that stopped being written from one that is merely behind; only the
    object's update time can. Measure it before ever calling an export broken."""
    try:
        return _gcs(bucket).objects().get(bucket=bucket, object=obj).execute().get("updated")
    except Exception:                                  # noqa: BLE001
        return None


def play_csv(raw):
    """Play's report CSVs: stored gzip-encoded (`gcloud storage cp` decompresses,
    `cat` does NOT, and gzipped bytes parse as a one-column CSV of mojibake
    rather than failing), UTF-16 with a BOM, and CRLF (a stray CR makes csv
    report "new-line character seen in unquoted field" for the whole file)."""
    import gzip
    if raw[:2] == b"\x1f\x8b":
        raw = gzip.decompress(raw)
    text = raw.decode("utf-16", "ignore") if raw[:2] in (b"\xff\xfe", b"\xfe\xff") \
        else raw.decode("utf-8-sig", "replace")
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    return list(csv.DictReader(io.StringIO(text)))


def _months(n):
    m, out = dt.date.today().replace(day=1), []
    for _ in range(n):
        out.append(m.strftime("%Y%m"))
        m = (m - dt.timedelta(days=1)).replace(day=1)
    return out


def _bucket():
    need("playPackage", "play.package")
    b = ID.get("playBucket")
    if not b:
        raise RuntimeError("set PLAY_REPORTS_BUCKET (Play Console -> Download reports -> "
                           "Statistics -> Copy Cloud Storage URI; NOT the developer id in the URL)")
    return b


# Play's install data runs ~6 days behind, AND the current month's file does
# not appear until part-way through the month. Two ordinary lags, stacked: so
# the alarm is past both. Anything less is Google being Google.
PLAY_INSTALLS_ALARM_DAYS = 14


def play_reports(state):
    """Installs, uninstalls, active devices and their splits, from the Play
    Console's Cloud Storage bucket. There is no installs metric in ANY version
    of the Reporting API; these monthly CSVs are the only route. The bucket
    holds OTHER apps' reports too, so every object name is package-scoped."""
    bucket, pkg = _bucket(), ID["playPackage"]
    got, how, newest_obj = {}, set(), None
    for kind in PLAY_REPORT_FILES:
        rows = []
        for ym in _months(4):
            obj = f"stats/installs/installs_{pkg}_{ym}_{kind}.csv"
            raw, via = _gcs_bytes(bucket, obj)
            if not raw:
                continue
            how.add(via)
            if kind == "overview" and (newest_obj is None or obj > newest_obj):
                newest_obj = obj
            try:
                rows.extend(play_csv(raw))
            except Exception:                          # noqa: BLE001 — one file, never the set
                continue
        if rows:
            got[kind] = rows
    if not got:
        raise RuntimeError(f"no reports readable in the bucket — a Console grant can take "
                           f"hours to reach its ACLs")

    daily = [{"date": r.get("Date"),
              "installs": num_or_none(r.get("Daily Device Installs")),
              "uninstalls": num_or_none(r.get("Daily Device Uninstalls")),
              "upgrades": num_or_none(r.get("Daily Device Upgrades")),
              "activeDevices": num_or_none(r.get("Active Device Installs")),
              "userInstalls": num_or_none(r.get("Daily User Installs"))}
             for r in got.get("overview", []) if r.get("Date")]
    daily.sort(key=lambda r: r["date"])

    def split(kind, col):
        agg = {}
        for r in got.get(kind, []):
            k, v = (r.get(col) or "").strip(), num_or_none(r.get("Daily Device Installs"))
            if k and v is not None:
                agg[k] = agg.get(k, 0) + v
        return dict(sorted(agg.items(), key=lambda kv: -kv[1])[:12])

    recent = daily[-28:]
    newest = recent[-1]["date"] if recent else None
    stale_days = None
    if newest:
        try:
            stale_days = (dt.date.today() - dt.date.fromisoformat(newest)).days
        except ValueError:
            stale_days = None
    written = _gcs_written(bucket, newest_obj) if newest_obj else None
    state["health"]["playInstalls"] = {
        "asOf": newest, "daily": recent,
        "installs28d": total(r["installs"] for r in recent),
        "uninstalls28d": total(r["uninstalls"] for r in recent),
        "activeDevices": recent[-1]["activeDevices"] if recent else None,
        "byCountry": split("country", "Country"), "byDevice": split("device", "Device"),
        "byOs": split("os_version", "Android OS Version"),
        "byVersion": split("app_version", "App Version Code"),
        "byLanguage": split("language", "Language"),
        "readVia": ", ".join(sorted(how)), "staleDays": stale_days,
        "fileWritten": written,
        "monthsFound": sorted({r["date"][:7] for r in recent if r.get("date")}),
    }
    n = total(r["installs"] for r in recent)
    wrote = f"; the export was last WRITTEN {written}" if written else ""
    if stale_days is not None and stale_days > PLAY_INSTALLS_ALARM_DAYS:
        return (f"NO NEW INSTALL ROW IN {stale_days} DAYS — newest is {newest}{wrote}. Past the "
                f"~6-day lag and the monthly-file delay: list the bucket "
                f"(tools/pulse_play_bucket_probe.py) before calling it broken. {n} install(s)")
    if stale_days is not None and stale_days > 3:
        return (f"{n} install(s) over {len(recent)} day(s) to {newest} ({stale_days}d behind — "
                f"Play's normal reporting lag){wrote}")
    return f"{n} install(s) over {len(recent)} day(s), {len(got)} report(s), via {', '.join(sorted(how))}"


def play_daily_exports(state):
    """The ratings and crashes exports: the CONTROL for the install export
    (same bucket, same account), and Play's running average rating, which the
    listing does not publish below a minimum audience."""
    bucket, pkg = _bucket(), ID["playPackage"]
    got = {}
    for kind in ("ratings", "crashes"):
        rows = []
        for ym in _months(3):
            raw, _ = _gcs_bytes(bucket, f"stats/{kind}/{kind}_{pkg}_{ym}_overview.csv")
            if raw:
                try:
                    rows.extend(play_csv(raw))
                except Exception:                      # noqa: BLE001
                    continue
        if rows:
            got[kind] = rows
    out = {}
    for r in got.get("ratings", []):
        if r.get("Date"):
            out.setdefault("ratings", []).append({
                "date": r["Date"], "daily": num_or_none(r.get("Daily Average Rating"), float),
                "total": num_or_none(r.get("Total Average Rating"), float)})
    for r in got.get("crashes", []):
        if r.get("Date"):
            out.setdefault("crashes", []).append({
                "date": r["Date"], "crashes": num_or_none(r.get("Daily Crashes")),
                "anrs": num_or_none(r.get("Daily ANRs"))})
    for k in out:
        out[k].sort(key=lambda x: x["date"])
    if not out:
        raise RuntimeError("no ratings or crashes exports readable")
    state["health"]["playDaily"] = {k: v[-60:] for k, v in out.items()}
    state["health"]["playDaily"]["asOf"] = max((v[-1]["date"] for v in out.values() if v), default=None)
    return ", ".join(f"{k}: {len(v)} day(s) to {v[-1]['date']}" for k, v in out.items())


def play_acquisition(state):
    """Store-listing acquisitions, visitors and conversion. NOT the same number
    as installs and never labeled as one: acquisitions count installs that came
    THROUGH the listing. It carries visitors, so it says whether the LISTING is
    working. Two file families live here: `total_*` is a rollup that can stall
    while the plain one is current, so prefer the plain name."""
    bucket, pkg = _bucket(), ID["playPackage"]
    by_day, by_country, by_source = {}, {}, {}
    for ym in _months(3):
        for dim, sink in (("country", by_country), ("traffic_source", by_source)):
            raw = None
            for stem in ("store_performance", "total_store_performance"):
                raw, _ = _gcs_bytes(bucket, f"stats/store_performance/{stem}_{pkg}_{ym}_{dim}.csv")
                if raw:
                    break
            if not raw:
                continue
            try:
                rows = play_csv(raw)
            except Exception:                          # noqa: BLE001
                continue
            for r in rows:
                acq = num_or_none(r.get("Store listing acquisitions"))
                vis = num_or_none(r.get("Store listing visitors"))
                if acq is None and vis is None:
                    continue                           # no such column: not a zero
                key = (r.get("Country / region") or r.get("Traffic source") or "?").strip()
                day = r.get("Date")
                if dim == "country" and day:
                    d0 = by_day.setdefault(day, {"acquisitions": 0, "visitors": 0})
                    d0["acquisitions"] += acq or 0
                    d0["visitors"] += vis or 0
                sink[key] = sink.get(key, 0) + (acq or 0)
    if not by_day:
        raise RuntimeError("no store-performance reports readable")
    daily = [{"date": k, **v} for k, v in sorted(by_day.items())][-60:]
    acq = sum(r["acquisitions"] for r in daily[-28:])
    vis = sum(r["visitors"] for r in daily[-28:])
    top = lambda d: dict(sorted(d.items(), key=lambda kv: -kv[1])[:12])  # noqa: E731
    state["health"]["playAcquisition"] = {
        "daily": daily, "asOf": daily[-1]["date"], "acquisitions28d": acq, "visitors28d": vis,
        "conversion28d": round(acq / vis, 4) if vis else None,
        "byCountry": top(by_country), "bySource": top(by_source),
    }
    return f"{acq} acquisition(s) from {vis} visitor(s) to {daily[-1]['date']}" + (
        f", {acq / vis:.0%} conversion" if vis else "")


def play_rating(state):
    """The public listing rating (Play has no ratings API), falling back to the
    daily export's running average when the scrape misses — and saying so."""
    pkg = need("playPackage", "play.package")
    avg = cnt = None
    try:
        html = get(f"https://play.google.com/store/apps/details?id={pkg}&hl=en&gl=US").decode("utf-8", "replace")
        m = re.search(r'\[\[\["([0-9]\.[0-9])"\]\],\[\[', html)
        avg = float(m.group(1)) if m else None
        c = re.search(r'(\d[\d,]*)\s*(?:reviews|ratings)', html)
        cnt = int(c.group(1).replace(",", "")) if c else None
    except urllib.error.HTTPError as e:
        if e.code != 404:
            raise
    via = "the store page"
    if avg is None:
        rs = [r for r in (((state.get("health") or {}).get("playDaily") or {}).get("ratings") or [])
              if isinstance(r.get("total"), (int, float))]
        if rs:
            avg, via = round(float(rs[-1]["total"]), 2), f"Play's daily export to {rs[-1].get('date')}"
    if avg is None and cnt is None:
        raise RuntimeError("the Play listing carries no rating yet (Play prints none below a minimum audience)")
    state["ratings"].append({"store": "Google Play", "average": avg, "count": cnt, "via": via,
                             "url": f"https://play.google.com/store/apps/details?id={pkg}"})
    return f"{avg} from {cnt if cnt is not None else 'an uncounted number of'} rating(s), via {via}"


# ─────────────────────────────────────────────────────────────── Amazon

# There IS an Amazon reporting API. `invalid_scope` reads exactly like a denied
# account and is not: the security profile must be MAPPED to each API at My
# Settings > API Access (/apps-and-games/console/api-access/home.html).
# ROUTE DISCRIMINATOR: an unknown path answers 400 "Unable to fetch the request
# scope for uri"; a REAL path with no data answers 404 (vitals) or 400 "Report
# not found" (sales). Never treat them as the same failure.
AMAZON_CREDS = Path.home() / ".config" / "amazon" / "appstore.json"
AMAZON_TOKEN_URL = "https://api.amazon.com/auth/o2/token"
AMAZON_API = "https://developer.amazon.com/api/appstore"
AMAZON_SCOPE = "adx_reporting::appstore:marketer"
AMAZON_METRIC_SETS = ("crashMetricSet", "anrMetricSet", "lmkMetricSet")


def _amazon_pkg():
    return need("amazonPackage", "amazon.package (the Fire TV package; often the same as play.package)")


def _amazon_app_id():
    v = os.environ.get("AMAZON_APP_ID", "").strip()
    if v or not AMAZON_CREDS.exists():
        return v
    try:
        return (json.loads(AMAZON_CREDS.read_text()).get("app_id") or "").strip()
    except Exception:                                  # noqa: BLE001
        return ""


def _amazon_token(scope=None):
    """Client-credentials token, or (None, why-not). TWO SCOPES, two APIs:
    `adx_reporting::appstore:marketer` reads vitals and sales,
    `appstore::apps:readwrite` reads the app's edits. A token minted for one is
    refused by the other, which reads as a permissions failure."""
    cid, secret = os.environ.get("AMAZON_CLIENT_ID"), os.environ.get("AMAZON_CLIENT_SECRET")
    if not (cid and secret) and AMAZON_CREDS.exists():
        d = json.loads(AMAZON_CREDS.read_text())
        cid, secret = d.get("client_id"), d.get("client_secret")
    if not (cid and secret):
        return None, "no Amazon credentials in this environment (AMAZON_CLIENT_ID / AMAZON_CLIENT_SECRET)"
    body = urllib.parse.urlencode({"grant_type": "client_credentials", "client_id": cid,
                                   "client_secret": secret, "scope": scope or AMAZON_SCOPE}).encode()
    req = urllib.request.Request(AMAZON_TOKEN_URL, data=body,
                                 headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        return json.load(urllib.request.urlopen(req, timeout=30))["access_token"], None
    except urllib.error.HTTPError as e:
        try:
            err = json.loads(e.read().decode()).get("error", "?")
        except Exception:                              # noqa: BLE001
            err = f"HTTP {e.code}"
        if err == "invalid_scope":
            return None, ("the security profile is not MAPPED to this API — My Settings > "
                          "API Access, attach it (a mapping, not a permission)")
        return None, f"Amazon token refused: {err}"


def amazon_vitals(state):
    pkg = _amazon_pkg()
    tok, why = _amazon_token()
    if not tok:
        raise RuntimeError(why)
    out, empty = {}, []
    for ms in AMAZON_METRIC_SETS:
        req = urllib.request.Request(f"{AMAZON_API}/vitals/apps/{pkg}/{ms}",
                                     headers={"Authorization": f"Bearer {tok}", "Accept": "application/json"})
        try:
            out[ms] = json.load(urllib.request.urlopen(req, timeout=45))
        except urllib.error.HTTPError as e:
            if e.code == 404:                          # real route, no data for this app
                empty.append(ms)
                continue
            raise RuntimeError(f"{ms}: HTTP {e.code}")
    state["health"]["amazonVitals"] = {
        "freshness": out, "empty": empty, "package": pkg,
        "console": "https://developer.amazon.com/reporting/console/apphealth/performance/applatency",
    }
    if out:
        return f"{len(out)} metric set(s) with data, {len(empty)} empty"
    return f"authenticated; Amazon holds no vitals for this app yet ({len(empty)}/{len(AMAZON_METRIC_SETS)} empty)"


def amazon_sales_rows(rows):
    """Amazon's SALES report rows -> (daily, byCountry, transactionTypes). Pure.
    For a FREE app every install is a $0.00 `Charge` row; a refund or an
    adjustment is not an install. The type histogram is kept so a future
    transaction type cannot be silently miscounted as one."""
    daily, country, kind = {}, {}, {}
    for r in rows:
        t = (r.get("Transaction Type") or "").strip()
        kind[t] = kind.get(t, 0) + 1
        if t != "Charge":
            continue
        day = (r.get("Transaction Time") or "")[:10]
        if day:
            daily[day] = daily.get(day, 0) + 1
        c = (r.get("Country/Region Code") or "??").strip()
        country[c] = country.get(c, 0) + 1
    return daily, country, kind


def amazon_installs(state):
    """Fire TV installs, from the SALES report. The obvious route does not exist:
        /download/report/acquisition/<y>/<m>  400 "Unable to fetch the request scope"  NO SUCH ROUTE
        /download/report/sales/<y>/<m>        200 + a 5-minute presigned S3 url to a CSV zip
    "Report not found" is a real route with no data for that month."""
    _amazon_pkg()
    tok, why = _amazon_token()
    if not tok:
        raise RuntimeError(why)
    t0 = dt.date.today()
    months = [(t0.year, t0.month)]
    prev = t0.replace(day=1) - dt.timedelta(days=1)
    months.append((prev.year, prev.month))
    rows, periods, missing = [], [], []
    for year, month in months:
        req = urllib.request.Request(f"{AMAZON_API}/download/report/sales/{year}/{month:02d}",
                                     headers={"Authorization": f"Bearer {tok}"})
        try:
            link = urllib.request.urlopen(req, timeout=45).read().decode().strip()
        except urllib.error.HTTPError as e:
            body = e.read().decode()[:160]
            if e.code == 400 and "Report not found" in body:
                missing.append(f"{year}-{month:02d}")
                continue
            if e.code == 400 and "request scope" in body:
                raise RuntimeError("the sales report route is gone — Amazon moved it")
            raise RuntimeError(f"sales {year}-{month:02d}: HTTP {e.code}")
        blob = urllib.request.urlopen(link, timeout=90).read()
        with zipfile.ZipFile(io.BytesIO(blob)) as z:
            for name in z.namelist():
                rows.extend(csv.DictReader(io.StringIO(z.read(name).decode("utf-8-sig", "replace"))))
        periods.append(f"{year}-{month:02d}")
    daily, country, kind = amazon_sales_rows(rows)
    state["health"]["amazonInstalls"] = {
        "daily": [{"date": d, "installs": n} for d, n in sorted(daily.items())],
        "byCountry": sorted(({"key": k, "value": v} for k, v in country.items()), key=lambda x: -x["value"]),
        "total": sum(daily.values()) if periods else None,
        "periods": periods, "noReport": missing, "transactionTypes": kind,
        "readVia": "Appstore Sales Reporting API (free installs are $0.00 Charge rows)",
        "console": "https://developer.amazon.com/apps-and-games/console/reports/download-center.html",
    }
    if not periods:
        return "no sales report exists yet for either month"
    return f"{sum(daily.values())} install(s) across {len(periods)} month(s), {len(country)} countries"


def amazon_live(state):
    """WHICH BUILD IS LIVE on Fire TV, read rather than declared. Amazon has no
    live-version route; the only way to see the live APK set is an EDIT, which
    Amazon seeds from what is live. THE GUARD: an edit that already exists is
    somebody's IN-FLIGHT SUBMISSION. This reader creates an edit only when
    there is none, deletes only the edit it created, and reads any existing
    one without touching it."""
    _amazon_pkg()
    tok, why = _amazon_token("appstore::apps:readwrite")
    if not tok:
        raise RuntimeError(why)
    app = _amazon_app_id()
    if not app:
        raise RuntimeError("no AMAZON_APP_ID — the app's devportal id is needed to ask which build is live")
    base = f"https://developer.amazon.com/api/appstore/v1/applications/{app}"

    def call(method, path, body=None, etag=None):
        headers = {"Authorization": f"Bearer {tok}", "Accept": "application/json",
                   "Content-Type": "application/json", "User-Agent": ua()}
        if etag:
            headers["If-Match"] = etag
        req = urllib.request.Request(base + path, data=body, method=method, headers=headers)
        try:
            r = urllib.request.urlopen(req, timeout=45)
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw.strip() else {}), r.headers.get("ETag")
        except urllib.error.HTTPError as e:
            return e.code, {}, e.headers.get("ETag")

    st, existing, _ = call("GET", "/edits")
    mine, eid = False, (existing or {}).get("id")
    if not eid:
        st, made, _ = call("POST", "/edits", b"")
        eid, mine = (made or {}).get("id"), True
        if not eid:
            raise RuntimeError(f"could not open an edit to read the live build (HTTP {st})")
    _, apks, _ = call("GET", f"/edits/{eid}/apks")
    builds = [{"versionCode": k.get("versionCode"), "name": k.get("name")}
              for k in (apks if isinstance(apks, list) else [])]
    if mine:                                           # delete ONLY what this reader created
        _, _, tag = call("GET", f"/edits/{eid}")
        call("DELETE", f"/edits/{eid}", etag=tag)
    live = max((b["versionCode"] for b in builds if b.get("versionCode") is not None), default=None)
    state["health"]["amazonLive"] = {
        "liveVersionCode": live, "builds": builds, "submissionInFlight": bool(eid and not mine),
        "readVia": "an existing edit, left untouched" if not mine else "a temporary edit, created and deleted",
        "console": "https://developer.amazon.com/apps-and-games/console/apps/list.html",
    }
    if not mine:
        return f"versionCode {live} in the OPEN edit — a submission is in flight, so this is what is staged"
    return f"versionCode {live} is live on Fire TV"


# ─────────────────────────────────────────── Roku — delivered, never served

def _roku_rows(csv_text):
    """Looker writes a leading unnamed index column on multi-row tables."""
    rows = list(csv.DictReader(io.StringIO(csv_text)))
    for r in rows:
        r.pop("", None)
    return rows


def roku_parse_zip(zf):
    """Every tile in one delivered Roku dashboard -> (daily, headline, tables,
    tiles, empty). Pure and tested. THREE KINDS OF TILE, not alternatives:
      * a DATED series — a date column (ANY case) plus numeric columns
      * a TABLE        — more than one row, kept whether or not it is dated
                         (crash logs carry a date AND Error Text / App Version)
      * a HEADLINE     — a single undated row of numbers
    An EMPTY tile is recorded, not dropped: forty empty device tiles mean
    nothing crashed on any model, which must stay distinguishable from a report
    that never arrived."""
    daily, headline, tables, tiles, empty = {}, {}, {}, [], []
    for name in zf.namelist():
        tile = name.rsplit("/", 1)[-1].replace(".csv", "")
        tiles.append(tile)
        rows = _roku_rows(zf.read(name).decode("utf-8-sig", "replace"))
        if not rows:
            empty.append(tile)
            continue
        for r in rows:
            date = next((v for k, v in r.items() if k and "date" in k.lower()
                         and re.match(r"^\d{4}-\d{2}-\d{2}$", str(v))), None)
            if not date:
                continue
            slot = daily.setdefault(date, {"date": date})
            for k, v in r.items():
                if not k or "date" in k.lower():
                    continue
                n = num_or_none(v, float)
                if n is not None:
                    slot[k.split(" Time Grain ")[-1].strip()] = n
        if len(rows) > 1:
            tables[tile] = [{k: v for k, v in r.items() if k and v not in (None, "")} for r in rows[:40]]
        if len(rows) == 1 and not any("date" in (k or "").lower() for k in rows[0]):
            for k, v in rows[0].items():
                n = num_or_none(v, float)
                if n is not None:
                    headline[k.split(" Time Grain ")[-1].strip()] = n
    return daily, headline, tables, tiles, empty


def _vkey(v):
    """1.0.75 sorts after 1.0.9: compare versions as numbers, never strings."""
    try:
        return tuple(int(x) for x in str(v or "").split("."))
    except ValueError:
        return (0,)


def roku_versions_in(tables):
    """Which versions Roku has SEEN IN THE FIELD. Crash logs carry `App
    Version`, and a version cannot appear there unless it is on real devices.
    EVIDENCE, not a roster: a version APPEARING proves it shipped; a flawless
    release never appears, so absence proves nothing."""
    seen: dict = {}
    for rows in (tables or {}).values():
        for r in rows:
            v = str(r.get("App Version") or "").strip()
            if not v:
                continue
            day = str(r.get("Date") or r.get("Error Key Date") or "")[:10]
            slot = seen.setdefault(v, {"version": v, "firstSeen": day, "lastSeen": day})
            if day:
                slot["firstSeen"] = min(slot["firstSeen"] or day, day)
                slot["lastSeen"] = max(slot["lastSeen"] or day, day)
    return sorted(seen.values(), key=lambda x: _vkey(x["version"]))


ROKU_QUIET_DAYS = 4


def roku_engagement(state):
    """Roku's Looker dashboards, delivered to our drop box. Roku has NO
    analytics API; the only automated way out is a scheduled delivery (email,
    webhook, S3, SFTP). The webhook posts to the Worker's /ingest/roku and this
    reads what landed. Payload, measured from a real delivery:
        {"scheduled_plan": {"title": "App Engagement", ...},
         "attachment": {"mimetype": "application/zip;base64", "data": "<b64 zip of CSVs>"}}
    One CSV per dashboard TILE: the tile names are the schema."""
    origin = need("ingest", "web.ingestOrigin")
    # The newest row we ALREADY hold, from the previous reading — read BEFORE
    # this reader writes its own (possibly empty) one. Reading it afterwards
    # measures what we just wrote, and the quiet-feed alarm never fires.
    held = max((r.get("date") or "" for r in
                (((state.get("_prev") or {}).get("health") or {}).get("rokuEngagement") or {}).get("daily") or []),
               default="")
    tok = os.environ.get("PULSE_INGEST_TOKEN")
    if not tok:
        raise RuntimeError("no PULSE_INGEST_TOKEN in this environment — the drop box cannot be read without it")
    try:
        drops = json.loads(get(f"{origin}/drops?vendor=roku&t={urllib.parse.quote(tok)}", timeout=45)).get("rows", [])
    except urllib.error.HTTPError as e:
        if e.code == 404:
            raise RuntimeError("the drop box refused the token (it answers 404, not 403, to a bad one)")
        raise RuntimeError(f"drop box: HTTP {e.code} — a 403 here is Cloudflare refusing the "
                           f"client, not the Worker refusing the token")
    daily, headline, tiles, consumed, bad, reports = {}, {}, [], [], [], {}
    for d in drops:
        try:
            body = json.loads(d.get("body") or "")
            zf = zipfile.ZipFile(io.BytesIO(base64.b64decode(body["attachment"]["data"])))
        except Exception as exc:                       # noqa: BLE001
            # KEEP the drop. A payload we cannot read is the only evidence of
            # the shape that broke us, and acking it would delete that.
            bad.append({"id": d.get("id"), "why": str(exc)[:120]})
            continue
        # Four dashboards, four schedules, one endpoint: kept APART by the
        # plan title, or a crash rate and an install count share a bucket.
        plan = ((body.get("scheduled_plan") or {}).get("title") or "").strip() or "unnamed"
        bucket = reports.setdefault(plan, {"daily": {}, "headline": {}, "tiles": [], "tables": {}, "empty": []})
        rdaily, rhead, rtables, rtiles, rempty = roku_parse_zip(zf)
        for k, v in rdaily.items():
            bucket["daily"][k] = {**bucket["daily"].get(k, {}), **v}
            daily.setdefault(k, {"date": k}).update(v)
        bucket["headline"].update(rhead)
        bucket["tables"].update(rtables)
        bucket["tiles"].extend(rtiles)
        bucket["empty"].extend(rempty)
        tiles.extend(rtiles)
        headline.update(rhead)
        consumed.append(d.get("id"))
    # ACK ONLY ON A REAL RUN. The drop box DELETES what it acks, so a dry run
    # that acked destroyed the delivery it was only supposed to look at.
    for did in (consumed if state.get("_apply") else []):
        try:
            urllib.request.urlopen(urllib.request.Request(
                f"{origin}/drops?id={did}&t={urllib.parse.quote(tok)}",
                method="POST", headers={"User-Agent": ua()}), timeout=30).read()
        except Exception:                              # noqa: BLE001 — a re-read is harmless; merge is keyed by date
            pass
    state["health"]["rokuEngagement"] = {
        "daily": sorted(daily.values(), key=lambda r: r["date"]),
        "headline": headline, "tiles": sorted(set(tiles)),
        "dropsRead": len(consumed), "unreadable": bad,
        "byReport": {k: {"daily": sorted(v["daily"].values(), key=lambda r: r["date"]),
                         "headline": v["headline"], "tiles": sorted(set(v["tiles"])),
                         "tables": v["tables"], "emptyTiles": sorted(set(v["empty"]))}
                     for k, v in reports.items()},
        "versionsSeen": roku_versions_in({k: t for rep in reports.values() for k, t in rep["tables"].items()}),
        "reportsSeen": sorted(reports),
        "readVia": "Looker scheduled delivery -> Worker /ingest/roku (no Roku API exists)",
        "console": ID.get("rokuConsole") or "https://developer.roku.com/",
    }
    kept = "" if state.get("_apply") else " (dry run — left in the box)"
    if bad:
        return f"{len(consumed)} drop(s) read{kept}, {len(bad)} UNREADABLE and kept for inspection"
    if not consumed:
        # "Nothing waiting" is normal between runs AND indistinguishable from a
        # deleted schedule or a rotated token. The age of the newest row we
        # already HOLD (captured before this reader overwrote it) is the alarm.
        if held:
            try:
                behind = (dt.date.today() - dt.date.fromisoformat(held)).days
            except ValueError:
                behind = None
            if behind is not None and behind > ROKU_QUIET_DAYS:
                raise RuntimeError(
                    f"no Roku delivery for {behind} days (newest row {held}). The report's own "
                    f"window ends ~2 days back, so the SCHEDULE is the suspect: check it still "
                    f"exists and still points at /ingest/roku with the current token")
        return "no delivery waiting — normal between scheduled runs"
    return (f"{len(consumed)} drop(s), {len(daily)} day(s), {len(set(tiles))} tile(s) from "
            f"{len(reports)} report(s) [{', '.join(sorted(reports))}]{kept}")


# ─────────────────────── The website and our own server — what they ALREADY see

def web_usage(state):
    """Page views from the counter we own (pulse/worker-example). Its entire
    storage is `day | path-shape | count`: no IP, cookie, visitor id, referrer
    or country. That costs referrers, countries and a funnel; it buys the
    privacy page being true. A VISIT (`(visit)`, one page load) and a ROUTE
    VIEW are different measurements and are never summed — summing reports
    navigation as audience."""
    origin = need("counter", "web.counterOrigin")
    d = get_json(f"{origin}/views?days=90", timeout=30)
    rows = d.get("rows") or []
    if not rows:
        raise RuntimeError("the counter is reachable but has no rows yet — just deployed, or the beacon is not live")
    by_day, by_path, visits = {}, {}, {}
    for r in rows:
        day, path, n = r.get("day"), r.get("path"), int(r.get("count") or 0)
        if not day:
            continue
        if path == "(visit)":
            visits[day] = visits.get(day, 0) + n
            continue
        by_day[day] = by_day.get(day, 0) + n
        by_path[path or "?"] = by_path.get(path or "?", 0) + n
    daily = [{"date": k, "views": by_day.get(k, 0), "visits": visits.get(k)}
             for k in sorted(set(by_day) | set(visits))]
    state["health"]["webUsage"] = {
        "daily": daily,
        "views28d": sum(r["views"] for r in daily[-28:]),
        "visits28d": total(r["visits"] for r in daily[-28:]),
        "byPath": dict(sorted(by_path.items(), key=lambda kv: -kv[1])[:12]),
        "since": d.get("since"),
        # The first day the counter separated visits from route views. Rows
        # before it are not comparable and the page says so.
        "splitFrom": min(visits) if visits else None,
    }
    return f"{sum(by_day.values())} route view(s) and {sum(visits.values())} visit(s) over {len(daily)} day(s)"


def counter_tallies(state):
    """Anonymous `day | kind | count` tallies our server already keeps in order
    to PROVIDE a feature (rooms opened, feed sign-ins, assistant calls). No app
    sends anything new: a usage number must come from something a server
    already receives, or from a vendor's own reporting — never from a client
    sending a count."""
    origin = need("counter", "web.counterOrigin")
    specs = ID.get("tallies") or []
    if not specs:
        raise NotConfigured("list web.tallies in ops/pulse.config.json")
    out, notes = {}, []
    t0 = dt.date.today()
    for spec in specs:
        name, kinds = spec.get("name"), list(spec.get("kinds") or [])
        if not (name and spec.get("path")):
            continue
        sep = "&" if "?" in spec["path"] else "?"
        d = get_json(f"{origin}{spec['path']}{sep}days=120", timeout=30)
        days: dict = {}
        for r in d.get("rows") or []:
            k = r.get("kind")
            if r.get("day") and (not kinds or k in kinds):
                days.setdefault(r["day"], {})[k] = int(r.get("count") or 0)
        kinds = kinds or sorted({k for v in days.values() for k in v})
        daily = [{"date": k, **{x: v.get(x, 0) for x in kinds}} for k, v in sorted(days.items())]

        def window(a, b):
            lo, hi = str(t0 - dt.timedelta(days=a)), str(t0 - dt.timedelta(days=b))
            return {k: sum(r.get(k, 0) for r in daily if lo <= r["date"] <= hi) for k in kinds}
        out[name] = {"label": spec.get("label") or name, "kinds": kinds, "daily": daily,
                     "since": d.get("since") or (daily[0]["date"] if daily else None),
                     "last28": window(27, 0), "prev28": window(55, 28), "note": spec.get("note")}
        notes.append(f"{name}: {sum(out[name]['last28'].values())} in 28 days")
    state["health"]["tallies"] = out
    return "; ".join(notes) or "no tally answered"


def cloud_api_usage(state):
    """A vendor's OWN count of the calls our app made (Cloud Monitoring's
    serviceruntime request_count for one service on one project). NOT
    telemetry: the app sends us nothing. Google serves these metrics only when
    the read is BILLED to a project with billing, so the request carries
    `x-goog-user-project`; without it the API answers "requires billing"."""
    c = ID.get("cloud") or {}
    project, service = c.get("project"), c.get("service")
    if not (project and service):
        raise NotConfigured("set cloudUsage.project and cloudUsage.service in ops/pulse.config.json")
    tok = _google(["https://www.googleapis.com/auth/monitoring.read"])
    end = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    start = end - dt.timedelta(days=90)
    params = urllib.parse.urlencode([
        ("filter", 'metric.type="serviceruntime.googleapis.com/api/request_count" '
                   f'AND resource.type="consumed_api" AND resource.labels.service="{service}"'),
        ("interval.startTime", start.strftime("%Y-%m-%dT%H:%M:%SZ")),
        ("interval.endTime", end.strftime("%Y-%m-%dT%H:%M:%SZ")),
        ("aggregation.alignmentPeriod", "86400s"),
        ("aggregation.perSeriesAligner", "ALIGN_SUM"),
        ("aggregation.crossSeriesReducer", "REDUCE_SUM"),
        ("aggregation.groupByFields", "resource.labels.method"),
        ("aggregation.groupByFields", "metric.labels.response_code_class"),
    ])
    series = json.loads(get(f"https://monitoring.googleapis.com/v3/projects/{project}/timeSeries?{params}",
                            {"Authorization": f"Bearer {tok}", "x-goog-user-project": project},
                            timeout=45).decode()).get("timeSeries") or []
    events = c.get("events") or {}
    units = c.get("units") or {}

    def day_of(pt):                                    # an aligned day ENDS at endTime
        t = dt.datetime.strptime(pt["interval"]["endTime"][:19], "%Y-%m-%dT%H:%M:%S")
        return str((t - dt.timedelta(seconds=1)).date())

    days, by_method = {}, {}
    for ts in series:
        method = ts["resource"]["labels"].get("method", "")
        ok = ts["metric"]["labels"].get("response_code_class", "") == "2xx"
        short = ".".join(method.rsplit(".", 2)[-2:])
        cost = units.get(method, units.get(method.rsplit(".", 1)[-1], 1))
        for pt in ts.get("points") or []:
            n = int(pt["value"].get("int64Value") or 0)
            dd = days.setdefault(day_of(pt), {"calls": 0, "errors": 0, "units": 0, **{e: 0 for e in events}})
            dd["calls"] += n
            dd["units"] += n * cost
            dd["errors"] += 0 if ok else n
            for e, suffix in events.items():
                if ok and method.endswith(suffix):
                    dd[e] += n
            m = by_method.setdefault(short, {"calls": 0, "errors": 0, "units": 0})
            m["calls"] += n
            m["units"] += n * cost
            m["errors"] += 0 if ok else n
    state["health"]["cloudUsage"] = {
        "service": service, "daily": [{"date": k, **v} for k, v in sorted(days.items())],
        "byMethod": dict(sorted(by_method.items(), key=lambda kv: -kv[1]["units"])),
        "events": list(events), "quotaPerDay": c.get("quotaPerDay"),
    }
    peak = max((v["units"] for v in days.values()), default=0)
    ev = ", ".join(f"{sum(v[e] for v in days.values())} {e}" for e in events)
    return f"{sum(v['calls'] for v in days.values())} call(s) in 90 days{'; ' + ev if ev else ''}; peak day {peak:,} units"


# ─────────────────────────────────────────── Google Search Console

def _gpost(url, token, body, extra=None):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST",
                                 headers={"Authorization": f"Bearer {token}", "User-Agent": ua(),
                                          "Content-Type": "application/json", **(extra or {})})
    with urllib.request.urlopen(req, timeout=45) as r:
        return json.loads(r.read().decode())


def search_console(state):
    """How people FIND the site: clicks, impressions, CTR and average position.
    Search data is `final` only and lags 2-3 days, so `through` is Google's
    newest finished day and every comparison is 28 days to `through` against
    the 28 before. A prior period Google never measured is NULL, not zero."""
    site = need("searchSite", "search.site")
    tok = _google(["https://www.googleapis.com/auth/webmasters.readonly"])
    base = "https://searchconsole.googleapis.com/webmasters/v3/sites/" + urllib.parse.quote(site, safe="")
    end = dt.date.today()

    def q(start, stop, dims, limit=100):
        return _gpost(base + "/searchAnalytics/query", tok,
                      {"startDate": str(start), "endDate": str(stop), "dimensions": dims,
                       "rowLimit": limit, "dataState": "final"}).get("rows") or []

    def row(r):
        return {"clicks": int(r.get("clicks") or 0), "impressions": int(r.get("impressions") or 0),
                "ctr": round(float(r.get("ctr") or 0), 4), "position": round(float(r.get("position") or 0), 2)}

    daily = [{"date": r["keys"][0], **row(r)} for r in q(end - dt.timedelta(days=95), end, ["date"], 400)]
    if not daily:
        raise RuntimeError("Search Console returned no days (a new property, or the robot is not a user on it)")
    through = dt.date.fromisoformat(daily[-1]["date"])
    cur0, prev0 = through - dt.timedelta(days=27), through - dt.timedelta(days=55)
    prev1 = cur0 - dt.timedelta(days=1)

    def tot(start, stop):
        rs = [d for d in daily if str(start) <= d["date"] <= str(stop)]
        c, i = sum(d["clicks"] for d in rs), sum(d["impressions"] for d in rs)
        pos = (sum(d["position"] * d["impressions"] for d in rs) / i) if i else None
        return {"clicks": c, "impressions": i, "ctr": round(c / i, 4) if i else None,
                "position": round(pos, 2) if pos else None, "days": len(rs)}

    prev_whole = sum(1 for d in daily if str(prev0) <= d["date"] <= str(prev1)) >= 28

    def split(dim, limit=100):
        now_rows = {r["keys"][0]: row(r) for r in q(cur0, through, [dim], limit)}
        before = {r["keys"][0]: row(r) for r in q(prev0, prev1, [dim], 1000)} if prev_whole else None
        out = []
        for k, v in now_rows.items():
            b = (before or {}).get(k) or {}
            out.append({"key": k, **v,
                        "prevClicks": b.get("clicks", 0) if before is not None else None,
                        "prevImpressions": b.get("impressions", 0) if before is not None else None,
                        "prevPosition": b.get("position")})
        return sorted(out, key=lambda r: (-r["clicks"], -r["impressions"]))

    sitemaps = []
    try:
        for sm in json.loads(get(base + "/sitemaps", {"Authorization": f"Bearer {tok}"}, 30).decode()).get("sitemap") or []:
            contents = sm.get("contents") or []
            sitemaps.append({
                "path": sm.get("path"), "lastSubmitted": sm.get("lastSubmitted"),
                "lastDownloaded": sm.get("lastDownloaded"), "isPending": sm.get("isPending"),
                "errors": int(sm.get("errors") or 0), "warnings": int(sm.get("warnings") or 0),
                "submitted": sum(int(c.get("submitted") or 0) for c in contents),
                "indexed": sum(int(c.get("indexed") or 0) for c in contents)})
    except Exception:                                  # noqa: BLE001 — a part, not the reading
        pass
    last28, prev28 = tot(cur0, through), tot(prev0, prev1)
    pages = split("page", 1000)
    pat = ID.get("pagePattern")
    focus = [r for r in pages if pat and re.search(pat, r["key"])]
    state["health"]["searchConsole"] = {
        "through": str(through), "daily": daily, "last28": last28,
        "prev28": prev28 if prev_whole else {**prev28, "whole": False},
        "queries": split("query"), "pages": pages[:50],
        "focusPages": {"pattern": pat, "clicks": sum(r["clicks"] for r in focus),
                       "impressions": sum(r["impressions"] for r in focus),
                       "pages": len(focus), "top": focus[:25]} if pat else None,
        "countries": split("country", 60), "devices": split("device", 5), "sitemaps": sitemaps,
        "url": "https://search.google.com/search-console?resource_id=" + urllib.parse.quote(site, safe=""),
    }
    return (f"{last28['clicks']} clicks / {last28['impressions']} impressions in 28 days to {through} "
            f"(prior 28: {prev28['clicks'] if prev_whole else 'not a whole period yet'})")


def search_index(state):
    """How much of what we publish Google has actually INDEXED. Inspects a
    date-seeded rotating SAMPLE of the sitemap's matching URLs through the URL
    Inspection API (2,000 a day per property), eight at a time (one at a time
    outran a whole reading's budget). The share is an ESTIMATE and says so;
    faults we can fix (redirect, noindex, a different Google canonical) are
    named per URL."""
    import random
    from concurrent.futures import ThreadPoolExecutor
    site = need("searchSite", "search.site")
    pat = need("pagePattern", "search.pagePattern")
    root = ID.get("site") or site.replace("sc-domain:", "https://").rstrip("/")
    tok = _google(["https://www.googleapis.com/auth/webmasters.readonly"])
    idx = get(f"{root.rstrip('/')}/sitemap.xml", timeout=30).decode()
    urls = []
    locs = re.findall(r"<loc>([^<]+)</loc>", idx)
    if "<sitemapindex" in idx:
        for sm in locs:
            urls += re.findall(r"<loc>([^<]+)</loc>", get(sm, timeout=60).decode())
    else:
        urls = locs
    pages = [u for u in urls if re.search(pat, u)]
    if not pages:
        raise RuntimeError(f"the sitemap lists no URL matching {pat!r}")
    rnd = random.Random(f"{today()}-{dt.datetime.now(dt.timezone.utc).hour // 12}")
    sample = rnd.sample(pages, min(ID.get("sampleSize") or 150, len(pages)))

    def inspect(u):
        try:
            return u, _gpost("https://searchconsole.googleapis.com/v1/urlInspection/index:inspect",
                             tok, {"inspectionUrl": u, "siteUrl": site})
        except urllib.error.HTTPError as e:
            if e.code == 429:                          # the day's quota: report what we have
                return u, None
            raise
    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(inspect, sample))
    by_state, faults, examples = {}, [], []
    for u, res in results:
        if res is None:
            continue
        ix = (res.get("inspectionResult") or {}).get("indexStatusResult") or {}
        cov = ix.get("coverageState") or "unknown"
        by_state[cov] = by_state.get(cov, 0) + 1
        row = {"url": u, "state": cov, "verdict": ix.get("verdict"), "lastCrawl": ix.get("lastCrawlTime"),
               "fetch": ix.get("pageFetchState"), "googleCanonical": ix.get("googleCanonical")}
        bad = (ix.get("pageFetchState") not in (None, "SUCCESSFUL", "PAGE_FETCH_STATE_UNSPECIFIED")
               or ix.get("indexingState") in ("BLOCKED_BY_META_TAG", "BLOCKED_BY_HTTP_HEADER")
               or (ix.get("googleCanonical") and ix.get("userCanonical")
                   and ix["googleCanonical"] != ix["userCanonical"]))
        if bad:
            faults.append(row)
        elif ix.get("verdict") != "PASS" and len(examples) < 40:
            examples.append(row)
    n = sum(by_state.values())
    indexed = sum(v for k, v in by_state.items() if "indexed" in k.lower() and "not indexed" not in k.lower())
    state["health"]["searchIndex"] = {
        "published": len(pages), "sampled": n, "pattern": pat,
        "indexedShare": round(indexed / n, 3) if n else None,
        "byState": dict(sorted(by_state.items(), key=lambda kv: -kv[1])),
        "faults": faults, "examples": examples,
    }
    return f"{indexed}/{n} sampled pages indexed of {len(pages):,} published; {len(faults)} fault(s)"


# ─────────────────────────────────────────────────── Who is talking about us

def _mention(state, source, title, body, url, author=None, date=None, extra=None):
    if not relevant(title, body, url):
        return False
    state["mentions"].append({"source": source, "title": clamp(title, 160), "excerpt": clamp(body, 400),
                              "url": url, "author": author, "date": date, **(extra or {})})
    return True


def _query():
    return need("query", "mentions.query")


def mentions_reddit(state):
    """Reddit's JSON search answers 403 to an unauthenticated caller; the RSS of
    the SAME search answers 200. Rate-limited hard, so one query, and fuzzy —
    `relevant()` is what makes the results usable."""
    import xml.etree.ElementTree as ET
    ns = {"a": "http://www.w3.org/2005/Atom"}
    xml = get(f"https://www.reddit.com/search.rss?q={urllib.parse.quote(_query())}&sort=new&limit=50")
    kept = 0
    for e in ET.fromstring(xml).findall("a:entry", ns):
        ln = e.find("a:link", ns)
        kept += _mention(state, "Reddit", e.findtext("a:title", "", ns),
                         re.sub(r"<[^>]+>", " ", e.findtext("a:content", "", ns) or ""),
                         ln.get("href") if ln is not None else "",
                         e.findtext("a:author/a:name", "", ns), e.findtext("a:updated", "", ns))
    return f"{kept} kept"


def mentions_hn(state):
    d = get_json("https://hn.algolia.com/api/v1/search?hitsPerPage=40&query=" + urllib.parse.quote(_query()))
    kept = 0
    for h in d.get("hits", []):
        url = h.get("url") or f"https://news.ycombinator.com/item?id={h.get('objectID')}"
        kept += _mention(state, "Hacker News", h.get("title") or h.get("story_title") or "",
                         h.get("comment_text") or h.get("story_text") or "", url, h.get("author"),
                         h.get("created_at"), {"points": h.get("points"), "comments": h.get("num_comments")})
    return f"{kept} kept of {d.get('nbHits', 0)}"


def mentions_lemmy(state):
    q, kept, errs = urllib.parse.quote(_query()), 0, []
    for host in ("lemmy.world", "lemmy.ml"):
        try:
            d = get_json(f"https://{host}/api/v3/search?q={q}&type_=All&limit=20")
        except Exception as e:                         # noqa: BLE001
            errs.append(f"{host}: {str(e)[:60]}")
            continue
        for p in d.get("posts", []):
            po = p.get("post", {})
            kept += _mention(state, "Lemmy", po.get("name", ""), po.get("body", ""),
                             po.get("ap_id") or f"https://{host}/post/{po.get('id')}",
                             (p.get("creator") or {}).get("name"), po.get("published"))
        for c in d.get("comments", []):
            co = c.get("comment", {})
            kept += _mention(state, "Lemmy", (c.get("post") or {}).get("name", ""), co.get("content", ""),
                             co.get("ap_id", ""), (c.get("creator") or {}).get("name"), co.get("published"))
    if len(errs) == 2:
        raise RuntimeError("; ".join(errs))
    return f"{kept} kept"


def mentions_news(state):
    """Google News RSS — the only free route to press coverage."""
    import xml.etree.ElementTree as ET
    xml = get(f"https://news.google.com/rss/search?q={urllib.parse.quote(_query())}&hl=en-US&gl=US&ceid=US:en")
    kept = 0
    for it in ET.fromstring(xml).iter("item"):
        kept += _mention(state, "News", it.findtext("title", ""), it.findtext("description", ""),
                         it.findtext("link", ""), it.findtext("source", ""), it.findtext("pubDate", ""))
    return f"{kept} kept"


def _bluesky_session(handle, pw):
    sess = json.loads(urllib.request.urlopen(urllib.request.Request(
        "https://bsky.social/xrpc/com.atproto.server.createSession",
        data=json.dumps({"identifier": handle, "password": pw}).encode(),
        headers={"Content-Type": "application/json", "User-Agent": ua()}), timeout=25).read())
    return {"Authorization": "Bearer " + sess["accessJwt"]}


def _social_on(platform, *env):
    """Config says whether we HAVE this platform; the environment holds the key.
    No profile and no key = not configured; a profile without its key = dark."""
    have = all(os.environ.get(e) for e in env)
    if not have and not ID["profiles"].get(platform):
        raise NotConfigured(f"no social.profiles.{platform} and no {'/'.join(env)}")
    if not have:
        raise RuntimeError(f"no {platform} credential in this environment ({'/'.join(env)})")


def mentions_bluesky(state):
    """Our own credential, used to search the whole network — not just our posts."""
    _social_on("bluesky", "BLUESKY_HANDLE", "BLUESKY_APP_PASSWORD")
    if not ID["strict"]:
        raise NotConfigured("set mentions.strict in ops/pulse.config.json")
    handle = os.environ["BLUESKY_HANDLE"]
    hdr = _bluesky_session(handle, os.environ["BLUESKY_APP_PASSWORD"])
    kept = 0
    for q in ID["strict"]:
        try:
            d = get_json("https://bsky.social/xrpc/app.bsky.feed.searchPosts?limit=25&q=" + urllib.parse.quote(q), hdr)
        except Exception:                              # noqa: BLE001
            continue
        for p in d.get("posts", []):
            a = p.get("author", {})
            if a.get("handle") == handle:              # our own program, counted elsewhere
                continue
            kept += _mention(state, "Bluesky", "", (p.get("record") or {}).get("text", ""),
                             f"https://bsky.app/profile/{a.get('handle')}/post/{p.get('uri', '').split('/')[-1]}",
                             a.get("handle"), (p.get("record") or {}).get("createdAt"),
                             {"likes": p.get("likeCount"), "reposts": p.get("repostCount")})
    return f"{kept} kept"


def _mastodon():
    inst = (os.environ.get("MASTODON_INSTANCE") or os.environ.get("MASTODON_BASE_URL") or "").rstrip("/")
    tok = os.environ.get("MASTODON_ACCESS_TOKEN")
    if not (inst and tok):
        if not ID["profiles"].get("mastodon"):
            raise NotConfigured("no social.profiles.mastodon and no MASTODON_INSTANCE/MASTODON_ACCESS_TOKEN")
        raise RuntimeError("no Mastodon credential in this environment")
    return inst, {"Authorization": "Bearer " + tok}


def mentions_mastodon(state):
    inst, hdr = _mastodon()
    if not ID["strict"]:
        raise NotConfigured("set mentions.strict in ops/pulse.config.json")
    try:                                               # who are WE: our own post is not a mention
        me = get_json(f"{inst}/api/v1/accounts/verify_credentials", hdr).get("acct", "")
    except Exception:                                  # noqa: BLE001
        me = ""
    kept = 0
    for q in ID["strict"]:
        d = get_json(f"{inst}/api/v2/search?type=statuses&limit=20&q=" + urllib.parse.quote(q), hdr)
        for s in d.get("statuses", []):
            acct = (s.get("account") or {}).get("acct", "")
            if me and acct == me:
                continue
            kept += _mention(state, "Mastodon", "", re.sub(r"<[^>]+>", " ", s.get("content", "")),
                             s.get("url", ""), acct, s.get("created_at"),
                             {"likes": s.get("favourites_count"), "reposts": s.get("reblogs_count")})
    return f"{kept} kept"


# ─────────────────────────────────────────────────────── The social program

def _ledger():
    led, met = REPO / ID["ledger"], REPO / ID["metrics"]
    if not led.exists():
        raise NotConfigured(f"no posting ledger at {ID['ledger']}")
    posts = json.loads(led.read_text()).get("posts", [])
    samples = json.loads(met.read_text()).get("samples", []) if met.exists() else []
    return posts, samples


def social_program(state):
    """What we posted, and what it did — joined from the two files a posting
    program keeps. This only presents what its own metrics job measured."""
    led, met = _ledger()
    best = {}
    for s in met:                                      # the LATEST window per post wins
        k = s.get("url")
        if k and (k not in best or (s.get("sampled") or "") > (best[k].get("sampled") or "")):
            best[k] = s
    posts, per = [], {}
    for row in sorted(led, key=lambda r: r.get("at") or "", reverse=True):
        m = (best.get(row.get("url")) or {}).get("metrics") or {}
        posts.append({"at": row.get("at"), "platform": row.get("platform"), "title": row.get("title"),
                      "id": row.get("id"), "slot": row.get("slot"), "format": row.get("format"),
                      "url": row.get("url"), "mediaId": row.get("mediaId"),
                      "likes": m.get("likes"), "reposts": m.get("reposts"),
                      "replies": m.get("replies"), "views": m.get("views"),
                      "window": (best.get(row.get("url")) or {}).get("window")})
        p = per.setdefault(row.get("platform"), {"posts": 0, "likes": 0, "replies": 0,
                                                 "reposts": 0, "views": 0, "measured": 0})
        p["posts"] += 1
        if m:
            p["measured"] += 1
            for k in ("likes", "replies", "reposts", "views"):
                p[k] += int(m.get(k) or 0)
    state["social"] = {"posts": posts[:120], "byPlatform": per, "totalPosts": len(led), "measured": len(best)}
    return f"{len(led)} post(s) across {len(per)} platform(s), {len(best)} measured"


def social_reach(state):
    """Follower counts — whether the program is building anything."""
    got = {}
    handle = os.environ.get("BLUESKY_HANDLE")
    if handle:
        try:
            d = get_json("https://public.api.bsky.app/xrpc/app.bsky.actor.getProfile?actor=" + urllib.parse.quote(handle))
            got["bluesky"] = {"followers": d.get("followersCount"), "posts": d.get("postsCount")}
        except Exception as e:                         # noqa: BLE001
            got["bluesky"] = {"error": str(e)[:80]}
    try:
        inst, hdr = _mastodon()
        try:
            d = get_json(f"{inst}/api/v1/accounts/verify_credentials", hdr)
            got["mastodon"] = {"followers": d.get("followers_count"), "posts": d.get("statuses_count")}
        except Exception as e:                         # noqa: BLE001
            got["mastodon"] = {"error": str(e)[:80]}
    except (NotConfigured, RuntimeError):
        pass
    uid, itok = os.environ.get("IG_USER_ID"), os.environ.get("IG_ACCESS_TOKEN")
    if uid and itok:
        try:
            d = get_json(f"https://graph.instagram.com/v21.0/{uid}?fields=followers_count,media_count&access_token={itok}")
            got["instagram"] = {"followers": d.get("followers_count"), "posts": d.get("media_count")}
        except Exception as e:                         # noqa: BLE001
            got["instagram"] = {"error": str(e)[:80]}
    if not got:
        if not ID["profiles"]:
            raise NotConfigured("no social.profiles and no social credentials")
        raise RuntimeError("no social credential in this environment")
    state["social"].setdefault("reach", {}).update(got)
    return ", ".join(f"{k}={v.get('followers')}" for k, v in got.items())


def social_replies(state):
    """A reply to one of our posts is the cheapest user research there is —
    surfaced as a mention so it lands in the same reading list."""
    _social_on("bluesky", "BLUESKY_HANDLE", "BLUESKY_APP_PASSWORD")
    handle = os.environ["BLUESKY_HANDLE"]
    hdr = _bluesky_session(handle, os.environ["BLUESKY_APP_PASSWORD"])
    d = get_json("https://bsky.social/xrpc/app.bsky.notification.listNotifications?limit=60", hdr)
    kept = 0
    for n in d.get("notifications", []):
        a = n.get("author", {})
        if n.get("reason") not in ("reply", "mention", "quote") or a.get("handle") == handle:
            continue
        state["mentions"].append({
            "source": "Bluesky reply", "title": n.get("reason", "").title(),
            "excerpt": clamp((n.get("record") or {}).get("text", ""), 400),
            "url": f"https://bsky.app/profile/{a.get('handle')}/post/{n.get('uri', '').split('/')[-1]}",
            "author": a.get("handle"), "date": n.get("indexedAt")})
        kept += 1
    return f"{kept} reply/mention notification(s)"


def _youtube_header():
    cid, csec, rtok = (os.environ.get(k) for k in ("YOUTUBE_CLIENT_ID", "YOUTUBE_CLIENT_SECRET", "YOUTUBE_REFRESH_TOKEN"))
    if not (cid and csec and rtok):
        return None
    body = urllib.parse.urlencode({"client_id": cid, "client_secret": csec, "refresh_token": rtok,
                                   "grant_type": "refresh_token"}).encode()
    tok = json.loads(urllib.request.urlopen(urllib.request.Request(
        "https://oauth2.googleapis.com/token", data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"}), timeout=25).read())["access_token"]
    return {"Authorization": "Bearer " + tok}


def social_liveness(state):
    """Ask each platform whether the post is STILL THERE. The ledger records
    what we published, not what survived; a deleted post is not reach. A post
    is `live` only when a platform CONFIRMS it; a reader that cannot answer
    leaves `live: null` (unknown), never 'gone'."""
    posts = (state.get("social") or {}).get("posts") or []
    if not posts:
        _ledger()
        raise RuntimeError("no posts in the ledger yet")
    try:
        yt_hdr = _youtube_header()
    except Exception:                                  # noqa: BLE001
        yt_hdr = None
    handle = os.environ.get("BLUESKY_HANDLE")
    # The author feed is PUBLIC, so it is not gated on a credential. An AT-URI
    # takes a DID, not a handle; comparing record keys from the feed avoids it.
    who = handle or next((r["url"].split("/profile/")[1].split("/")[0] for r in posts
                          if r.get("platform") == "bluesky" and "/profile/" in (r.get("url") or "")), None)
    bsky_live = None
    if who:
        try:
            live, cursor = set(), None
            for _ in range(4):
                u = f"https://public.api.bsky.app/xrpc/app.bsky.feed.getAuthorFeed?actor={urllib.parse.quote(who)}&limit=100"
                d = get_json(u + (f"&cursor={urllib.parse.quote(cursor)}" if cursor else ""))
                live |= {(it.get("post", {}).get("uri") or "").rstrip("/").split("/")[-1] for it in d.get("feed", [])}
                cursor = d.get("cursor")
                if not cursor:
                    break
            bsky_live = live
        except Exception:                              # noqa: BLE001
            bsky_live = None
    try:
        inst, mhdr = _mastodon()
    except (NotConfigured, RuntimeError):
        inst = mhdr = None
    igtok, thtok = os.environ.get("IG_ACCESS_TOKEN"), os.environ.get("THREADS_ACCESS_TOKEN")

    def check(row):
        plat, url = row.get("platform"), row.get("url") or ""
        try:
            if plat == "bluesky":
                return None if bsky_live is None else url.rstrip("/").split("/")[-1] in bsky_live
            if plat == "mastodon":
                sid = url.rstrip("/").split("/")[-1]
                if not (inst and sid.isdigit()):
                    return None
                try:
                    get_json(f"{inst}/api/v1/statuses/{sid}", mhdr)
                    return True
                except urllib.error.HTTPError as e:
                    return False if e.code in (404, 410) else None
            if plat == "youtube":
                m = re.search(r"(?:shorts/|watch\?v=|youtu\.be/)([\w-]{6,})", url)
                if not (yt_hdr and m):
                    return None
                return bool(get_json("https://www.googleapis.com/youtube/v3/videos?part=id&id=" + m.group(1), yt_hdr).get("items"))
            if plat in ("instagram", "threads"):
                mid = row.get("mediaId") or (re.search(r"/(\d{10,})/?$", url) or [None, None])[1]
                tok = igtok if plat == "instagram" else thtok
                if not (mid and tok):
                    return None
                host = "graph.instagram.com" if plat == "instagram" else "graph.threads.net"
                try:
                    get_json(f"https://{host}/v21.0/{mid}?fields=id&access_token={tok}")
                    return True
                except urllib.error.HTTPError as e:
                    return False if e.code in (400, 404) else None
        except Exception:                              # noqa: BLE001
            return None
        return None

    live = gone = unknown = 0
    for row in posts:
        row["live"] = v = check(row)
        live, gone, unknown = live + (v is True), gone + (v is False), unknown + (v is None)
    per = {}
    for row in posts:                                  # counts follow what SURVIVED
        if row.get("live") is False:
            continue
        p2 = per.setdefault(row.get("platform"), {"posts": 0, "likes": 0, "replies": 0,
                                                  "reposts": 0, "views": 0, "measured": 0})
        p2["posts"] += 1
        if row.get("likes") is not None:
            p2["measured"] += 1
            for k in ("likes", "replies", "reposts", "views"):
                p2[k] += int(row.get(k) or 0)
    state["social"].update({"byPlatform": per, "totalPosts": live + unknown,
                            "deleted": gone, "unverified": unknown})
    return f"{live} live, {gone} deleted, {unknown} could not be checked"


def youtube_channel(state):
    """Subscribers, views and comments. A token that holds `youtube.upload`
    ONLY answers 403 here, and that is a CHOICE (a CI secret that can post but
    cannot read the account), reported as one — not a fault."""
    hdr = _youtube_header()
    if not hdr:
        if not ID["profiles"].get("youtube"):
            raise NotConfigured("no social.profiles.youtube and no YOUTUBE_* credentials")
        raise RuntimeError("no YouTube credential in this environment")
    note = []
    try:
        items = get_json("https://www.googleapis.com/youtube/v3/channels?part=statistics&mine=true", hdr).get("items", [])
        if items:
            st = items[0].get("statistics", {})
            state["social"].setdefault("reach", {})["youtube"] = {
                "followers": num_or_none(st.get("subscriberCount")), "posts": num_or_none(st.get("videoCount")),
                "views": num_or_none(st.get("viewCount"))}
            note.append("channel read")
    except urllib.error.HTTPError as e:
        if e.code != 403:
            raise
        state["social"].setdefault("reach", {})["youtube"] = {
            "error": "the token is youtube.upload only, by design — stats need youtube.readonly"}
        note.append("stats need youtube.readonly (the token is upload-only, by design)")
    kept = 0
    for row in (state.get("social") or {}).get("posts", []):
        vid = re.search(r"(?:shorts/|watch\?v=|youtu\.be/)([\w-]{6,})", row.get("url") or "")
        if row.get("platform") != "youtube" or not vid:
            continue
        try:
            d = get_json(f"https://www.googleapis.com/youtube/v3/commentThreads?part=snippet&maxResults=20&videoId={vid.group(1)}", hdr)
        except Exception:                              # noqa: BLE001
            continue
        for c in d.get("items", []):
            sn = (((c.get("snippet") or {}).get("topLevelComment") or {}).get("snippet") or {})
            state["mentions"].append({"source": "YouTube comment", "title": row.get("title") or "",
                                      "excerpt": clamp(sn.get("textOriginal"), 400), "url": row["url"],
                                      "author": sn.get("authorDisplayName"), "date": sn.get("publishedAt"),
                                      "likes": sn.get("likeCount")})
            kept += 1
    note.append(f"{kept} comment(s)")
    return ", ".join(note)


# ──────────────────────────────────────────── GitHub and the CI fleet

def gh(args):
    p = subprocess.run(["gh", *args], capture_output=True, text=True, timeout=90)
    if p.returncode != 0:
        raise RuntimeError((p.stderr or p.stdout or "gh failed").strip().splitlines()[-1][:160])
    return json.loads(p.stdout or "null")


def github(state):
    repo = need("repo", "product.repo")
    try:
        r = gh(["api", f"repos/{repo}"])
    except FileNotFoundError:
        raise RuntimeError("the gh CLI is not installed here") from None

    def maybe(ep):                                     # traffic needs push access; say so, never 0
        try:
            return gh(["api", ep]) or {}
        except Exception:                              # noqa: BLE001
            return {}
    traffic, clones = maybe(f"repos/{repo}/traffic/views"), maybe(f"repos/{repo}/traffic/clones")
    state["github"] = {
        "stars": r.get("stargazers_count"), "forks": r.get("forks_count"),
        "watchers": r.get("subscribers_count"), "openIssues": r.get("open_issues_count"),
        "views14d": traffic.get("count"), "uniques14d": traffic.get("uniques"),
        "clones14d": clones.get("count"), "url": f"https://github.com/{repo}",
    }
    issues = maybe(f"repos/{repo}/issues?state=open&per_page=20&sort=updated") or []
    owners = set(ID["ownerLogins"])
    state["health"]["issues"] = [{
        "number": i.get("number"), "title": clamp(i.get("title"), 140),
        "author": (i.get("user") or {}).get("login"), "url": i.get("html_url"),
        "updated": i.get("updated_at"), "labels": [lb["name"] for lb in i.get("labels", [])],
        "external": (i.get("user") or {}).get("login") not in owners,
    } for i in (issues if isinstance(issues, list) else []) if "pull_request" not in i]
    ext = sum(1 for i in state["health"]["issues"] if i["external"])
    return f"{r.get('stargazers_count')} star(s), {len(state['health']['issues'])} open issue(s), {ext} from outside"


def workflows(state):
    """The fleet's own verdict, from the auditor that already exists. Its
    printed lines ARE the interface — the same regex the issue reporter reads,
    so the two can never disagree about what a finding is."""
    tool = REPO / "tools" / "audit_workflow_health.py"
    if not tool.exists():
        raise NotConfigured("no tools/audit_workflow_health.py")
    repo = os.environ.get("GITHUB_REPOSITORY") or ID.get("repo")
    if not repo:
        raise NotConfigured("set product.repo in ops/pulse.config.json")
    p = subprocess.run([sys.executable, str(tool)], capture_output=True, text=True, timeout=900,
                       cwd=str(REPO), env={**os.environ, "GITHUB_REPOSITORY": repo})
    findings = []
    for line in (p.stdout or "").splitlines():
        m = re.match(r"\s*(BROKEN|KILLED|FAILED|DROPPED|STALE|SILENT|DRAINED)\s+(.+)", line)
        if m:
            findings.append({"severity": m.group(1), "workflow": clamp(m.group(2), 160)})
    # A POSITIVE test that it audited something: the auditor exits 0 when it
    # audits nothing ("nothing audited"), and "0 findings" from a run that
    # looked at nothing is the confident zero this page exists to refuse.
    checked = re.search(r"Checked (\d+) workflows", p.stdout or "")
    if not checked or checked.group(1) == "0":
        tail = (p.stdout or p.stderr or "").strip().splitlines()
        raise RuntimeError(f"the fleet auditor audited nothing: {tail[-1][:140] if tail else 'exit ' + str(p.returncode)}")
    state["health"]["workflows"] = findings[:40]
    urgent = [f for f in findings if f["severity"] in ("BROKEN", "KILLED")]
    return f"{len(findings)} finding(s), {len(urgent)} urgent, across {checked.group(1)} workflow(s)"


# ─────────────────────────── Stores with no API at all — declared, not guessed

MANUAL = REPO / "ops" / "stores-manual.json"


def manual_stores(state):
    """Stores with no machine-readable state (LG, Samsung; Roku and Amazon until
    their routes are wired) are declared in ops/stores-manual.json, so the page
    shows the whole estate rather than the half that has an API. Each row names
    its `route`. A DECLARED FACT LOSES TO A READ ONE: Amazon's live versionCode
    (amazon_live), Roku's field versions (applied in main) and the web row's
    newest deploy replace what was typed."""
    if not MANUAL.exists():
        state["stores"] += []
        return "no ops/stores-manual.json — only machine-read stores are shown"
    rows = [r for r in json.loads(MANUAL.read_text()).get("stores", []) if r.get("store")]
    for r in rows:
        r.setdefault("manual", True)
    h, read = state.get("health") or {}, 0
    al = h.get("amazonLive") or {}
    for r in rows:
        if r.get("store") == "Amazon Appstore" and al.get("liveVersionCode"):
            vc = al["liveVersionCode"]
            if al.get("submissionInFlight"):
                r["inFlight"] = {"version": f"vc{vc}", "state": "IN REVIEW"}
                r["live"] = r.get("version")
            else:
                r["version"] = r["live"] = f"vc{vc}"
                r["versionCode"] = vc
            r["read"], read = "Amazon submission API", read + 1
    web = next((r for r in rows if r.get("store") == "Web (PWA)"), None)
    tok = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if web and tok and ID.get("repo") and ID.get("deployWorkflow"):
        try:
            runs = get_json(f"https://api.github.com/repos/{ID['repo']}/actions/workflows/"
                            f"{ID['deployWorkflow']}/runs?status=success&per_page=1",
                            {"Authorization": f"Bearer {tok}", "Accept": "application/vnd.github+json"}
                            ).get("workflow_runs") or []
            if runs:
                web["version"], web["since"] = runs[0]["head_sha"][:7], runs[0]["updated_at"]
                web["read"], read = "the newest successful deploy", read + 1
        except Exception:                              # noqa: BLE001 — the row keeps what it declared
            pass
    state["stores"] += rows
    return f"{len(rows)} declared store(s), {read} version(s) read rather than declared"


def roku_store_version(state) -> bool:
    """The Roku row's version = the newest build Roku's own delivery has ever
    reported (versionsSeen, merged across readings — so this runs in main(),
    after the merge; on a run with no delivery the reader alone sees none)."""
    seen = ((state.get("health") or {}).get("rokuEngagement") or {}).get("versionsSeen") or []
    row = next((r for r in state.get("stores", []) if r.get("store") == "Roku Channel Store"), None)
    if not seen or not row:
        return False
    newest = max(seen, key=lambda v: _vkey(v.get("version")))
    row["version"] = row["live"] = newest["version"]
    row["since"] = newest.get("firstSeen") or row.get("since")
    row["read"] = "seen in Roku's own delivery"
    return True


# ──────────────────────────────────────────────────── What people are ASKING

WANT = re.compile(
    r"\b(wish|would love|would like|please add|hope (?:you|they)|any chance|"
    r"feature request|it needs|needs? to|should (?:be able|have|add|support)|"
    r"can you (?:add|make|support)|missing|would be (?:great|nice|amazing)|"
    r"my only (?:complaint|gripe|wish)|the one thing)\b", re.I)
LOVE = re.compile(
    r"\b(love|loving|amazing|excellent|perfect|fantastic|brilliant|"
    r"beautiful|so good|well done|thank you|thanks for|best app|"
    r"exactly what|intuitive|works (?:really |very )?well|works great|"
    r"easy to use|great app|impressive|delightful|a joy)\b", re.I)


def sentences(text):
    return [s.strip() for s in re.split(r"(?<=[.!?])\s+|\n+", text or "") if len(s.strip()) > 12]


def distribution(state):
    """How the written reviews divide across the five stars, per store."""
    by = {}
    for r in state["reviews"]:
        if r.get("rating"):
            by.setdefault(r["store"], {i: 0 for i in range(1, 6)})[int(r["rating"])] += 1
    state["distribution"] = by
    return ", ".join(f"{k}: {sum(v.values())} rated" for k, v in by.items()) or "none yet"


def asks(state):
    """Pull the sentence a person actually WROTE. No summary, no score."""
    wants, loves = [], []
    src = ([{"kind": "review", "who": r.get("author"), "where": r.get("store"),
             "text": f"{r.get('title', '')} {r.get('body', '')}", "url": r.get("url"),
             "date": r.get("date")} for r in state["reviews"]]
           + [{"kind": "mention", "who": m.get("author"), "where": m.get("source"),
               "text": m.get("excerpt"), "url": m.get("url"), "date": m.get("date")}
              for m in state["mentions"]])
    for s in src:
        for sent in sentences(s["text"]):
            row = {**{k: s[k] for k in ("kind", "who", "where", "url", "date")}, "text": clamp(sent, 260)}
            if WANT.search(sent):
                wants.append(row)
            elif LOVE.search(sent):
                loves.append(row)
    state["asks"], state["loves"] = wants[:60], loves[:60]
    return f"{len(wants)} request(s), {len(loves)} bit(s) of praise"


# ─────────────────────────────────────────────────────────────────── The run

SOURCES = [
    ("apple_stores", apple_stores),
    ("apple_reviews", apple_reviews),
    ("apple_rating", apple_rating),
    ("apple_performance", apple_performance),
    ("apple_downloads", apple_downloads),
    ("play_stores", play_stores),
    ("play_reviews", play_reviews),
    ("play_vitals", play_vitals),
    ("play_crashes", play_crashes),                   # after play_stores: reads the live build
    ("play_users", play_users),
    ("play_reports", play_reports),
    ("play_daily_exports", play_daily_exports),
    ("play_rating", play_rating),                     # after the export it falls back to
    ("play_acquisition", play_acquisition),
    ("amazon_vitals", amazon_vitals),
    ("amazon_installs", amazon_installs),
    ("amazon_live", amazon_live),
    ("roku_engagement", roku_engagement),
    ("manual_stores", manual_stores),                 # after amazon_live: a read fact wins
    ("social_program", social_program),
    ("social_reach", social_reach),
    ("social_replies", social_replies),
    ("social_liveness", social_liveness),
    ("youtube_channel", youtube_channel),
    ("mentions_reddit", mentions_reddit),
    ("mentions_hn", mentions_hn),
    ("mentions_lemmy", mentions_lemmy),
    ("mentions_news", mentions_news),
    ("mentions_bluesky", mentions_bluesky),
    ("mentions_mastodon", mentions_mastodon),
    ("github", github),
    ("workflows", workflows),
    ("web_usage", web_usage),
    ("counter_tallies", counter_tallies),
    ("cloud_api_usage", cloud_api_usage),
    ("search_console", search_console),
    ("search_index", search_index),
    ("distribution", distribution),
    ("asks", asks),                                   # must run last: it reads the rest
]

# Top-level sections a reader owns. A failed reader keeps its last value.
OWNS = {"apple_stores": "stores", "play_stores": "stores", "manual_stores": "stores",
        "apple_reviews": "reviews", "play_reviews": "reviews",
        "apple_rating": "ratings", "play_rating": "ratings",
        "distribution": "distribution", "github": "github", "social_program": "social"}

# EVERY health key a reader writes must be listed. A key missing here is not
# preserved when its reader fails — it is simply GONE from the next reading,
# which is the confident zero one level up: the page shows nothing and says
# nothing about why. Measured: three sections vanished on a run without their
# credentials while two others survived the same run and were correctly marked
# stale — which is exactly what made the loss invisible. The test suite asserts
# this map covers every `state["health"][...] =` in this file.
HEALTH_OWNS = {"play_reports": "playInstalls", "play_crashes": "playCrashes",
               "play_users": "playUsers", "play_vitals": "playVitals",
               "play_acquisition": "playAcquisition", "play_daily_exports": "playDaily",
               "apple_downloads": "appleDownloads", "apple_performance": "applePerf",
               "amazon_vitals": "amazonVitals", "amazon_installs": "amazonInstalls",
               "amazon_live": "amazonLive", "roku_engagement": "rokuEngagement",
               "web_usage": "webUsage", "counter_tallies": "tallies",
               "cloud_api_usage": "cloudUsage",
               "search_console": "searchConsole", "search_index": "searchIndex",
               "github": "issues", "workflows": "workflows"}
# Secondary keys that ride with a reader's main key.
HEALTH_ALSO = {"play_crashes": ["playLiveBuild"], "play_vitals": ["playVitalsNote"]}

_MENTION_OWNER = {
    "mentions_reddit": ("Reddit",), "mentions_hn": ("Hacker News",), "mentions_lemmy": ("Lemmy",),
    "mentions_news": ("News",), "mentions_bluesky": ("Bluesky",), "mentions_mastodon": ("Mastodon",),
    "social_replies": ("Bluesky reply",), "youtube_channel": ("YouTube comment",),
}


def blank():
    return {"stores": [], "ratings": [], "reviews": [], "mentions": [], "distribution": {},
            "social": {}, "health": {}, "github": {}, "asks": [], "loves": [], "sources": {}}


def dedupe(rows, key):
    seen, out = set(), []
    for r in rows:
        k = key(r)
        if k not in seen:
            seen.add(k)
            out.append(r)
    return out


def history_row(state):
    """One compact line per day. SCALARS only — this series has to survive
    forever, so nothing in it may grow."""
    ap = next((r for r in state["ratings"] if r["store"] == "App Store"), {})
    pl = next((r for r in state["ratings"] if r["store"] == "Google Play"), {})
    social = state.get("social") or {}
    per, reach = social.get("byPlatform") or {}, social.get("reach") or {}
    health = state.get("health") or {}
    return {
        "date": today(),
        "appleRating": ap.get("average"), "appleRatings": ap.get("count"),
        "playRating": pl.get("average"), "playRatings": pl.get("count"),
        "reviews": len(state["reviews"]), "mentions": len(state["mentions"]),
        "posts": social.get("totalPosts"),
        "likes": sum(int(p.get("likes") or 0) for p in per.values()) if per else None,
        "followers": total((v or {}).get("followers") for v in reach.values()),
        "stars": (state.get("github") or {}).get("stars"),
        "views14d": (state.get("github") or {}).get("views14d"),
        "pagesIndexed": (health.get("searchIndex") or {}).get("indexedShare"),
        "searchClicks28d": ((health.get("searchConsole") or {}).get("last28") or {}).get("clicks"),
        "urgent": sum(1 for f in health.get("workflows", []) if f.get("severity") in ("BROKEN", "KILLED")),
    }


def merge_roku(state, prev):
    """Roku's delivery is a rolling window, so its days, headline, per-report
    series and versions MERGE rather than replace: a day that fell out of
    Looker's window still happened, a headline tile nobody redelivered keeps
    its last value, and a build seen last week still shipped."""
    rk = state["health"].get("rokuEngagement")
    if rk is None:
        return
    old = (prev.get("health") or {}).get("rokuEngagement") or {}
    by_date = {r["date"]: r for r in old.get("daily", [])}
    for row in rk.get("daily", []):
        by_date[row["date"]] = {**by_date.get(row["date"], {}), **row}
    rk["daily"] = sorted(by_date.values(), key=lambda r: r["date"])[-120:]
    rk["headline"] = {**(old.get("headline") or {}), **(rk.get("headline") or {})}
    prev_rep = old.get("byReport") or {}
    for name, cur in (rk.get("byReport") or {}).items():
        merged = {r["date"]: r for r in (prev_rep.get(name) or {}).get("daily", [])}
        for row in cur.get("daily", []):
            merged[row["date"]] = {**merged.get(row["date"], {}), **row}
        cur["daily"] = sorted(merged.values(), key=lambda r: r["date"])[-120:]
    for name, old_rep in prev_rep.items():
        rk.setdefault("byReport", {}).setdefault(name, old_rep)
    rk["reportsSeen"] = sorted(rk.get("byReport") or {})
    prev_v = {v["version"]: v for v in old.get("versionsSeen") or []}
    for v in rk.get("versionsSeen") or []:
        if v["version"] in prev_v:
            v["firstSeen"] = min(filter(None, [prev_v[v["version"]].get("firstSeen"), v["firstSeen"]]) or [""])
        prev_v[v["version"]] = v
    rk["versionsSeen"] = sorted(prev_v.values(), key=lambda x: _vkey(x["version"]))


def degraded(sources: dict, ran: set) -> tuple[int, int, bool]:
    """(dark, configured, refuse). Counts only readers that RAN this time and
    are CONFIGURED: a reader the app has not set up is the same on every
    machine, while a missing credential is exactly what a laptop has and CI
    does not."""
    rows = [v for k, v in sources.items() if k in ran and not v.get("off")]
    dark = sum(1 for v in rows if not v.get("ok"))
    return dark, len(rows), bool(rows) and dark * 3 >= len(rows)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true", help="write ops/pulse.json")
    ap.add_argument("--force", action="store_true",
                    help="write even when a third or more of the configured readers were dark")
    ap.add_argument("--only", help="comma-separated source names")
    ap.add_argument("--out", default=str(OUT))
    a = ap.parse_args()

    want = {s.strip() for s in a.only.split(",")} if a.only else None
    out = Path(a.out)
    prev = {}
    if out.exists():
        try:
            prev = json.loads(out.read_text())
        except json.JSONDecodeError:
            prev = {}

    state = blank()
    # A reader that CONSUMES its source (the drop box deletes what it acks)
    # must know whether this run will be kept. A dry run that destroys the only
    # copy of a delivery is not a dry run.
    state["_apply"] = bool(a.apply)
    state["_prev"] = prev                              # stateful readers read what we already HOLD
    if want:
        # A PARTIAL run must not delete what it did not collect: start from the
        # last reading and replace only the parts these sources own.
        for key in ("stores", "ratings", "reviews", "mentions", "social", "health",
                    "github", "asks", "loves", "distribution"):
            if key in prev:
                state[key] = prev[key]
        state["sources"] = dict(prev.get("sources") or {})
        owns = {"apple_stores": ["stores"], "play_stores": ["stores"], "manual_stores": ["stores"],
                "apple_reviews": ["reviews"], "play_reviews": ["reviews"],
                "apple_rating": ["ratings"], "play_rating": ["ratings"],
                "asks": ["asks", "loves"], "distribution": ["distribution"],
                "github": ["github"], "social_program": ["social"]}
        for src in want:
            for key in owns.get(src, []):
                state[key] = blank()[key]
        # A store row is owned per STORE: a play_stores re-read must not drop
        # the Apple rows, or the declared ones, that it did not re-read.
        redo = {s for r, s in (("apple_stores", "App Store"), ("play_stores", "Google Play")) if r in want}
        state["stores"] = [r for r in (prev.get("stores") or [])
                           if r.get("store") not in redo and not (r.get("manual") and "manual_stores" in want)]

    print(f"pulse — {now()}  config: {CONFIG_PATH.name if CONFIG_PATH.exists() else 'none (every app-specific reader is off)'}\n")
    ran = set()
    for name, fn in SOURCES:
        if want and name not in want:
            continue
        ran.add(name)
        try:
            note = fn(state)
            state["sources"][name] = {"ok": True, "note": note, "at": now()}
            print(f"  {'ok':<4} {name:<20} {note}")
        except NotConfigured as e:
            state["sources"][name] = {"ok": False, "off": True, "note": f"not configured: {e}", "at": now()}
            print(f"  {'off':<4} {name:<20} not configured: {str(e)[:100]}")
        except ImportError as e:
            why = f"missing Python package {e.name or e} (pip install PyJWT cryptography google-api-python-client google-auth)"
            state["sources"][name] = {"ok": False, "note": why, "at": now()}
            print(f"  {'--':<4} {name:<20} {why[:110]}")
        except (Exception, SystemExit) as e:           # noqa: BLE001 — one source, never the run
            state["sources"][name] = {"ok": False, "note": str(e)[:200] or type(e).__name__, "at": now()}
            print(f"  {'--':<4} {name:<20} {str(e)[:110]}")

    # A source that FAILED keeps its last good value, marked stale. Dropping it
    # would put a hole where four reviews were, and a hole reads as "none".
    stale = dict(prev.get("stale") or {}) if want else {}
    for name, res in state["sources"].items():
        key = OWNS.get(name)
        if name not in ran or res["ok"] or res.get("off") or not key or not prev.get(key):
            continue
        if not state.get(key):
            state[key] = prev[key]
            stale[key] = prev.get("generatedAt")
        elif key in ("stores", "ratings", "reviews"):
            have = {r.get("store") for r in state[key]}
            carried = [r for r in prev[key] if r.get("store") not in have]
            if carried:
                state[key] = state[key] + carried
                stale[key] = prev.get("generatedAt")
    prev_health = prev.get("health") or {}
    for name, key in HEALTH_OWNS.items():
        res = state["sources"].get(name)
        for k in [key] + HEALTH_ALSO.get(name, []):
            if name in ran and res and not res["ok"] and not res.get("off") \
                    and not state["health"].get(k) and prev_health.get(k):
                state["health"][k] = prev_health[k]
                stale[k] = prev.get("generatedAt")
    # A reader that ANSWERED can still be holding old data: Play's install
    # export past both of its lags is a warning the page must show.
    pi = state["health"].get("playInstalls") or {}
    if (pi.get("staleDays") or 0) > PLAY_INSTALLS_ALARM_DAYS:
        stale["playInstalls"] = pi.get("asOf")
    # A partial run inherits the last reading's stale marks; a reader that
    # answered this time clears its own.
    for k in list(stale):
        owners = [n for n, key in {**OWNS, **HEALTH_OWNS}.items() if key == k] + \
                 [n for n, keys in HEALTH_ALSO.items() if k in keys]
        ran_owners = [n for n in owners if n in ran]
        if k != "playInstalls" and ran_owners and all(state["sources"][n]["ok"] for n in ran_owners):
            stale.pop(k)
    state["stale"] = stale

    # Mentions and reviews ACCUMULATE. These searches are fuzzy: a real mention
    # on one run can be absent the next, and replacing the list would make a
    # genuine finding evaporate — the same lie as a confident zero, told slowly.
    state["reviews"] = dedupe(sorted(state["reviews"] + (prev.get("reviews") or []),
                                     key=lambda r: r.get("date") or "", reverse=True),
                              lambda r: (r.get("store"), r.get("id")))[:MAX_REVIEWS]
    state["mentions"] = dedupe(sorted(state["mentions"] + (prev.get("mentions") or []),
                                      key=lambda m: m.get("date") or "", reverse=True),
                               lambda m: m.get("url"))[:MAX_MENTIONS]
    merge_roku(state, prev)
    roku_store_version(state)

    hist = [h for h in prev.get("history", []) if h.get("date") != today()]
    hist.append(history_row(state))
    state["history"] = hist[-MAX_HISTORY:]
    state["generatedAt"] = now()
    # What the page needs to know about the app, so pulse.js hard-codes none of it.
    state["app"] = {"name": ID["name"], "site": ID["site"], "timezone": ID["timezone"],
                    "repo": ID["repo"], "repoUrl": f"https://github.com/{ID['repo']}" if ID["repo"] else "",
                    "appleAppId": ID["appleAppId"], "playPackage": ID["playPackage"],
                    "profiles": ID["profiles"], "tallies": [t.get("name") for t in ID["tallies"]]}
    try:
        text = (REPO / "AppVersion.xcconfig").read_text()
        state["repoVersion"] = re.search(r"^MARKETING_VERSION\s*=\s*(\S+)", text, re.M).group(1)
        state["repoBuild"] = re.search(r"^CURRENT_PROJECT_VERSION\s*=\s*(\S+)", text, re.M).group(1)
    except Exception:                                  # noqa: BLE001
        pass
    for k in ("_apply", "_prev"):                      # run flags never reach the reading
        state.pop(k, None)
    state["_"] = ("Written by tools/pulse_collect.py. `history` is the series and is append-only per "
                  "day; everything else is the latest reading. A source that could not answer says "
                  "so in `sources` (`off` = not configured) — never assume a zero.")

    ok = sum(1 for k, v in state["sources"].items() if k in ran and v["ok"])
    off = sum(1 for k, v in state["sources"].items() if k in ran and v.get("off"))
    dark, configured, refuse = degraded(state["sources"], ran)
    print(f"\n{ok}/{configured} configured reader(s) answered, {dark} dark, {off} not configured · "
          f"{len(state['reviews'])} review(s) · {len(state['mentions'])} mention(s) · "
          f"{len(state['asks'])} request(s)")

    # A DEGRADED RUN MUST NOT OVERWRITE A GOOD READING. CI holds every
    # credential; a laptop holds a few. A local --apply with many readers dark
    # still carries each dark section forward (correct in itself), and
    # committing that file replaced CI's fresh numbers with older ones — which
    # is how a platform vanished from the page hours after it was fixed. The
    # guard is on the SHAPE of the run, not the machine.
    if a.apply and refuse and not a.force:
        print(f"\nREFUSING TO WRITE: {dark} of {configured} configured readers were dark, so this "
              f"reading is mostly carried-forward and would replace a fresher one. Pass --force "
              f"if you mean it.")
        return 0
    if a.apply:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(state, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"wrote {out} ({out.stat().st_size // 1024} KB, {len(state['history'])} history row(s))")
    else:
        print("(dry run — pass --apply to write)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
