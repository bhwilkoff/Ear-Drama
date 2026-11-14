"""frame_blind: an all-black PNG is blind; a real Duo frame is not."""
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from PIL import Image  # noqa: E402

import frame_blind  # noqa: E402

REAL = Path(__file__).resolve().parent.parent / "build/qa/duo-2026-11-14/outer/home.png"


def main():
    bad = []
    with tempfile.TemporaryDirectory() as d:
        black = Path(d) / "black.png"
        Image.new("RGBA", (1398, 2034), (0, 0, 0, 255)).save(black)
        near = Path(d) / "near.png"
        Image.new("RGB", (400, 800), (2, 1, 3)).save(near)
        for p, label in ((black, "all-black frame"), (near, "near-black frame")):
            if not frame_blind.is_blind(p):
                bad.append(f"{label} not judged blind")
    if REAL.exists():
        if frame_blind.is_blind(REAL):
            bad.append("a real Duo frame judged blind")
    else:
        print(f"SKIP positive control: {REAL} is not on this machine")
    for b in bad:
        print("FAIL", b)
    print("passed" if not bad else f"{len(bad)} failed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
