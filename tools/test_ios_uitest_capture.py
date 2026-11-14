"""The multi-display capture photographs only while the app is running, and never after the run's terminate
(Duo, 2026-11-14: a frame taken after the app exited showed the owner's private Messages conversation).

    python3 tools/test_ios_uitest_capture.py
"""
import re
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ios_uitest as U  # noqa: E402

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


class R:
    stdout = stderr = ""


def run_case(states):
    """states: what the app-alive probe answers, in order. Returns (captures made, files left)."""
    out = Path(tempfile.mkdtemp())
    seq = iter(states)
    made = []

    def capture(did, dest):
        made.append(did)
        dest.write_bytes(b"png")
        return R()
    U.frame_blind.is_blind = lambda p: False
    U.display_evidence("udid", ["A", "B"], out, alive=lambda: next(seq), capture=capture)
    return made, sorted(p.name for p in out.iterdir())


made, left = run_case([True, True, True, True])
check("app running: both displays captured", (made, len(left)), (["A", "B"], 2))
made, left = run_case([False, False])
check("negative control: app not running, nothing is captured", (made, left), ([], []))
made, left = run_case([None, None])
check("device could not be asked: nothing is captured", (made, left), ([], []))
made, left = run_case([True, False, False])
check("app gone after the capture: the frame is deleted", (made, left), (["A"], []))

src = Path(U.__file__).read_text()
body = src[src.index("def run(entry"):]
check("no capture call follows the terminate in run()", "display_evidence(" in body.split("terminate_verified")[-1], False)
check("the sampler stops before the terminate", body.index("sampler.stop.set()") < body.index("terminate_verified"), True)
check("no after-the-run capture", bool(re.search(r"^\s*display_evidence\(", body, re.M)), False)

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
