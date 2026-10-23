"""The on-screen transcript gate (tools/transcript_gate.py), with controls.

    python3 tests/test_transcript_gate.py
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import transcript_gate as G

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


import random
rng = random.Random(7)
vocab = ("the caller said she waited by phone again wrong number operator night house husband "
         "hospital clock listen voice line ringing murder plan bridge quiet street window").split()
speech = " ".join(rng.choice(vocab) for _ in range(4500))
check("ordinary speech at 150 words a minute is shown", G.shown(speech, 1800)[0], True)
check("music-heavy speech at 60 words a minute is shown", G.shown(" ".join(speech.split()[:1800]), 1800)[0], True)
loop = " ".join("thank you for watching" for _ in range(500))
check("a speech-to-text loop is not shown", G.shown(loop, 1800)[0], False)
check("control: too few words for the length is not shown", G.shown(speech[:400], 1800)[0], False)
check("control: an empty transcript is not shown", G.shown("", 1800)[0], False)
check("control: no length is not shown", G.shown(speech, 0)[0], False)
check("features name what decided", sorted(G.features(speech, 1800)), ["repeat", "words", "wpm"])

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
