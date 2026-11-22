#!/usr/bin/env python3
"""Fit gate and frames for the device voices' cast (WEB-DESIGN 4.10 "The voices on the cast sheet" and
4.16 item 13; PLAYS-DESIGN 2.8), light and dark, at 320, 375, 430 and 1440 px, in headless Chrome over the
DevTools protocol (tools/web_run.py's launcher).

Nothing is spoken: before the page loads, `speechSynthesis` is replaced with a stub that lists a fixed set
of voices (empty at first, then a `voiceschanged`, as Chrome does) and records every utterance instead of
speaking it. For each width and theme it casts a real play (Record this), then shoots the cast sheet with
its voice chips, a part whose cast voice this browser lacks (the warning and the fallback voice), the voice
picker for the largest part (and presses Hear: the utterance must be the part's own first line), the picker
for Stage directions (Not read first), the reader's Voices sheet, and Hear the cast running (the dock
label and the followed line).

Fails on a sideways scroll, a chip missing or drawn outside its card, a picker wider than the screen or
with no voice checked, a preview that reads anything but the part's first line, auto-cast not giving the
largest part the best voice, a missing voice without its warning, or Hear the cast not following a line.

    python3 tools/web_fit_cast.py              # exit 1 on any problem
    python3 tools/web_fit_cast.py --shots DIR  # also write a PNG per frame
    python3 tools/web_fit_cast.py --widths 375,1440

The play is picked from the bundled castable scripts, never named: the first with four or more speaking
parts and stage directions.

Negative control: make VoiceCast.autoCast take `pool.slice().reverse()`; "the largest part is not read by
the best voice" fails.
"""
import base64, json, os, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import web_run  # noqa: E402

WIDTHS = (320, 375, 430, 1440)
BUNDLE = os.path.join(ROOT, 'catalog', 'plays', 'castable-scripts.json')

STUB = r"""(() => {
  const V = (name, voiceURI, lang, local = true, dflt = false) => ({ name, voiceURI, lang, localService: local, default: dflt });
  const all = [
    V('Samantha', 'com.apple.voice.compact.en-US.Samantha', 'en-US', true, true),
    V('Ava (Premium)', 'com.apple.voice.premium.en-US.Ava', 'en-US'),
    V('Daniel', 'com.apple.voice.compact.en-GB.Daniel', 'en-GB'),
    V('Karen', 'com.apple.voice.compact.en-AU.Karen', 'en-AU'),
    V('Moira', 'com.apple.voice.compact.en-IE.Moira', 'en-IE'),
    V('Zoe (Enhanced)', 'com.apple.voice.enhanced.en-US.Zoe', 'en-US'),
    V('Fred', 'com.apple.speech.synthesis.voice.Fred', 'en-US'),
    V('Google US English', 'Google US English', 'en-US', false),
    V('Thomas', 'com.apple.voice.compact.fr-FR.Thomas', 'fr-FR'),
  ];
  let list = [];
  const listeners = [];
  window.__errors = [];
  window.addEventListener('error', (e) => window.__errors.push(String(e.message)));
  window.addEventListener('unhandledrejection', (e) => window.__errors.push(String(e.reason)));
  window.__spoken = [];
  const synth = {
    getVoices: () => list.slice(),
    speak(u) { window.__spoken.push({ text: u.text, voice: u.voice && u.voice.name, rate: u.rate, pitch: u.pitch, volume: u.volume }); window.__last = u; },
    cancel() { const u = window.__last; window.__last = null; if (u && u.onend) setTimeout(() => u.onend(), 0); },
    pause() {}, resume() {}, speaking: false, pending: false,
    addEventListener: (t, fn) => { if (t === 'voiceschanged') listeners.push(fn); },
    removeEventListener: (t, fn) => { const i = listeners.indexOf(fn); if (i >= 0) listeners.splice(i, 1); },
  };
  Object.defineProperty(window, 'speechSynthesis', { value: synth, configurable: true });
  window.SpeechSynthesisUtterance = function (text) { this.text = text; };
  setTimeout(() => { list = all; listeners.slice().forEach(fn => fn(new Event('voiceschanged'))); }, 400);
})();"""


def pick_script():
    for s in json.load(open(BUNDLE))['scripts']:
        speaking = [r for r in s['roles'] if r['lines'] >= 1]
        if len(speaking) >= 4 and any(l['kind'] == 'direction' for l in s['lines']):
            return s
    raise SystemExit('no script with four parts and directions in the bundle')


def main():
    shots = sys.argv[sys.argv.index('--shots') + 1] if '--shots' in sys.argv else None
    if shots:
        os.makedirs(shots, exist_ok=True)
    widths = [int(x) for x in sys.argv[sys.argv.index('--widths') + 1].split(',')] if '--widths' in sys.argv else WIDTHS
    script = pick_script()
    work = tempfile.mkdtemp(prefix='fit-cast-')
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
    srv = subprocess.Popen([sys.executable, '-c', srv_code, str(port), work], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)
    print(f'script {script["id"]} ({len(script["lines"])} lines, {len(script["roles"])} roles)')
    problems = []

    def run(w, dark):
        tag = f'{w} {"dark" if dark else "light"}'
        h = 900 if w > 600 else 760
        profile = tempfile.mkdtemp(prefix='fit-cast-chrome-')
        proc = None
        try:
            proc, ws = web_run._launch(profile)
            cdp = web_run.CDP(ws)
            cdp.call('Page.enable')
            cdp.call('Page.addScriptToEvaluateOnNewDocument', {'source': STUB})
            cdp.call('Emulation.setDeviceMetricsOverride', {'width': w, 'height': h, 'deviceScaleFactor': 1, 'mobile': w < 600})
            cdp.call('Emulation.setEmulatedMedia', {'features': [{'name': 'prefers-color-scheme', 'value': 'dark' if dark else 'light'}]})
            ev = lambda js, aw=False: cdp.call('Runtime.evaluate', {'expression': js, 'returnByValue': True, 'awaitPromise': aw, 'userGesture': True}, timeout=30).get('result', {}).get('value')
            settle = lambda: ev("document.fonts.ready.then(() => new Promise(r => setTimeout(() => requestAnimationFrame(() => requestAnimationFrame(r)), 250)))", True)

            def shot(name):
                settle()
                if shots:
                    png = cdp.call('Page.captureScreenshot', {'format': 'png'}, timeout=30)
                    open(os.path.join(shots, f'cast-{name}-{"dark" if dark else "light"}-{w}.png'), 'wb').write(base64.b64decode(png['data']))

            def bad(msg):
                problems.append(f'{tag}: {msg}')

            def wait(js, what, secs=25):
                t0 = time.time()
                while not ev(f"!!({js})"):
                    if time.time() - t0 > secs:
                        bad(f'{what} never appeared (page errors: {ev("JSON.stringify(window.__errors)")})'); shot('timeout'); return False
                    time.sleep(0.2)
                return True

            sideways = "document.documentElement.scrollWidth > innerWidth"
            cdp.call('Page.navigate', {'url': f'http://127.0.0.1:{port}/?play={script["id"]}&mute=1'}, timeout=30)
            if not wait("[...document.querySelectorAll('button')].some(b => /Record this/.test(b.textContent))", 'Record this'): return
            ev("[...document.querySelectorAll('button')].find(b => /Record this/.test(b.textContent)).click()")
            if not wait("document.querySelectorAll('.vc-chip').length > 0 && !document.querySelector('.vc-chip[data-state=none]')", 'the voice chips'): return
            settle()
            # Auto-cast: the largest part is read by the best voice; directions Not read.
            chips = json.loads(ev("JSON.stringify([...document.querySelectorAll('.pl-part')].map(c => { const ch = c.querySelector('.vc-chip'); const r = c.getBoundingClientRect(); const cr = ch && ch.getBoundingClientRect();"
                                  " return { name: c.querySelector('.pl-part-name').textContent, chip: ch ? ch.querySelector('.vc-chip-name').textContent : null, tune: ch && ch.querySelector('.vc-chip-tune') ? ch.querySelector('.vc-chip-tune').textContent : '', state: ch && ch.dataset.state, out: ch ? (cr.right > r.right + 1 || cr.left < r.left - 1) : false }; }))"))
            if not chips or chips[0]['chip'] != 'Ava (Premium)': bad(f'the largest part is not read by the best voice: {chips[:1]}')
            if any(c['out'] for c in chips): bad(f'a chip spills out of its card: {[c["name"] for c in chips if c["out"]]}')
            dirs = [c for c in chips if c['name'] == 'Stage directions']
            if dirs and dirs[0]['chip'] != 'Not read': bad(f'Stage directions read by default: {dirs[0]}')
            if len({c['chip'] for c in chips[:4]}) < 4: bad(f'the four largest parts do not have distinct voices: {[c["chip"] for c in chips[:4]]}')
            if ev(sideways): bad('the cast sheet scrolls sideways')
            shot('sheet')
            # A cast voice this browser lacks: the second part falls back, visibly.
            # Only choices are kept (Decision 086): write one for the second part, as the picker would.
            ev("(() => { const all = JSON.parse(localStorage.getItem('ed.cast') || '{}');"
               " const links = [...document.querySelectorAll('.pl-part-link')].map(a => new URL(a.href).searchParams);"
               " const pid = links[0].get('production'); const id = links.map(q => q.get('part')).filter(x => x.startsWith('role:'))[1];"
               " const k = 'p:' + pid; const row = all[k] || { parts: {}, at: Date.now() }; row.v = 2;"
               " row.parts[id] = { engine: 'system', voice: 'gone', name: 'Allison (Enhanced)', rate: 1, pitch: 1 }; all[k] = row;"
               " localStorage.setItem('ed.cast', JSON.stringify(all)); })()")
            # Decision 079 deletes a production with no take on load, so give this one a first take (a short
            # silence written through the page's own store) before the reload.
            took = ev("(async () => { const st = await PlaysUI.openStore(); const p = st.productions[0]; const line = Object.keys(p.chosen || {})[0] || 'l1';"
                      " const bytes = PlaysCore.encodeWav(new Float32Array(4800), 48000, 24); await st.importTake(p.id, 'fit-take.wav', bytes);"
                      " await st.save(PlaysCore.addTake(st.production(p.id), { id: 'fit-take', lineID: line, part: 'x', file: 'fit-take.wav', created: PlaysCore.now(), frames: 4800,"
                      " sampleRate: 48000, capture: 'direct', heard: {}, peak: 0.1, bleed: false })); return st.production(p.id).takes.length; })()", True)
            if took != 1: bad(f'the fit could not give the production a first take: {took!r}')
            here = ev('location.href')
            cdp.call('Page.navigate', {'url': here + ('' if 'mute=1' in here else '&mute=1')}, timeout=30)
            if not wait("document.querySelector('.vc-chip[data-state=missing]')", 'the missing-voice chip'): return
            label = ev("document.querySelector('.vc-chip[data-state=missing]').getAttribute('aria-label')")
            if 'Allison (Enhanced) is not in this browser' not in (label or ''): bad(f'the fallback is not named: {label!r}')
            if w in (375, 1440): shot('fallback')
            ev("document.querySelector('.vc-chip[data-state=missing]').click()")
            if wait("document.querySelector('dialog.vc-sheet[open] .vc-missing:not([hidden])')", 'the missing-voice warning in the picker'):
                if w in (375, 1440): shot('picker-missing')
                ev("document.querySelector('dialog.vc-sheet[open]').close()")
            # The picker for the largest part, and Hear reads its own first line.
            ev("document.querySelector('.vc-chip').click()")
            if not wait("document.querySelector('dialog.vc-sheet[open]')", 'the voice picker'): return
            pk = json.loads(ev("JSON.stringify((() => { const d = document.querySelector('dialog.vc-sheet[open]'); const r = d.getBoundingClientRect();"
                               " return { w: r.width, right: r.right, rows: d.querySelectorAll('.vc-row').length, checked: (d.querySelector('input:checked') || {}).value || null, sw: d.scrollWidth > d.clientWidth + 1 }; })())"))
            if pk['right'] > w + 1 or pk['sw']: bad(f'the picker is wider than the screen: {pk}')
            if pk['rows'] != 8: bad(f'the picker lists {pk["rows"]} rows, want Default and the 7 local English voices')
            if not pk['checked']: bad('no voice is checked in the picker')
            shot('picker')
            ev("window.__spoken.length = 0; document.querySelectorAll('dialog.vc-sheet[open] .vc-hear')[2].click()")
            time.sleep(0.2)
            heard = ev("JSON.stringify(window.__spoken)")
            first = next(l for l in script['lines'] if l['kind'] == 'speech' and l['role'] == max(script['roles'], key=lambda r: r['lines'])['name'])
            want = ' '.join(p['say'] for p in first['parts'] if 'say' in p).replace('_', '').strip()
            got = json.loads(heard or '[]')
            if not got or got[0]['text'] != want: bad(f'Hear did not read the part\'s first line: {got[:1]} want {want[:40]!r}')
            if got and got[0]['volume'] != 0: bad('a preview under ?mute=1 was not muted')
            if w == 375: shot('picker-hearing')
            ev("document.querySelector('dialog.vc-sheet[open]').close()")
            # Stage directions: Not read first.
            ev("[...document.querySelectorAll('.pl-part')].find(c => c.querySelector('.pl-part-name').textContent === 'Stage directions').querySelector('.vc-chip').click()")
            if wait("document.querySelector('dialog.vc-sheet[open]')", 'the directions picker'):
                v = ev("(document.querySelector('dialog.vc-sheet[open] input:checked') || {}).value")
                if v != 'default': bad(f'Stage directions picker: {v!r} checked, want Default (Not read)')
                if w in (375, 1440): shot('picker-directions')
                ev("document.querySelector('dialog.vc-sheet[open]').close()")
            # The reader: Voices, then Hear the cast.
            cdp.call('Page.navigate', {'url': f'http://127.0.0.1:{port}/?read={script["id"]}&mute=1'}, timeout=30)
            if not wait("!!document.querySelector('.rd-line') && document.querySelector('.rd-page').textContent.length > 0", 'the reader'): return
            settle()
            ev("document.querySelector('[aria-label=Voices]').click()")
            if wait("document.querySelectorAll('dialog[open] .vc-cast-row .vc-chip').length > 0 && !document.querySelector('dialog[open] .vc-chip[data-state=none]')", "the reader's Voices"):
                if ev("(() => { const d = document.querySelector('dialog[open]'); return d.scrollWidth > d.clientWidth + 1; })()"): bad('Voices scrolls sideways')
                shot('reader-voices')
                ev("document.querySelector('dialog[open]').close()")
            bars = json.loads(ev("JSON.stringify([...document.querySelectorAll('.rd-bar')].map(b => Math.round(b.getBoundingClientRect().height)))"))
            if any(b > 64 for b in bars): bad(f'a reader bar wraps: {bars}')
            ev("document.querySelector('.rd-hear').click()")
            if wait("document.querySelector('.rd-now') && !document.querySelector('.rd-dock').hidden", 'Hear the cast following a line', 8):
                dock = ev("document.querySelector('.rd-dock').textContent")
                if not dock.startswith('Device voice'): bad(f'the dock does not label the device voice: {dock!r}')
                if ev(sideways): bad('the reader scrolls sideways while reading')
                shot('reader-hearing')
            ev("document.querySelector('.rd-hear').click()")
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
