#!/usr/bin/env python3
"""Fit gate and frames for the Sound part's studio and the sound board (WEB-DESIGN 4.16 item 14a; B32 3, 7),
light and dark, at 320, 375, 430 and 1440 px, in headless Chrome over the DevTools protocol.

Nothing is heard. Chrome runs with --mute-audio and every page with ?mute=1; the device voice and the microphone
are web_fit_studio's stubs (a voice that speaks nothing, an oscillator nobody hears). The pack is the fixture
(tools/fixtures/sounds/, made by tools/make_sound_fixture.mjs), named with ?sounds= on this machine only; its three
planted rows (CC-BY, no evidence, a refused host) must never be listed.

For each width and theme: cast a real play (Record this); the cast sheet must list Sound with its cue count and
Stage directions; Take part on Sound must land in the reader's Sound studio with a ring on every cue row and the
first slot outlined; the board (a sheet below the spread width, the panel from it) opens on a search seeded from
the cue's words or empty, the pack's categories then Mine; Download a category, Add a sound (In cue, the
placement control, Start, Level and fades), Hear it in place (pressed, then stopped); the page then lists the
sound under its cue; the next slot takes a loop as a Bed with an Until picked on the page (the bed's rule drawn);
no match ("No sound called ..." with Record it); Mine empty; Record a sound (an own sound, then Add); a performed
cue (the round control: the headphones gate, room tone, a take on the slot); Done with this part; then Stage
directions' studio, a take state at each direction's end. Then the pack absent (no library at all) and the pack
unreachable (one line).

Fails on: a sideways scroll; a bottom bar taller than 72 px or a dock row that wraps; the board scrolling sideways;
the panel not beside the script at 1440 px, or beside it below 860 px; a missing Sound row, ring, outline,
category, state line or control; a planted row listed; page errors.

    python3 tools/web_fit_sound.py              # exit 1 on any problem
    python3 tools/web_fit_sound.py --shots DIR  # also write a PNG per frame
    python3 tools/web_fit_sound.py --widths 375,1440

The play is picked from the bundled castable scripts, never named: the first with eight or more cue rows and a
stage direction.
"""
import base64, json, os, re, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import web_run  # noqa: E402
from web_fit_studio import STUB, launch  # noqa: E402

WIDTHS = (320, 375, 430, 1440)
BUNDLE = os.path.join(ROOT, 'catalog', 'plays', 'castable-scripts.json')
FIXTURE = 'tools/fixtures/sounds/sounds.json'
CUE = re.compile(r'^[\s(\[_]*(?:(?:sounds?|noises?) of\b|music\b)', re.I)


def cue_rows(s):
    n = 0
    for line in s['lines']:
        if line['kind'] in ('sound', 'music'):
            n += 1
        elif line['kind'] == 'speech':
            for p in line.get('parts', []):
                k = list(p)[0]
                if k == 'sound' or (k == 'direction' and CUE.match(p[k] or '')):
                    n += 1
    return n


def pick_script():
    for s in json.load(open(BUNDLE))['scripts']:
        if cue_rows(s) >= 8 and any(line['kind'] == 'direction' for line in s['lines']):
            return s
    raise SystemExit('no script with eight cue rows and a direction in the bundle')


def main():
    shots = sys.argv[sys.argv.index('--shots') + 1] if '--shots' in sys.argv else None
    if shots:
        os.makedirs(shots, exist_ok=True)
    widths = [int(x) for x in sys.argv[sys.argv.index('--widths') + 1].split(',')] if '--widths' in sys.argv else WIDTHS
    script = pick_script()
    n_cues = cue_rows(script)
    n_dirs = sum(1 for line in script['lines'] if line['kind'] == 'direction')
    work = tempfile.mkdtemp(prefix='fit-sound-')
    for f in os.listdir(ROOT):
        if f not in ('index.html', '.git', 'build', 'android', 'apple', 'docs', 'worker', 'windows', 'data'):
            os.symlink(os.path.join(ROOT, f), os.path.join(work, f))
    os.makedirs(os.path.join(work, 'data', 'plays'))
    os.symlink(BUNDLE, os.path.join(work, 'data', 'plays', 'castable-scripts.json'))
    open(os.path.join(work, 'index.html'), 'w').write(open(os.path.join(ROOT, 'index.html')).read())
    srv_code = ("import sys,http.server,functools\n"
                "class S(http.server.ThreadingHTTPServer):\n request_queue_size=256\n daemon_threads=True\n"
                "class H(http.server.SimpleHTTPRequestHandler):\n def log_message(self,*a): pass\n"
                "S(('127.0.0.1',int(sys.argv[1])),functools.partial(H,directory=sys.argv[2])).serve_forever()\n")
    port = 8400 + os.getpid() % 400
    srv = subprocess.Popen(['nice', '-n', '15', sys.executable, '-c', srv_code, str(port), work], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)
    print(f'script {script["id"]} ({len(script["lines"])} lines), {n_cues} cue rows, {n_dirs} directions')
    problems = []

    def run(w, dark):
        tag = f'{w} {"dark" if dark else "light"}'
        h = 900 if w > 600 else 780
        profile = tempfile.mkdtemp(prefix='fit-sound-chrome-')
        proc = None
        try:
            proc, ws = launch(profile)
            cdp = web_run.CDP(ws)
            cdp.call('Page.enable')
            cdp.call('Page.addScriptToEvaluateOnNewDocument', {'source': STUB})
            cdp.call('Emulation.setDeviceMetricsOverride', {'width': w, 'height': h, 'deviceScaleFactor': 1, 'mobile': w < 600})
            cdp.call('Emulation.setEmulatedMedia', {'features': [{'name': 'prefers-color-scheme', 'value': 'dark' if dark else 'light'}]})
            ev = lambda js, aw=False: cdp.call('Runtime.evaluate', {'expression': js, 'returnByValue': True, 'awaitPromise': aw, 'userGesture': True}, timeout=30).get('result', {}).get('value')
            settle = lambda: ev("document.fonts.ready.then(() => new Promise(r => setTimeout(() => requestAnimationFrame(() => requestAnimationFrame(r)), 350)))", True)
            key = lambda k: ev(f"document.dispatchEvent(new KeyboardEvent('keydown', {{ key: {json.dumps(k)}, bubbles: true, cancelable: true }}))")
            click_text = lambda sel, rx: ev(f"(() => {{ const b = [...document.querySelectorAll({json.dumps(sel)})].find(x => {rx}.test(x.textContent) && !x.disabled); if (b) b.click(); return !!b; }})()")

            def shot(name):
                settle()
                if shots:
                    png = cdp.call('Page.captureScreenshot', {'format': 'png'}, timeout=30)
                    open(os.path.join(shots, f'sound-{name}-{"dark" if dark else "light"}-{w}.png'), 'wb').write(base64.b64decode(png['data']))

            def bad(msg):
                problems.append(f'{tag}: {msg}')

            def wait(js, what, secs=25):
                t0 = time.time()
                while not ev(f"!!({js})"):
                    if time.time() - t0 > secs:
                        bad(f'{what} never appeared (page errors: {ev("JSON.stringify(window.__errors)")})'); shot('timeout'); return False
                    time.sleep(0.2)
                return True

            def fit(where):
                s = json.loads(ev("""JSON.stringify((() => { const b = document.querySelector('.rd-bottom').getBoundingClientRect();
                  const rows = [...document.querySelectorAll('.sb-dock .st-status')].map(r => Math.round(r.getBoundingClientRect().height));
                  const d = document.querySelector('dialog.sb-sheet[open]');
                  return { sideways: document.documentElement.scrollWidth > innerWidth, bar: Math.round(b.height), rows,
                           sheet: !!d && d.scrollWidth > d.clientWidth + 1,
                           side: !document.querySelector('.st-side').hidden }; })())"""))
                if s['sideways']: bad(f'{where}: the page scrolls sideways')
                if s['bar'] > 72: bad(f'{where}: the bottom bar is {s["bar"]} px tall (wraps)')
                if any(r > 60 for r in s['rows']): bad(f'{where}: a dock row wraps {s["rows"]}')
                if s['sheet']: bad(f'{where}: the board scrolls sideways')
                if w >= 900 and not s['side']: bad(f'{where}: the board is not beside the script at {w} px')
                if w < 860 and s['side']: bad(f'{where}: the board is beside the script at {w} px')

            def board():
                if w < 860 and not ev("!!document.querySelector('dialog.sb-sheet[open]')"):
                    ev("document.querySelector('.st-open').click()")
                    return wait("document.querySelector('dialog.sb-sheet[open] .sb-find')", 'the board sheet', 5)
                return True

            def close_board():
                if w < 860:
                    ev("(() => { const d = document.querySelector('dialog.sb-sheet[open]'); if (d) d.close(); })()")

            base = f'http://127.0.0.1:{port}/?play={script["id"]}&mute=1'
            cdp.call('Page.navigate', {'url': f'{base}&sounds={FIXTURE}'}, timeout=30)
            if not wait("[...document.querySelectorAll('button')].some(b => /Record this/.test(b.textContent))", 'Record this'): return
            ev("[...document.querySelectorAll('button')].find(b => /Record this/.test(b.textContent)).click()")
            if not wait("document.querySelector('button[aria-label=\"Take part: Sound\"]')", 'Take part: Sound on the cast sheet'): return
            settle()
            rows = json.loads(ev("JSON.stringify([...document.querySelectorAll('.pl-grid > li')].map(li => li.textContent.replace(/\\s+/g, ' ').trim()))"))
            sound_row = next((r for r in rows if r.startswith('Sound')), '')
            if f'{n_cues} cues' not in sound_row: bad(f'the Sound row does not count its cues: {sound_row!r}')
            if not any(r.startswith('Stage directions') for r in rows): bad('no Stage directions row on the cast sheet')
            if w in (375, 1440):
                ev("document.querySelector('button[aria-label=\"Take part: Sound\"]').scrollIntoView({ block: 'center' })")
                shot('cast')
            ev("document.querySelector('button[aria-label=\"Take part: Sound\"]').click()")
            if not wait("document.querySelector('.sb-dock') && document.querySelector('.sb-ring')", "the Sound part's studio"): return
            settle()
            if 'part=sound' not in ev('location.search'): bad(f'the cast sheet did not land in the Sound studio: {ev("location.search")}')
            rings = ev("document.querySelectorAll('.sb-ring').length")
            if rings != n_cues: bad(f'{rings} slot rings for {n_cues} cue rows')
            if not ev("!!document.querySelector('.sb-cur')"): bad('the current slot is not outlined')
            if not wait("document.querySelector('.sb-chips button')", 'the categories', 10): return
            fit('studio')
            shot('studio')
            if not board(): return
            if not wait("[...document.querySelectorAll('.sb-chips button')].length === 4", 'the pack categories and Mine', 10): return
            chips = json.loads(ev("JSON.stringify([...document.querySelectorAll('.sb-chips button')].map(b => b.textContent))"))
            if chips != ['Weather', 'Doors', 'Music', 'Mine']: bad(f'the categories are {chips}')
            if ev("/Planted/.test(document.querySelector('.sb-results').textContent)"): bad('a planted row the rights gate refuses is listed')
            ev("(() => { const q = document.querySelector('.sb-q'); q.value = ''; q.dispatchEvent(new Event('input')); })()")
            # Download Weather; add its first cue.
            if not click_text('.sb-cat .sb-dl', '/Download/') and False: pass
            ev("(() => { const c = [...document.querySelectorAll('.sb-cat')].find(x => /Weather/.test(x.textContent)); const b = c && c.querySelector('.sb-dl'); if (b) b.click(); })()")
            if not wait("[...document.querySelectorAll('.sb-cat')].some(x => /Weather/.test(x.textContent) && /Downloaded/.test(x.textContent))", 'Weather downloaded', 15): return
            ev("[...document.querySelectorAll('.sb-chips button')].find(b => b.textContent === 'Weather').click()")
            settle()
            if not click_text('.sb-results .sb-add', '/Add/'): bad('no Add on a result'); return
            if not wait("document.querySelector('.sb-cue .sb-place') && document.querySelector('.sb-add.on')", 'the sound in the cue with its placement', 5): return
            if not ev("!!document.querySelector('.sb-more') && [...document.querySelectorAll('.sb-set')].some(x => /Start|Until/.test(x.textContent))"): bad('no Start or Level and fades')
            ev("document.querySelector('.sb-inplace').click()")
            if wait("/Stop/.test(document.querySelector('.sb-inplace').textContent)", 'Hear it in place playing', 5):
                ev("document.querySelector('.sb-inplace').click()")
            settle()
            fit('board')
            ev("(document.querySelector('.st-side') && !document.querySelector('.st-side').hidden ? document.querySelector('.st-side') : document.querySelector('dialog.sb-sheet[open]')).scrollTop = 0")
            shot('board')
            close_board()
            settle()
            if not ev("!!document.querySelector('.sb-cur .sb-snd')"): bad('the page does not list the chosen sound under its cue')
            shot('page')
            # The next slot: a loop as a Bed, its Until picked on the page.
            key('j')
            settle()
            if not board(): return
            ev("[...document.querySelectorAll('.sb-chips button')].find(b => b.textContent === 'Weather').click()")
            ev("(() => { const q = document.querySelector('.sb-q'); q.value = 'rain'; q.dispatchEvent(new Event('input')); })()")
            settle()
            if not click_text('.sb-results .sb-add', '/Add/'): bad('no Add for the loop'); return
            if not wait("document.querySelector('.sb-place')", 'the placement control for the loop', 5): return
            ev("document.querySelector('.sb-place input[value=bed]').click()")
            if not wait("document.querySelector('.sb-place label.on') && /Bed/.test(document.querySelector('.sb-place label.on').textContent) && document.querySelector('.sb-until')", 'the loop as a Bed with its Until', 5): return
            ev("document.querySelector('.sb-until').click()")
            if not wait("/Tap the last line/.test(document.querySelector('.sb-dock').textContent)", 'the Until pick', 5): return
            ev("""(() => { const cur = document.querySelector('.sb-cur'); const line = cur.closest('.rd-line');
                     let n = line.nextElementSibling, k = 0; while (n && (k < 3 || !n.classList.contains('rd-line'))) { if (n.classList.contains('rd-line')) k++; n = n.nextElementSibling; }
                     (n || line).click(); })()""")
            if not wait("document.querySelectorAll('.rd-line.sb-bed').length >= 2", "the bed's rule across lines", 5): return
            settle()
            close_board()
            settle()
            shot('bed')
            # No match, and Mine empty.
            if not board(): return
            ev("(() => { const b = [...document.querySelectorAll('.sb-chips button')].find(x => x.getAttribute('aria-pressed') === 'true' && x.textContent !== 'Mine'); if (b) b.click(); })()")
            ev("(() => { const q = document.querySelector('.sb-q'); q.value = 'zeppelin'; q.dispatchEvent(new Event('input')); })()")
            if not wait("/No sound called “zeppelin”\\./.test(document.querySelector('.sb-results').textContent) && /Record it/.test(document.querySelector('.sb-results').textContent)", 'the no-match state', 5): return
            ev("document.querySelector('.sb-results').scrollIntoView({ block: 'center' })")
            if w in (375, 1440): shot('nomatch')
            ev("(() => { const q = document.querySelector('.sb-q'); q.value = ''; q.dispatchEvent(new Event('input')); })()")
            ev("[...document.querySelectorAll('.sb-chips button')].find(b => b.textContent === 'Mine').click()")
            if not wait("/No sounds of your own yet\\./.test(document.querySelector('.sb-results').textContent) && document.querySelector('.sb-rec-own') && document.querySelector('.sb-bring')", 'Mine empty', 5): return
            if w in (375, 1440): shot('mine-empty')
            # Record a sound of my own (no headphones gate), then Add it.
            ev("document.querySelector('.sb-rec-own').click()")
            if not wait("document.querySelector('[data-act=own-stop]')", 'recording an own sound', 8): return
            ev("window.__micGain && (window.__micGain.gain.value = 0.3)")
            time.sleep(1.0)
            ev("document.querySelector('[data-act=own-stop]').click()")
            if not wait("/My sound 1/.test(document.querySelector('.sb-results').textContent)", 'the own sound in Mine', 10): return
            click_text('.sb-results .sb-add', '/Add/')
            if not wait("[...document.querySelectorAll('.sb-in .body-strong')].some(x => x.textContent === 'My sound 1')", 'the own sound in the cue', 5): return
            close_board()
            # A performed cue: the round control asks for headphones first, records the room, then the cue.
            key('j')
            settle()
            if ev("!!document.querySelector('dialog.sb-sheet[open]')"): bad('the board stayed open after Done')
            ev("document.querySelector('.st-transport [data-act=record]').click()")
            if not wait("document.querySelector('#sb-headphones')", 'the headphones gate at the first press', 5): return
            fit('gate')
            if w in (375, 1440): shot('gate')
            ev("document.getElementById('sb-headphones').click(); document.querySelector('.st-go').click()")
            if not wait("document.querySelector('.st-transport [data-act=record]:not(:disabled)') && !document.querySelector('#sb-headphones') && !/Quiet/.test(document.querySelector('.sb-dock').textContent)", 'the dock after room tone', 15): return
            ev("document.querySelector('.st-transport [data-act=record]').click()")
            if not wait("document.querySelector('.sb-dock .st-rec')", 'the microphone open for the performed cue', 12): return
            ev("window.__micGain.gain.value = 0.3")
            time.sleep(1.0)
            fit('performing')
            if w in (375, 1440): shot('performing')
            ev("window.__micGain.gain.value = 0.0005")
            ev("document.querySelector('.st-transport [data-act=stop]').click()")
            if not wait("/Your take 1/.test(document.querySelector('.sb-dock').textContent)", 'the performed cue in its slot', 10): return
            # Done with this part, then Stage directions: a take state at each direction's end.
            if not board(): return
            click_text('.sb-panel .st-acts .btn', '/Done with this part/')
            if not wait("document.querySelector('button[aria-label=\"Take part: Stage directions\"]')", 'the cast sheet after Done', 10): return
            settle()
            row = ev("(() => { const li = [...document.querySelectorAll('.pl-grid > li')].find(x => (x.querySelector('.pl-part-name') || {}).textContent === 'Sound'); return li ? li.textContent.replace(/\\s+/g, ' ') : ''; })()")
            if not re.search(r'of \d+ cues · 1 bed', row or ''):
                bad(f'the Sound row after taking it: {row!r} in {ev("JSON.stringify([...document.querySelectorAll(\'.pl-grid > li\')].map(li => li.textContent.slice(0, 40)))")}')
            if w in (375, 1440): shot('cast-after')
            ev("document.querySelector('button[aria-label=\"Take part: Stage directions\"]').click()")
            if not wait("document.querySelector('.rd-take-end')", "Stage directions' take states", 10): return
            ends = ev("document.querySelectorAll('.rd-take-end').length")
            if ends != n_dirs: bad(f'{ends} direction take states for {n_dirs} directions')
            settle()
            if w in (375, 1440): shot('directions')
            errs = [e for e in json.loads(ev("JSON.stringify(window.__errors)")) if not e.startswith('sync ')]
            if errs: bad(f'page errors: {errs[:3]}')
            # The pack absent: no library at all. Unreachable: one line.
            for variant, sounds, want in (('absent', '', None), ('unreachable', '&sounds=tools/fixtures/sounds/missing.json', 'The sounds are not downloaded yet.')):
                ev("sessionStorage.removeItem('ed.sounds.local')")
                cdp.call('Page.navigate', {'url': f'http://127.0.0.1:{port}/?read={script["id"]}&mute=1{sounds}'}, timeout=30)
                if not wait("document.querySelector('.rd-line')", f'the reader ({variant})'): return
                prod = ev("(async () => { const s = await PlaysUI.openStore(); await s.load(); const p = s.productions.find(x => x.scriptID === %s); return p && p.id; })()" % json.dumps(script['id']), True)
                cdp.call('Page.navigate', {'url': f'http://127.0.0.1:{port}/?read={script["id"]}&production={prod}&part=sound&mute=1{sounds}'}, timeout=30)
                if not wait("document.querySelector('.sb-dock')", f'the Sound studio ({variant})'): return
                if not board(): return
                if not wait("document.querySelector('.sb-chips button')", 'the chips', 10): return
                settle()
                chips = json.loads(ev("JSON.stringify([...document.querySelectorAll('.sb-chips button')].map(b => b.textContent))"))
                if chips != ['Mine']: bad(f'pack {variant}: the categories are {chips}, want only Mine')
                text = ev("document.querySelector('.sb-results').textContent")
                if want and want not in text: bad(f'pack {variant}: no line {want!r}')
                if not want and 'not downloaded' in text: bad('pack absent: a line about downloading shows')
                if not ev("!!document.querySelector('.sb-rec-own')"): bad(f'pack {variant}: no Record a sound')
                fit(f'pack {variant}')
                if w in (375, 1440): shot(f'pack-{variant}')
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
        srv.wait(5)
    print(f'{"FAIL" if problems else "PASS"}: {len(problems)} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
