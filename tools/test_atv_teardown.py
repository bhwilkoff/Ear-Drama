#!/usr/bin/env python3
"""Guard: an Apple TV harness never powers a test device off, and its QA item comes from the data.

Owner rule: never sleep a test device. The teardown used to send turn_off (and
tools/atv_teardown.sh did by default); a TV was left dark for the owner. The item
the runners open is chosen from the published index, not pinned to one title.

    python3 tools/test_atv_teardown.py
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import apple_device as A  # noqa: E402
import app_config as C  # noqa: E402


def main():
    fails = []
    sent = []
    A.ATV._run = lambda self, *cmd, timeout=40: sent.append(cmd)
    A.terminate_verified = lambda udid, exe=None: (True, "gone")
    ok, lines = A.teardown({"name": "tv", "platform": "tvos", "udid": "X"}, found_power="off")
    if sent:
        fails.append(f"teardown sent the TV commands {sent}")
    if not ok:
        fails.append("teardown of a gone app must be ok")
    for name in ("apple_device.py", "atv_teardown.sh", "atv_run.py", "atv_scenario.py"):
        text = (HERE / name).read_text()
        if "turn_off" in text:
            fails.append(f"{name} still mentions turn_off")
    if hasattr(A.ATV, "turn_off_verified"):
        fails.append("ATV.turn_off_verified is back")

    index = {"fields": ["key", "name", "downloads"], "rows": [
        ["zzshow", "Zz Show", 99], ["librivoxA", "Alpha Beta Gamma", 5], ["librivoxB", "Bravo Charlie", 50]]}
    series = {"librivoxB": {"fields": ["id", "num", "rights"], "episodes": [["b|s0", 0, "clean"], ["b|s1", 1, "clean"]]},
              "librivoxA": {"fields": ["id", "num", "rights"], "episodes": [["a|s1", 1, "clean"]]}}
    fetch = lambda p: index if p.startswith("index/") else series[p.split("/")[1][:-5]]
    got = C.pick_qa_item(fetch)
    if got != ("b|s1", r"Bravo\s+Charlie"):
        fails.append(f"pick_qa_item chose {got}")
    series["librivoxB"]["episodes"] = [["b|s1", 1, "unclaimed"]]
    if C.pick_qa_item(fetch)[0] != "a|s1":
        fails.append("a section that is not clean was chosen")
    for f in fails:
        print("FAIL:", f)
    print("atv teardown guard:", "FAILED" if fails else "ok")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
