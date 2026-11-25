"""Six short phrases from a script, picked by rule (R4-9 section 2.6).

One from each sixth of the script: the rarest words in one sentence, 8 words (7 if no 8 fit), no part's name,
every word said before in radio speech (so a typing error is not "rare"). Deterministic: the same script gives
the same phrases.
"""
import math

from originality import normalize as N

COUNT = 6
LENGTHS = (8, 7)
SEEN_MIN = 2


def _windows(sent_words, n, freq, names, total):
    for i in range(len(sent_words) - n + 1):
        win = sent_words[i:i + n]
        if any(w in names or freq.get(w, 0) < SEEN_MIN for w in win):
            continue
        yield sum(math.log(total / freq[w]) for w in win), i, win


def pick(text, parts, freq):
    """Up to COUNT phrases, in script order."""
    names = {w for p in parts or [] for w in N.words(p)}
    total = sum(freq.values()) or 1
    sents = [N.words(s) for s in N.sentences(N.strip_labels(text))]
    sents = [s for s in sents if len(s) >= LENGTHS[-1]]
    if not sents:
        return []
    out = []
    for part in range(COUNT):
        lo, hi = part * len(sents) // COUNT, (part + 1) * len(sents) // COUNT
        for n in LENGTHS:
            best = max(((sc, -si, -i, win) for si in range(lo, hi) for sc, i, win in _windows(sents[si], n, freq, names, total)),
                       default=None)
            if best:
                out.append(" ".join(best[3]))
                break
    return list(dict.fromkeys(out))
