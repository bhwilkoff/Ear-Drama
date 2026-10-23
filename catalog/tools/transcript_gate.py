"""Whether an automatic transcript is shown on screen (DECISIONS 058).

Calibrated 2026-10-22 on 184 archive.org transcripts measured against human
scripts (measure_transcripts.py). Good transcripts ran 130-170 words per minute
of audio with almost no repeated four-word runs; the one real failure (Dragnet
1955-04-05) read 70 words a minute with 45% of its four-word runs repeated, the
loop a speech-to-text model falls into on music and noise; music-heavy shows that
were transcribed well ran as low as 61 words a minute. The near-zero scores
in that sample were scripts matched to the wrong broadcast, not bad transcripts.
Every transcript stays searchable; only the on-screen text is gated.
"""
import collections
import re

WORD = re.compile(r"[a-z0-9']+")
MIN_WPM, MAX_WPM = 50, 220
MAX_REPEAT = 0.10


def features(text, length_s):
    w = WORD.findall((text or "").lower())
    grams = [tuple(w[i:i + 4]) for i in range(len(w) - 3)]
    counts = collections.Counter(grams)
    repeat = sum(n for n in counts.values() if n > 2) / max(1, len(grams))
    wpm = len(w) / (length_s / 60) if length_s else 0.0
    return {"words": len(w), "wpm": round(wpm, 1), "repeat": round(repeat, 3)}


def shown(text, length_s):
    """(bool, features): True when the transcript may appear on screen."""
    f = features(text, length_s)
    return MIN_WPM <= f["wpm"] <= MAX_WPM and f["repeat"] <= MAX_REPEAT, f
