#!/usr/bin/env python3
"""Fit gate and frames for Library > Voices and the cast's Defaults (Decision 086; WEB-DESIGN 4.11a; PLAYS-DESIGN 2.8
rule 11), light and dark, at 375 and 1440 px, in headless Chrome over the DevTools protocol (tools/web_run.py).

Nothing is spoken and no model is fetched: before the page loads, `speechSynthesis` is a stub with a fixed voice list
that records utterances; `navigator.gpu` is stubbed present (or absent, for the refusal); the Kokoro manifest is a
stub; in the downloading state the model's bytes are a stream that stops partway; in the downloaded state Cache Storage
answers for the model and the self-test result is preset. The state comes from the URL's #fit= so one injected script
serves them all.

Frames (with --shots DIR): the first-launch step (WEB-DESIGN 4.11b) and the step on a full disk; Library, scrolled to its Voices section, not downloaded, downloading, downloaded, and unsupported; the cast sheet
with its Default chips and the "Better voices" offer (not downloaded), and with the Kokoro Defaults (downloaded).

Fails on a sideways scroll, a sheet wider than the screen, a Download button without the manifest's size, no progress
while downloading, Kokoro voices missing once downloaded or listed while not, a refusal missing in a browser without
WebGPU, the engine's scripts requested while the model is absent, an untouched chip not saying Default, the largest
part not read by the first Default voice, a Move up that does not reorder, or a Hear under ?mute=1 that was not muted.

    python3 tools/web_fit_voices.py                # exit 1 on any problem
    python3 tools/web_fit_voices.py --shots DIR    # also write a PNG per frame

Negative control: make VoiceCast.ordered() drop its engine rank; "the largest part is not read by Heart (Kokoro)" fails.
"""
import base64, json, os, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import web_run  # noqa: E402

WIDTHS = (375, 1440)
BUNDLE = os.path.join(ROOT, 'catalog', 'plays', 'castable-scripts.json')
web_run.QUIET = web_run.QUIET + ['--autoplay-policy=user-gesture-required']

STUB = r"""(() => {
  const mode = (location.hash.match(/fit=(\w+)/) || [])[1] || 'absent';
  window.__fitMode = mode;
  const V = (name, voiceURI, lang, local = true, dflt = false) => ({ name, voiceURI, lang, localService: local, default: dflt });
  const all = [
    V('Samantha', 'com.apple.voice.compact.en-US.Samantha', 'en-US', true, true),
    V('Ava (Premium)', 'com.apple.voice.premium.en-US.Ava', 'en-US'),
    V('Daniel', 'com.apple.voice.compact.en-GB.Daniel', 'en-GB'),
    V('Karen', 'com.apple.voice.compact.en-AU.Karen', 'en-AU'),
    V('Zoe (Enhanced)', 'com.apple.voice.enhanced.en-US.Zoe', 'en-US'),
    V('Fred', 'com.apple.speech.synthesis.voice.Fred', 'en-US'),
    V('Google US English', 'Google US English', 'en-US', false),
    V('English United Kingdom', 'en-gb-x-rjs-local', 'en_GB'),
    V('English Australia', 'en-au-x-aua-local', 'en_AU'),
    ...['iob', 'iog', 'iol', 'iom', 'sfg', 'tpc', 'tpd', 'tpf'].map((c, i) => V('English United States' + (i ? ' ' + (i + 1) : ''), 'en-us-x-' + c + '-local', 'en_US')),
  ];
  window.__errors = [];
  window.addEventListener('error', (e) => window.__errors.push(String(e.message)));
  window.addEventListener('unhandledrejection', (e) => window.__errors.push(String(e.reason)));
  window.__spoken = [];
  window.__scripts = [];
  new MutationObserver((ms) => ms.forEach(m => m.addedNodes.forEach(n => { if (n.tagName === 'SCRIPT' && n.src) window.__scripts.push(n.src); })))
    .observe(document, { childList: true, subtree: true });
  const synth = {
    getVoices: () => all.slice(),
    speak(u) { window.__spoken.push({ text: u.text, voice: u.voice && u.voice.name, volume: u.volume }); window.__last = u; },
    cancel() { const u = window.__last; window.__last = null; if (u && u.onend) setTimeout(() => u.onend(), 0); },
    pause() {}, resume() {}, speaking: false, pending: false,
    addEventListener() {}, removeEventListener() {},
  };
  Object.defineProperty(window, 'speechSynthesis', { value: synth, configurable: true });
  window.SpeechSynthesisUtterance = function (text) { this.text = text; };
  if (mode === 'full' && navigator.storage) navigator.storage.estimate = async () => ({ quota: 400e6, usage: 90e6 });
  Object.defineProperty(Navigator.prototype, 'gpu', { configurable: true,
    get: () => (mode === 'unsupported' ? undefined : { requestAdapter: async () => ({}) }) });
  const manifest = { format: 1, files: [
    { path: 'model.onnx', role: 'model', bytes: 325532232, sha256: 'a'.repeat(64), license: 'Apache-2.0' },
    { path: 'voices.bin', role: 'voices', bytes: 14680064, sha256: 'b'.repeat(64), license: 'Apache-2.0' },
    { path: 'tokenizer.json', role: 'vocab', bytes: 3497, sha256: 'c'.repeat(64), license: 'Apache-2.0' }] };
  const realFetch = window.fetch.bind(window);
  window.fetch = (u, o) => {
    const s = String(u && u.url ? u.url : u);
    if (s.includes('data/kokoro/manifest.json')) return Promise.resolve(new Response(JSON.stringify(manifest), { headers: { 'content-type': 'application/json' } }));
    if (s.includes('data/kokoro/')) {
      let sent = 0;
      const body = new ReadableStream({ pull(c) { if (sent < 4) { sent++; c.enqueue(new Uint8Array(29e6)); } else return new Promise(() => {}); } });
      return Promise.resolve(new Response(body));
    }
    return realFetch(u, o);
  };
  try {
    localStorage.removeItem('ed.kokoro.off');
    if (mode === 'ready') localStorage.setItem('ed.kokoro.check', JSON.stringify({ ok: true, rtf: 0.2, at: 1, cache: 'ed-kokoro-v5' }));
    else localStorage.removeItem('ed.kokoro.check');
  } catch (e) { window.__errors.push(String(e)); }
  if (mode === 'ready') {
    const real = window.caches;
    const fake = { match: async () => new Response(new Uint8Array(1)), put: async () => {}, delete: async () => true };
    Object.defineProperty(window, 'caches', { configurable: true, value: {
      has: async (n) => n === 'ed-kokoro-v5' || real.has(n), open: async (n) => (n === 'ed-kokoro-v5' ? fake : real.open(n)),
      delete: (n) => real.delete(n), keys: () => real.keys(), match: (...a) => real.match(...a) } });
  }
})();"""


def pick_script():
    for s in json.load(open(BUNDLE))['scripts']:
        speaking = [r for r in s['roles'] if r['lines'] >= 1]
        if len(speaking) >= 4:
            return s
    raise SystemExit('no script with four parts in the bundle')


def main():
    shots = sys.argv[sys.argv.index('--shots') + 1] if '--shots' in sys.argv else None
    if shots:
        os.makedirs(shots, exist_ok=True)
    widths = [int(x) for x in sys.argv[sys.argv.index('--widths') + 1].split(',')] if '--widths' in sys.argv else WIDTHS
    script = pick_script()
    work = tempfile.mkdtemp(prefix='fit-voices-')
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
    port = 8000 + os.getpid() % 400
    srv = subprocess.Popen([sys.executable, '-c', srv_code, str(port), work], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)
    print(f'script {script["id"]} ({len(script["roles"])} roles)')
    problems = []
    base = f'http://127.0.0.1:{port}/'

    def run(w, dark):
        tag = f'{w} {"dark" if dark else "light"}'
        h = 900 if w > 600 else 760
        profile = tempfile.mkdtemp(prefix='fit-voices-chrome-')
        proc = None
        try:
            proc, ws = web_run._launch(profile)
            cdp = web_run.CDP(ws)
            cdp.call('Page.enable')
            cdp.call('Page.addScriptToEvaluateOnNewDocument', {'source': STUB})
            cdp.call('Emulation.setDeviceMetricsOverride', {'width': w, 'height': h, 'deviceScaleFactor': 1, 'mobile': w < 600})
            cdp.call('Emulation.setEmulatedMedia', {'features': [{'name': 'prefers-color-scheme', 'value': 'dark' if dark else 'light'}]})
            ev = lambda js, aw=False: cdp.call('Runtime.evaluate', {'expression': js, 'returnByValue': True, 'awaitPromise': aw, 'userGesture': True}, timeout=30).get('result', {}).get('value')
            settle = lambda: ev("document.fonts.ready.then(() => new Promise(r => setTimeout(() => requestAnimationFrame(() => requestAnimationFrame(r)), 300)))", True)

            def shot(name):
                settle()
                if shots:
                    png = cdp.call('Page.captureScreenshot', {'format': 'png'}, timeout=30)
                    open(os.path.join(shots, f'voices-{name}-{"dark" if dark else "light"}-{w}.png'), 'wb').write(base64.b64decode(png['data']))

            def bad(msg):
                problems.append(f'{tag}: {msg}')

            def wait(js, what, secs=25):
                t0 = time.time()
                while not ev(f"!!({js})"):
                    if time.time() - t0 > secs:
                        bad(f'{what} never appeared (page errors: {ev("JSON.stringify(window.__errors)")})'); shot('timeout'); return False
                    time.sleep(0.2)
                return True

            def go(url):
                cdp.call('Page.navigate', {'url': 'about:blank'}, timeout=30)
                cdp.call('Page.navigate', {'url': url}, timeout=30)
                time.sleep(0.5)

            sheet = "document.querySelector('#view-library:not([hidden]) #voices')"
            fits = ("(() => { const d = document.querySelector('#voices'); const r = d.getBoundingClientRect();"
                    " return r.right <= innerWidth + 1 && d.scrollWidth <= d.clientWidth + 1 && document.documentElement.scrollWidth <= innerWidth; })()")
            lib = f'{base}?view=library&section=voices&mute=1&onboard=0'
            no_settings = "!document.querySelector('#settings-row') && ![...document.querySelectorAll('#view-library button, #view-library a, dialog')].some(b => /^Settings$/.test(b.textContent.trim()))"
            engine = "window.__scripts.some(s => /kokoro-(model|voice)\\.js/.test(s))"

            # 1. Not downloaded: Library's Voices section, reached by its deep link; no Settings page or row anywhere.
            go(f'{lib}#fit=absent')
            if not wait(f"{sheet} && document.querySelector('.vs-hifi[data-state=absent] .vs-get')", 'Library > Voices, not downloaded'): return
            if not ev(no_settings): bad('Library still offers a Settings row or sheet')
            if ev("document.querySelector('#voices').getBoundingClientRect().top") > ev("innerHeight") * 0.5: bad('the section link did not scroll Voices into view')
            tail = ev("[...document.querySelectorAll('#library-foot .lib-group > *')].map(n => n.id)")
            if tail[:2] != ['account-row', 'voices-more']: bad(f'Voices is not the foot row after Account (Decision 087): {tail}')
            if not ev("document.getElementById('voices-more').open"): bad('the deep link did not open the Voices disclosure')
            label = ev("document.querySelector('.vs-get').textContent")
            if label != 'Download (340 MB)': bad(f'the Download button reads {label!r}, want the manifest size')
            if ev("document.querySelectorAll('.vs-row[data-voice^=kokoro]').length"): bad('Kokoro voices listed before the download')
            rows = ev("document.querySelectorAll('.vs-row').length")
            if rows != 16: bad(f'{rows} device voice rows, want 16: six named, UK and Australia, the eight Pixel voices')
            if ev(engine): bad('the engine scripts loaded while the model is absent')
            if not ev(fits): bad('Voices is wider than the screen (not downloaded)')
            first = ev("document.querySelector('.vs-row .vc-name').textContent")
            if first != 'Ava (Premium)': bad(f'the best device voice is not first: {first!r}')
            shot('absent')
            # Move Samantha up: the order changes and is kept.
            ev("[...document.querySelectorAll('.vs-row')].find(r => r.querySelector('.vc-name').textContent === 'Samantha').querySelector('[aria-label=\"Move Samantha up\"]').click()")
            order = json.loads(ev("JSON.stringify([...document.querySelectorAll('.vs-row .vc-name')].map(n => n.textContent))"))
            if order.index('Samantha') >= 2: bad(f'Move up did not reorder: {order}')
            if 'system:' not in (ev("localStorage.getItem('ed.voices')") or ''): bad('the order was not kept')
            ev("localStorage.removeItem('ed.voices')")
            ev("window.__spoken.length = 0; document.querySelector('.vs-row .vc-hear').click()")
            time.sleep(0.3)
            sp = json.loads(ev("JSON.stringify(window.__spoken)") or '[]')
            if not sp or sp[0]['volume'] != 0: bad(f'a Hear under ?mute=1 was not muted: {sp[:1]}')

            # 2. Downloading: Download pressed; the stream stops partway.
            go(f'{lib}#fit=absent')
            if not wait("document.querySelector('.vs-hifi[data-state=absent] .vs-get:not([disabled])')", 'the Download button'): return
            ev("document.querySelector('.vs-get').click()")
            if not wait("document.querySelector('.vs-hifi[data-state=downloading] progress') && Number(document.querySelector('.vs-progress').value) > 50e6", 'download progress'): return
            prog = ev("document.querySelector('.vs-hifi .tabular').textContent")
            if not prog or not prog.endswith('of 340 MB'): bad(f'the progress reads {prog!r}')
            if not ev(fits): bad('Voices is wider than the screen (downloading)')
            shot('downloading')

            # 3. Downloaded: Kokoro first, attribution, Delete with the size; the device's voices folded.
            go(f'{lib}#fit=ready')
            if not wait("document.querySelector('.vs-hifi[data-state=ready]') && document.querySelectorAll('.vs-row[data-voice^=kokoro]').length", 'Library > Voices, downloaded'): return
            k = ev("document.querySelectorAll('.vs-row[data-voice^=kokoro]').length")
            if k != 28: bad(f'{k} Kokoro rows, want 28')
            if ev("document.querySelector('.vs-row .vc-name').textContent") != 'Heart (Kokoro)': bad('Heart (Kokoro) is not first')
            if 'Apache-2.0' not in (ev("(document.querySelector('.vs-credit') || {}).textContent") or ''): bad('no attribution under the voices')
            if ev("document.querySelector('.vs-delete').textContent") != 'Delete (340 MB)': bad('Delete does not name the size')
            # Hear on a Kokoro voice that cannot read the line (here: no phonemes) falls to a device voice, never silence (PLAYS-DESIGN 2.8 rule 10).
            ev("window.__spoken.length = 0; document.querySelector('.vs-row .vc-hear').click()")
            time.sleep(0.6)
            sp = json.loads(ev("JSON.stringify(window.__spoken)") or '[]')
            if not sp: bad('Hear on a Kokoro voice that cannot read the line said nothing')
            elif sp[0]['volume'] != 0: bad(f'that Hear was not muted: {sp[:1]}')
            if not ev(fits): bad('Voices is wider than the screen (downloaded)')
            shot('ready')

            # 4. The cast sheet with the Kokoro Defaults.
            go(f'{base}?play={script["id"]}&mute=1&onboard=0#fit=ready')
            if not wait("[...document.querySelectorAll('button')].some(b => /Record this/.test(b.textContent))", 'Record this'): return
            ev("[...document.querySelectorAll('button')].find(b => /Record this/.test(b.textContent)).click()")
            if not wait("document.querySelectorAll('.vc-chip').length > 0 && /Kokoro/.test(document.querySelector('.vc-chip').textContent)", 'Kokoro Default chips'): return
            chip = ev("document.querySelector('.vc-chip').textContent")
            if 'Heart (Kokoro)' not in chip: bad(f'the largest part is not read by Heart (Kokoro): {chip!r}')
            if 'Default' not in chip: bad(f'an untouched chip does not say Default: {chip!r}')
            if ev("!!document.querySelector('.vc-better')"): bad('"Better voices" offered with the voices here')
            if ev("document.documentElement.scrollWidth > innerWidth"): bad('the cast sheet scrolls sideways')
            shot('cast-ready')
            ev("document.querySelector('.vc-chip').click()")
            if wait("document.querySelector('dialog.vc-sheet[open] input[value=default]:checked')", 'the picker with Default checked'):
                shot('picker-default')
                ev("document.querySelector('dialog.vc-sheet[open]').close()")

            # 5. The cast sheet before the download: device-voice Defaults and the one offer.
            go(f'{base}?play={script["id"]}&mute=1&onboard=0#fit=absent')
            if not wait("[...document.querySelectorAll('button')].some(b => /Record this/.test(b.textContent)) || document.querySelector('.vc-chip')", 'Record this'): return
            if not ev("document.querySelector('.vc-chip')"):
                ev("[...document.querySelectorAll('button')].find(b => /Record this/.test(b.textContent)).click()")
            if not wait("document.querySelectorAll('.vc-chip').length > 0 && !document.querySelector('.vc-chip[data-state=none]')", 'device Default chips'): return
            if not wait("document.querySelector('.vc-better')", 'the Better voices offer'): return
            if ev("document.querySelectorAll('.vc-better').length") != 1: bad('more than one "Better voices" on the cast sheet')
            if ev(engine): bad('the engine scripts loaded on the cast sheet while the model is absent')
            shot('cast-absent')
            ev("document.querySelector('.vc-better').click()")
            if not wait(f"{sheet} && !document.querySelector('dialog[open]') && location.search.includes('section=voices')", 'Better voices opening Library at Voices'): return

            # 6. Unsupported: no WebGPU.
            go(f'{lib}#fit=unsupported')
            if not wait("document.querySelector('.vs-hifi[data-state=unsupported] .refusal')", 'the refusal without WebGPU'): return
            ref = ev("document.querySelector('.vs-hifi .refusal').textContent")
            if ref != 'This browser can’t run Kokoro voices.': bad(f'the refusal reads {ref!r}')
            if ev(engine): bad('the engine scripts loaded without WebGPU')
            shot('unsupported')
            # 7. Better voices at first launch (WEB-DESIGN 4.11b, PLAYS-DESIGN 2.8 rule 13): once at launch, Not now kept,
            #    once more at the first cast or record, then never; low storage said; never where the browser cannot run them.
            step = "document.querySelector('dialog#voices-step[open]')"
            ev("localStorage.removeItem('ed.voicesStep')")
            go(f'{base}?mute=1#fit=unsupported')
            time.sleep(1.5)
            if ev(step): bad('the step showed in a browser without WebGPU')
            go(f'{base}?mute=1#fit=absent')
            if not wait(f"{step} && document.querySelector('#voices-step .vs-get')", 'the first-launch step'): return
            if ev("document.querySelector('#voices-step .vs-get').textContent") != 'Download (340 MB)': bad('the step does not name the size on Download')
            if ev("document.querySelector('#voices-step h2').textContent") != 'Better voices': bad('the step is not headed Better voices')
            if ev("document.activeElement && document.activeElement.textContent") != 'Not now': bad('the step does not focus Not now')
            if ev("(() => { const r = document.querySelector('#voices-step').getBoundingClientRect(); return r.left < 0 || r.right > innerWidth + 1; })()"): bad('the step is wider than the screen')
            if ev(engine): bad('the step loaded the engine scripts')
            shot('step')
            ev("document.querySelector('#voices-step .vstep-close').click()")
            time.sleep(0.3)
            if ev(step): bad('Not now did not close the step')
            if ev("localStorage.getItem('ed.voicesStep')") != '1': bad('the launch offer was not recorded')
            go(f'{base}?mute=1#fit=absent')
            time.sleep(1.5)
            if ev(step): bad('the step showed again at the next launch')
            go(f'{base}?play={script["id"]}&mute=1#fit=absent')
            if not wait(step, 'the step at the first cast'): return
            ev("document.querySelector('#voices-step').close()")
            if ev("localStorage.getItem('ed.voicesStep')") != '2': bad('the first-use offer was not recorded')
            go(f'{base}?play={script["id"]}&mute=1#fit=absent')
            time.sleep(1.5)
            if ev(step): bad('the step showed a third time')
            go(f'{base}?mute=1&voices_step=1#fit=full')
            if not wait(f"{step} && document.querySelector('#voices-step .vs-get[disabled]')", 'the step on a full disk'): return
            full = ev("(document.querySelector('#voices-step .vs-error') || {}).textContent")
            if full != 'Not enough space: 310 MB free.': bad(f'the low-storage warning reads {full!r}')
            if ev("localStorage.getItem('ed.voicesStep')") != '2': bad('the door wrote the record')
            shot('step-full')

            errs = json.loads(ev("JSON.stringify(window.__errors)") or '[]')
            if errs: bad(f'page errors: {errs[:3]}')
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
