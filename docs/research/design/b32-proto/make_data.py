"""B32 mock data: the real lines L0172-L0191 of Caesar Rodney's Ride (gut-28051) and the cast of Toinette and the
Elves (gut-58546-2), written to data.js. No word of a play is written by hand."""
import os, json, sys, collections
L, out = sys.argv[1], sys.argv[2]
def script(sid):
    d = json.load(open(os.path.join(L, "scripts", sid + ".json")))
    return [s for s in d["scripts"] if s["id"] == sid][0]
r = script("gut-28051")
lines = r["lines"][171:191]
def cast(sc):
    c = collections.Counter(); first = {}; cue = 0
    for i, ln in enumerate(sc["lines"]):
        p = ln.get("role") if ln["kind"] == "speech" else ln["kind"]
        c[p] += 1; first.setdefault(p, i)
        for pt in ln.get("parts", []):
            if "sound" in pt: cue += 1
    sp = sorted([k for k in c if k not in ("direction", "sound")], key=lambda k: (-c[k], first[k]))
    return {"parts": [[k, c[k]] for k in sp], "directions": c["direction"], "cues": cue + c["sound"]}
t = script("gut-58546-2")
rc = cast(r)
data = {"rodney": {"id": r["id"], "title": r["title"], "author": r["authors"][0]["display"], "lines": lines, "cast": rc},
        "toinette": {"id": t["id"], "title": t["title"], "lines": t["lines"][0:5], "author": t["authors"][0]["display"] if t["authors"] else "", "cast": cast(t)}}
open(out, "w").write("const DATA = " + json.dumps(data, ensure_ascii=False) + ";\n")
print(rc, cast(t))
