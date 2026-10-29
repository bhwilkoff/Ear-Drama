"""Direction D's build step: the series facts the shared sample lacks, and the tonal grade for every
picture D draws in a repeated slot, measured as uniform-imagery-design proposes (the 500 px Commons
thumbnail, inside the crop the slot shows; one linear map on luminance, k in [1.0, 1.6]).

python3 build_data.py <cacheDir>
Reads ../shared/sample.js and eardrama.org/data/index/series.json (cached in cacheDir with the thumbnails);
writes data.js (window.EDD). The grade formula is d2b-1/grade.py's, unchanged."""
import json, os, sys, re, urllib.request, hashlib, time
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = sys.argv[1]
os.makedirs(os.path.join(CACHE, 't500'), exist_ok=True)
UA = {'User-Agent': 'EarDrama-design-research/1.0 (ben@learningischange.com)'}


def get(url, fn):
    path = os.path.join(CACHE, fn)
    if not os.path.exists(path):
        for i in range(4):
            try:
                with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
                    open(path, 'wb').write(r.read())
                break
            except Exception as e:
                print('retry', url, e)
                time.sleep(3 + 4 * i)
    return path


src = open(os.path.join(HERE, '..', 'shared', 'sample.js')).read()
ED = json.loads(src[src.index('{'):src.rstrip().rstrip(';').rindex('}') + 1])
F = json.load(open(get('https://eardrama.org/data/manifest.json', 'manifest.json')))['fields']
idx = json.load(open(get('https://eardrama.org/data/index/series.json', 'series.json')))
S = {r[0]: dict(zip(idx['fields'], r)) for r in idx['rows']}

# The series D names outside the sample's own series records: a day's rows, the same-night rows,
# the evening's slots, Search. Only the projection's fields; the art array becomes an object.
keys = {r['series'] for r in ED['day']['rows']} | {r['series'] for r in ED['sameNight'] + ED['sameNightBare']}
keys |= {'escape', 'gunsmoke', 'dinahshoreshow', 'burnsandallen', 'jackbennyprogram', 'whistler'}
for ev in [ED['evening']] + ED['evening']['years']:
    for s in ev['slots']:
        if s.get('episode'):
            keys.add(s['episode']['id'].split('|')[0])
series = {}
for k in sorted(keys):
    s = S.get(k)
    if not s:
        continue
    art = dict(zip(F['art'], s['art'])) if s.get('art') else None
    series[k] = {'name': s['name'], 'genre': s['genre'], 'star': s['star'], 'art': art,
                 'episodes': s['episodes'], 'first': s['first'], 'last': s['last']}

# Every picture D draws in a repeated slot.
arts = {}
def add(a):
    if a and a.get('url'):
        arts[a['url']] = a
for s in ED['popular']:
    add(s.get('art'))
for p in ED['faces']:
    add(p.get('art'))
for c in ED['suspenseRich']['credits']:
    add(c.get('art'))
for e in ED['suspense']['season']:
    for f in e.get('faces') or []:
        add(f.get('art'))
for s in series.values():
    add(s['art'])

WIDE = 1.15
def crop_rect(w, h, f):
    if not w or not h:
        return None
    a = w / h
    if not f and a > WIDE:
        return None
    full = min(a, 1)
    cl = lambda v, lo, hi: min(hi, max(lo, v))
    s, left, top = full, 0.5 * (a - full), 0.2 * (1 - full)
    if f:
        s = cl(2 * max(f[2] * a, f[3]), full / 4, full)
        left = cl((f[0] + f[2] / 2) * a - s / 2, 0, a - s)
        top = cl(f[1] + f[3] / 2 - s / 2, 0, 1 - s)
    return dict(x=left / a, y=top, w=s / a, h=s)

T0, T1, KMIN, KMAX = 0.04, 0.96, 1.0, 1.6
grades = {}
for url, a in sorted(arts.items()):
    fn = get(url + '?width=500', 't500/' + hashlib.md5(url.encode()).hexdigest()[:12])
    try:
        rgb = np.asarray(Image.open(fn).convert('RGB')).astype(float) / 255
    except Exception as e:
        print('unreadable', url, e)
        continue
    c = crop_rect(a['width'], a['height'], a.get('face'))
    H, W = rgb.shape[:2]
    reg = rgb
    if c:
        reg = rgb[int(c['y'] * H):max(int((c['y'] + c['h']) * H), int(c['y'] * H) + 1),
                  int(c['x'] * W):max(int((c['x'] + c['w']) * W), int(c['x'] * W) + 1)]
    L = 0.2126 * reg[..., 0] + 0.7152 * reg[..., 1] + 0.0722 * reg[..., 2]
    mx, mn = reg.max(-1), reg.min(-1)
    sat = float(np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0).mean())
    warm = float((reg[..., 0] - reg[..., 2]).mean())
    lo, hi = float(np.percentile(L, 1)), float(np.percentile(L, 99))
    k = (T1 - T0) / max(hi - lo, 1e-3)
    if k <= KMIN:
        k, o = 1.0, 0.0
    elif k >= KMAX:
        k = KMAX
        o = 0.5 - k * (lo + hi) / 2
    else:
        o = T0 - lo * k
    tone = 'mono' if sat < 0.06 else ('sepia' if sat < 0.22 and warm > 0.03 else 'color')
    crop_px = round((c['h'] if c else 1) * a['height']) if a['height'] else None
    grades[url] = {'k': round(k, 3), 'o': round(o, 3), 'tone': tone, 'cropPx': crop_px}

out = {'generatedFrom': ED['generatedAt'], 'series': series, 'grades': grades}
open(os.path.join(HERE, 'data.js'), 'w').write(
    '/* Built by build_data.py: series facts from eardrama.org/data/index/series.json and the measured grade '
    '(uniform-imagery-design) per picture. */\nwindow.EDD = ' + json.dumps(out, separators=(',', ':')) + ';\n')
n = len(grades)
print(f'{len(series)} series, {n} pictures graded: '
      f"{sum(1 for g in grades.values() if g['k'] == 1.0)} identity, {sum(1 for g in grades.values() if g['k'] == KMAX)} at the cap; "
      f"tones {dict((t, sum(1 for g in grades.values() if g['tone'] == t)) for t in ('mono', 'sepia', 'color'))}")
