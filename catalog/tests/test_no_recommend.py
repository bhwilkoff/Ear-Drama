"""The never-recommend rule for the Nazi state's own speeches (Archive Watch Decision 149).

Broken control (2026-10-19): with a bare-name pattern (no speech word required), 4/5 pass —
the US program ABOUT Hitler is flagged, which is the over-reach this rule exists to avoid.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import build_db as B

FLAG = ["Adolf Hitler - Reichstagsrede 1939-09-01", "Goebbels Sportpalastrede", "Rede Hermann Göring 1942"]
KEEP = ["The Shadow 1938-10-09 Death Stalks the Shadow", "Words at War 1944-06-06 The Hitler Gang",
        "Adolph Hitler and the Nazi Movement"]  # its series is "Founder's Day Speech": tested apart, not joined


def main():
    failed = 0
    for t in FLAG:
        if not B.NO_RECOMMEND.search(t):
            failed += 1
            print("FAIL not flagged:", t)
    for t in KEEP:
        if B.NO_RECOMMEND.search(t):
            failed += 1
            print("FAIL control flagged:", t)
    print(f"{6 - failed}/6 passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
