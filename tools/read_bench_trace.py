#!/usr/bin/env python3
"""One timeline from a read-bench T7 trace (docs/DEVICE-HARNESSES.md "Read-room bench").

    python3 tools/read_bench_trace.py docs/research/data/t7c/<tag>-T7-trace.json [--repeats]

Merges the leader's presses, the Worker's states as the leader's socket saw them (cursor, generation, the last lines
done), and every device's [readdiag] record lines (take start/end, line-done sent/skipped/refused, justDid cleared),
all on the host clock, so the layer whose output first diverges can be read off. --repeats prints only the window
around each line some device opened more than once.
"""
import json
import sys
from collections import Counter


def timeline(t):
    ev = []
    for p in t["presses"]:
        ev.append((p["press_local_ms"], "LEADER", f"press {p['line']} base {p['base']} (cursor was {p.get('cursor_before')})"))
    prev = None
    for h in t["history"]:
        if prev is None or (h["cursor"], h["gen"], len(h["done"])) != (prev["cursor"], prev["gen"], len(prev["done"])):
            ev.append((h["at"], "WORKER", f"cursor {h['cursor']} gen {h['gen']} done ...{h['done'][-3:]}"))
        prev = h
    for d, lines in t["devices"].items():
        for ln in lines:
            ts, rest = ln.split(" ", 1)
            body = rest.split("[readdiag]")[-1].strip()
            if body.startswith(("lit ", "clock", "transport")):
                continue
            ev.append((float(ts), d, body))
    ev.sort(key=lambda e: e[0])
    return ev


def main():
    t = json.load(open(sys.argv[1]))
    ev = timeline(t)
    t0 = ev[0][0] if ev else 0
    rows = [f"{(e[0] - t0) / 1000:8.2f}  {e[1]:6}  {e[2]}" for e in ev]
    if "--repeats" in sys.argv:
        opens = Counter((e[1], e[2].split()[1]) for e in ev if e[2].startswith("rec "))
        rep = {line for (_, line), n in opens.items() if n > 1}
        keep = set()
        for i, e in enumerate(ev):
            if any(f" {line} " in f" {e[2]} " for line in rep):
                keep.update(range(max(0, i - 3), min(len(ev), i + 4)))
        rows = [rows[i] for i in sorted(keep)]
        print(f"lines opened more than once: {sorted(rep)}")
    print("\n".join(rows))


if __name__ == "__main__":
    main()
