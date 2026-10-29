"""Writes data.js for the D2b-2 Record a Line prototype from the castable bundle.

python3 build_data.py <repo root>

Every word on the prototype's script screens is the bundle's own slice of the
printed text (catalog/plays/castable-scripts.json). The play's hue is a rule over
Project Gutenberg's own subject headings and bookshelves (pg_catalog.csv, read
2026-10-29), copied below with the heading that decided it: comedy when a subject
or shelf says Comedy plays, Farce, Tragicomedy or Humour; drama otherwise.
"""
import json
import sys
from pathlib import Path

GUTENBERG_SUBJECT = {
    '47826': ('comedy', 'Comedy plays'),
    '54702': ('drama', 'Rome -- History -- Nero, 54-68 -- Drama'),
    '49295': ('drama', 'United States -- History -- Civil War, 1861-1865 -- Drama'),
    '28051': ('drama', 'Radio plays'),
    '2265': ('drama', 'Tragedies (Drama)'),
    '1502': ('drama', 'Historical drama'),
    '7364': ('comedy', 'Category: Humour'),
    '12039': ('comedy', 'Tragicomedy'),
    '67583': ('drama', 'Jewish singers -- Drama'),
    '27357': ('drama', 'Radio plays'),
    '5071': ('drama', 'Man-woman relationships -- Drama'),
    '28527': ('drama', 'Radio plays'),
    '49916': ('drama', 'Married people -- Drama'),
    '28511': ('drama', 'Radio plays'),
    '76327': ('comedy', 'Comedy plays'),
}
BINS = 48


def author_name(a):
    last, _, first = a['name'].partition(', ')
    first = first.split(' (')[0]
    return f'{first} {last}'.strip() if first else last


def text_of(line):
    out = []
    for p in line['parts']:
        if 'say' in p:
            out.append({'say': p['say']})
        else:
            k = next(iter(p))
            out.append({'dir': p[k]})
    return out


def main(root):
    bundle = json.loads((Path(root) / 'catalog/plays/castable-scripts.json').read_text())
    plays = []
    scene = None
    for s in bundle['scripts']:
        gid = s['id'].split('-')[1]
        speeches = [l for l in s['lines'] if l['kind'] == 'speech']
        n = len(speeches)
        roles = sorted(s['roles'], key=lambda r: (-r['words'], r['name']))
        presence = {}
        for i, l in enumerate(speeches):
            b = min(BINS - 1, i * BINS // max(1, n))
            presence.setdefault(l['role'], [0] * BINS)[b] += 1
        words = sum(r['words'] for r in roles)
        genre, heading = GUTENBERG_SUBJECT[gid]
        plays.append({
            'id': s['id'], 'title': s['title'].strip(), 'kind': s['kind'],
            'radio': 'Radio plays' == heading,
            'authors': [{'name': author_name(a), 'born': a.get('born'), 'died': a.get('died')} for a in s['authors']],
            'genre': genre, 'genreEvidence': heading, 'source': s['source']['url'],
            'rights': s['rights']['evidence'][0]['claim'] if s['rights'].get('evidence') else '',
            'words': words, 'speeches': n,
            'roles': [{'name': r['name'], 'lines': r['lines'], 'words': r['words'],
                       'presence': presence.get(r['name'], [0] * BINS)} for r in roles],
        })
        if s['id'] == 'gut-28051':
            ids = [l['id'] for l in speeches]
            a, b = ids.index('L0106'), ids.index('L0172')
            rodney = [l['id'] for l in speeches if l['role'] == 'RODNEY']
            scene = {'lines': [{'id': l['id'], 'role': l['role'], 'parts': text_of(l)} for l in speeches[a:b + 1]],
                     'rodneyLines': rodney, 'speechIndex': {i: k for k, i in enumerate(ids)}}
            scene['speechIndex'] = {k: scene['speechIndex'][k] for k in [l['id'] for l in scene['lines']]}
            scene['total'] = n
    plays.sort(key=lambda p: p['words'])
    out = 'window.REC = ' + json.dumps({'plays': plays, 'scene': scene}, separators=(',', ':')) + ';\n'
    Path(__file__).with_name('data.js').write_text(out)
    print('plays', len(plays), 'bytes', len(out))


if __name__ == '__main__':
    main(sys.argv[1])
