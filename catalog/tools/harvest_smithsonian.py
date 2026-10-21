#!/usr/bin/env python3
"""Smithsonian Open Access: radio objects, photographs and portraits, from the
bulk metadata on the public S3 bucket (no key), never the image binaries.

WHY the bulk files and not api.si.edu: the API needs an api.data.gov key, and
DEMO_KEY answered OVER_RATE_LIMIT from this egress IP on the first call
(2026-10-21) — it is shared. The bucket is the same EDAN records, line-delimited
JSON, 256 shards a unit (NMAH ~9.8 MB a shard), read at ~10 MB/s.

Each shard is streamed, filtered (a radio word AND a broadcast word, below) and
only the matches are written to .cache/smithsonian/<unit>/<shard>.json.gz, so a
re-run skips finished shards (resumable). A record keeps: title, date, unit,
record id + guid, object type, topics, names, the RECORD's metadata usage and
EACH media item's own usage ("CC0" or "Usage conditions apply"), and the
media's delivery URLs (the largest the record lists).

Run: python3 tools/harvest_smithsonian.py [--units nmah,npg,nmaahc,sia]
"""
import argparse
import gzip
import json
import os
import re
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ia_lib as L

DIR = os.path.join(L.CACHE, "smithsonian")
BUCKET = "https://smithsonian-open-access.s3-us-west-2.amazonaws.com/metadata/edan/"
RADIO = re.compile(r"\bradio\b", re.I)
CONTEXT = re.compile(r"\b(broadcast\w*|program\w*|microphone\w*|announcer|studio|station|receiver\w*|network|nbc|cbs|"
                     r"mutual|actor|actress|comedian|show|serial|drama|wjz|weaf|kdka|transcription|on the air)\b", re.I)


def keep(d):
    c = d.get("content") or {}
    txt = json.dumps({k: c.get(k) for k in ("freetext", "indexedStructured")}, ensure_ascii=False) + " " + (d.get("title") or "")
    return bool(RADIO.search(txt) and CONTEXT.search(txt))


def slim(d):
    c = d.get("content") or {}
    dn = c.get("descriptiveNonRepeating") or {}
    ft = c.get("freetext") or {}
    ix = c.get("indexedStructured") or {}
    media = []
    for m in ((dn.get("online_media") or {}).get("media") or []):
        if m.get("type") not in ("Images", "Screen Images", None):
            continue
        res = m.get("resources") or []
        jpg = [r for r in res if ".jpg" in (r.get("url") or "")] or res
        big = max(jpg, key=lambda r: (r.get("width") or 0) * (r.get("height") or 0), default=None)
        media.append({"id": m.get("idsId"), "usage": (m.get("usage") or {}).get("access"),
                      "content": m.get("content"), "thumbnail": m.get("thumbnail"),
                      "largest": (big or {}).get("url"), "width": (big or {}).get("width"),
                      "height": (big or {}).get("height")})
    def lab(key):
        return [x.get("content") for x in (ft.get(key) or []) if x.get("content")]
    return {
        "id": dn.get("record_ID") or d.get("id"), "guid": dn.get("guid"), "unit": d.get("unitCode"),
        "title": d.get("title"), "record_link": dn.get("record_link") or ("https://www.si.edu/object/" + dn["record_ID"] if dn.get("record_ID") else None),
        "metadata_usage": (dn.get("metadata_usage") or {}).get("access"),
        "dates": lab("date"), "names": lab("name"), "object_type": lab("objectType"),
        "set": lab("setName"), "credit": lab("creditLine"), "notes": lab("notes")[:6],
        "rights_text": lab("objectRights"),
        "topics": ix.get("topic") or [], "ix_names": ix.get("name") or [], "ix_dates": ix.get("date") or [],
        "media": media,
    }


def shard(unit, url):
    name = url.rsplit("/", 1)[-1].replace(".txt", "")
    out = os.path.join(DIR, unit, name + ".json.gz")
    if os.path.exists(out):
        return L.read_json(out), True
    req = urllib.request.Request(url, headers={"User-Agent": L.UA})
    rows = []
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            for line in r:
                try:
                    d = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if keep(d):
                    rows.append(slim(d))
    except Exception as e:  # a partial shard is not written: it re-reads next time
        print(f"shard failed {url}: {e}", file=sys.stderr)
        return None, False
    L.write_json(out, rows, gz=True)
    return rows, False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--units", default="nmah,npg,nmaahc,sia")
    a = ap.parse_args()
    failed, total = [], {}
    for unit in a.units.split(","):
        os.makedirs(os.path.join(DIR, unit), exist_ok=True)
        idx = L.get(BUCKET + unit + "/index.txt", raw=True)
        if idx is None:
            failed.append(unit + "/index.txt")
            continue
        urls = [u.strip() for u in idx.decode().split() if u.strip().endswith(".txt")]
        n = 0
        for i, u in enumerate(urls):
            rows, cached = shard(unit, u)
            if rows is None:
                failed.append(u)
                continue
            n += len(rows)
            if not cached and i % 16 == 0:
                print(f"{unit} {i + 1}/{len(urls)} kept {n}", file=sys.stderr)
        total[unit] = {"shards": len(urls), "kept": n}
    L.write_json(os.path.join(DIR, "summary.json"), {"units": total, "failed": failed})
    print(json.dumps({"units": total, "failed": len(failed)}), file=sys.stderr)
    if not any(v["kept"] for v in total.values()):
        sys.exit(1)


if __name__ == "__main__":
    main()
