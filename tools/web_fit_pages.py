#!/usr/bin/env python3
"""Fit gate and frames for Stations, Surprise, Search and a person's page (WEB-DESIGN 4.6, 4.9, 4.13, 4.14; D3-8): light and
dark, at 320, 375, 390 and 430 px. Rows are 64 px with a 48 px window, button rows stay on one line, the page never
scrolls sideways, and no tile or head name overflows.
Reads the live catalog (network) in headless Chrome, muted; never presses Play.

    python3 tools/web_fit_pages.py              # exit 1 on any problem
    python3 tools/web_fit_pages.py --shots DIR  # also write a PNG per frame

Negative control: delete the `.g-round` rule from css/styles.css; a person's window stops being round and the check fails.

V7 (WEB-DESIGN 6.4g, item pages wear Home's hero) adds item routes chosen from the data (the most downloaded
series with a picture and the most downloaded dated one without, that one's first dated episode, the voice
with the most episodes and a portrait and the one without, a play) at 375 and 1440 px, plus fixtures
injected over the live data: a series whose `gallery` holds two pictures (the row must draw) and one whose
holds one (it must not), an episode whose title carries an upload's `#NNN` tag, and a finished ear drama.
It fails on: an item page's head art that is a blank box (no loaded picture, no drawn label); an upload's
catalog number or identifier in an item page's h1; a recordings disclosure open on load, or copies outside
it; a pictures row with fewer than two pictures, or none where two were given. `--only PREFIX` runs only
the routes whose name starts with PREFIX.
Negative controls (each seen to fail 2026-11-19): in js/app.js heroArt return `{ node: el('span'), shape:
'label' }` for the label -> "the head art is a blank box"; drop the `API.uploadTagged` branch of the episode
title -> "raw upload title in the head" (episode-raw); give the recordings `details` `open: true` -> "the
recordings disclosure is open on load"; change `>= 2` to `>= 1` in API.galleryOf -> "a pictures row with
fewer than 2" (series-gallery1).
"""
import json, os, re, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import web_run  # noqa: E402

def after_the_evening():
    """An instant (ISO, UTC) one hour after today's published evening ends, for the harness's ?now= door."""
    import datetime, urllib.request
    day = json.load(urllib.request.urlopen('https://eardrama.org/data/tonight.json', timeout=30))['days'][time.strftime('%Y-%m-%d')]
    last = max(datetime.datetime.fromisoformat(s['utc_end'].replace('Z', '+00:00')) for s in day['slots'])
    return (last + datetime.timedelta(hours=1)).strftime('%Y-%m-%dT%H:%M:%SZ')


def item_routes():
    """V7's item pages, chosen from the live data (never pinned), and the fixtures each needs: (name, query,
    ready, selector, widths, stub)."""
    import urllib.parse, urllib.request
    data = 'https://eardrama.org/data/'
    get = lambda u: json.load(urllib.request.urlopen(data + u, timeout=30))
    idx = get('index/series.json')
    F = {k: i for i, k in enumerate(idx['fields'])}
    rows = sorted(idx['rows'], key=lambda r: (-(r[F['downloads']] or 0), r[F['key']]))
    pic = next(r for r in rows if r[F['picture']] and r[F['picture']][1] and r[F['picture']][2])
    nopic = next(r for r in rows if not r[F['picture']] and r[F['first']])
    ser = get(f"series/{urllib.parse.quote(nopic[F['key']])}.json")
    EF = {k: i for i, k in enumerate(ser['fields'])}
    ep = next(e for e in ser['episodes'] if e[EF['date']] and len(e[EF['date']]) == 10)
    voices = get('index/voices.json')
    VF = {k: i for i, k in enumerate(voices['fields'])}
    vs = sorted(voices['rows'], key=lambda v: -(v[VF['episodes']] or 0))
    face = next(v for v in vs if v[VF['art']])
    bare = next(v for v in vs if not v[VF['art']])
    plays = get('plays/library/index.json')['plays']
    play = sorted(plays, key=lambda p: (p['voices'], p['id']))[len(plays) // 2]
    title_at = get('manifest.json')['fields']['detail'].index('title')
    q, k = urllib.parse.quote, pic[F['key']]
    others = [r[F['picture']] for r in rows if r[F['picture']] and r[F['picture']][1] and r[F['key']] != k][:2]
    gal = lambda n: {'series': {k: {'gallery': others[:n]}}}
    raw = {'episode': {'id': ep[EF['id']], 'at': title_at, 'title': 'AbyM #026 ' + (ep[EF['title']] or '')}}
    drama = {'drama': {'id': 'd0', 'script_id': play['id'], 'title': play['title'], 'source': None,
                       'credits': [{'part': 'role:' + r, 'name': n} for r, n in zip(['A', 'B'], ['Pat', 'Sam'])],
                       'archive_url': 'https://archive.org/details/eardrama-d0', 'published_at': 1763500000000}}
    W = (375, 1440)
    last = lambda name: re.escape(name.split()[-1])
    return [('series-picture', f'?series={q(k)}&mute=1', last(pic[F['name']]), '.g-head-hero', W, {}),
            ('series-label', f"?series={q(nopic[F['key']])}&mute=1", last(nopic[F['name']]), '.g-head-hero svg.lb', W, {}),
            ('series-gallery2', f'?series={q(k)}&mute=1', last(pic[F['name']]), '.g-gallery', W, gal(2)),
            ('series-gallery1', f'?series={q(k)}&mute=1', last(pic[F['name']]), '.g-head-hero', (375,), gal(1)),
            ('episode-label', f"?item={q(ep[EF['id']])}&mute=1", r'Recording', '.g-head-hero svg.lb', W, {}),
            ('episode-raw', f"?item={q(ep[EF['id']])}&mute=1", r'Recording', '.g-head-hero', (375,), raw),
            ('person-face', f"?person={q(face[VF['id']])}&mute=1", last(face[VF['name']]), '.g-head-hero .g-shaped img, .g-head-hero svg.lb', W, {}),
            ('person-label', f"?person={q(bare[VF['id']])}&mute=1", last(bare[VF['name']]), '.g-head-hero svg.lb', W, {}),
            ('play', f"?play={q(play['id'])}&mute=1", r'Parts', '.g-head-hero', W, {}),
            ('drama', '?drama=d0&mute=1', r'Cast', '.g-head-hero svg.lb', W, drama)]


STUB = r"""(() => {
  const F = %s;
  const orig = window.fetch.bind(window);
  const json = (o, status = 200) => Promise.resolve(new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } }));
  window.fetch = async (input, init) => {
    const u = String(input && input.url ? input.url : input);
    for (const [k, extra] of Object.entries(F.series || {})) if (u.endsWith(`/series/${k}.json`)) { const d = await (await orig(input, init)).json(); return json({ ...d, ...extra }); }
    if (F.episode && /\/episodes\/[^/]+\.json$/.test(u)) { const d = await (await orig(input, init)).json(); if (d[F.episode.id]) d[F.episode.id][F.episode.at] = F.episode.title; return json(d); }
    if (F.drama && u.includes('archive.org/metadata/')) return json({ files: [{ name: 'a.mp3', format: 'VBR MP3' }] });
    if (F.drama && u.includes('/v1/plays/finished/')) return json(F.drama);
    return orig(input, init);
  };
})()"""

ROUTES = [('stations', '?view=radio&mute=1', r'Stations', '.station.g-row', 1),
          ('stations-ended', '?view=radio&mute=1&now=' + after_the_evening(), r'Stations',
           '.station.g-row .station-go[aria-label^="Replay"]', 1),
          ('surprise', '?view=surprise&mute=1', r'Surprise', '.pick .g-head', 2),
          ('search', '?view=search&q=welles&mute=1', r'People', '#search-body .g-row .g-window', 2),
          ('episode-air', '?item=xminusone%7C1956-04-24&mute=1', r'On the air', '.g-face .g-window[data-fill="block"]', 1),
          ('person-portrait', '?person=otrr:6237&mute=1', r'Webb', '.g-head .g-window img', 1),
          ('person-monogram', '?person=otrr:6267&mute=1', r'Welles', '.g-head .g-window[data-fill="block"]', 1)]
JS = r"""(async () => {
  const bad = [];
  await new Promise(r => setTimeout(r, 2500));
  const de = document.documentElement;
  if (de.scrollWidth > innerWidth) bad.push(`page scrolls sideways: ${de.scrollWidth} > ${innerWidth}`);
  document.querySelectorAll('.btn').forEach(b => { const r = b.getBoundingClientRect(); if (r.width && r.height > 64) bad.push('button wraps: ' + b.textContent.slice(0, 20)); });
  document.querySelectorAll('.g-name, .g-head-name').forEach(n => { if (n.scrollWidth > n.clientWidth + 1) bad.push('name overflows: ' + n.textContent.slice(0, 30)); });
  const view = document.querySelector('.view:not([hidden])');
  view.querySelectorAll('.g-row').forEach(r => {
    const h = r.getBoundingClientRect().height, w = r.querySelector('.g-window, .g-date');
    if (h < 63.5) bad.push('row under 64 px: ' + r.textContent.slice(0, 30));
    if (!w) bad.push('row without its visual: ' + r.textContent.slice(0, 30));
    else if (Math.abs(w.getBoundingClientRect().width - 48) > 1) bad.push('visual is not 48 px: ' + r.textContent.slice(0, 30));
  });
  view.querySelectorAll('a[href*="person="] > .g-window').forEach(w => { if (getComputedStyle(w).borderRadius !== '50%%') bad.push('a person window is not round'); });
  // A monogram in a round window is centered on its ink (cap height), not the line box: the glyphs' own box
  // is within 2 %% of the circle's center, both ways.
  await document.fonts.load('700 100px "Big Shoulders"');
  const cx = document.createElement('canvas').getContext('2d');
  view.querySelectorAll('.g-face > .g-window[data-fill="block"], .g-round[data-fill="block"]').forEach(w => {
    const t = w.querySelector('svg.lb text.lb-display'), box = w.getBoundingClientRect();
    if (!t || !box.width) return;
    const u = box.width / 100, size = parseFloat(t.getAttribute('font-size'));
    cx.font = `700 ${size * u}px "Big Shoulders"`;
    const m = cx.measureText(t.textContent);
    const top = parseFloat(t.getAttribute('y')) * u - m.actualBoundingBoxAscent, bot = parseFloat(t.getAttribute('y')) * u + m.actualBoundingBoxDescent;
    const left = parseFloat(t.getAttribute('x')) * u - m.width / 2 - m.actualBoundingBoxLeft + 0, right = parseFloat(t.getAttribute('x')) * u - m.width / 2 + m.actualBoundingBoxRight;
    const dy = Math.abs((top + bot) / 2 - box.height / 2) / box.height, dx = Math.abs((left + right) / 2 - box.width / 2) / box.width;
    if (dy > 0.02 || dx > 0.02) bad.push(`monogram off center in ${t.textContent}: dy ${(dy * 100).toFixed(1)} %% dx ${(dx * 100).toFixed(1)} %%`);
    if (t.getAttribute('text-anchor') !== 'middle') bad.push('round monogram is not anchored in the middle: ' + t.textContent);
  });
  if (!view.querySelector(%r)) bad.push('nothing drew for %s');
  // V7 (WEB-DESIGN 6.4g): an item page's head art is never a blank box, and its h1 never raw upload text.
  const hero = view.querySelector('.g-head-hero');
  if (hero) {
    const art = hero.querySelector('.g-head-art'), img = art && art.querySelector('.g-shaped img');
    if (img && !img.complete) await Promise.race([img.decode().catch(() => {}), new Promise(r => setTimeout(r, 8000))]);
    const now = art && art.querySelector('.g-shaped img'), lb = art && art.querySelector('svg.lb'), box = art && art.getBoundingClientRect();
    const drew = (now && now.complete && now.naturalWidth > 0) || (lb && lb.childElementCount > 0) || (art && art.querySelector('.pl-open .pl-open-sp'));
    if (!box || box.width < 40 || box.height < 40 || !drew) bad.push('the head art is a blank box');
    const h1 = hero.querySelector('h1');
    if (h1 && API.uploadTagged(h1.textContent)) bad.push('raw upload title in the head: ' + h1.textContent.slice(0, 40));
  }
  view.querySelectorAll('details.recordings').forEach(d => { if (d.open) bad.push('the recordings disclosure is open on load'); });
  if (view.querySelector('.versions') && !view.querySelector('details.recordings .versions')) bad.push('recordings outside their disclosure');
  const gal = view.querySelector('.g-gallery');
  if (gal && gal.querySelectorAll('figure').length < 2) bad.push('a pictures row with fewer than 2');
  const shown = document.body.innerText + ' ' + [...document.querySelectorAll('[aria-label]')].map(n => n.getAttribute('aria-label')).join(' ');
  const iso = shown.match(/\d{4}[-‑](0[1-9]|1[0-2])([-‑](0[1-9]|[12]\d|3[01]))?(?!\d)/);
  if (iso) bad.push('an ISO date is on screen: ' + iso[0]);
  document.querySelectorAll('.versions .version').forEach(v => {
    const id = v.querySelector('label').textContent.match(/\w*_\w*|[A-Za-z]{4,}\d{3,}|\d{3,}[A-Za-z]{4,}/);
    if (id) bad.push('an archive.org identifier is in the Recordings list: ' + id[0]);
  });
  return JSON.stringify(bad);
})()"""


def main():
    shots = sys.argv[sys.argv.index('--shots') + 1] if '--shots' in sys.argv else None
    if shots:
        os.makedirs(shots, exist_ok=True)
    work = tempfile.mkdtemp(prefix='fit-pages-')
    for f in os.listdir(ROOT):
        if f not in ('index.html', '.git', 'build', 'android', 'apple', 'catalog', 'docs', 'worker', 'windows'):
            os.symlink(os.path.join(ROOT, f), os.path.join(work, f))
    html = open(os.path.join(ROOT, 'index.html')).read().replace(
        '<head>', '<head><meta name="ed-data" content="https://eardrama.org/data/">', 1)
    open(os.path.join(work, 'index.html'), 'w').write(html)
    srv_code = ("import sys,http.server,functools\n"
                "class S(http.server.ThreadingHTTPServer):\n request_queue_size=256\n daemon_threads=True\n"
                "class H(http.server.SimpleHTTPRequestHandler):\n def log_message(self,*a): pass\n"
                "S(('127.0.0.1',int(sys.argv[1])),functools.partial(H,directory=sys.argv[2])).serve_forever()\n")
    port = 8300 + os.getpid() % 500
    srv = subprocess.Popen([sys.executable, '-c', srv_code, str(port), work],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)
    state = {'dark': False, 'js': '', 'out': [], 'stub': None}
    orig = web_run.CDP.call

    def call(self, method, params=None, timeout=20):
        if method == 'Page.navigate':
            orig(self, 'Emulation.setEmulatedMedia', {'features': [
                {'name': 'prefers-color-scheme', 'value': 'dark' if state['dark'] else 'light'}]})
            if state['stub']:
                orig(self, 'Page.addScriptToEvaluateOnNewDocument', {'source': STUB % json.dumps(state['stub'])})
        if method == 'Page.captureScreenshot':
            r = orig(self, 'Runtime.evaluate', {'expression': state['js'], 'returnByValue': True,
                                                'awaitPromise': True}, 30)
            state['out'] = json.loads(r['result']['value'])
        return orig(self, method, params, timeout)
    web_run.CDP.call = call
    problems = 0
    try:
        only = sys.argv[sys.argv.index('--only') + 1] if '--only' in sys.argv else None
        routes = [(n, q, r, s, (320, 375, 390, 430), {}) for n, q, r, s, _ in ROUTES] + item_routes()
        for name, query, ready, sel, widths, stub in routes:
            if only and not name.startswith(only):
                continue
            for dark in (False, True):
                for w in widths:
                    state.update(dark=dark, js=JS % (sel, name), out=['never measured'], stub=stub or None)
                    png = f'{name}-{"dark" if dark else "light"}-{w}.png'
                    out = os.path.join(shots, png) if shots else os.path.join(work, 'fit.png')
                    web_run.shoot(f'http://127.0.0.1:{port}/{query}', w, 900, out, ready)
                    problems += len(state['out'])
                    print(('FAIL ' if state['out'] else 'ok   ') + f"{name} {w} {'dark' if dark else 'light'} {state['out'] or ''}")
    finally:
        srv.terminate()
    print(f'{"FAIL" if problems else "PASS"}: {problems} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
