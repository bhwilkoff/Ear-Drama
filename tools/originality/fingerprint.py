"""Word k-grams and winnowing (Schleimer, Wilkerson, Aiken 2003).

Every K words in a row become a 47-bit number; a known text keeps the least number of every W in a row, so
any K + W - 1 = 16 words in common are sure to share one. The script being checked keeps all of its own.
"""
import collections
import hashlib

DOC_BITS = 17
K = 5
W = 12
M = (1 << 61) - 1
B = 0x1F3D5B79A2C4E681 % M

_vocab = {}


def tok(w):
    h = _vocab.get(w)
    if h is None:
        h = _vocab[w] = int.from_bytes(hashlib.blake2b(w.encode(), digest_size=8).digest(), "big") % M
    return h


def grams(ws, k):
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
    """The least hash of every w in a row (the rightmost on a tie), kept once."""
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
