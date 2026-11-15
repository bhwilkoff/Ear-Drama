#!/usr/bin/env python3
"""Fit gate and frames for the studio inside the reader (WEB-DESIGN 4.16 item 14, PLAYS-DESIGN 2.9; Decision
076 S3), light and dark, at 320, 375, 430 and 1440 px, in headless Chrome over the DevTools protocol.

Nothing is heard and nothing is recorded from a real microphone. Before the page loads, `speechSynthesis` is a
stub that lists a fixed set of voices and ends each utterance after 0.6 s without speaking, and
`navigator.mediaDevices.getUserMedia` is a stub: a 160 Hz oscillator in its own AudioContext, never connected
to the speakers, whose level the harness sets (`__micGain`), or a refusal (`NotAllowedError`) while
`__denyMic` is set. Chrome runs with --mute-audio. The account is stubbed signed in after the page loads (no
reload follows), so recording is reachable without a real sign-in.

For each width and theme: cast a real play (Record this), Take part on the largest part (the cast sheet's
door, which must land in the reader's studio), then: the headphones gate; Start recording with the
microphone refused (the refusal frame); Start recording again (room tone, then the dock idle); Line by line,
Space records the current line (the recording frame: the line outlined red, the meter, "Recording"); Space
stops; R records it again; the take list (a sheet below the spread width, the panel beside the script from
it: the wide frame); delete the unchosen take.

Fails on: the cast sheet's door not opening the studio; a sideways scroll; a bottom bar taller than 72 px or
a dock row that wraps; the panel not beside the script at 1440 px or beside it below 860 px; a take-state
badge missing from a line of the part; the current line not outlined; no refusal when the microphone is
refused; the recording state not drawn; Record again not keeping the first take; a Delete offered on the
chosen take; a delete that leaves the take.

    python3 tools/web_fit_studio.py              # exit 1 on any problem
    python3 tools/web_fit_studio.py --shots DIR  # also write a PNG per frame
    python3 tools/web_fit_studio.py --widths 375,1440

The play is picked from the bundled castable scripts, never named: the first with four or more speaking parts.

Negative control (2026-11-14): js/studio.js with `who.append(b)` and `badges.set(lid, b)` removed fails with
"a line of the part has no take state: 0 badges for 81 lines".
"""
import base64, json, os, subprocess, sys, tempfile, time, urllib.request
from pathlib import Path

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import web_run  # noqa: E402

WIDTHS = (320, 375, 430, 1440)
BUNDLE = os.path.join(ROOT, 'catalog', 'plays', 'castable-scripts.json')

STUB = r"""(() => {
  const V = (name, voiceURI, lang, local = true, dflt = false) => ({ name, voiceURI, lang, localService: local, default: dflt });
  const all = [V('Samantha', 'v.samantha', 'en-US', true, true), V('Ava (Premium)', 'v.ava', 'en-US'), V('Daniel', 'v.daniel', 'en-GB'),
               V('Karen', 'v.karen', 'en-AU'), V('Moira', 'v.moira', 'en-IE'), V('Zoe (Enhanced)', 'v.zoe', 'en-US')];
  let list = [];
  const listeners = [];
  window.__errors = [];
  window.addEventListener('error', (e) => window.__errors.push(String(e.message)));
  window.addEventListener('unhandledrejection', (e) => window.__errors.push(String(e.reason)));
  const ce = console.error;
  console.error = (...a) => { window.__errors.push(a.map(x => (x && x.stack) || String(x)).join(' ')); ce(...a); };
  window.__spoken = [];
  const synth = {
    getVoices: () => list.slice(),
    speak(u) { window.__spoken.push(u.text); window.__last = u; setTimeout(() => { if (window.__last === u) { window.__last = null; u.onend && u.onend(); } }, 600); },
    cancel() { const u = window.__last; window.__last = null; if (u && u.onend) setTimeout(() => u.onend(), 0); },
    pause() {}, resume() {}, speaking: false, pending: false,
    addEventListener: (t, fn) => { if (t === 'voiceschanged') listeners.push(fn); },
    removeEventListener: (t, fn) => { const i = listeners.indexOf(fn); if (i >= 0) listeners.splice(i, 1); },
  };
  Object.defineProperty(window, 'speechSynthesis', { value: synth, configurable: true });
  window.SpeechSynthesisUtterance = function (text) { this.text = text; };
  setTimeout(() => { list = all; listeners.slice().forEach(fn => fn(new Event('voiceschanged'))); }, 300);
  // The microphone: an oscillator nobody hears, at a level the harness sets; or a refusal.
  window.__denyMic = false;
  Object.defineProperty(navigator, 'mediaDevices', { configurable: true, value: {
    enumerateDevices: async () => [],
    async getUserMedia() {
      if (window.__denyMic) throw new DOMException('Permission denied', 'NotAllowedError');
      const ctx = new AudioContext();
      const osc = ctx.createOscillator(); osc.frequency.value = 160;
      const g = ctx.createGain(); g.gain.value = 0.0005;
      const dest = ctx.createMediaStreamDestination();
      osc.connect(g); g.connect(dest); osc.start();
      await ctx.resume();
      window.__micGain = g;
      return dest.stream;
    } } });
  window.confirm = () => true;
})();"""

SIGN_IN = "API.account.signedIn = () => true; API.account.available = () => ({ apple: true, google: true }); true"


def launch(profile):
    proc = subprocess.Popen(
        [web_run.CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--mute-audio', '--no-first-run',
         '--no-default-browser-check', '--autoplay-policy=no-user-gesture-required', '--disable-features=Translate,MediaRouter',
         '--remote-debugging-port=0', f'--user-data-dir={profile}', 'about:blank'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    port_file = Path(profile) / 'DevToolsActivePort'
    t0 = time.time()
    while time.time() - t0 < 20:
        try:
            port = int(port_file.read_text().split()[0])
            pages = json.loads(urllib.request.urlopen(f'http://127.0.0.1:{port}/json/list', timeout=3).read())
            page = next((p for p in pages if p.get('type') == 'page'), None)
            if page:
                return proc, page['webSocketDebuggerUrl']
        except (OSError, ValueError, IndexError):
            pass
        time.sleep(0.1)
    web_run._kill(proc)
    raise RuntimeError('Chrome never exposed a debuggable page')


def pick_script():
    for s in json.load(open(BUNDLE))['scripts']:
        if len([r for r in s['roles'] if r['lines'] >= 1]) >= 4:
            return s
    raise SystemExit('no script with four parts in the bundle')


def main():
    shots = sys.argv[sys.argv.index('--shots') + 1] if '--shots' in sys.argv else None
    if shots:
        os.makedirs(shots, exist_ok=True)
    widths = [int(x) for x in sys.argv[sys.argv.index('--widths') + 1].split(',')] if '--widths' in sys.argv else WIDTHS
    script = pick_script()
    work = tempfile.mkdtemp(prefix='fit-studio-')
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
    largest = max(script['roles'], key=lambda r: r['lines'])
    print(f'script {script["id"]} ({len(script["lines"])} lines), part {largest["name"]!r} ({largest["lines"]} lines)')
    problems = []

    def run(w, dark):
        tag = f'{w} {"dark" if dark else "light"}'
        h = 900 if w > 600 else 760
        profile = tempfile.mkdtemp(prefix='fit-studio-chrome-')
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

            def shot(name):
                settle()
                if shots:
                    png = cdp.call('Page.captureScreenshot', {'format': 'png'}, timeout=30)
                    open(os.path.join(shots, f'studio-{name}-{"dark" if dark else "light"}-{w}.png'), 'wb').write(base64.b64decode(png['data']))

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
                  const rows = [...document.querySelectorAll('.st-status, .st-mode')].map(r => Math.round(r.getBoundingClientRect().height));
                  return { sideways: document.documentElement.scrollWidth > innerWidth, bar: Math.round(b.height), rows,
                           side: !document.querySelector('.st-side').hidden, sideW: Math.round(document.querySelector('.st-side').getBoundingClientRect().width),
                           per: getComputedStyle(document.querySelector('.rd')).getPropertyValue('--rd-per').trim() }; })())"""))
                if s['sideways']: bad(f'{where}: the page scrolls sideways')
                if s['bar'] > 72: bad(f'{where}: the bottom bar is {s["bar"]} px tall (wraps)')
                if any(r > 60 for r in s['rows']): bad(f'{where}: a dock row wraps {s["rows"]}')
                if w >= 900 and not s['side']: bad(f'{where}: the panel is not beside the script at {w} px')
                if w < 860 and s['side']: bad(f'{where}: the panel is beside the script at {w} px')
                return s

            cdp.call('Page.navigate', {'url': f'http://127.0.0.1:{port}/?play={script["id"]}&mute=1'}, timeout=30)
            if not wait("[...document.querySelectorAll('button')].some(b => /Record this/.test(b.textContent))", 'Record this'): return
            ev(SIGN_IN)
            ev("[...document.querySelectorAll('button')].find(b => /Record this/.test(b.textContent)).click()")
            if not wait("document.querySelector('button[aria-label^=\"Take part\"]')", 'Take part'): return
            ev("document.querySelector('button.btn-primary[aria-label^=\"Take part\"], button[aria-label^=\"Take part\"]').click()")
            if not wait("document.querySelector('.st-dock') && document.querySelector('.rd-line')", "the reader's studio from the cast sheet"): return
            settle()
            if 'read=' not in ev('location.search'): bad(f'the cast sheet did not land in the reader: {ev("location.search")}')
            n_badges = ev("document.querySelectorAll('.rd-take').length")
            if n_badges != largest['lines']: bad(f'a line of the part has no take state: {n_badges} badges for {largest["lines"]} lines')
            if not ev("!!document.querySelector('.rd-line.rd-cur')"): bad('no current line is outlined')
            fit('gate')
            if w in (375, 1440): shot('gate')
            # The microphone refused.
            ev("window.__denyMic = true; const c = document.getElementById('st-headphones'); c.click(); true")
            ev("document.querySelector('.st-go').click()")
            if wait("document.querySelector('.st-gate .refusal')", 'the refusal for a refused microphone', 8):
                txt = ev("document.querySelector('.st-gate .refusal').textContent")
                if 'needs the microphone' not in txt: bad(f'the refusal says {txt!r}')
                shot('denied')
            # Started: room tone, then the dock idle.
            ev("window.__denyMic = false; document.querySelector('.st-go').click()")
            if not wait("document.querySelector('.st-mode')", 'the dock after room tone', 15): return
            settle()
            fit('idle')
            if not ev("(() => { const n = document.querySelector('.rd-line.rd-cur'); const cr = document.querySelector('.rd-clip').getBoundingClientRect(); return n && [...n.getClientRects()].some(r => r.right > cr.left && r.left < cr.right); })()"):
                bad('the current line is not on the page')
            shot('idle')
            # Line by line: Space records the current line.
            ev("[...document.querySelectorAll('.st-mode input')].find(i => i.value === 'lines').click()")
            settle()
            cur = ev("document.querySelector('.rd-line.rd-cur').id")
            key(' ')
            if not wait("document.querySelector('.st-rec')", 'the microphone open after the cue', 10): return
            ev("window.__micGain.gain.value = 0.3")
            time.sleep(1.2)
            fit('recording')
            if not ev("!!document.querySelector('.rd-line.rd-rec')"): bad('the line being recorded is not outlined red')
            if not ev("document.querySelectorAll('.st-meter i').length === 40"): bad('no level meter while recording')
            shot('recording')
            ev("window.__micGain.gain.value = 0.0005")
            key(' ')
            if not wait(f"document.querySelector('#{cur} .rd-take[data-state=chosen]')", 'the take state after the take', 10): return
            # Record again keeps the first take.
            time.sleep(0.4)
            key('r')
            if not wait("document.querySelector('.st-rec')", 'the microphone open for Record again', 10): return
            ev("window.__micGain.gain.value = 0.3")
            time.sleep(0.8)
            ev("window.__micGain.gain.value = 0.0005")
            key(' ')
            if not wait(f"document.querySelector('#{cur} .rd-take-n') && document.querySelector('#{cur} .rd-take-n').textContent === '2'", 'two takes after Record again', 10): return
            settle()
            # The take list: the sheet below the spread width, the panel beside the script from it.
            if w < 860:
                ev("document.querySelector('.st-takes-btn').click()")
                if not wait("document.querySelector('dialog.st-sheet[open] .st-take')", 'the take list sheet', 5): return
            rows = json.loads(ev("JSON.stringify([...document.querySelectorAll('.st-takes .st-take')].map(r => ({ on: r.classList.contains('on'), checked: r.querySelector('input').checked, del: !!r.querySelector('.st-del') })))"))
            if len(rows) != 2: bad(f'the take list has {len(rows)} takes, want 2')
            elif not (rows[1]['on'] and rows[1]['checked'] and not rows[0]['on']): bad(f'the newest take is not the chosen one: {rows}')
            if any(r['on'] and r['del'] for r in rows): bad('a Delete is offered on the chosen take')
            if dark is False or w in (375, 1440): shot('takes' if w < 860 else 'wide')
            # A part another member holds names them, not a voice (the chip's row is replaced).
            if dark is False or w in (375, 1440):
                got = ev("(() => { const box = document.querySelector('.st-sec .vc-cast'); const ids = [...box.querySelectorAll('.vc-cast-row')].slice(1, 3).map(r => r.dataset.part); box.setNames({ [ids[0]]: 'Ada Lovelace', [ids[1]]: 'Grace H.' }); return JSON.stringify([...box.querySelectorAll('.vc-cast-who')].map(n => n.textContent)); })()")
                if json.loads(got) != ['Ada Lovelace', 'Grace H.']: bad(f'the cast does not show the performers: {got}')
                if ev("document.querySelectorAll('.st-sec .vc-cast-row .vc-chip').length") != ev("document.querySelectorAll('.st-sec .vc-cast-row').length") - 2: bad('a held part still shows a voice chip')
                shot('cast-names')
                ev("document.querySelector('.st-sec .vc-cast').setNames({})")
            if ev("(() => { const d = document.querySelector('dialog.st-sheet[open]'); return !!d && d.scrollWidth > d.clientWidth + 1; })()"): bad('the take list sheet scrolls sideways')
            ev("document.querySelector('.st-takes .st-del').click()")
            if not wait(f"document.querySelectorAll('.st-takes .st-take').length === 1 && document.querySelector('#{cur} .rd-take-n').textContent === '1'", 'the deleted take gone', 5): return
            if w < 860:
                ev("document.querySelector('dialog.st-sheet[open]').close()")
            # Step: a take opens its review in the bar; Keep makes my next line current.
            ev("[...document.querySelectorAll('.st-mode input')].find(i => i.value === 'step').click()")
            settle()
            key(' ')
            if not wait("document.querySelector('.st-rec')", 'the microphone open in Step', 10): return
            ev("window.__micGain.gain.value = 0.3")
            time.sleep(0.8)
            ev("window.__micGain.gain.value = 0.0005")
            key(' ')
            if not wait("document.querySelector('.st-transport [data-act=keep]')", "Step's review", 10): return
            fit('review')
            if ev("(() => { const b = document.querySelector('.rd-bottom'); return [...b.querySelectorAll('button')].some(x => { const r = x.getBoundingClientRect(); return r.width && (r.right > innerWidth + 1 || r.left < -1); }); })()"):
                bad("a button of Step's review is off the screen")
            if w in (320, 375, 1440): shot('review')
            key('Enter')
            if not wait(f"document.querySelector('.rd-line.rd-cur') && document.querySelector('.rd-line.rd-cur').id !== '{cur}'", "Keep moving to my next line", 5): return
            # Sync runs against the stubbed account and fails; that is the stub, not the studio.
            errs = [e for e in json.loads(ev("JSON.stringify(window.__errors)")) if not e.startswith('sync ')]
            if errs: bad(f'page errors: {errs}')
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
