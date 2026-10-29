"""Build the D2 prototypes' small data sample from the live projection.

Reads https://eardrama.org/data/ (cached under raw/), writes one sample.json.
Everything in it is the projection's own data; nothing is written by hand
except the choice of which records to sample.
"""
import json, os, sys, collections, statistics
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fetch import get

PEOPLE_DIR = '/private/tmp/claude-501/-Users-bhwilkoff-Documents-GitHub-Ear-Drama/3500bd8e-5556-4177-ae20-9f6ead58871b/scratchpad/d1a/data/people'
OUT = sys.argv[1]

def fnv1a(s):
    h = 0x811c9dc5
    for b in s.encode('utf-8'):
        h ^= b
        h = (h * 0x01000193) & 0xffffffff
    return h

def shard(i):
    return format(fnv1a(i) & 0xfff, '03x')

m = get('manifest.json')
F = m['fields']
def rows(fields, rs):
    return [dict(zip(fields, r)) for r in rs]
def art(a):
    if not a: return None
    return dict(zip(F['art'], a))

idx = get('index/series.json')
S = {r['key']: r for r in rows(idx['fields'], idx['rows'])}
shows = [s for s in S.values() if s['episodes'] >= 10]
singles = [s for s in S.values() if s['episodes'] == 1]
small = [s for s in S.values() if 1 < s['episodes'] < 10]

def detail(eid):
    d = get(f'episodes/{shard(eid)}.json')
    rec = d.get(eid)
    if not rec: return None
    x = dict(zip(F['detail'], rec))
    x['id'] = eid
    x['recordings'] = rows(F['recording'], x.get('recordings') or [])
    cr = []
    for c in x.get('credits') or []:
        c = dict(zip(F['credit'], c))
        c['art'] = art(c.get('art'))
        cr.append(c)
    x['credits'] = cr
    x['star'] = x.get('star')
    if isinstance(x['star'], list):
        x['star'] = dict(zip(F['credit'], x['star']))
        x['star']['art'] = art(x['star'].get('art'))
    if x.get('arc'):
        x['arc'] = dict(zip(F['arc'], x['arc']))
    x.pop('li', None); x.pop('ltp', None)
    for r in x['recordings']:
        r.pop('url', None)
    return x

def strip(key):
    p = get(f'series/{key}.json')
    eps = rows(p['fields'], p['episodes'])
    years = sorted(int(e['date'][:4]) for e in eps if e['date'])
    hist = collections.Counter(years)
    core = None
    if years:
        lo = years[int(0.05 * (len(years) - 1))]
        hi = years[int(0.95 * (len(years) - 1))]
        core = [lo, hi]
    return p, eps, dict(sorted(hist.items())), core

def series_card(key, with_strip=True):
    s = dict(S[key])
    s['art'] = art(s['art'])
    s.pop('sortName', None)
    if with_strip:
        _, eps, hist, core = strip(key)
        s['hist'] = hist; s['core'] = core
        s['dated'] = sum(hist.values())
    return s

out = {'generatedAt': m['generatedAt'], 'counts': m['counts'], 'genreNames': m['genreNames'],
       'rightsLines': m['rightsLines'], 'variantLines': m.get('variantLines'),
       'tiers': {'shows': len(shows), 'showEpisodes': sum(s['episodes'] for s in shows),
                 'small': len(small), 'singles': len(singles), 'series': len(S)}}

# Shows by downloads (the Popular sort), and a decade x genre field over shows.
pop = sorted([s for s in shows if s['downloads']], key=lambda s: -s['downloads'])
TOP = [s['key'] for s in pop[:24]]
out['popular'] = [series_card(k) for k in TOP]
field = collections.Counter()
for s in shows:
    if s['first'] and s['genre']:
        dec = int(s['first'][:3]) * 10
        if 1920 <= dec <= 1960:
            field[(s['genre'], dec)] += 1
out['field'] = [{'genre': g, 'decade': d, 'shows': n} for (g, d), n in sorted(field.items())]
out['fieldUnsorted'] = sum(1 for s in shows if not s['genre'])

# Faces: the most-heard people with a served portrait.
people = {}
for n in sorted(os.listdir(PEOPLE_DIR)):
    for r in json.load(open(os.path.join(PEOPLE_DIR, n)))['rows']:
        people[r[0]] = r
faces = sorted([p for p in people.values() if p[3]], key=lambda p: -p[2])[:48]
out['faces'] = [{'id': p[0], 'name': p[1], 'episodes': p[2], 'art': art(p[3])} for p in faces]

# This day: October 29, every surviving year.
day = rows(get('index/days/10-29.json')['fields'], get('index/days/10-29.json')['rows'])
def tier(r):
    """The two-tier line (D1a §4.1): a show has ten or more episodes."""
    n = S[r['series']]['episodes'] if r['series'] in S else 1
    r['seriesEpisodes'] = n
    r['show'] = n >= 10
    return r
for r in day: r.pop('url', None); r.pop('li', None); r.pop('ltp', None); tier(r)
out['day'] = {'md': '10-29', 'rows': day}

# The rich series and a sparse one.
sp, seps, shist, score = strip('suspense')
out['suspense'] = {k: sp[k] for k in ('key', 'name', 'genre', 'first', 'last', 'networks', 'star', 'seasons')}
out['suspense'].update({'episodes': len(seps), 'hist': shist, 'core': score, 'downloads': S['suspense']['downloads']})
season = [e for e in seps if e['season'] == '1943-44']
for e in season: e.pop('url', None); e.pop('li', None); e.pop('ltp', None)
# Each 1943-44 episode's face and guests, from its Detail row.
for e in season:
    d = detail(e['id'])
    if d:
        e['network'] = d.get('network'); e['sponsor'] = d.get('sponsor')
        e['star'] = d.get('star')
        e['faces'] = [c for c in d['credits'] if c.get('art') and c['role'] == 'cast'][:3]
out['suspense']['season'] = season
out['suspenseRich'] = detail('suspense|1943-12-02')

# Gunsmoke, a show with a portrait.
gp, geps, ghist, gcore = strip('gunsmoke')
g = series_card('gunsmoke', with_strip=False)
g.update({'hist': ghist, 'core': gcore, 'seasons': gp.get('seasons')})
g['sample'] = [{k: e[k] for k in ('id', 'date', 'title', 'length')} for e in geps if e['date'] and e['date'].startswith('1952')][:12]
out['gunsmoke'] = g

# Sparse series: a small undated, unsorted series with a readable name.
cands = [s for s in small if not s['genre'] and not s['first'] and not s['star'] and 2 <= s['episodes'] <= 4
         and s['name'][:1].isalpha() and len(s['name']) < 30 and s['downloads']]
cands.sort(key=lambda s: -s['downloads'])
out['sparseCandidates'] = [s['name'] + ' | ' + s['key'] for s in cands[:25]]
key = os.environ.get('SPARSE') or cands[0]['key']
pp = get(f'series/{key}.json')
peps = rows(pp['fields'], pp['episodes'])
for e in peps: e.pop('url', None); e.pop('li', None); e.pop('ltp', None)
out['sparse'] = {k: pp.get(k) for k in ('key', 'name', 'genre', 'first', 'last', 'networks', 'star', 'seasons')}
out['sparse']['episodes'] = peps
out['sparseBare'] = detail(peps[0]['id'])

# The bare episode (D1b's case).
rn = get('series/1945radionews.json')
rne = rows(rn['fields'], rn['episodes'])
bare = next((e for e in rne if e['date'] == '1945-10-22'), rne[0])
out['bare'] = detail(bare['id'])
out['bareSeries'] = {k: S['1945radionews'][k] for k in ('key', 'name', 'genre', 'first', 'last', 'episodes')}

# The same night as the rich episode.
dd = rows(get('index/days/12-02.json')['fields'], get('index/days/12-02.json')['rows'])
out['sameNight'] = [tier({k: r[k] for k in ('id', 'title', 'series', 'seriesName', 'length')}) for r in dd if r['date'] == '1943-12-02']

db = get('index/days/10-22.json')
out['sameNightBare'] = [tier({k: r[k] for k in ('id', 'title', 'series', 'seriesName', 'length')})
                        for r in rows(db['fields'], db['rows']) if r['date'] == '1945-10-22']

# Tonight's evening on Stations.
t = get('tonight.json')
ev = t['days'].get('2026-10-29') or next(iter(t['days'].values()))
out['evening'] = {k: ev.get(k) for k in ('evening', 'picked', 'network', 'station', 'coverage')}
def slots(ss):
    return [{k: s.get(k) for k in ('et_start', 'et_end', 'length_min', 'gap', 'known_series', 'episode')} for s in ss]
out['evening']['slots'] = slots(ev['slots'])
out['evening']['years'] = [{'evening': y['evening'], 'network': y['network'], 'station': y['station'], 'slots': slots(y['slots'])} for y in ev.get('years', [])]

# The castable radio play.
cs = get('plays/castable-scripts.json')['scripts']
crr = next(s for s in cs if s['title'].startswith('Caesar Rodney'))
out['play'] = {k: crr[k] for k in ('id', 'kind', 'title', 'authors', 'source', 'rights', 'roles')}
out['play']['lines'] = [l for l in crr['lines'] if l['kind'] == 'speech'][:40]
out['plays'] = [{'id': s['id'], 'title': s['title'].strip(), 'kind': s['kind'], 'parts': len(s['roles']),
                 'words': sum(r['words'] for r in s['roles']), 'authors': s['authors']} for s in cs]

json.dump(out, open(OUT, 'w'), ensure_ascii=False, separators=(',', ':'))
print('bytes', os.path.getsize(OUT))
print('tiers', out['tiers'])
print('sparse', out['sparse']['name'], len(out['sparse']['episodes']))
print('cands', out['sparseCandidates'][:25])
print('season', len(season), 'sameNight', len(out['sameNight']))
print('evening', out['evening']['evening'], [s for s in out['evening']['slots'] if not s['gap']][:3])
print('rich', json.dumps(out['suspenseRich'])[:1500])
print('bare', json.dumps(out['bare'])[:800])
