"""Static share pages: a real page at every served series and episode path.

    python3 build_share_pages.py <web projection dir> <site dir> [--origin https://eardrama.org]

`/series/{key}` and `/episode/{id}` are the links every app shares. GitHub Pages
answers a path it does not hold with a 404, which no preview bot reads, so each
served series and episode gets `series/{key}/index.html` / `episode/{id}/index.html`
carrying its card (title, description, Open Graph, Twitter, canonical) from the
web projection's data only, and a script that hands a person to the web app.
An aliased id (contract section 3.5) forwards to its successor; a tombstoned id
says it is no longer served. A path this does not write stays with 404.html.

An og:image is written only when the portrait's own record carries no credit
line (a license that needs credit sets `credit`, contract section 3.3a): the
card would show the picture without it.
"""
import argparse
import html
import json
import os
import sys
import urllib.parse

IMAGE_WIDTH = 1200


def load(web, rel, default=None):
    p = os.path.join(web, rel)
    if not os.path.exists(p):
        return default
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def path_safe(name):
    """An id that can be a directory name on the host; the rest stay with 404.html."""
    return bool(name) and name not in (".", "..") and not any(c in name for c in '/\\?#') \
        and all(ord(c) >= 32 for c in name)


def years(first, last):
    a, b = (first or "")[:4], (last or "")[:4]
    if a and b and a != b:
        return f"{a}–{b}"
    return a or b or None


def free_image(art):
    """The portrait's URL at card size, or None when it is absent or owes a credit."""
    if not art or not art[0] or art[3]:
        return None
    return f"{art[0]}{'&' if '?' in art[0] else '?'}width={IMAGE_WIDTH}"


def page(title, description, canonical, image, to, body):
    """One document. `to` is the web app URL a script hands a person to, or None."""
    e = lambda s: html.escape(s, quote=True)
    tags = [
        f'<link rel="canonical" href="{e(canonical)}">',
        '<meta property="og:site_name" content="Ear Drama">',
        '<meta property="og:type" content="website">',
        f'<meta property="og:title" content="{e(title)}">',
        f'<meta property="og:url" content="{e(canonical)}">',
        f'<meta name="twitter:card" content="{"summary_large_image" if image else "summary"}">',
        f'<meta name="twitter:title" content="{e(title)}">',
    ]
    if description:
        tags += [f'<meta name="description" content="{e(description)}">',
                 f'<meta property="og:description" content="{e(description)}">',
                 f'<meta name="twitter:description" content="{e(description)}">']
    if image:
        tags += [f'<meta property="og:image" content="{e(image)}">', f'<meta name="twitter:image" content="{e(image)}">']
    script = f"<script>location.replace({json.dumps(to)})</script>" if to else ""
    robots = "" if to else '<meta name="robots" content="noindex">'
    return ('<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width, initial-scale=1">'
            f"<title>{e(title)}</title>{robots}{''.join(tags)}{script}</head><body>{body}</body></html>\n")


def write(site, kind, name, text):
    d = os.path.join(site, kind, name)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "index.html"), "w", encoding="utf-8") as f:
        f.write(text)


def build(web, site, origin):
    origin = origin.rstrip("/")
    q = lambda s: urllib.parse.quote(s, safe="")
    genres = (load(web, "manifest.json", {}) or {}).get("genreNames", {})
    idx = load(web, "index/series.json")
    sf = idx["fields"]
    series = {r[sf.index("key")]: dict(zip(sf, r)) for r in idx["rows"]}
    s_alias = load(web, "index/series-aliases.json", {})
    s_tomb = load(web, "index/series-tombstones.json", [])
    e_alias = load(web, "index/aliases.json", {})
    e_tomb = load(web, "index/tombstones.json", [])
    counts = {"series": 0, "episodes": 0, "forwards": 0, "tombstones": 0, "skipped": 0}

    def url(kind, name):
        return f"{origin}/{kind}/{q(name)}"

    def gone(kind, name):
        if not path_safe(name):
            counts["skipped"] += 1
            return
        write(site, kind, name, page("No longer in Ear Drama", None, url(kind, name), None, None,
                                     '<p>This is no longer in Ear Drama. <a href="/">Ear Drama</a></p>'))
        counts["tombstones"] += 1

    def forward(kind, old, new, param):
        if not path_safe(old):
            counts["skipped"] += 1
            return
        write(site, kind, old, page("Ear Drama", None, url(kind, new), None, f"/?{param}={q(new)}",
                                    f'<p><a href="{html.escape(url(kind, new))}">Open in Ear Drama</a></p>'))
        counts["forwards"] += 1

    for key, s in series.items():
        if not path_safe(key):
            counts["skipped"] += 1
            continue
        n = s["episodes"]
        bits = [genres.get(s["genre"]), years(s["first"], s["last"]), s["networks"],
                f"{n} episode{'' if n == 1 else 's'}"]
        write(site, "series", key, page(
            f"{s['name']} | Ear Drama", ", ".join(b for b in bits if b), url("series", key), free_image(s["art"]),
            f"/?series={q(key)}",
            f'<p><a href="/?series={q(key)}">{html.escape(s["name"])} on Ear Drama</a></p>'))
        counts["series"] += 1
    for old, new in sorted(s_alias.items()):
        forward("series", old, new, "series")
    for key in s_tomb:
        gone("series", key)
    for old, new in sorted(e_alias.items()):
        forward("episode", old, new, "item")
    for eid in e_tomb:
        gone("episode", eid)

    di = {n: i for i, n in enumerate(load(web, "manifest.json")["fields"]["detail"])}
    for fn in sorted(os.listdir(os.path.join(web, "episodes"))):
        for eid, d in load(web, f"episodes/{fn}").items():
            s = series.get(d[di["series"]])
            if not s or not path_safe(eid):
                counts["skipped"] += 1
                continue
            name, date, net = d[di["title"]], d[di["date"]], d[di["network"]]
            title = name or (f"{s['name']}, {date}" if date else s["name"])
            star = d[di["star"]] if len(d) > di["star"] else None
            art = next((c[4] for c in d[di["credits"]] if star and c[3] == star), None) or s["art"]
            desc = ", ".join(b for b in [s["name"], date, net, years(s["first"], s["last"])] if b)
            write(site, "episode", eid, page(
                f"{title} | Ear Drama", desc, url("episode", eid), free_image(art), f"/?item={q(eid)}",
                f'<p><a href="/?item={q(eid)}">{html.escape(title)} on Ear Drama</a></p>'))
            counts["episodes"] += 1
    return counts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("web")
    ap.add_argument("site")
    ap.add_argument("--origin", default=None)
    a = ap.parse_args()
    origin = a.origin
    if not origin:
        cname = os.path.join(os.path.dirname(__file__), "..", "..", "CNAME")
        origin = "https://" + open(cname).read().strip()
    c = build(a.web, a.site, origin)
    files = nbytes = 0
    for kind in ("series", "episode"):
        for root, _, fs in os.walk(os.path.join(a.site, kind)):
            for f in fs:
                files += 1
                nbytes += os.path.getsize(os.path.join(root, f))
    print(f"share pages: {c['series']} series, {c['episodes']} episodes, {c['forwards']} forwards, "
          f"{c['tombstones']} tombstones, {c['skipped']} left to 404.html; {files} files, {nbytes} bytes")
    if c["series"] == 0 or c["episodes"] == 0:
        print("::error::no share pages written", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
