import json, os, sys, urllib.request
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'raw')
os.makedirs(OUT, exist_ok=True)
BASE = 'https://eardrama.org/data/'

def get(p):
    f = os.path.join(OUT, p.replace('/', '_'))
    if not os.path.exists(f):
        with urllib.request.urlopen(BASE + p, timeout=60) as r:
            open(f, 'wb').write(r.read())
    return json.load(open(f))

if __name__ == '__main__':
    for p in sys.argv[1:]:
        d = get(p)
        print(p, os.path.getsize(os.path.join(OUT, p.replace('/', '_'))))
