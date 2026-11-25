"""The index: one sorted array of unsigned 64-bit numbers per source (47 bits of a k-gram hash, 17 of document
number). No word of a text is in it (Decision 045). The Workshop's part is a file of its own, so it can be left
out; a source that is required and missing is refused.

Layout of an index folder:
    MANIFEST.json            date, k, w, per-source docs / words / prints / sha256
    gut.u64 gut.json         Gutenberg plays and drama books        (required)
    tr.u64  tr.json          archive.org's automatic transcripts    (required)
    grw.u64 grw.json         Generic Radio Workshop scripts         (optional, separable)
    freq.json.gz             how many times each word is said in radio speech (counts, no order)
    titles-<src>.json.gz     our own titles (gut, grw, cce), by normalized title
"""
import array
import bisect
import collections
import gzip
import hashlib
import json
import mmap
import os
import time

from originality import fingerprint as F
from originality import normalize as N

REQUIRED = ("gut", "tr")
OPTIONAL = ("grw",)
DF_CAP = 60


class IndexRefused(Exception):
    pass


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def jload(path):
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rt") as f:
        return json.load(f)


def documents(cache, transcripts_path, src):
    """(name, getter) of one source, in a fixed order. The caches are read-only."""
    if src in ("gut", "grw"):
        d, body = ("gutenberg", N.gut_body) if src == "gut" else ("grw", N.grw_body)
        base = os.path.join(cache, d, "text")
        for f in sorted(os.listdir(base)):
            yield f"{src}-{f[:-4]}", lambda p=os.path.join(base, f), b=body: N.strip_labels(b(read(p)))
    else:
        rows = jload(transcripts_path)
        for k in sorted(rows):
            t = rows[k].get("text")
            if t:
                yield "tr-" + k, lambda t=t: t


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def build_source(src, docs, out, k=F.K, w=F.W, freq=None):
    """docs: iterable of (name, text). Writes <src>.u64 and <src>.json; returns the manifest entry."""
    buckets = [array.array("Q") for _ in range(64)]
    names, words_n, prints_n = [], 0, 0
    for doc, (name, text) in enumerate(docs):
        if doc >= 1 << F.DOC_BITS:
            raise IndexRefused("too_many_documents")
        ws = N.words(text)
        if freq is not None:
            freq.update(ws)
        fp = F.winnow(F.grams(ws, k), w)
        names.append([name, len(ws)])
        words_n += len(ws)
        prints_n += len(fp)
        for h in fp:
            v = h << F.DOC_BITS | doc
            buckets[v >> 58].append(v)
    path = os.path.join(out, src + ".u64")
    with open(path, "wb") as f:
        for i, b in enumerate(buckets):
            array.array("Q", sorted(b)).tofile(f)
            buckets[i] = None
    with open(os.path.join(out, src + ".json"), "w") as f:
        json.dump({"names": names}, f)
    return {"docs": len(names), "words": words_n, "prints": prints_n, "bytes": os.path.getsize(path), "sha256": sha256(path)}


def write_manifest(out, date, k, w, sources):
    man = {"format": 1, "date": date, "k": k, "w": w, "sources": sources}
    with open(os.path.join(out, "MANIFEST.json"), "w") as f:
        json.dump(man, f, indent=1, sort_keys=True)
    return man


def write_freq(out, freq):
    with gzip.open(os.path.join(out, "freq.json.gz"), "wt") as f:
        json.dump({x: n for x, n in freq.items() if n >= 2}, f)


def build_titles(cache, out):
    """Our own titles, as the site already shows them: plays, radio scripts, renewed dramas."""
    def person(n):
        n = (n or "").strip()
        if "," in n:
            a, b = n.split(",", 1)
            n = f"{b.strip()} {a.strip()}"
        return n.title() if n.isupper() else n
    tabs = {"gut": {}, "grw": {}, "cce": {}}

    def add(src, id_, title, author):
        for key in N.title_keys(title):
            tabs[src].setdefault(key, []).append([id_, title, person(author)])
    for p in jload(os.path.join(cache, "gutenberg", "plays.json"))["plays"]:
        a = (p.get("authors") or [{}])[0].get("name", "")
        add("gut", p["id"], p["title"], a)
    for g in jload(os.path.join(cache, "grw", "scripts.json"))["scripts"]:
        add("grw", "grw-" + g["id"], g["title"], "")
    for i, r in enumerate(jload(os.path.join(cache, "cce_drama_renewals.json.gz"))):
        if r.get("title"):
            add("cce", "cce-" + str(r.get("r") or i), r["title"], r.get("author") or "")
    for src, t in tabs.items():
        with gzip.open(os.path.join(out, f"titles-{src}.json.gz"), "wt") as f:
            json.dump(t, f)
    return {s: len(t) for s, t in tabs.items()}


def build(cache, transcripts_path, out, date, without=(), k=F.K, w=F.W):
    """One source at a time: its texts are read, indexed and dropped before the next."""
    os.makedirs(out, exist_ok=True)
    t0 = time.time()
    freq = collections.Counter()
    sources = {}
    for src in REQUIRED + OPTIONAL:
        if src in without:
            continue
        docs = ((n, g()) for n, g in documents(cache, transcripts_path, src))
        sources[src] = build_source(src, docs, out, k, w, freq if src == "tr" else None)
    write_freq(out, freq)
    titles = build_titles(cache, out)
    for s in without:
        t = os.path.join(out, f"titles-{s}.json.gz")
        if os.path.exists(t):
            os.remove(t)
    man = write_manifest(out, date, k, w, sources)
    man["seconds"] = round(time.time() - t0)
    man["titles"] = titles
    return man


class Index:
    def __init__(self, d, verify=False):
        try:
            self.man = jload(os.path.join(d, "MANIFEST.json"))
        except (OSError, ValueError):
            raise IndexRefused("no_manifest")
        self.k, self.w, self.date = self.man["k"], self.man["w"], self.man["date"]
        self.id = hashlib.sha256(json.dumps(self.man, sort_keys=True).encode()).hexdigest()[:12]
        self.parts, self.left_out = [], []
        try:
            self._open(d, verify)
        except BaseException:
            self.close()
            raise
        self.dir = d
        self.sources = [p[0] for p in self.parts]
        self.works = sum(len(p[3]) for p in self.parts)
        self._freq = self._titles = None

    def _open(self, d, verify):
        for src in REQUIRED + OPTIONAL:
            p = os.path.join(d, src + ".u64")
            ent = self.man["sources"].get(src)
            if not (ent and os.path.exists(p) and os.path.exists(os.path.join(d, src + ".json"))):
                if src in REQUIRED:
                    raise IndexRefused("source_missing")
                self.left_out.append(src)
                continue
            if ent["docs"] <= 0 or os.path.getsize(p) != ent["bytes"]:
                raise IndexRefused("source_empty_or_changed")
            if verify and sha256(p) != ent["sha256"]:
                raise IndexRefused("source_sha")
            names = [n for n, _ in jload(os.path.join(d, src + ".json"))["names"]]
            if len(names) != ent["docs"]:
                raise IndexRefused("source_names")
            with open(p, "rb") as f:
                mm = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
            self.parts.append((src, mm, memoryview(mm).cast("Q"), names))

    def close(self):
        for src, mm, a, names in self.parts:
            a.release()
            mm.close()
        self.parts = []

    @property
    def freq(self):
        if self._freq is None:
            self._freq = jload(os.path.join(self.dir, "freq.json.gz"))
        return self._freq

    @property
    def titles(self):
        if self._titles is None:
            self._titles = {}
            for s in ("gut", "grw", "cce"):
                p = os.path.join(self.dir, f"titles-{s}.json.gz")
                if os.path.exists(p):
                    self._titles[s] = jload(p)
        return self._titles

    def docs_of(self, h, cap=DF_CAP):
        out = []
        for src, mm, a, names in self.parts:
            lo =bisect.bisect_left(a, h << F.DOC_BITS)
            while lo < len(a) and a[lo] >> F.DOC_BITS == h:
                out.append(names[a[lo] & ((1 << F.DOC_BITS) - 1)])
                lo += 1
                if len(out) > cap:
                    return []
        return out

    def match(self, text, df_cap=DF_CAP, exclude=lambda n: False):
        """(words, [features per document]). A run is hits in one document, each within w + 4 words of the last."""
        ws = N.words(text)
        gap = self.w + 4
        pos = collections.defaultdict(list)
        seen = set()
        for i, h in enumerate(F.grams(ws, self.k)):
            # Each k-gram counts once, at its first place: a transcript that loops on "I'm a man" is not a copy.
            if h in seen:
                continue
            seen.add(h)
            for d in self.docs_of(h, df_cap):
                pos[d].append(i)
        res = []
        for d, ps in pos.items():
            if exclude(d):
                continue
            runs, a, last, n = [], ps[0], ps[0], 1
            for p in ps[1:]:
                if p - last > gap:
                    runs.append((a, last, n))
                    a, n = p, 0
                last, n = p, n + 1
            runs.append((a, last, n))
            solid = [(x, y + self.k) for x, y, m in runs if m >= 3]
            lens = [y - x for x, y in solid]
            res.append({"doc": d, "hits": len(ps), "run": max(lens, default=0), "copied": sum(lens),
                        "covered": sum(lens) / max(1, len(ws)), "spans": solid})
        res.sort(key=lambda r: (-r["copied"], -r["hits"]))
        return len(ws), res
