#!/usr/bin/env python3
"""Write a swatch sheet of every board and mark on every ground, light and dark (D2c-1).

  python3 swatches.py ../../../../design-tokens.json ../surfaces/swatches.html [title]

Each ground (background, surface, surfaceAlt) gets a row of the eight boards
as D draws them (the name in display type, a fact line, a run strip in the
on-board color with its empty years at 30%, a print mount), then the marks on
that ground: legend keys, a cast fingerprint of the marks side by side, a
part's face, and the chrome beside them (ink Play, the wayfinding blue, the
record button next to drama). Under each board: its text's APCA Lc and its
APCA against the ground. Colors are written inline from the token file, so a
sheet can be made for any token file (tokens-d2b-3.json for the before).
"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, 'palette_check.py')).read().split("if __name__")[0]
exec(src)

tp, out = sys.argv[1], sys.argv[2]
title = sys.argv[3] if len(sys.argv) > 3 else 'Boards and marks on every ground'
t = json.load(open(tp))
col = t['color']
keys = [k for k in col['genre'] if not k.startswith('$')]
NAMES = {'drama': 'Drama', 'mystery': 'Mystery', 'scifi': 'Science fiction', 'western': 'Western', 'comedy': 'Comedy',
         'news': 'News', 'documentary': 'Documentary', 'serial': 'Serials'}
board = col.get('board', col['genre']); onb = col.get('onBoard', col['onGenre'])
BARS = [0, 2, 5, 9, 12, 14, 13, 11, 0, 8, 10, 6, 3, 0, 1, 4]
font = os.path.relpath(os.path.join(HERE, '..', '..', '..', '..', 'fonts'), os.path.dirname(os.path.abspath(out)))
H = [f'''<!doctype html><html lang="en"><meta charset="utf-8"><title>{title}</title><style>
@font-face {{ font-family: "Big Shoulders"; src: url("{font}/big-shoulders.woff2") format("woff2"); font-weight: 700; }}
@font-face {{ font-family: "Public Sans"; src: url("{font}/public-sans.woff2") format("woff2"); font-weight: 100 900; }}
body {{ margin: 0; font: 13px/1.3 "Public Sans", system-ui, sans-serif; }}
.mode {{ padding: 20px 24px 8px; }} h1 {{ font: 700 28px/1 "Big Shoulders"; margin: 0 0 12px; }}
.ground {{ border-radius: 12px; padding: 14px; margin-bottom: 14px; }}
.gl {{ font-size: 12px; margin-bottom: 8px; }}
.boards {{ display: grid; grid-template-columns: repeat(8, 1fr); gap: 10px; }}
.b {{ border-radius: 12px; padding: 6px 6px 8px; display: flex; flex-direction: column; gap: 5px; }}
.b .mount {{ aspect-ratio: 4 / 3; border-radius: 4px; }}
.b .nm {{ font: 700 19px/1 "Big Shoulders"; text-transform: uppercase; padding: 0 3px; }}
.b .fx {{ font-size: 12px; padding: 0 3px; }}
.b svg {{ width: 100%; height: 16px; padding: 0 3px; box-sizing: border-box; }}
.num {{ font: 11px/1.3 ui-monospace, Menlo, monospace; margin-top: 3px; }}
.marks {{ display: flex; flex-wrap: wrap; align-items: center; gap: 10px 18px; margin-top: 12px; }}
.key {{ display: inline-flex; align-items: center; gap: 6px; }} .key i {{ width: 10px; height: 10px; border-radius: 2px; display: inline-block; }}
.strip {{ display: flex; gap: 1px; width: 260px; height: 8px; }} .strip i {{ flex: 1; border-radius: 1px; }}
.face {{ width: 30px; height: 30px; border-radius: 50%; display: inline-flex; align-items: center; justify-content: center; font: 700 15px/1 "Big Shoulders"; }}
.btn {{ display: inline-flex; align-items: center; height: 36px; padding: 0 14px; border-radius: 8px; font-weight: 600; }}
.rec {{ width: 36px; height: 36px; border-radius: 50%; display: inline-flex; align-items: center; justify-content: center; }}
.rec i {{ width: 12px; height: 12px; border-radius: 50%; display: block; }}
</style><body>''']
for mode in ('light', 'dark'):
    br = {k: v[mode] for k, v in col['brand'].items() if not k.startswith('$')}
    H.append(f'<div class="mode" style="background:{br["background"]};color:{br["text"]}"><h1>{title}: {mode}</h1>')
    print_ground = '#EDEDED' if mode == 'light' else '#2A2A2E'
    for g_name in ('background', 'surface', 'surfaceAlt'):
        G = br[g_name]
        H.append(f'<div class="ground" style="background:{G};box-shadow:0 0 0 1px {br["border"]}"><div class="gl" style="color:{br["textMuted"]}">on {g_name} {G}</div><div class="boards">')
        for k in keys:
            bd, on = board[k][mode], onb[k][mode]
            dim = mix(on, bd, 0.3)
            bars = ''.join(f'<rect x="{i * 10}" y="{16 - max(1, v)}" width="8" height="{max(1, v)}" fill="{on if v else dim}"/>' for i, v in enumerate(BARS))
            H.append(f'<div><div class="b" style="background:{bd};color:{on}"><div class="mount" style="background:{print_ground}"></div>'
                     f'<div class="nm">{NAMES[k]}</div><svg viewBox="0 0 160 16" preserveAspectRatio="none">{bars}</svg><div class="fx">1943–1961 · 1,101</div></div>'
                     f'<div class="num" style="color:{br["textMuted"]}">{bd}<br>text Lc {apca(on, bd):.0f}<br>vs ground Lc {apca(bd, G):.0f}</div></div>')
        H.append('</div><div class="marks">')
        for k in keys:
            H.append(f'<span class="key"><i style="background:{col["genre"][k][mode]}"></i>{NAMES[k]}</span>')
        H.append('<span class="strip">' + ''.join(f'<i style="background:{col["genre"][k][mode]};flex:{n}"></i>' for k, n in zip(keys, (5, 4, 3, 3, 2, 2, 2, 1))) + '</span>')
        H.append(''.join(f'<span class="face" style="background:{col["genre"][k][mode]};color:{col["onGenre"][k][mode]}">{NAMES[k][0]}</span>' for k in keys))
        H.append(f'<span class="btn" style="background:{br["primary"]};color:{br["onPrimary"]}">Play</span>'
                 f'<span class="btn" style="background:{br["secondary"]};color:{br["onSecondary"]}">Shows</span>'
                 f'<span class="btn" style="color:{br["link"]}">All 80</span>'
                 f'<span class="key"><span class="b" style="background:{board["drama"][mode]};width:36px;height:36px;padding:0"></span>'
                 f'<span class="rec" style="background:{br["record"]}"><i style="background:{br["onRecord"]}"></i></span></span>')
        H.append('</div></div>')
    H.append('</div>')
H.append('</body></html>')
os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
open(out, 'w').write('\n'.join(H))
print('wrote', out)
