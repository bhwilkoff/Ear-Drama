#!/usr/bin/env python3
"""Fit gate and frames for finding a play (B31 W1 + W2; WEB-DESIGN 4.15 item 3, 4.6, 4.10, 6.4r): Record's Plays
(the search field, the facet chips, the ways in, the grid), the facets chosen, Filters, a search by character and by
spoken line, a play's page, and the four states, at 320, 375 and 430 px (each inside an iframe that wide: headless
Chrome will not lay a page out narrower than about 500) and 1440 px, light and dark. Fails on:

  - a page that scrolls sideways, or a problem state where none was asked for;
  - a play's label that drew nothing, or whose text leaves its window;
  - a tile, row or rail window showing a title page or an author's portrait (B31 1.4: only `work`, `production` or
    `book` lead outside the play's own page; read from the index's `picture.kind`);
  - a play twice among the rails (B31 3.1);
  - "quality of mercy" not finding a line in The Merchant of Venice, or "candida" no character;
  - a state frame that does not show its state's words;
  - a search ("quality of mercy", "to be or not to be", "love", a word one play says) that fetches more than about
    2 MB compressed in search files and scripts (each file's gzip size, counted by the server).

The play library is the local build (catalog/out/plays-library, B31 C1/C3: `--library DIR`); every other data path
is proxied to the published projection (`--data URL`, default https://eardrama.org/data/), so the series and the
manifest are the real ones. Headless Chrome runs with --mute-audio and --autoplay-policy=user-gesture-required on
its own port and profile, every URL carries ?mute=1, nothing presses Play, and the browser and server are stopped on
the way out.

    python3 tools/web_fit_plays.py                 # exit 1 on any problem
    python3 tools/web_fit_plays.py --shots DIR     # also write a PNG per frame
    python3 tools/web_fit_plays.py --only record,play

Negative control: in js/api.js playWindowPicture, return artRow(p) for any kind; the author-portrait check fails on
Record and in Search (seen 2026-11-26).
"""
import base64, gzip, http.server, json, os, re, shutil, socketserver, subprocess, sys, tempfile, threading, time, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import web_run  # noqa: E402
from web_fit_label import launch  # noqa: E402

WINDOW_KINDS = ('work', 'production', 'book')

CHECK = r"""(() => {
  const f = document.querySelector('iframe#fit');
  const doc = f ? f.contentDocument : document, win = f ? f.contentWindow : window;
  const bad = [];
  const shown = (n) => { const r = n.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
  doc.querySelectorAll('svg.lb.lb-play').forEach(svg => {
    if (!shown(svg)) return;
    if (!svg.childElementCount) bad.push('an empty play label');
    // Across, the drawn box; up and down, the cap box from the baseline (0.8 em in the display face, 0.73 in the
    // body face), as web_fit_label reads it: the font's ascent above the capitals is not ink.
    svg.querySelectorAll(':scope > text').forEach(t => { const b = t.getBBox();
      const size = parseFloat(t.getAttribute('font-size')), base = parseFloat(t.getAttribute('y'));
      const top = base - size * (t.classList.contains('lb-display') ? 0.8 : 0.73);
      if (b.x < -0.5 || top < -0.5 || b.x + b.width > 100.5 || base > 100.5) bad.push('label text leaves its window: ' + t.textContent); });
  });
  // Every window outside the play's own head: which play it is and whether it shows a picture.
  const wins = [...doc.querySelectorAll('a[href*="play="] .g-window, a[href*="read="] .g-window')].filter(shown)
    .map(w => ({ id: new URLSearchParams(w.closest('a').getAttribute('href').replace(/^[^?]*\?/, '')).get('play') || new URLSearchParams(w.closest('a').getAttribute('href').replace(/^[^?]*\?/, '')).get('read'),
                 img: !!w.querySelector('img') }));
  const rails = [...doc.querySelectorAll('#record-body .shelf .rail')].map(ul => [...ul.querySelectorAll(':scope > li > a:first-of-type')].map(a => new URLSearchParams(a.getAttribute('href').replace(/^[^?]*\?/, '')).get('play') || new URLSearchParams(a.getAttribute('href').replace(/^[^?]*\?/, '')).get('read')));
  if (doc.documentElement.scrollWidth > win.innerWidth) bad.push(`page scrolls sideways: ${doc.documentElement.scrollWidth} > ${win.innerWidth}`);
  const prob = doc.querySelector('.state-problem');
  return JSON.stringify({ bad, wins, rails, problem: prob ? prob.textContent.trim().slice(0, 60) : null, text: doc.body.innerText.slice(0, 20000),
                          labels: doc.querySelectorAll('svg.lb-play').length, dialog: !!doc.querySelector('dialog[open]') });
})()"""

FRAME = """<!doctype html><meta charset="utf-8"><style>html,body{margin:0;background:#888}</style>
<iframe id="fit" src="%s" width="%d" height="%d" style="border:0;display:block"></iframe>"""


def serve(work, library, data, fault):
    """The app from `work`, /data/plays/library/ from `library`, the rest of /data/ from `data` (cached)."""
    cache = {}
    gz = {}

    class H(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *a, **k):
            super().__init__(*a, directory=work, **k)

        def log_message(self, *a):
            pass

        def do_GET(self):
            path = urllib.parse.urlsplit(self.path).path
            if path.startswith('/data/'):
                rel = path[len('/data/'):]
                if fault['on'] and rel.startswith('plays/'):
                    self.send_error(500)
                    return
                if rel.startswith('plays/library/'):
                    fn = os.path.join(library, rel[len('plays/library/'):])
                    if not os.path.isfile(fn):
                        self.send_error(404)
                        return
                    body = open(fn, 'rb').read()
                    if rel.startswith(('plays/library/search/', 'plays/library/scripts/', 'plays/library/characters')):
                        if fn not in gz:
                            gz[fn] = len(gzip.compress(body, 6))
                        fault.setdefault('bytes', []).append(gz[fn])
                else:
                    if rel not in cache:
                        try:
                            cache[rel] = (200, urllib.request.urlopen(data + rel, timeout=30).read())
                        except urllib.error.HTTPError as e:
                            cache[rel] = (e.code, b'')
                        except Exception:
                            cache[rel] = (502, b'')
                    code, body = cache[rel]
                    if code != 200:
                        self.send_error(code)
                        return
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                try:
                    self.wfile.write(body)
                except (BrokenPipeError, ConnectionResetError):
                    pass   # the page moved on before the file arrived
                return
            return super().do_GET()

    class S(socketserver.ThreadingMixIn, http.server.HTTPServer):
        daemon_threads = True
        request_queue_size = 256

    port = 9200 + os.getpid() % 300
    srv = S(('127.0.0.1', port), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, port


def pages(index, rare):
    rows = index['plays']
    by_title = {r['title']: r for r in rows}
    # The play page: the design's first frame play when the library has it, else the first with a form and a picture.
    play = by_title.get('How He Lied to Her Husband') or next((r for r in rows if r.get('form') and r.get('picture')), rows[0])
    bare = next((r for r in rows if not r.get('picture') and not r.get('form')), rows[-1])
    return [
        # name, query, ready regex, expect (regex over the page's text), state
        ('record', '?view=record&mute=1', r'Fewest voices', None, None),
        ('facets', '?view=record&voices=3-4&mute=1', r'Fewest voices', r'Fewest voices\s*\d', None),
        ('filters', '?view=record&voices=3-4&mute=1', r'Fewest voices', r'Show [\d,]+ plays', 'filters'),
        ('search-candida', '?view=record&q=candida&mute=1', r'Characters', r'Characters[\s\S]*Candida', None),
        ('search-mercy', '?view=record&q=quality%20of%20mercy&mute=1', r'Lines[\s\S]*(quality|Quality) of mercy', r'The Merchant of Venice', None),
        ('search-view', '?view=search&q=quality%20of%20mercy&mute=1', r'Lines[\s\S]*(quality|Quality) of mercy', r'Merchant of Venice', None),
        ('search-hamlet', '?view=record&q=to%20be%20or%20not%20to%20be&mute=1', r'Lines|No plays match', None, None),
        ('search-love', '?view=record&q=love&mute=1', r'Lines|No plays match', r'Lines', None),
        ('search-rare', f'?view=record&q={urllib.parse.quote(rare)}&mute=1', r'Lines|No plays match', r'Lines', None),
        ('play', f"?play={urllib.parse.quote(play['id'])}&mute=1", r'Record this', r'Parts', None),
        ('play-bare', f"?play={urllib.parse.quote(bare['id'])}&mute=1", r'Record this', r'Parts', None),
        ('state-empty', '?view=record&voices=2-2&length=91%2B&mute=1', r'Nothing matches|Fewest voices', r'Nothing matches these filters', None),
        ('state-error', '?view=record&mute=1', r'did not load', r'This did not load', 'fault'),
        ('state-offline', '?view=record&mute=1', r'offline', r'You are offline', 'offline'),
    ]


def rare_word(library):
    """A word one play says, from the library's own shards (never pinned): the first such of eight letters or more."""
    for f in sorted(os.listdir(os.path.join(library, 'search', 'said'))):
        for w, deltas in sorted(json.load(open(os.path.join(library, 'search', 'said', f))).items()):
            if len(deltas) == 1 and len(w) >= 8 and w.isalpha() and w.isascii():
                return w
    return 'quality'


BUDGET = 2_100_000   # B31 W2: no search fetches more than about 2 MB compressed (the shards, characters and scripts)


def main():
    shots = sys.argv[sys.argv.index('--shots') + 1] if '--shots' in sys.argv else None
    data = sys.argv[sys.argv.index('--data') + 1] if '--data' in sys.argv else 'https://eardrama.org/data/'
    library = sys.argv[sys.argv.index('--library') + 1] if '--library' in sys.argv else os.path.join(ROOT, 'catalog', 'out', 'plays-library')
    only = set(sys.argv[sys.argv.index('--only') + 1].split(',')) if '--only' in sys.argv else None
    widths = [int(w) for w in sys.argv[sys.argv.index('--widths') + 1].split(',')] if '--widths' in sys.argv else [320, 375, 430, 1440]
    index = json.load(open(os.path.join(library, 'index.json')))
    kinds = {r['id']: (r.get('picture') or {}).get('kind') for r in index['plays']}
    if not index.get('facets'):
        print('FAIL: the library has no facets (built before B31 C3): rebuild it, then run again')
        return 1
    if shots:
        os.makedirs(shots, exist_ok=True)
    work = tempfile.mkdtemp(prefix='fit-plays-')
    for f in os.listdir(ROOT):
        if f not in ('.git', 'build', 'android', 'apple', 'catalog', 'docs', 'worker', 'windows', 'data'):
            os.symlink(os.path.join(ROOT, f), os.path.join(work, f))
    fault = {'on': False}
    srv, port = serve(work, library, data, fault)
    profile = tempfile.mkdtemp(prefix='fit-plays-chrome-')
    proc = None
    problems = 0
    try:
        proc, cdp = launch(profile)
        cdp.call('Page.enable')
        cdp.call('Network.enable')
        for name, q, ready, expect, state in pages(index, rare_word(library)):
            if only and name not in only:
                continue
            for dark in (False, True):
                for w in widths:
                    if state in ('fault', 'offline', 'filters') and w not in (375, 1440):
                        continue
                    h = 1900 if w < 600 else 1200
                    fault['on'] = state == 'fault'
                    url = f'http://127.0.0.1:{port}/{q}'
                    if state == 'offline':
                        # Opened online at Library (the shell kept by the service worker), then the network goes and the
                        # Record tab is pressed: the library's read fails offline.
                        url = f'http://127.0.0.1:{port}/?view=library&mute=1'
                    if w < 600:
                        fn = f'frame-{name}-{w}-{"d" if dark else "l"}.html'
                        open(os.path.join(work, fn), 'w').write(FRAME % (url, w, h))
                        url = f'http://127.0.0.1:{port}/{fn}'
                    cdp.call('Emulation.setDeviceMetricsOverride', {'width': w if w > 600 else 600, 'height': h, 'deviceScaleFactor': 1, 'mobile': False})
                    cdp.call('Emulation.setEmulatedMedia', {'features': [{'name': 'prefers-color-scheme', 'value': 'dark' if dark else 'light'}]})
                    fault['bytes'] = []
                    cdp.call('Page.navigate', {'url': url}, timeout=30)
                    if state == 'offline':
                        time.sleep(5)
                        cdp.call('Network.emulateNetworkConditions', {'offline': True, 'latency': 0, 'downloadThroughput': -1, 'uploadThroughput': -1})
                        cdp.call('Runtime.evaluate', {'expression': "(() => { const f = document.querySelector('iframe#fit'); const d = f ? f.contentDocument : document; const w = f ? f.contentWindow : window; return w.caches.keys().then(ks => Promise.all(ks.filter(k => k.startsWith('ed-data')).map(k => w.caches.delete(k)))).then(() => { [...d.querySelectorAll('a[data-nav=record]')].find(a => a.getBoundingClientRect().width > 0).click(); }); })()", 'awaitPromise': True})
                    t0, rx, ok_ready = time.time(), re.compile(ready, re.I), False
                    get_text = "(() => { const f = document.querySelector('iframe#fit'); const d = f ? f.contentDocument : document; return d && d.body ? d.body.innerText : ''; })()"
                    while time.time() - t0 < 60:
                        v = cdp.call('Runtime.evaluate', {'expression': get_text, 'returnByValue': True})
                        if rx.search(v.get('result', {}).get('value') or ''):
                            ok_ready = True
                            break
                        time.sleep(0.3)
                    time.sleep(2.5)
                    if name.startswith('search'):
                        t1 = time.time()
                        while time.time() - t1 < 60 and cdp.call('Runtime.evaluate', {'expression': "(() => { const f = document.querySelector('iframe#fit'); const d = f ? f.contentDocument : document; return !!d.querySelector('.pl-lines-busy'); })()", 'returnByValue': True})['result'].get('value'):
                            time.sleep(0.3)
                    if state == 'filters':
                        cdp.call('Runtime.evaluate', {'expression': "(() => { const f = document.querySelector('iframe#fit'); const d = f ? f.contentDocument : document; const b = [...d.querySelectorAll('.pl-facet-btn')][0]; if (b) b.click(); })()"})
                        time.sleep(1)
                    cdp.call('Runtime.evaluate', {'expression': "(() => { const f = document.querySelector('iframe#fit'); const d = f ? f.contentDocument : document; return d.fonts.ready.then(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))); })()", 'awaitPromise': True}, timeout=15)
                    r = cdp.call('Runtime.evaluate', {'expression': CHECK, 'returnByValue': True})
                    out = json.loads(r['result']['value'])
                    bad = list(out['bad']) + ([] if ok_ready else ['never ready'])
                    if out['problem'] and state not in ('fault', 'offline'):
                        bad.append('a problem state: ' + out['problem'])
                    if expect and not re.search(expect, out['text']) and not (state == 'filters'):
                        bad.append(f'missing: {expect}')
                    if state == 'filters':
                        dtext = cdp.call('Runtime.evaluate', {'expression': "(() => { const f = document.querySelector('iframe#fit'); const d = f ? f.contentDocument : document; const g = d.querySelector('dialog[open]'); return g ? g.innerText : ''; })()", 'returnByValue': True})['result'].get('value') or ''
                        if not re.search(expect, dtext):
                            bad.append('Filters did not open with Show N plays')
                    for wd in out['wins']:
                        if wd['img'] and kinds.get(wd['id']) not in WINDOW_KINDS:
                            bad.append(f"a {kinds.get(wd['id'])} picture in a window outside the play's page: {wd['id']}")
                    flat = [i for rail in out['rails'] for i in rail]
                    if name == 'record' and len(flat) != len(set(flat)):
                        bad.append('a play twice among the rails')
                    if name.startswith('search'):
                        got = sum(fault.get('bytes') or [])
                        print(f'     {name} {w}: {got / 1e6:.2f} MB compressed in {len(fault.get("bytes") or [])} search files and scripts')
                        if got > BUDGET:
                            bad.append(f'a search fetched {got / 1e6:.2f} MB compressed, over {BUDGET / 1e6:.1f}')
                    if name == 'record' and not out['rails']:
                        bad.append('no rails')
                    if name in ('record', 'facets', 'play') and not out['labels']:
                        bad.append('no play label drawn')
                    problems += len(set(bad))
                    print(('FAIL ' if bad else 'ok   ') + f'{name} {w} {"dark" if dark else "light"} ({out["labels"]} labels) {sorted(set(bad)) or ""}')
                    if shots:
                        params = {'format': 'png'}
                        if w < 600:
                            params['clip'] = {'x': 0, 'y': 0, 'width': w, 'height': h, 'scale': 1}
                        s = cdp.call('Page.captureScreenshot', params, timeout=30)
                        open(os.path.join(shots, f'{name}-{w}-{"dark" if dark else "light"}.png'), 'wb').write(base64.b64decode(s['data']))
                    if state == 'offline':
                        cdp.call('Network.emulateNetworkConditions', {'offline': False, 'latency': 0, 'downloadThroughput': -1, 'uploadThroughput': -1})
                    fault['on'] = False
    finally:
        if proc:
            web_run._kill(proc)
        srv.shutdown()
        srv.server_close()
        shutil.rmtree(profile, ignore_errors=True)
        shutil.rmtree(work, ignore_errors=True)
    print(f'{"FAIL" if problems else "PASS"}: {problems} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
