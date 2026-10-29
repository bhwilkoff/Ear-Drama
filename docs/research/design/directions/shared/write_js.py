import json, os, sys
src, out = sys.argv[1], sys.argv[2]
d = json.load(open(src))
d.pop('sparseCandidates', None)
# A fixture production: D1c's fixture cast (Pat, Sam, Ada), not real people.
d['production'] = {
    'fixture': True, 'play': 'gut-28051', 'director': 'Pat',
    'recorded': ['2026-10-23', '2026-10-29'], 'published': '2026-10-29',
    'cast': [
        {'part': 'URIAH', 'by': 'Pat', 'lines': 97, 'done': 97, 'last': '2026-10-24'},
        {'part': 'RODNEY', 'by': 'Sam', 'lines': 76, 'done': 76, 'last': '2026-10-27'},
        {'part': 'PRUDENCE', 'by': 'Ada', 'lines': 27, 'done': 27, 'last': '2026-10-26'},
        {'part': 'MCKEEN', 'by': 'Sam', 'lines': 44, 'done': 12, 'claimed': '2026-10-25', 'opens': '2026-11-01'},
        {'part': 'FRANKLIN', 'by': None, 'lines': 41, 'done': 0},
        {'part': 'VOICE', 'by': None, 'lines': 7, 'done': 0},
    ],
    'inviteExpires': '2026-11-05',
}
head = ('/* A small sample of https://eardrama.org/data/ (generated ' + d['generatedAt'] +
        '), built by build_sample.py for the D2 prototypes. The production is a fixture (D1c\'s Pat, Sam, Ada). */\n')
open(out, 'w').write(head + 'window.ED = ' + json.dumps(d, ensure_ascii=False, separators=(',', ':')) + ';\n')
print(os.path.getsize(out))
for l in d['play']['lines'][:14]:
    print(l['id'], l['role'], l['parts'][0].get('say', '')[:70])
