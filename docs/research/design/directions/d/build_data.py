"""Direction D's build step (D2c-3): the series facts the shared sample lacks, the picture that leads each
show (contract section 3.3a: series.picture, picture_kind show/star/person, picture_source), the run of
every show D draws, and the tonal grade for every picture D draws in a repeated slot, measured as
uniform-imagery-design proposes (the 500 px Commons thumbnail, inside the crop the slot shows; one linear
map on luminance, k in [1.0, 1.6]).

python3 build_data.py <cacheDir> <ear-drama.sqlite>
The database is a projection built by catalog/tools/build_projection.py with the D2c-2 picture columns
(read only; the live eardrama.org index did not carry them yet on 2026-10-29). Reads ../shared/sample.js.
Writes data.js (window.EDD). The grade formula is d2b-1/grade.py's, unchanged."""
import collections
import hashlib
import json
import os
import sqlite3
import sys
import time
import urllib.request

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE, DB = sys.argv[1], sys.argv[2]
os.makedirs(os.path.join(CACHE, 't500'), exist_ok=True)
UA = {'User-Agent': 'EarDrama-design-research/1.0 (ben@learningischange.com)'}
SHOW_LINE = 5  # owner, 2026-10-29: "Having more shows is better, so 5."


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
db = sqlite3.connect(f'file:{DB}?mode=ro', uri=True)

# The shows D draws: the most downloaded (recomputed at the show line of 5), the day's and the nights'
# rows, the evening's slots, Search, Library, the series pages, and Browse A to Z from B for a wall that is
# mostly boards (the catalog's real share).
top = [k for (k,) in db.execute(
    'SELECT key FROM series WHERE episodes >= ? AND downloads IS NOT NULL ORDER BY downloads DESC LIMIT 24', (SHOW_LINE,))]
az = [k for (k,) in db.execute(
    "SELECT key FROM series WHERE episodes >= ? AND sort_name >= 'b' ORDER BY sort_name LIMIT 24", (SHOW_LINE,))]
keys = set(top) | set(az) | {r['series'] for r in ED['day']['rows']} | {r['series'] for r in ED['sameNight'] + ED['sameNightBare']}
keys |= {'escape', 'gunsmoke', 'dinahshoreshow', 'burnsandallen', 'jackbennyprogram', 'whistler', 'suspense', 'dragnet',
         'ourmissbrooks', 'xminusone', ED['sparse']['key'], ED['bareSeries']['key']}
for ev in [ED['evening']] + ED['evening']['years']:
    for s in ev['slots']:
        if s.get('episode'):
            keys.add(s['episode']['id'].split('|')[0])

people = {}
def person(pid):
    if pid and pid not in people:
        r = db.execute('SELECT name FROM people WHERE id = ?', (pid,)).fetchone()
        people[pid] = r[0] if r else None
    return people.get(pid)

series = {}
for k in sorted(keys):
    r = db.execute('SELECT s.name, s.genre, s.first_date, s.last_date, s.episodes, s.networks, s.downloads, s.star, '
                   's.picture_kind, s.picture_source, a.url, a.width, a.height, a.face, a.evidence_url '
                   'FROM series s LEFT JOIN art a ON a.id = s.picture WHERE s.key = ?', (k,)).fetchone()
    if not r:
        continue
    name, genre, first, last, n, nets, dl, star, kind, psrc, url, w, h, face, ev = r
    years = sorted(int(d[:4]) for (d,) in db.execute(
        'SELECT air_date FROM episodes WHERE series_key = ? AND air_date IS NOT NULL', (k,)))
    hist = dict(sorted(collections.Counter(years).items()))
    core = [years[int(0.05 * (len(years) - 1))], years[int(0.95 * (len(years) - 1))]] if years else None
    pic = None
    if url:
        pic = {'url': url, 'width': w, 'height': h, 'face': [float(v) for v in face.split(',')] if face else None,
               'evidence': ev, 'kind': kind, 'source': psrc, 'who': person(star) if kind in ('star', 'person') else None}
    series[k] = {'name': name, 'genre': genre or '', 'first': first, 'last': last, 'episodes': n,
                 'networks': ', '.join(json.loads(nets)) if nets else None, 'downloads': dl,
                 'picture': pic, 'hist': hist, 'core': core, 'dated': len(years)}

# The counts the screens state: the show line at 5 (2,036 shows), the tail, and the pictures' kinds.
shows = db.execute('SELECT count(*) FROM series WHERE episodes >= ?', (SHOW_LINE,)).fetchone()[0]
tiers = {'shows': shows,
         'singles': db.execute('SELECT count(*) FROM series WHERE episodes = 1').fetchone()[0],
         'small': db.execute('SELECT count(*) FROM series WHERE episodes BETWEEN 2 AND ?', (SHOW_LINE - 1,)).fetchone()[0]}
kinds = dict(db.execute('SELECT coalesce(picture_kind, "board"), count(*) FROM series WHERE episodes >= ? GROUP BY 1', (SHOW_LINE,)))
field = [{'genre': g, 'decade': int(d), 'shows': c} for g, d, c in db.execute(
    "SELECT genre, substr(first_date, 1, 3) || '0', count(*) FROM series WHERE episodes >= ? AND genre IS NOT NULL AND genre != '' "
    'AND first_date IS NOT NULL GROUP BY 1, 2', (SHOW_LINE,)) if 1920 <= int(d) <= 1960]
unsorted = db.execute("SELECT count(*) FROM series WHERE episodes >= ? AND (genre IS NULL OR genre = '')", (SHOW_LINE,)).fetchone()[0]

# Every picture D draws in a repeated slot.
arts = {}
def add(a):
    if a and a.get('url'):
        arts[a['url']] = a
for p in ED['faces']:
    add(p.get('art'))
for c in ED['suspenseRich']['credits']:
    add(c.get('art'))
for e in ED['suspense']['season']:
    for f in e.get('faces') or []:
        add(f.get('art'))
for s in series.values():
    add(s['picture'])

WIDE = 1.15
def crop_rect(w, h, f):
    if not w or not h:
        return None
    a = w / h
    if not f and a > WIDE:
        return None
    full = min(a, 1)
    cl = lambda v, lo, hi: min(hi, max(lo, v))
    s, left, top_ = full, 0.5 * (a - full), 0.2 * (1 - full)
    if f:
        s = cl(2 * max(f[2] * a, f[3]), full / 4, full)
        left = cl((f[0] + f[2] / 2) * a - s / 2, 0, a - s)
        top_ = cl(f[1] + f[3] / 2 - s / 2, 0, 1 - s)
    return dict(x=left / a, y=top_, w=s / a, h=s)

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

out = {'generatedFrom': db.execute("SELECT value FROM meta WHERE key = 'generatedAt'").fetchone()[0].strip('"'),
       'showLine': SHOW_LINE, 'tiers': tiers, 'kinds': kinds, 'field': field, 'fieldUnsorted': unsorted,
       'top': top, 'az': az, 'series': series, 'grades': grades}
open(os.path.join(HERE, 'data.js'), 'w').write(
    '/* Built by build_data.py from a projection with the D2c-2 picture columns: series facts, the picture that '
    'leads each show (contract 3.3a), runs, and the measured grade (uniform-imagery-design) per picture. */\n'
    'window.EDD = ' + json.dumps(out, separators=(',', ':'), ensure_ascii=False) + ';\n')
n = len(grades)
drawn = collections.Counter((s['picture'] or {}).get('kind', 'board') for s in series.values())
print(f'{len(series)} series ({dict(drawn)} drawn); shows {shows}, kinds {kinds}; {n} pictures graded: '
      f"{sum(1 for g in grades.values() if g['k'] == 1.0)} identity, {sum(1 for g in grades.values() if g['k'] == KMAX)} at the cap")
