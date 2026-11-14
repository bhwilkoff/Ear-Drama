#!/usr/bin/env python3
"""Fit gate and frames for the script reader (WEB-DESIGN 4.16, Decision 076), light and dark, at 320, 375,
430 and 1440 px, in headless Chrome over the DevTools protocol (tools/web_run.py's launcher). For each
width and theme it opens a real script in Pages (the default), then Contents, Search, "I'm playing" with
Hide my lines and a peek, the text three steps larger, and Scroll. Fails on a sideways scroll, a bar that
wraps, one page per screen at 1440 px or two below 900 px, a reading position lost when the text size
changes, a hidden line whose words still show, empty Contents or Search for a script that has them, or a
page turn that does not move the page.

    python3 tools/web_fit_reader.py              # exit 1 on any problem
    python3 tools/web_fit_reader.py --shots DIR  # also write a PNG per frame
    python3 tools/web_fit_reader.py --data URL   # another data plane (default: the local data/ link)
    python3 tools/web_fit_reader.py --widths 375,1440

The script is picked from the data, never named: the first play in the built library (else the bundle)
with at least four contents entries and a part of twenty lines or more.

Negative control: make ReaderCore.lineAtPage return the LAST line starting on the page; "the reading
position moved when the text grew" fails.
"""
import base64, json, os, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import web_run  # noqa: E402

WIDTHS = (320, 375, 430, 1440)
LIB = os.path.join(ROOT, 'catalog', 'out', 'plays-library')
BUNDLE = os.path.join(ROOT, 'catalog', 'plays', 'castable-scripts.json')


def pick_script():
    """A script with contents and a real part, from the data (never a pinned title)."""
    sys.path.insert(0, os.path.join(ROOT, 'catalog', 'tools'))
    import script_parse as P
    def ok(s):
        heads = len(s.get('sections', [])) + sum(1 for l in s['lines'] if l['kind'] != 'speech' and P.section_level(l.get('source')))
        return heads >= 4 and max((r['lines'] for r in s['roles']), default=0) >= 20
    if os.path.exists(os.path.join(LIB, 'index.json')):
        for row in json.load(open(os.path.join(LIB, 'index.json')))['plays']:
            s = json.load(open(os.path.join(LIB, row['path'])))['scripts'][0]
            if ok(s):
                return s
    for s in json.load(open(BUNDLE))['scripts']:
        if ok(s):
            return s
    raise SystemExit('no script with contents in the data')


STATE = r"""(() => {
  const q = (s) => document.querySelector(s);
  const clip = q('.rd-clip'), flow = q('.rd-flow');
  if (!clip) return JSON.stringify({ missing: true });
  const cr = clip.getBoundingClientRect();
  const lines = [...document.querySelectorAll('.rd-line')];
  const visible = (n) => [...n.getClientRects()].some(r => r.right > cr.left + 2 && r.left < cr.right - 2 && r.bottom > cr.top && r.top < cr.bottom);
  const firstVisible = lines.find(visible);
  const de = document.documentElement;
  const bars = [...document.querySelectorAll('.rd-bar')].map(b => Math.round(b.getBoundingClientRect().height));
  return JSON.stringify({
    layout: q('.rd').dataset.layout, per: getComputedStyle(q('.rd')).getPropertyValue('--rd-per').trim(),
    page: q('.rd-page').textContent, where: q('.rd-where').textContent, transform: flow.style.transform,
    first: firstVisible ? firstVisible.id : null, sideways: de.scrollWidth > innerWidth, bars,
    clipW: Math.round(cr.width), scrollTop: q('.rd-stage').scrollTop, pos: (JSON.parse(localStorage.getItem('ed.reader.pos') || '{}')[new URLSearchParams(location.search).get('read')] || {}).line,
  });
})()"""


def main():
    shots = sys.argv[sys.argv.index('--shots') + 1] if '--shots' in sys.argv else None
    data = sys.argv[sys.argv.index('--data') + 1] if '--data' in sys.argv else None
    if shots:
        os.makedirs(shots, exist_ok=True)
    widths = [int(x) for x in sys.argv[sys.argv.index('--widths') + 1].split(',')] if '--widths' in sys.argv else WIDTHS
    script = pick_script()
    work = tempfile.mkdtemp(prefix='fit-reader-')
    for f in os.listdir(ROOT):
        if f not in ('index.html', '.git', 'build', 'android', 'apple', 'docs', 'worker', 'windows'):
            os.symlink(os.path.join(ROOT, f), os.path.join(work, f))
    html = open(os.path.join(ROOT, 'index.html')).read()
    if data:
        html = html.replace('<meta name="ed-data" content="data/">', f'<meta name="ed-data" content="{data}">', 1)
    open(os.path.join(work, 'index.html'), 'w').write(html)
    srv_code = ("import sys,http.server,functools\n"
                "class S(http.server.ThreadingHTTPServer):\n request_queue_size=256\n daemon_threads=True\n"
                "class H(http.server.SimpleHTTPRequestHandler):\n def log_message(self,*a): pass\n"
                "S(('127.0.0.1',int(sys.argv[1])),functools.partial(H,directory=sys.argv[2])).serve_forever()\n")
    port = 8800 + os.getpid() % 400
    srv = subprocess.Popen([sys.executable, '-c', srv_code, str(port), work], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)
    part = max(script['roles'], key=lambda r: r['lines'])['name']
    word = next(w for l in script['lines'] if l['kind'] == 'speech' for p in l['parts'] if 'say' in p
                for w in p['say'].split() if len(w) > 5 and w.isalpha())
    print(f'script {script["id"]} ({len(script["lines"])} lines), part {part!r}, search {word!r}')
    problems = []

    def run(w, dark):
        tag = f'{w} {"dark" if dark else "light"}'
        h = 900 if w > 600 else 760
        profile = tempfile.mkdtemp(prefix='fit-reader-chrome-')
        proc = None
        try:
            proc, ws = web_run._launch(profile)
            cdp = web_run.CDP(ws)
            cdp.call('Page.enable')
            cdp.call('Emulation.setDeviceMetricsOverride', {'width': w, 'height': h, 'deviceScaleFactor': 1, 'mobile': w < 600})
            cdp.call('Emulation.setEmulatedMedia', {'features': [{'name': 'prefers-color-scheme', 'value': 'dark' if dark else 'light'}]})
            ev = lambda js, aw=False: cdp.call('Runtime.evaluate', {'expression': js, 'returnByValue': True, 'awaitPromise': aw}, timeout=30).get('result', {}).get('value')
            st = lambda: json.loads(ev(STATE))
            # Settled: fonts in, the page's slide finished (a measure taken mid-slide reads the wrong
            # page; a fixed sleep did, at 430 and 1440 px), then two frames painted.
            settle = lambda: ev("document.fonts.ready.then(() => new Promise(r => { const f = document.querySelector('.rd-flow');"
                                " const t0 = performance.now(); const done = () => (!f || !f.getAnimations().length || performance.now() - t0 > 3000)"
                                " ? requestAnimationFrame(() => requestAnimationFrame(r)) : setTimeout(done, 50); setTimeout(done, 120); }))", True)

            def shot(name):
                settle()
                if shots:
                    png = cdp.call('Page.captureScreenshot', {'format': 'png'}, timeout=30)
                    open(os.path.join(shots, f'reader-{name}-{"dark" if dark else "light"}-{w}.png'), 'wb').write(base64.b64decode(png['data']))

            def bad(msg):
                problems.append(f'{tag}: {msg}')

            cdp.call('Page.navigate', {'url': f'http://127.0.0.1:{port}/?read={script["id"]}&mute=1'}, timeout=30)
            t0 = time.time()
            while not ev("!!document.querySelector('.rd-line') && document.querySelector('.rd-page').textContent.length > 0"):
                if time.time() - t0 > 25:
                    bad('the reader never drew'); shot('timeout'); return
                time.sleep(0.2)
            settle()
            s = st()
            if s['layout'] != 'pages': bad(f'opens in {s["layout"]}, not pages')
            want = '2' if w >= 900 + 48 else '1'
            if s['per'] != want: bad(f'{s["per"]} page(s) a screen, want {want}')
            if s['sideways']: bad('the page scrolls sideways')
            if any(b > 64 for b in s['bars']): bad(f'a bar wraps: {s["bars"]}')
            if ' of ' not in s['page']: bad(f'no page count: {s["page"]!r}')
            shot('pages')
            # A turn moves the page and the count.
            ev("document.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }))")
            settle()
            s2 = st()
            if s2['page'] == s['page'] or s2['transform'] == s['transform']: bad(f'a turn did not move: {s["page"]} -> {s2["page"]}')
            for _ in range(3):
                ev("document.dispatchEvent(new KeyboardEvent('keydown', { key: 'PageDown', bubbles: true }))")
            settle()
            before = st()
            # Text three steps larger: the line first on the page stays on the page.
            ev("document.querySelector('[aria-label=Text]').click()")
            for _ in range(3):
                ev("document.querySelector('[aria-label=\"Larger text\"]').click()")
            settle()
            if w in (375, 1440): shot('text-sheet')
            ev("document.querySelector('dialog[open]').close()")
            settle()
            after = st()
            seen = ev(f"(() => {{ const n = document.getElementById({json.dumps(before['first'])}); const cr = document.querySelector('.rd-clip').getBoundingClientRect(); return [...n.getClientRects()].some(r => r.right > cr.left + 2 && r.left < cr.right - 2); }})()")
            if not seen: bad(f'the reading position moved when the text grew ({before["first"]} not on {after["page"]}; saved {before["pos"]} then {after["pos"]}; was {before["page"]})')
            shot('pages-larger')
            ev("document.querySelector('[aria-label=Text]').click()")
            for _ in range(3):
                ev("document.querySelector('[aria-label=\"Smaller text\"]').click()")
            ev("document.querySelector('dialog[open]').close()")
            settle()
            back = ev(f"(() => {{ const n = document.getElementById({json.dumps(before['first'])}); const cr = document.querySelector('.rd-clip').getBoundingClientRect(); return [...n.getClientRects()].some(r => r.right > cr.left + 2 && r.left < cr.right - 2); }})()")
            if not back: bad('the reading position moved when the text shrank back')
            # Contents.
            ev("document.querySelector('[aria-label=Contents]').click()")
            n = ev("document.querySelectorAll('dialog[open] .rd-toc-btn').length")
            if not n: bad('Contents is empty for a script with headings')
            shot('contents')
            ev("document.querySelector('dialog[open] .rd-toc-btn:nth-child(1), dialog[open] .rd-toc li:last-child .rd-toc-btn').click()")
            settle()
            # Search.
            ev("document.querySelector('[aria-label=Search]').click()")
            ev(f"(() => {{ const i = document.querySelector('dialog[open] .rd-q'); i.value = {json.dumps(word)}; i.dispatchEvent(new Event('input')); }})()")
            time.sleep(0.4)
            hits = ev("document.querySelectorAll('dialog[open] .rd-hit').length")
            if not hits: bad(f'Search found no line for {word!r}')
            shot('search')
            ev("document.querySelector('dialog[open] .rd-hit').click()")
            settle()
            # I'm playing, hide my lines, peek.
            ev(f"(() => {{ const s = document.querySelector('.rd-part-sel'); s.value = 'role:' + {json.dumps(part)}; s.dispatchEvent(new Event('change')); }})()")
            ev("[...document.querySelectorAll('.rd-tool')][0].click()")
            ev("[...document.querySelectorAll('.rd-tool')][1].click()")
            settle()
            hid = ev("(() => { const cr = document.querySelector('.rd-clip').getBoundingClientRect(); const n = [...document.querySelectorAll('.rd-mine .rd-said')].find(x => { const r = x.getBoundingClientRect(); return r.left < cr.right && r.right > cr.left; }); return n ? getComputedStyle(n).color : null; })()")
            if hid is None: bad('no line of the part on the page after Next line')
            elif hid not in ('rgba(0, 0, 0, 0)', 'transparent'): bad(f'a hidden line still shows its words ({hid})')
            shot('rehearse')
            ev("(() => { const cr = document.querySelector('.rd-clip').getBoundingClientRect(); const n = [...document.querySelectorAll('.rd-mine')].find(x => { const r = x.getBoundingClientRect(); return r.left < cr.right && r.right > cr.left; }); if (n) n.click(); })()")
            peek = ev("(() => { const n = document.querySelector('.rd-peek .rd-said'); return n ? getComputedStyle(n).color : null; })()")
            if not peek or peek in ('rgba(0, 0, 0, 0)', 'transparent'): bad('a tap did not peek the hidden line')
            shot('peek')
            # Scroll.
            ev("[...document.querySelectorAll('.rd-tool')][1].click()")
            ev("document.querySelector('[aria-label=Text]').click()")
            ev("document.querySelector('input[name=rd-layout][value=scroll]').click()")
            ev("document.querySelector('dialog[open]').close()")
            settle()
            s3 = st()
            if s3['layout'] != 'scroll': bad('Scroll did not take')
            if s3['sideways']: bad('Scroll scrolls sideways')
            if not s3['page'].endswith('%'): bad(f'Scroll shows no place: {s3["page"]!r}')
            shot('scroll')
        except Exception as e:  # a blind instrument says so
            problems.append(f'{tag}: harness error {e!r}')
        finally:
            if proc:
                web_run._kill(proc)

    try:
        for dark in (False, True):
            for w in widths:
                n = len(problems)
                run(w, dark)
                print(('FAIL ' if len(problems) > n else 'ok   ') + f'{w} {"dark" if dark else "light"} {problems[n:] or ""}')
    finally:
        srv.terminate()
    print(f'{"FAIL" if problems else "PASS"}: {len(problems)} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
