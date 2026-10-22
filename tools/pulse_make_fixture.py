#!/usr/bin/env python3
"""
pulse_make_fixture.py — a synthetic Pulse reading, so the page can be seen and
tested before a single credential is wired.

Every number is invented and deterministic (seeded). The SHAPE is the one
tools/pulse_collect.py writes, including the parts that exist to be honest:
a reader that could not read, a reader that is not configured, a stale section,
a missing column that stays null, a crash with a fix in review, an unreplied
low review. `tools/test_pulse_render.mjs` renders it; open /pulse/?fixture to
see it.

  python3 tools/pulse_make_fixture.py            # writes pulse/fixture.json
  python3 tools/pulse_make_fixture.py --today 2026-09-30
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import random
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "pulse" / "fixture.json"


def build(today: dt.date) -> dict:
    rnd = random.Random(20260930)
    iso = lambda d: d.isoformat()                                    # noqa: E731
    day = lambda k: today - dt.timedelta(days=k)                     # noqa: E731
    at = lambda k, h=14: dt.datetime.combine(day(k), dt.time(h, 5), dt.timezone.utc).isoformat()  # noqa: E731

    def series(n, base, spread, lag=1, key="v", drift=0.0):
        return [{"date": iso(day(n + lag - 1 - i)),
                 key: max(0, int(base + drift * i + rnd.gauss(0, spread)))} for i in range(n)]

    apple_days = []
    for i in range(30):
        by = {"iPhone": max(0, int(18 + rnd.gauss(0, 5))), "iPad": max(0, int(4 + rnd.gauss(0, 2))),
              "Apple TV": max(0, int(9 + rnd.gauss(0, 3))), "Desktop": max(0, int(2 + rnd.gauss(0, 1)))}
        apple_days.append({"date": iso(day(30 - i)), "units": sum(by.values()), "byDevice": by})
    tot = lambda k: sum(r["byDevice"][k] for r in apple_days)       # noqa: E731
    per_dev = {k: {"units": tot(k), "byCountry": {"US": int(tot(k) * .7), "GB": int(tot(k) * .12), "CA": int(tot(k) * .08)},
                   "byVersion": {"1.4.2": int(tot(k) * .8), "1.4.1": int(tot(k) * .2)}}
               for k in ("iPhone", "iPad", "Apple TV", "Desktop")}

    play_inst = [{"date": iso(day(36 - i)), "installs": max(0, int(22 + rnd.gauss(0, 6))),
                  "uninstalls": max(0, int(4 + rnd.gauss(0, 2))), "upgrades": 30,
                  "activeDevices": 900 + i * 6, "userInstalls": 20} for i in range(28)]
    # One day whose export carried no uninstall column: it stays NULL.
    play_inst[-3]["uninstalls"] = None
    acq = [{"date": iso(day(34 - i)), "acquisitions": max(0, int(17 + rnd.gauss(0, 4))),
            "visitors": max(1, int(60 + rnd.gauss(0, 10)))} for i in range(27)]
    roku_daily = [{"date": iso(day(9 - i)), "Channel Installs": max(0, int(12 + rnd.gauss(0, 4))),
                   "Channel Uninstalls": max(0, int(1 + rnd.gauss(0, 1))), "Visitors": 40 + i,
                   "Viewers": 25 + i, "Bounce Rate": 38.0 - i, "Total Minutes Streamed": 600 + 20 * i}
                  for i in range(7)]
    # Two App Health days carry crash counts and NO install column: absent, never 0.
    roku_daily += [{"date": iso(day(2)), "Total Count of Crashes": 3.0},
                   {"date": iso(day(1)), "Total Count of Crashes": 1.0}]
    web = [{"date": iso(day(40 - i)), "views": max(0, int(300 + 4 * i + rnd.gauss(0, 30))),
            "visits": (max(0, int(80 + i + rnd.gauss(0, 12))) if i >= 10 else None)} for i in range(40)]
    sc_daily = [{"date": iso(day(64 - i)), "clicks": max(0, int(20 + i * .6 + rnd.gauss(0, 5))),
                 "impressions": max(0, int(900 + i * 15 + rnd.gauss(0, 80))), "ctr": 0.021, "position": 14.2 - i * .05}
                for i in range(62)]
    rooms = [{"date": iso(day(30 - i)), "room": max(0, int(6 + rnd.gauss(0, 2))),
              "guest": max(0, int(11 + rnd.gauss(0, 4)))} for i in range(30)]

    def w28(rows, k, a, b):
        lo, hi = iso(today - dt.timedelta(days=a)), iso(today - dt.timedelta(days=b))
        return sum(r.get(k, 0) for r in rows if lo <= r["date"] <= hi)

    history = []
    for i in range(30):
        history.append({"date": iso(day(29 - i)), "appleRating": round(4.3 + i * .004, 2), "appleRatings": 40 + i,
                        "playRating": 4.1, "playRatings": 22, "reviews": 30 + i // 3, "mentions": 8 + i // 5,
                        "posts": 40 + i, "likes": 300 + i * 9, "followers": 210 + i * 3, "stars": 12 + i // 6,
                        "views14d": 140 + i, "pagesIndexed": round(0.30 + i * 0.006, 3),
                        "searchClicks28d": 500 + i * 6, "urgent": 1 if i == 29 else 0})

    posts = []
    for i, plat in enumerate(["bluesky", "mastodon", "youtube", "instagram"] * 6):
        posts.append({"at": at(i, 15), "platform": plat, "title": f"Sample post {i + 1}", "id": f"item-{i}",
                      "slot": "evening", "format": "clip", "url": f"https://social.example/{plat}/{i}",
                      "likes": None if i < 2 else rnd.randint(0, 14), "reposts": rnd.randint(0, 3),
                      "replies": rnd.randint(0, 2), "views": rnd.randint(40, 400) if plat == "youtube" else None,
                      "window": None if i < 2 else "144h", "live": False if i == 7 else (None if i == 9 else True)})

    now = dt.datetime.combine(today, dt.time(13, 20), dt.timezone.utc).isoformat()
    src = lambda ok=True, note="", off=False: {"ok": ok, "note": note, "at": now, **({"off": True} if off else {})}  # noqa: E731
    return {
        "app": {"name": "Sample App", "site": "https://sample.example", "timezone": "America/Denver",
                "repo": "example-owner/sample-app", "repoUrl": "https://github.com/example-owner/sample-app",
                "appleAppId": "1234567890", "playPackage": "com.example.sample",
                "profiles": {"bluesky": "https://bsky.app/profile/sample.example",
                             "mastodon": "https://mastodon.social/@sample",
                             "youtube": "https://www.youtube.com/@sample",
                             "instagram": "https://www.instagram.com/sample.example/"},
                "tallies": ["rooms"]},
        "generatedAt": now,
        "stores": [
            {"store": "App Store", "platform": "Apple TV", "state": "READY_FOR_SALE", "version": "1.4.2", "live": "1.4.2",
             "route": "App Store Connect API", "url": "https://appstoreconnect.apple.com/"},
            {"store": "App Store", "platform": "iPhone & iPad", "state": "WAITING_FOR_REVIEW", "version": "1.4.3", "live": "1.4.2",
             "inFlight": {"version": "1.4.3", "state": "WAITING_FOR_REVIEW"}, "route": "App Store Connect API",
             "url": "https://appstoreconnect.apple.com/"},
            {"store": "App Store", "platform": "Mac", "state": "READY_FOR_SALE", "version": "1.4.2", "live": "1.4.2",
             "since": iso(day(5)), "route": "App Store Connect API", "url": "https://appstoreconnect.apple.com/"},
            {"store": "Google Play", "platform": "Production", "state": "INPROGRESS", "version": "1.4.3", "live": "1.4.2",
             "build": "1042", "inFlight": {"version": "1.4.3", "build": "1043", "state": "INPROGRESS"},
             "route": "Play Developer API", "url": "https://play.google.com/console"},
            {"store": "Google Play", "platform": "Internal", "state": "COMPLETED", "version": "1.4.3", "live": "1.4.3",
             "build": "1043", "route": "Play Developer API", "url": "https://play.google.com/console"},
            {"store": "Amazon Appstore", "platform": "Fire TV", "state": "LIVE", "version": "vc1042", "live": "vc1042",
             "versionCode": 1042, "since": iso(day(20)), "api": "vitals", "manual": True, "read": "Amazon submission API",
             "route": "Submission API (live build), Sales report (installs)", "url": "https://developer.amazon.com/"},
            {"store": "Roku Channel Store", "platform": "Roku", "state": "LIVE", "version": "1.0.12", "live": "1.0.12",
             "since": iso(day(8)), "manual": True, "read": "seen in Roku's own delivery",
             "route": "Looker scheduled delivery (no API)", "url": "https://developer.roku.com/"},
            {"store": "LG Content Store", "platform": "webOS", "state": "NOT SUBMITTED", "version": None, "since": None,
             "manual": True, "route": "declared by hand (no API)", "url": "https://seller.lgappstv.com/"},
            {"store": "Web (PWA)", "platform": "the website", "state": "LIVE", "version": "a1b2c3d", "since": at(0, 9),
             "manual": True, "read": "the newest successful deploy", "url": "https://sample.example"},
        ],
        "ratings": [{"store": "App Store", "average": 4.42, "count": 69, "url": "https://apps.apple.com/"},
                    {"store": "Google Play", "average": 4.1, "count": None, "via": "Play's daily export", "url": "https://play.google.com/"}],
        "reviews": [
            {"store": "App Store", "id": "r1", "rating": 2, "title": "Stopped playing after the update",
             "body": "Since the last update nothing plays on my Apple TV. I wish it had a way to report this in the app.",
             "author": "viewer_one", "territory": "USA", "date": at(3), "responded": False, "url": "https://appstoreconnect.apple.com/"},
            {"store": "App Store", "id": "r2", "rating": 5, "title": "Exactly what I wanted",
             "body": "Works really well and the design is beautiful. Thank you for making this.", "author": "viewer_two",
             "territory": "GBR", "date": at(6), "responded": True, "url": "https://appstoreconnect.apple.com/"},
            {"store": "Google Play", "id": "g1", "rating": 4, "title": "", "body": "Great app. Would be great to have a watchlist.",
             "author": "A Person", "territory": "EN", "date": at(2), "responded": False, "device": "sabrina",
             "appVersion": "1.4.2", "url": "https://play.google.com/console"},
        ],
        "mentions": [
            {"source": "Reddit", "title": "Anyone tried Sample App on Apple TV?", "excerpt": "It is on the App Store now and it is great.",
             "url": "https://reddit.example/1", "author": "u/someone", "date": at(4)},
            {"source": "Bluesky", "title": "", "excerpt": "Please add Chromecast support to sample.example!",
             "url": "https://bsky.example/2", "author": "someone.bsky.social", "date": at(1), "likes": 4},
        ],
        "distribution": {"App Store": {"1": 1, "2": 2, "3": 3, "4": 9, "5": 25}, "Google Play": {"1": 0, "2": 0, "3": 1, "4": 3, "5": 5}},
        "asks": [{"kind": "review", "who": "viewer_one", "where": "App Store", "url": "https://appstoreconnect.apple.com/",
                  "date": at(3), "text": "I wish it had a way to report this in the app."},
                 {"kind": "mention", "who": "someone.bsky.social", "where": "Bluesky", "url": "https://bsky.example/2",
                  "date": at(1), "text": "Please add Chromecast support to sample.example!"}],
        "loves": [{"kind": "review", "who": "viewer_two", "where": "App Store", "url": "https://appstoreconnect.apple.com/",
                   "date": at(6), "text": "Works really well and the design is beautiful."}],
        "social": {"posts": posts, "totalPosts": 23, "measured": 22, "deleted": 1, "unverified": 1,
                   "byPlatform": {p: {"posts": 6, "likes": 30 + 5 * i, "replies": 4, "reposts": 6, "views": 900 if p == "youtube" else 0,
                                      "measured": 5} for i, p in enumerate(["bluesky", "mastodon", "youtube", "instagram"])},
                   "reach": {"bluesky": {"followers": 140, "posts": 60}, "mastodon": {"followers": 55, "posts": 58},
                             "youtube": {"error": "the token is youtube.upload only, by design — stats need youtube.readonly"},
                             "instagram": {"followers": 72, "posts": 30}}},
        "github": {"stars": 17, "forks": 2, "watchers": 3, "openIssues": 4, "views14d": 170, "uniques14d": 40,
                   "clones14d": 9, "url": "https://github.com/example-owner/sample-app"},
        "health": {
            "appleDownloads": {"daily": apple_days, "total14d": sum(r["units"] for r in apple_days[-14:]),
                               "total28d": sum(r["units"] for r in apple_days[-28:]),
                               "byDevice": {k: tot(k) for k in ("iPhone", "Apple TV", "iPad", "Desktop")},
                               "byCountry": {"US": 700, "GB": 120, "CA": 80, "DE": 40, "AU": 30},
                               "byVersion": {"1.4.2": 800, "1.4.1": 170}, "perDevice": per_dev,
                               "skippedProductTypes": {"7": 310, "7T": 41, "3F": 12}},
            "applePerf": {"metrics": [{"platform": "iOS", "category": "launch", "metric": "launchTime", "value": 0.82, "unit": "s"},
                                      {"platform": "iOS", "category": "hang", "metric": "hangRate", "value": 0.4, "unit": "s/h"}],
                          "regressions": [], "improving": ["Launch time improved 12% in 1.4.2"]},
            "playVitals": {"crashRate": 0.0061, "crashRateDays": 28, "anrRate": 0.0021, "anrRateDays": 28},
            "playCrashes": [
                {"type": "CRASH", "cause": "java.lang.IllegalArgumentException", "location": "androidx.compose.foundation.lazy.LazyList",
                 "users": 7, "reports": 11, "lastSeen": at(2), "firstBuild": "1038", "lastBuild": "1042", "api": "29-35",
                 "stale": False, "url": "https://play.google.com/console/crashes/aaaa1111bbbb2222",
                 "fixedIn": {"versionCode": 1043, "version": "1.4.3", "what": "duplicate lazy-list keys", "fix": "uniqueBy at every call site"},
                 "ours": "Exception java.lang.IllegalArgumentException · at com.example.sample.ui.Shelf.kt:88"},
                {"type": "ANR", "cause": "Input dispatching timed out", "location": "android.os.MessageQueue",
                 "users": 2, "reports": 2, "lastSeen": at(5), "firstBuild": "1042", "lastBuild": "1042", "api": "33-34",
                 "stale": False, "url": "https://play.google.com/console/anrs/cccc3333dddd4444", "fixedIn": None, "ours": None},
                {"type": "CRASH", "cause": "java.lang.NullPointerException", "location": "com.example.sample.Player",
                 "users": 5, "reports": 9, "lastSeen": at(26), "firstBuild": "1030", "lastBuild": "1036", "api": "29-34",
                 "stale": True, "url": "https://play.google.com/console/crashes/eeee5555ffff6666", "fixedIn": None, "ours": None},
            ],
            "playLiveBuild": 1042,
            "playUsers": {"daily": [{"date": iso(day(4)), "users": 120.0}], "byDimension": {}, "window": f"{iso(day(31))}..{iso(day(4))}"},
            "playInstalls": {"asOf": play_inst[-1]["date"], "daily": play_inst,
                             "installs28d": sum(r["installs"] for r in play_inst),
                             "uninstalls28d": sum(r["uninstalls"] for r in play_inst if r["uninstalls"] is not None),
                             "activeDevices": play_inst[-1]["activeDevices"], "byCountry": {"US": 300, "IN": 120, "BR": 80},
                             "byDevice": {"sabrina": 90, "gazelle": 40}, "byOs": {"Android 14": 200, "Android 12": 90},
                             "byVersion": {"1042": 500}, "byLanguage": {"en_US": 400}, "readVia": "service account",
                             "staleDays": 9, "fileWritten": at(3, 20), "monthsFound": [iso(day(9))[:7]]},
            "playDaily": {"ratings": [{"date": iso(day(30 - i)), "daily": 4.0, "total": round(4.05 + i * .002, 3)} for i in range(27)],
                          "crashes": [{"date": iso(day(30 - i)), "crashes": rnd.randint(0, 4), "anrs": rnd.randint(0, 1)} for i in range(27)],
                          "asOf": iso(day(4))},
            "playAcquisition": {"daily": acq, "asOf": acq[-1]["date"], "acquisitions28d": sum(r["acquisitions"] for r in acq),
                                "visitors28d": sum(r["visitors"] for r in acq),
                                "conversion28d": round(sum(r["acquisitions"] for r in acq) / sum(r["visitors"] for r in acq), 4),
                                "byCountry": {"US": 200, "IN": 90}, "bySource": {"Google Play search": 240, "Third-party referrers": 60}},
            "amazonVitals": {"freshness": {}, "empty": ["crashMetricSet", "anrMetricSet", "lmkMetricSet"], "package": "com.example.sample",
                             "console": "https://developer.amazon.com/"},
            "amazonInstalls": {"daily": [{"date": iso(day(k)), "installs": n} for k, n in ((20, 1), (18, 3), (15, 2), (9, 4), (6, 1), (2, 2))],
                               "byCountry": [{"key": "US", "value": 10}, {"key": "GB", "value": 3}], "total": 13,
                               "periods": [iso(today)[:7]], "noReport": [], "transactionTypes": {"Charge": 13, "Refund": 1},
                               "readVia": "Appstore Sales Reporting API (free installs are $0.00 Charge rows)",
                               "console": "https://developer.amazon.com/"},
            "amazonLive": {"liveVersionCode": 1042, "builds": [{"versionCode": 1042, "name": "1.4.2"}], "submissionInFlight": False,
                           "readVia": "a temporary edit, created and deleted", "console": "https://developer.amazon.com/"},
            "rokuEngagement": {"daily": roku_daily,
                               "headline": {"Account Channel Installs": 310.0, "Account Channel Uninstalls": 22.0,
                                            "Channel Crashes as % of Total Devices Streaming": 2.6,
                                            "Rebuffers per Hours Streamed": 0.21, "Average Minutes Streamed per Viewer": 23.5,
                                            "Avg Daily Viewers": 31.0, "Hours Streamed": 160.0},
                               "tiles": ["new_installs", "brightscript_crash_logs"], "dropsRead": 0, "unreadable": [],
                               "byReport": {"App Health": {"daily": roku_daily[-2:], "headline": {}, "tiles": ["brightscript_crash_logs"],
                                                           "tables": {"brightscript_crash_logs": [
                                                               {"Date": iso(day(2)), "Roku OS Release": "14.5.0", "App Version": "1.0.12",
                                                                "Error Text": "&hf4 invalid component", "Total Count of Crashes": "3",
                                                                "Total Count of Devices with Crashes": "2"},
                                                               {"Date": iso(day(1)), "Roku OS Release": "13.0.0", "App Version": "1.0.12",
                                                                "Error Text": "type mismatch", "Total Count of Crashes": "1",
                                                                "Total Count of Devices with Crashes": "1"}]},
                                                           "emptyTiles": ["malone"]},
                                            "App Engagement": {"daily": roku_daily[:-2], "headline": {}, "tiles": ["new_installs"],
                                                               "tables": {}, "emptyTiles": []}},
                               "versionsSeen": [{"version": "1.0.11", "firstSeen": iso(day(20)), "lastSeen": iso(day(9))},
                                                {"version": "1.0.12", "firstSeen": iso(day(8)), "lastSeen": iso(day(1))}],
                               "reportsSeen": ["App Engagement", "App Health"],
                               "readVia": "Looker scheduled delivery -> Worker /ingest/roku (no Roku API exists)",
                               "console": "https://developer.roku.com/"},
            "webUsage": {"daily": web, "views28d": sum(r["views"] for r in web[-28:]),
                         "visits28d": sum(r["visits"] or 0 for r in web[-28:]),
                         "byPath": {"/": 3000, "/browse": 2100, "/item": 1700, "/search": 800, "/about": 120},
                         "since": iso(day(90)), "splitFrom": web[10]["date"]},
            "tallies": {"rooms": {"label": "Rooms opened", "kinds": ["room", "guest"],
                                  "daily": rooms, "since": rooms[0]["date"],
                                  "last28": {"room": w28(rooms, "room", 27, 0), "guest": w28(rooms, "guest", 27, 0)},
                                  "prev28": {"room": w28(rooms, "room", 55, 28), "guest": w28(rooms, "guest", 55, 28)},
                                  "note": "Kept by the server as it opens rooms: day | kind | count, nothing else."}},
            "searchConsole": {"through": sc_daily[-1]["date"], "daily": sc_daily,
                              "last28": {"clicks": sum(r["clicks"] for r in sc_daily[-28:]), "impressions": sum(r["impressions"] for r in sc_daily[-28:]),
                                         "ctr": 0.022, "position": 12.9, "days": 28},
                              "prev28": {"clicks": sum(r["clicks"] for r in sc_daily[-56:-28]), "impressions": sum(r["impressions"] for r in sc_daily[-56:-28]),
                                         "ctr": 0.02, "position": 14.0, "days": 28},
                              "queries": [{"key": "sample app", "clicks": 210, "impressions": 3100, "ctr": .068, "position": 2.1,
                                           "prevClicks": 150, "prevImpressions": 2500, "prevPosition": 2.6},
                                          {"key": "sample app apple tv", "clicks": 44, "impressions": 900, "ctr": .049, "position": 6.3,
                                           "prevClicks": 0, "prevImpressions": 0, "prevPosition": None}],
                              "pages": [{"key": "https://sample.example/", "clicks": 300, "impressions": 5000, "ctr": .06, "position": 3.0,
                                         "prevClicks": 250, "prevImpressions": 4600, "prevPosition": 3.3}],
                              "focusPages": {"pattern": "/item/", "clicks": 90, "impressions": 4000, "pages": 60, "top": []},
                              "countries": [{"key": "usa", "clicks": 320, "impressions": 7000, "ctr": .046, "position": 11.0,
                                             "prevClicks": 280, "prevImpressions": 6500, "prevPosition": 12.0}],
                              "devices": [{"key": "DESKTOP", "clicks": 250, "impressions": 5200, "ctr": .048, "position": 10.0,
                                           "prevClicks": 200, "prevImpressions": 5000, "prevPosition": 11.0}],
                              "sitemaps": [{"path": "https://sample.example/sitemap.xml", "lastSubmitted": at(10), "lastDownloaded": at(1),
                                            "isPending": False, "errors": 0, "warnings": 0, "submitted": 1200, "indexed": 460}],
                              "url": "https://search.google.com/search-console"},
            "searchIndex": {"published": 1200, "sampled": 150, "pattern": "/item/", "indexedShare": 0.47,
                            "byState": {"Submitted and indexed": 70, "Discovered - currently not indexed": 60, "URL is unknown to Google": 20},
                            "faults": [{"url": "https://sample.example/item/x", "state": "Duplicate, Google chose different canonical than user",
                                        "verdict": "NEUTRAL", "lastCrawl": at(3), "fetch": "SUCCESSFUL",
                                        "googleCanonical": "https://sample.example/item/y"}],
                            "examples": []},
            "issues": [{"number": 12, "title": "Subtitles drift on long files", "author": "outsider", "url": "https://github.com/",
                        "updated": at(2), "labels": ["bug"], "external": True}],
            "workflows": [{"severity": "FAILED", "workflow": "Nightly build  conclusion=failure"}],
        },
        "sources": {
            **{k: src(True, "read") for k in ("apple_stores", "apple_reviews", "apple_rating", "apple_performance",
                                              "apple_downloads", "play_stores", "play_reviews", "play_vitals", "play_crashes",
                                              "play_users", "play_reports", "play_daily_exports", "play_rating", "play_acquisition",
                                              "amazon_vitals", "amazon_installs", "amazon_live", "roku_engagement", "manual_stores",
                                              "social_program", "social_reach", "social_liveness", "mentions_reddit", "mentions_hn",
                                              "mentions_lemmy", "mentions_news", "mentions_bluesky", "github", "workflows",
                                              "web_usage", "counter_tallies", "search_console", "search_index", "distribution", "asks")},
            "youtube_channel": src(True, "stats need youtube.readonly (the token is upload-only, by design), 0 comment(s)"),
            "mentions_mastodon": src(False, "no Mastodon credential in this environment"),
            "social_replies": src(False, "not configured: no social.profiles.threads", off=True),
            "cloud_api_usage": src(False, "not configured: set cloudUsage.project and cloudUsage.service", off=True),
        },
        "stale": {"playInstalls": play_inst[-1]["date"]},
        "history": history,
        "repoVersion": "1.4.3", "repoBuild": "1043",
        "_": "SYNTHETIC FIXTURE from tools/pulse_make_fixture.py — every number is invented.",
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--today", help="YYYY-MM-DD (default: today, UTC)")
    ap.add_argument("--out", default=str(OUT))
    a = ap.parse_args()
    t = dt.date.fromisoformat(a.today) if a.today else dt.datetime.now(dt.timezone.utc).date()
    Path(a.out).write_text(json.dumps(build(t), indent=1) + "\n")
    print(f"wrote {a.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
