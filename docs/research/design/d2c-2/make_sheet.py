"""D2c-2 contact sheet data: 40 shows (5+ episodes), the picture each wore before and after the
show-first rule (contract section 3.3a), graded by d2b-1/grade.py (uniform-imagery-design).

    python3 make_sheet.py <before ear-drama.sqlite> <after ear-drama.sqlite> <workdir>

Writes <workdir>/sheet.json (the pictures, for grade.py), then runs grade.py, then rewrites
<workdir>/data.js as window.SHEET = {before: [...], after: [...]} in the same show order, with the
boards (no picture) put back. Also prints 20 before/after star pairs.
"""
import json
import os
import sqlite3
import subprocess
import sys

before_db, after_db, work = sys.argv[1:4]
os.makedirs(work, exist_ok=True)

def pictures(db, after):
    c = sqlite3.connect(db)
    cols = {r[1] for r in c.execute("PRAGMA table_info(series)")}
    pic = "s.picture" if after else "p.portrait"
    kind = "s.picture_kind, s.picture_source" if "picture_kind" in cols else "NULL, NULL"
    out = {}
    for key, name, genre, n, star, url, w, h, face, ev, k, src in c.execute(f"""
            SELECT s.key, s.name, s.genre, s.episodes, pe.name, a.url, a.width, a.height, a.face, a.evidence_url, {kind}
            FROM series s LEFT JOIN people pe ON pe.id = s.star LEFT JOIN people p ON p.id = s.star
            LEFT JOIN art a ON a.id = {pic} WHERE s.episodes >= 5"""):
        out[key] = dict(key=key, show=name, genre=genre or None, episodes=n, name=star or "", url=url, w=w, h=h,
                        face=[float(v) for v in face.split(",")] if face else None, evidence=ev,
                        kind=k or ("person" if url else None), source=src)
    return out


B, A = pictures(before_db, False), pictures(after_db, True)
show_gain = sorted((k for k in A if A[k]["kind"] == "show"), key=lambda k: -A[k]["episodes"])
star_change = sorted((k for k in A if A[k]["kind"] == "star" and B[k]["name"] != A[k]["name"]),
                     key=lambda k: -A[k]["episodes"])
star_new = sorted((k for k in A if A[k]["kind"] == "star" and not B[k]["url"]), key=lambda k: -A[k]["episodes"])
same = sorted((k for k in A if A[k]["kind"] in ("star", "person") and B[k]["name"] == A[k]["name"]),
              key=lambda k: -A[k]["episodes"])
board = sorted((k for k in A if not A[k]["url"]), key=lambda k: -A[k]["episodes"])
pick = []
for group, n in ((show_gain, 22), (star_change, 8), (star_new, 4), (same, 3), (board, 3)):
    pick += [k for k in group if k not in pick][:n]
pick = pick[:40]
print("picked", len(pick), "show", len([k for k in pick if A[k]["kind"] == "show"]))

entries = []
for phase, src in (("before", B), ("after", A)):
    for k in pick:
        p = dict(src[k], phase=phase, why=(src[k]["kind"] or "board") + (f" {src[k]['source']}" if src[k]["source"] else ""))
        entries.append(p)
json.dump([p for p in entries if p["url"]], open(os.path.join(work, "sheet.json"), "w"))
grade = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "d2b-1", "grade.py")
subprocess.run([sys.executable, grade, work], check=True)
graded = {(p["phase"], p["key"]): p for p in json.loads(open(os.path.join(work, "data.js")).read()[len("window.SHEET = "):-2])}
data = {ph: [graded.get((ph, k)) or next(p for p in entries if p["phase"] == ph and p["key"] == k) for k in pick]
        for ph in ("before", "after")}
open(os.path.join(work, "data.js"), "w").write("window.SHEET = " + json.dumps(data) + ";\n")

print("\n20 before/after pairs (series: before star -> after picture)")
pairs = [k for k in show_gain + star_change + star_new if B[k]["name"] or A[k]["kind"] != "show"][:20]
for k in pairs:
    a = A[k]
    after = (f"show image ({a['source']}): {a['evidence'].rsplit('File:', 1)[-1]}" if a["kind"] == "show"
             else f"{a['name']} ({a['kind']}, {a['source']})")
    print(f"- {B[k]['show']} ({B[k]['episodes']} eps): {B[k]['name'] or 'board'} -> {after}")
