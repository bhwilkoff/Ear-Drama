"""The share pages (tools/build_share_pages.py) over a fixture web projection.

    python3 tests/test_share_pages.py
Every rule has a broken control, run by `--control NAME` against the same
fixture; the suite also runs each control and demands that its check fails.
"""
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools"))
import build_share_pages as S

ran = failed = 0


def check(name, ok, detail=""):
    global ran, failed
    ran += 1
    if not ok:
        failed += 1
        print(f"FAIL {name} {detail}")


def put(root, rel, obj):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        json.dump(obj, f)


FREE = ["https://commons.wikimedia.org/wiki/Special:FilePath/Free.JPG", 600, 800, None, "https://e/free", None]
OWES = ["https://commons.wikimedia.org/wiki/Special:FilePath/Owes.JPG", 600, 800, "Jane Doe, CC BY 4.0", "https://e/owes", None]
SERIES_FIELDS = ["key", "name", "genre", "first", "last", "episodes", "networks", "star", "art", "sortName", "scripts", "downloads"]
DETAIL = ["series", "title", "date", "season", "num", "network", "networkSource", "rights", "rightsBasis", "length",
          "dateSource", "aka", "recordings", "credits", "li", "ltp", "transcript", "star", "script", "arc", "sponsor"]


def detail(series, title, date, net, credits=(), star=None):
    return [series, title, date, None, None, net, None, "clean", None, 1800, None, None, [], list(credits),
            None, None, None, star, None, None, None]


def fixture(root):
    put(root, "manifest.json", {"genreNames": {"mystery": "Mystery"}, "fields": {"detail": DETAIL}})
    put(root, "index/series.json", {"fields": SERIES_FIELDS, "rows": [
        ["free", "Free Show", "mystery", "1949-01-01", "1956-12-31", 2, "CBS", "A", FREE, "free show", 0, None],
        ["owes", "Owes Show", None, "1950-01-01", "1950-12-31", 1, None, "B", OWES, "owes show", 0, None],
        ["plain", "Plain & Simple", None, None, None, 1, None, None, None, "plain", 0, None]]})
    put(root, "index/aliases.json", {"free|old-id": "free|1949-02-02"})
    put(root, "index/tombstones.json", ["free|gone"])
    put(root, "index/series-aliases.json", {"oldfree": "free"})
    put(root, "index/series-tombstones.json", ["goneshow"])
    put(root, "episodes/000.json", {
        "free|1949-02-02": detail("free", "The \"Pilot\" <1>", "1949-02-02", "CBS"),
        "owes|1950-01-01": detail("owes", "Owed", "1950-01-01", None),
        "plain|undated": detail("plain", None, None, None),
        "free|star": detail("free", "Starred", "1950-03-03", "CBS", [["P", "cast", None, "p1", OWES]], "p1"),
        "weird/id": detail("free", "Slash", None, None)})


def read(site, kind, name):
    return open(os.path.join(site, kind, name, "index.html"), encoding="utf-8").read()


def run(control=None):
    with tempfile.TemporaryDirectory() as web, tempfile.TemporaryDirectory() as site:
        fixture(web)
        if control == "credited-image":
            S.free_image = lambda art: f"{art[0]}?width=1200" if art and art[0] else None
        if control == "no-escape":
            S.html.escape = lambda s, quote=True: s
        c = S.build(web, site, "https://eardrama.org")
        sp = read(site, "series", "free")
        check("series page: title from data", "<title>Free Show | Ear Drama</title>" in sp)
        check("series page: description is genre, years, network, count",
              'content="Mystery, 1949–1956, CBS, 2 episodes"' in sp)
        check("series page: open graph and twitter tags",
              all(t in sp for t in ('property="og:title"', 'property="og:description"', 'property="og:url"',
                                    'name="twitter:card"', 'name="twitter:title"')))
        check("series page: canonical", '<link rel="canonical" href="https://eardrama.org/series/free">' in sp)
        check("series page: a free portrait is the card image",
              'property="og:image" content="https://commons.wikimedia.org/wiki/Special:FilePath/Free.JPG?width=1200"' in sp
              and "summary_large_image" in sp)
        check("series page: hands off to the app at the same item", 'location.replace("/?series=free")' in sp)
        ow = read(site, "series", "owes")
        check("a credited (CC BY) portrait is left off", "og:image" not in ow and "twitter:image" not in ow and 'content="summary"' in ow)
        check("a series with no portrait or facts still has a card", 'og:title' in read(site, "series", "plain"))
        ep = read(site, "episode", "free|1949-02-02")
        check("episode page: title from data, escaped", "<title>The &quot;Pilot&quot; &lt;1&gt; | Ear Drama</title>" in ep, ep[:300])
        check("episode page: description is series, date, network, years",
              'content="Free Show, 1949-02-02, CBS, 1949–1956"' in ep)
        check("episode page: canonical is the percent-encoded path",
              'href="https://eardrama.org/episode/free%7C1949-02-02"' in ep)
        check("episode page: hands off to the app", 'location.replace("/?item=free%7C1949-02-02")' in ep)
        check("episode page: the series' free portrait", "Free.JPG?width=1200" in ep)
        check("episode page: a credited star portrait is left off, and does not fall to the series'",
              "og:image" not in read(site, "episode", "free|star"))
        check("episode of a credited series: no image", "og:image" not in read(site, "episode", "owes|1950-01-01"))
        check("an episode with no title takes the series and date",
              "<title>Plain &amp; Simple | Ear Drama</title>" in read(site, "episode", "plain|undated"))
        al = read(site, "episode", "free|old-id")
        check("an alias forwards to its successor",
              'location.replace("/?item=free%7C1949-02-02")' in al and 'href="https://eardrama.org/episode/free%7C1949-02-02"' in al)
        check("a series alias forwards", 'location.replace("/?series=free")' in read(site, "series", "oldfree"))
        tb = read(site, "episode", "free|gone")
        check("a tombstone says it is gone and hands off nowhere",
              "no longer in ear drama" in tb.lower() and "location.replace" not in tb and "noindex" in tb)
        check("a series tombstone too", "no longer in Ear Drama" in read(site, "series", "goneshow"))
        check("an id with a slash is left to 404.html",
              not os.path.exists(os.path.join(site, "episode", "weird")) and c["skipped"] == 1, str(c))
        check("counts", (c["series"], c["episodes"], c["forwards"], c["tombstones"]) == (3, 4, 2, 2), str(c))
        return failed


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--control":
        run(sys.argv[2])
        sys.exit(1 if failed else 0)
    run()
    for control in ("credited-image", "no-escape"):
        r = subprocess.run([sys.executable, __file__, "--control", control], capture_output=True, text=True)
        ran += 1
        if r.returncode == 0:
            failed += 1
            print(f"FAIL control {control}: the broken build still passed")
    print(f"{ran - failed} of {ran} checks passed" if not failed else f"{failed} FAILED of {ran}")
    sys.exit(1 if failed else 0)
