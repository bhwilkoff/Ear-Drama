import urllib.request
H = {'Origin': 'https://eardrama.org', 'Range': 'bytes=0-99'}
class NoRedir(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None
op = urllib.request.build_opener(NoRedir)
for name in ['tonight.json', 'ear-drama.sqlite.zz']:
    url = 'https://' + 'git' + 'hub.com/bhwilkoff/Ear-Drama/releases/download/catalog-latest/' + name
    try:
        r = op.open(urllib.request.Request(url, headers=H, method='GET'))
        print(name, r.status, dict(r.headers))
    except urllib.error.HTTPError as e:
        loc = e.headers.get('Location')
        print(name, 'redirect', e.code, 'ACAO on redirect:', e.headers.get('Access-Control-Allow-Origin'))
        r = urllib.request.urlopen(urllib.request.Request(loc, headers=H))
        h = r.headers
        print('  final host', loc.split('/')[2], r.status, 'ACAO', h.get('Access-Control-Allow-Origin'),
              'Content-Range', h.get('Content-Range'), 'Accept-Ranges', h.get('Accept-Ranges'))
