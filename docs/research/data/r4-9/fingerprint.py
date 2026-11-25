"""R4-9 measurement: normalization, word k-grams, winnowed index (research only, not product code).

    python3 fingerprint.py build <cache dir> <transcripts.json.gz or -> <out dir> [k] [w] [norm 0|1]

The index is one sorted array of unsigned 64-bit numbers: 47 bits of a k-gram's hash, 17 bits of
document number. No word of a text is in it. Standard library only.
"""
import array
import bisect
import collections
import gzip
import hashlib
import html
import json
import mmap
import os
import re
import sys
import time
import unicodedata

DOC_BITS = 17
M = (1 << 61) - 1
B = 0x1F3D5B79A2C4E681 % M

# One spelling for both sides. A table, not a model: what it maps is printed here.
EARLY = {"thou": "you", "thee": "you", "ye": "you", "thy": "your", "thine": "your", "hath": "has", "doth": "does",
         "hast": "have", "dost": "do", "art": "are", "wilt": "will", "shalt": "shall", "canst": "can", "didst": "did",
         "wast": "were", "wert": "were", "hadst": "had", "wouldst": "would", "couldst": "could", "shouldst": "should",
         "mine": "my", "oer": "over", "eer": "ever", "neer": "never", "een": "even", "ere": "before", "tis": "its",
         "twas": "itwas", "twill": "itwill", "thro": "through", "tho": "though", "altho": "although", "til": "till",
         "colour": "color", "honour": "honor", "favour": "favor", "labour": "labor", "neighbour": "neighbor",
         "grey": "gray", "theatre": "theater", "centre": "center", "shew": "show", "shewn": "shown",
         "okay": "ok", "alright": "allright", "mister": "mr", "missus": "mrs", "doctor": "dr", "cannot": "cant"}
WORD = re.compile(r"[a-z0-9']+")
SPAN = re.compile(r"\[[^\[\]]{0,240}\]|\([^()]{0,240}\)")
LABEL = re.compile(r"^[ \t_*]*([A-Z][A-Za-z.'’\- ]{0,30}?)[ _*]*(?:[.:;][_*]*|(?=\n|$))(?=\s|$)")


def canon(w):
    if w.endswith("'d") and len(w) > 3:
        w = w[:-2] + "ed"
    w = w.replace("'", "")
    if w in EARLY:
        return EARLY[w]
    if len(w) > 5 and w.endswith("eth"):
        return w[:-3] + "s"
    if len(w) > 5 and w.endswith("our"):
        return w[:-3] + "or"
    if len(w) > 5 and w.endswith("ise"):
        return w[:-3] + "ize"
    return w


_vocab, _canon = {}, {}


def words(text, norm=1):
    t = text
    if not t.isascii():
        t = unicodedata.normalize("NFKD", t.replace("’", "'").replace("‘", "'"))
        t = "".join(c for c in t if not unicodedata.combining(c))
    raw = WORD.findall(t.replace("_", "").lower())
    if not norm:
        return [x.replace("'", "") for x in raw]
    out = []
    for x in raw:
        c = _canon.get(x)
        if c is None:
            c = _canon[x] = canon(x)
        if c:
            out.append(c)
    return out


def strip_labels(text):
    """Speaker labels that open three paragraphs or more, and bracketed spans, are not words of the play."""
    text = SPAN.sub(" ", text)
    paras = re.split(r"\n\s*\n|\n(?=[A-Z][A-Z .'’]{1,24}[.:])", text)
    n, hit = collections.Counter(), []
    for p in paras:
        m = LABEL.match(p)
        lab = m.group(1).strip().lower() if m else None
        hit.append((p, m, lab))
        if lab and len(lab.split()) <= 4:
            n[lab] += 1
    return "\n".join(p[m.end():] if m and n[lab] >= 3 else p for p, m, lab in hit)


def tok(w):
    h = _vocab.get(w)
    if h is None:
        h = _vocab[w] = int.from_bytes(hashlib.blake2b(w.encode(), digest_size=8).digest(), "big") % M
    return h


def grams(ws, k):
    """The rolling hash of each k words, cut to 47 bits."""
    if len(ws) < k:
        return []
    bk = pow(B, k - 1, M)
    h, out, t = 0, [], [tok(w) for w in ws]
    for i in range(k):
        h = (h * B + t[i]) % M
    out.append(h)
    for i in range(k, len(t)):
        h = ((h - t[i - k] * bk) * B + t[i]) % M
        out.append(h)
    return [(x * 0x9E3779B97F4A7C15 & 0xFFFFFFFFFFFFFFFF) >> DOC_BITS for x in out]


def winnow(g, w):
    """Schleimer, Wilkerson, Aiken (2003): the least hash of every w in a row, kept once."""
    out, dq, last = set(), collections.deque(), -1
    for i, x in enumerate(g):
        while dq and g[dq[-1]] >= x:
            dq.pop()
        dq.append(i)
        if dq[0] <= i - w:
            dq.popleft()
        if i >= w - 1 and dq[0] != last:
            last = dq[0]
            out.add(g[last])
    if g and len(g) < w:
        out.add(min(g))
    return out


def gut_body(raw):
    t = raw.replace("\r", "")
    a = re.search(r"\*\*\* ?START OF TH(?:E|IS) PROJECT GUTENBERG[^\n]*\n", t)
    b = re.search(r"\*\*\* ?END OF TH(?:E|IS) PROJECT GUTENBERG", t)
    return t[a.end() if a else 0: b.start() if b else len(t)]


def grw_body(raw):
    t = raw.replace("\r", "")
    t = re.sub(r"<br\s*/?>", "\n", t, flags=re.I)
    t = re.sub(r"</p>", "\n\n", t, flags=re.I)
    return html.unescape(re.sub(r"<[^>]+>", "", t))


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def documents(cache, transcripts):
    for d, kind, body in (("gutenberg", "gut", gut_body), ("grw", "grw", grw_body)):
        base = os.path.join(cache, d, "text")
        for f in sorted(os.listdir(base)):
            yield f"{kind}-{f[:-4]}", lambda p=os.path.join(base, f), b=body: strip_labels(b(read(p)))
    if transcripts:
        rows = json.load(gzip.open(transcripts))
        for k in sorted(rows):
            t = rows[k].get("text")
            if t:
                yield "tr-" + k, lambda t=t: t


def build(cache, transcripts, out, k=5, w=12, norm=1):
    os.makedirs(out, exist_ok=True)
    t0 = time.time()
    buckets = [array.array("Q") for _ in range(64)]
    names, stats = [], collections.Counter()
    for doc, (name, get) in enumerate(documents(cache, transcripts)):
        ws = words(get(), norm)
        fp = winnow(grams(ws, k), w)
        names.append([name, len(ws)])
        src = name.split("-")[0]
        stats[src + "_docs"] += 1
        stats[src + "_words"] += len(ws)
        stats[src + "_prints"] += len(fp)
        for h in fp:
            v = h << DOC_BITS | doc
            buckets[v >> 58].append(v)
    with open(os.path.join(out, "index.u64"), "wb") as f:
        for i, b in enumerate(buckets):
            array.array("Q", sorted(b)).tofile(f)
            buckets[i] = None
    meta = {"k": k, "w": w, "norm": norm, "names": names, "stats": dict(stats), "seconds": round(time.time() - t0)}
    with open(os.path.join(out, "meta.json"), "w") as f:
        json.dump(meta, f)
    print(json.dumps({x: meta[x] for x in ("k", "w", "norm", "stats", "seconds")}),
          os.path.getsize(os.path.join(out, "index.u64")))


class Index:
    def __init__(self, d):
        self.meta = json.load(open(os.path.join(d, "meta.json")))
        f = open(os.path.join(d, "index.u64"), "rb")
        self.mm = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
        self.a = memoryview(self.mm).cast("Q")
        self.k, self.w, self.norm = self.meta["k"], self.meta["w"], self.meta["norm"]
        self.names = [n for n, _ in self.meta["names"]]

    def docs_of(self, h, cap):
        lo = bisect.bisect_left(self.a, h << DOC_BITS)
        out = []
        while lo < len(self.a) and self.a[lo] >> DOC_BITS == h:
            out.append(self.a[lo] & ((1 << DOC_BITS) - 1))
            lo += 1
            if len(out) > cap:
                return []
        return out

    def match(self, text, df_cap=60, exclude=lambda n: False):
        """(words, [features per document]). A run is hits in one document, each within w + 4 words of the last."""
        ws = words(text, self.norm)
        gap = self.w + 4
        pos = collections.defaultdict(list)
        seen = set()
        for i, h in enumerate(grams(ws, self.k)):
            # Each k-gram counts once, at its first place: a transcript that loops on "I'm a man" is not a copy.
            if h in seen:
                continue
            seen.add(h)
            for d in self.docs_of(h, df_cap):
                pos[d].append(i)
        res = []
        for d, ps in pos.items():
            if exclude(self.names[d]):
                continue
            runs, a, last, n = [], ps[0], ps[0], 1
            for p in ps[1:]:
                if p - last > gap:
                    runs.append((a, last, n))
                    a, n = p, 0
                last, n = p, n + 1
            runs.append((a, last, n))
            solid = [y - x + self.k for x, y, m in runs if m >= 3]
            res.append({"doc": self.names[d], "hits": len(ps), "run": max(solid, default=0),
                        "copied": sum(solid), "covered": sum(solid) / max(1, len(ws))})
        res.sort(key=lambda r: (-r["copied"], -r["hits"]))
        return len(ws), res


if __name__ == "__main__":
    if sys.argv[1] == "build":
        a = sys.argv[2:]
        build(a[0], a[1] if a[1] != "-" else None, a[2], *(int(x) for x in a[3:]))
