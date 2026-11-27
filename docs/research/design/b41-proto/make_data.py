"""B41 mock data: Trifles by Susan Glaspell (Project Gutenberg 59432, script gut-59432-101), lines L0026 to L0050,
and its roles with their line counts, written to data.js. No word of the play is written by hand; directions are
cleaned of their source brackets only. Usage: python3 make_data.py <play library dir> data.js"""
import os, json, re, sys

L, out = sys.argv[1], sys.argv[2]
d = json.load(open(os.path.join(L, "scripts", "gut-59432-101.json")))
s = [x for x in d["scripts"] if x["id"] == "gut-59432-101"][0]


def clean(t):
    return re.sub(r"\s+", " ", re.sub(r"[\[\]_]", "", t)).strip()


lines = []
for ln in s["lines"][25:50]:
    if ln["kind"] == "direction":
        lines.append({"id": ln["id"], "part": "direction", "text": clean(ln["source"])})
    else:
        lines.append({"id": ln["id"], "part": ln["role"],
                      "parts": [{"say": p["say"]} if "say" in p else {"direction": clean(p["direction"])}
                                for p in ln["parts"]]})
data = {"id": s["id"], "title": s["title"], "author": s["authors"][0]["display"], "count": len(s["lines"]),
        "roles": [[r["name"], r["lines"]] for r in sorted(s["roles"], key=lambda r: -r["lines"])], "lines": lines}
open(out, "w").write("const DATA = " + json.dumps(data, ensure_ascii=False) + ";\n")
print(data["roles"], len(lines))
