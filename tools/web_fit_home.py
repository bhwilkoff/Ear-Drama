#!/usr/bin/env python3
"""Fit gate and frames for Home and Record (WEB-DESIGN 4.2, 4.15; Decision 075), light and dark, at 320,
375, 390, 430 and 1440 px: Home with no history and with history (Continue leads under On the air),
during tonight's evening and in the day (a genre station leads), and Record. Fails on a door row or
button row that wraps apart, a word broken inside itself, a sideways scroll, an overflowing tile name,
an opening line that runs out sideways, a Home that drew no On the air block, no doors, or no rows, a
Record with no play tiles, or either page without Today's scene and its opening (2026-11-15 review).

Reads the live catalog (network) in headless Chrome, muted; never presses Play.

    python3 tools/web_fit_home.py              # exit 1 on any problem
    python3 tools/web_fit_home.py --shots DIR  # also write a PNG per frame
    python3 tools/web_fit_home.py --data URL   # read another projection (default https://eardrama.org/data/)

V5 (WEB-DESIGN 4.2r, Decision 081) adds: the doors are two; nothing on the first screen is as large as
the hero's window; no rail opens on a show the row above shows; no show twice on Home (Continue is
personal and outside the rule); at 1024 px and wider Today's scene's board is at most 60% of the
column; and On the air never shows an upload's `#NNN` tag, against fx.html, which reads the same data
through /fx/ with every slot's episode given a raw upload title (frames home-raw-*, 375 px).
`--only PREFIX` runs only the frames whose name starts with PREFIX.

Negative controls (V5, each seen to fail 2026-11-19): add the Listen door back in homeDoors (js/app.js)
-> "the doors are 3"; set `.home-live-win > .g-window` to `width: 96px` -> "as large as the hero";
call `sceneCard(scene)` on Home without `{ wide: true }` -> "a full-width slab"; drop `seen.has(k)` in
API.homeShows -> "opens on a show the row above shows" and "appears twice"; draw `epTitle(ep)` in
On the air without `API.uploadTagged` -> "raw upload title in On the air" (home-raw-*).
The doors-wrap check stays; its first control (deleting the doors' `grid-auto-flow: column`) named a
grid the two quiet doors no longer use.
Second (2026-11-15): delete `flex-wrap: nowrap;` from `.pl-scene-actions`; at 320 px Try a line, Hear
it and Read wrap and "a button row wrap apart" fails (it did, before that rule).
"""
import datetime, json, os, subprocess, sys, tempfile, time, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import web_run  # noqa: E402

SERIES = [('dragnet', 'Dragnet', '1949'), ('gunsmoke', 'Gunsmoke', '1952'), ('suspense', 'Suspense', '1942')]
EPS = [{'id': f'{k}|{y}-0{i + 1}-0{i + 1}', 'title': None, 'series': k, 'seriesName': n, 'date': f'{y}-0{i + 1}-0{i + 1}',
        'url': f'https://archive.org/download/{k}/{y}.mp3', 'length': 1800} for i, (k, n, y) in enumerate(SERIES)]
HISTORY = {'ed.history': [dict(e, at=10**12 - i) for i, e in enumerate(EPS)],
           'ed.positions': {e['id']: {'t': 600, 'd': 1800, 'at': 10**12 - i} for i, e in enumerate(EPS)}}
WIDTHS = (320, 375, 390, 430, 1440)

JS = r"""(() => {
  const bad = [];
  const view = %s;
  const root = document.getElementById(view === 'record' ? 'view-record' : 'view-listen');
  root.querySelectorAll('.btn').forEach(b => { const r = b.getBoundingClientRect(); if (r.width && r.height > 64) bad.push('button wraps: ' + b.textContent.trim().slice(0, 24)); });
  const rowsApart = (sel, name) => root.querySelectorAll(sel).forEach(row => {
    const kids = [...row.children].filter(k => k.getBoundingClientRect().width > 0);
    const tops = new Set(kids.map(k => Math.round(k.getBoundingClientRect().top)));
    if (tops.size > 1) bad.push(name + ' wrap apart');
  });
  rowsApart('.home-doors', 'the doors');
  rowsApart('.home-live-actions', 'On the air’s buttons');
  rowsApart('.actions-one', 'a button row');
  root.querySelectorAll('.pl-scene-said, .pl-open-sp').forEach(n => { if (n.scrollWidth > n.clientWidth + 1) bad.push('an opening line runs out sideways'); });
  const de = document.documentElement;
  if (de.scrollWidth > innerWidth) bad.push(`page scrolls sideways: ${de.scrollWidth} > ${innerWidth}`);
  root.querySelectorAll('.g-name').forEach(n => { if (n.scrollWidth > n.clientWidth + 1) bad.push('tile name overflows: ' + n.textContent.slice(0, 30)); });
  // A word broken inside itself: one word's glyphs on two lines.
  const sel = '.pl-open-said, .pl-scene-said, .pl-scene-who, .home-door-lab, .btn, .g-name, .ep-title, .section-header, .g-kicker, .segmented button, .tab span, .g-facts span, .g-head-name';
  document.querySelectorAll(sel).forEach(n => {
    if (!n.getBoundingClientRect().width) return;
    const walk = document.createTreeWalker(n, NodeFilter.SHOW_TEXT);
    for (let t = walk.nextNode(); t; t = walk.nextNode()) {
      const re = /[^\s\-\u2010-\u2014\/]+/g; let m;   // a break at a hyphen, dash or slash is between words
      while ((m = re.exec(t.data))) {
        const rg = document.createRange(); rg.setStart(t, m.index); rg.setEnd(t, m.index + m[0].length);
        const tops = new Set([...rg.getClientRects()].filter(r => r.width > 0.5).map(r => Math.round(r.top)));
        if (tops.size > 1) bad.push('a word breaks inside itself: ' + m[0]);
      }
    }
  });
  if (view === 'home') {
    if (!root.querySelector('.home-doors')) bad.push('no doors');
    // §4.2r (Decision 081): the composition rules.
    const shown = (n) => n.getBoundingClientRect().width > 0;
    const doors = [...root.querySelectorAll('.home-doors > a')].filter(shown);
    if (doors.length !== 2) bad.push(`the doors are ${doors.length}, not two`);
    const screen = Math.min(innerHeight, innerWidth < 600 ? 812 : 900);
    const hero = root.querySelector('.home-live .g-window');
    if (hero) {
      const hw = hero.getBoundingClientRect().width;
      for (const w of root.querySelectorAll('.g-window')) {
        if (w === hero || !shown(w) || w.getBoundingClientRect().top >= screen) continue;
        if (w.getBoundingClientRect().width >= hw) { bad.push(`a window on the first screen is as large as the hero (${Math.round(w.getBoundingClientRect().width)} >= ${Math.round(hw)})`); break; }
      }
      if (hero.getBoundingClientRect().top >= screen) bad.push('the hero is not on the first screen');
    }
    const keyOf = (a) => { const m = /[?&](?:item|series)=([^&|%%]+)/.exec(a.getAttribute('href') || ''); return m ? decodeURIComponent(m[1]) : null; };
    const heroLink = root.querySelector('.home-live a[href*="item="]');
    const rows = [];
    if (heroLink) rows.push([keyOf(heroLink)]);
    root.querySelectorAll('.g-rail, .g-night .g-grid').forEach(r => {
      if (r.closest('.ear-drama-only [data-lead], #cont-h')) return;
      const keys = [...r.querySelectorAll('.g-tile')].map(keyOf).filter(Boolean);
      if (keys.length) rows.push(keys);
    });
    for (let i = 1; i < rows.length; i++) {
      if (rows[i - 1].includes(rows[i][0])) bad.push(`a rail opens on a show the row above shows: ${rows[i][0]}`);
    }
    const seen = new Set();
    rows.flat().forEach(k => { if (seen.has(k)) bad.push(`a show appears twice on Home: ${k}`); seen.add(k); });
    const scene = root.querySelector('.pl-scene');
    if (scene && innerWidth >= 1024) {
      const board = [scene, ...scene.querySelectorAll('*')].filter(n => n.dataset && n.dataset.genre !== undefined && shown(n))
        .map(n => n.getBoundingClientRect().width).reduce((a, b) => Math.max(a, b), 0);
      const col = root.getBoundingClientRect().width;
      if (board > col * 0.6) bad.push(`Today's scene is a full-width slab: its board is ${Math.round(board)} of ${Math.round(col)} px`);
    }
    const live = root.querySelector('.home-live');
    if (live && /(^|\s)#\s?\d+\b/.test(live.textContent)) bad.push('raw upload title in On the air: ' + live.textContent.match(/\S*\s?#\s?\d+[^·]*/)[0].slice(0, 40));
    if (%s && !root.querySelector('.home-live')) bad.push('no On the air block');
    if (!root.querySelector('.g-tile')) bad.push('Home drew no tiles');
    if (%s && !root.querySelector('#cont-h')) bad.push('history but no Continue');
  } else if (!root.querySelector('.pl-cast, .pl-open')) bad.push('Record drew no play tiles');
  if (!root.querySelector('.pl-scene .pl-scene-sp')) bad.push('no scene card with its opening');
  if (document.querySelector('.state-problem')) bad.push('a problem state is on screen: ' + document.querySelector('.state-problem').textContent.trim().slice(0, 40));
  return JSON.stringify([...new Set(bad)]);
})()"""


def main():
    shots = sys.argv[sys.argv.index('--shots') + 1] if '--shots' in sys.argv else None
    data = sys.argv[sys.argv.index('--data') + 1] if '--data' in sys.argv else 'https://eardrama.org/data/'
    if shots:
        os.makedirs(shots, exist_ok=True)
    work = tempfile.mkdtemp(prefix='fit-home-')
    for f in os.listdir(ROOT):
        if f not in ('index.html', '.git', 'build', 'android', 'apple', 'catalog', 'docs', 'worker', 'windows'):
            os.symlink(os.path.join(ROOT, f), os.path.join(work, f))
    html = open(os.path.join(ROOT, 'index.html')).read().replace(
        '<meta name="ed-data" content="data/">', f'<meta name="ed-data" content="{data}">', 1)
    open(os.path.join(work, 'index.html'), 'w').write(html)
    open(os.path.join(work, 'fx.html'), 'w').write(html.replace(f'content="{data}"', 'content="fx/"', 1))
    # fx.html reads the same data through /fx/, where every slot's episode in tonight.json and
    # stations.json carries a raw upload title: On the air must never show it (AGENTS.md).
    srv_code = ("import sys,json,http.server,functools,urllib.request\n"
                "RAW='AbyM #026 The Girl on Shipwreck Island Pt 03 More About Gracie Than Meets the Eye'\n"
                "def raw(o):\n"
                " if isinstance(o,dict):\n"
                "  e=o.get('episode')\n"
                "  if isinstance(e,dict) and 'title' in e: e['title']=RAW\n"
                "  [raw(v) for v in o.values()]\n"
                " elif isinstance(o,list): [raw(v) for v in o]\n"
                "class S(http.server.ThreadingHTTPServer):\n request_queue_size=256\n daemon_threads=True\n"
                "class H(http.server.SimpleHTTPRequestHandler):\n def log_message(self,*a): pass\n"
                " def do_GET(self):\n"
                "  if not self.path.startswith('/fx/'): return super().do_GET()\n"
                "  try: body=urllib.request.urlopen(sys.argv[3]+self.path[4:],timeout=30).read()\n"
                "  except Exception as e:\n"
                "   self.send_response(getattr(e,'code',502)); self.end_headers(); return\n"
                "  if self.path.split('?')[0].endswith(('/stations.json','/tonight.json')):\n"
                "   d=json.loads(body); raw(d); body=json.dumps(d).encode()\n"
                "  self.send_response(200); self.send_header('content-type','application/json')\n"
                "  self.send_header('content-length',str(len(body))); self.end_headers(); self.wfile.write(body)\n"
                "S(('127.0.0.1',int(sys.argv[1])),functools.partial(H,directory=sys.argv[2])).serve_forever()\n")
    port = 8300 + os.getpid() % 500
    srv = subprocess.Popen([sys.executable, '-c', srv_code, str(port), work, data],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)
    state = {'dark': False, 'hist': False, 'view': 'home', 'live': True, 'out': []}
    orig = web_run.CDP.call

    def call(self, method, params=None, timeout=20):
        if method == 'Page.navigate':
            orig(self, 'Emulation.setTimezoneOverride', {'timezoneId': state['zone']})
            orig(self, 'Emulation.setEmulatedMedia', {'features': [
                {'name': 'prefers-color-scheme', 'value': 'dark' if state['dark'] else 'light'}]})
            seed = ''.join(f"localStorage.setItem({k!r},{json.dumps(json.dumps(v))});"
                           for k, v in HISTORY.items()) if state['hist'] else ''
            orig(self, 'Page.addScriptToEvaluateOnNewDocument', {'source': seed})
        if method == 'Page.captureScreenshot':
            # The rows load one by one: wait (up to 20 s) for the first tile, then let the rest land. A
            # fixed wait alone failed the fixture frames, whose data comes through the /fx/ proxy.
            if state['view'] == 'home':
                t0 = time.time()
                while time.time() - t0 < 20 and not orig(self, 'Runtime.evaluate', {
                        'expression': "!!document.querySelector('#view-listen .g-tile')", 'returnByValue': True})['result'].get('value'):
                    time.sleep(0.25)
            time.sleep(2.5)
            js = lambda b: 'true' if b else 'false'
            r = orig(self, 'Runtime.evaluate', {'expression': JS % (
                json.dumps(state['view']), js(state['live']), js(state['hist'])), 'returnByValue': True})
            state['out'] = json.loads(r['result']['value'])
        return orig(self, method, params, timeout)
    web_run.CDP.call = call
    # The clock is read from the published data, never from the wall clock (2026-11-25: "no On the air
    # block" failed after local midnight and ten day-history frames failed when the file's window and
    # the machine's date disagreed). The evening case is 2 minutes into the first published slot that is
    # not a gap; the day case is the first hour from a station's first slot on that no evening covers.
    # Chrome's zone is pinned to the file's zone so the date the client reads is the file's own date.
    def published(name):
        return json.loads(urllib.request.urlopen(data.rstrip('/') + '/' + name, timeout=30).read())
    tonight, stations = published('tonight.json'), published('stations.json')
    state['zone'] = tonight.get('zone', 'America/New_York')
    parse = lambda t: datetime.datetime.strptime(t, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=datetime.timezone.utc)
    evenings = [(parse(sl['utc_start']), parse(sl['utc_end'])) for d in tonight['days'].values() for sl in d['slots']]
    first = next(parse(sl['utc_start']) for k in sorted(tonight['days']) for sl in tonight['days'][k]['slots'] if not sl.get('gap'))
    evening_at = first + datetime.timedelta(minutes=2)
    day_at = parse(stations['stations'][0]['slots'][0]['utc_start']) + datetime.timedelta(hours=1)
    for _ in range(48):
        if not any(a <= day_at < b for a, b in evenings):
            break
        day_at += datetime.timedelta(hours=1)
    iso = lambda t: t.strftime('%Y-%m-%dT%H:%M:%SZ')
    print(f'clock: evening {iso(evening_at)}, day {iso(day_at)}, zone {state["zone"]}', flush=True)
    cases = [('home-evening', 'home', f'?view=home&mute=1&now={iso(evening_at)}', False, True),
             ('home-day-history', 'home', f'?view=home&mute=1&now={iso(day_at)}', True, True),
             ('record', 'record', '?view=record&mute=1', False, False)]
    # The raw-title fixture (V5): tonight leading and a station leading, at 375 px.
    raw_cases = [('home-raw-evening', 'home', f'fx.html?view=home&mute=1&now={iso(evening_at)}', False, True),
                 ('home-raw-day', 'home', f'fx.html?view=home&mute=1&now={iso(day_at)}', False, True)]
    runs = [(c, d, w) for c in cases for d in (False, True) for w in WIDTHS] + [(c, False, 375) for c in raw_cases]
    if '--only' in sys.argv:   # a prefix of the frame names, for a negative control
        runs = [r for r in runs if r[0][0].startswith(sys.argv[sys.argv.index('--only') + 1])]
    problems = 0
    try:
        for (name, view, q, hist, live), dark, w in runs:
            state.update(dark=dark, hist=hist, view=view, live=live, out=['never measured'])
            fn = f'{name}-{"dark" if dark else "light"}-{w}.png'
            out = os.path.join(shots, fn) if shots else os.path.join(work, 'fit.png')
            rec = web_run.shoot(f'http://127.0.0.1:{port}/{q}', w, 2400 if w < 600 else 1600, out,
                                r'Plays' if view == 'record' else r'Find a show')
            if rec.get('timed_out'):
                state['out'].append('timed out waiting')
            problems += len(state['out'])
            print(('FAIL ' if state['out'] else 'ok   ') + f"{name} {w} {'dark' if dark else 'light'} {state['out'] or ''}", flush=True)
    finally:
        srv.terminate()
    print(f'{"FAIL" if problems else "PASS"}: {problems} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
