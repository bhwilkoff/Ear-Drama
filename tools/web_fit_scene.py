#!/usr/bin/env python3
"""Fit gate and frames for recording one scene (PLAYS-DESIGN §2.12, WEB-DESIGN 4.15): Record's Scenes for two voices,
a scene card pressed, the scene's cast sheet, Take part, and the studio over the scene, at 375 px (inside an iframe
that wide: headless Chrome will not lay a page out narrower than about 500) and 1440 px, light and dark.

Fails on: no recording scene card (a library without `scenes[].to`); the card not landing on a cast sheet; a cast
sheet whose title is not the play's with the heading, or whose speaking parts are not the scene's; Take part not
landing in the studio; a studio line outside the scene's range; a sideways scroll.

The library is the local build (catalog/out/plays-library, built with `--no-phonemes` is enough); the rest of /data/
is proxied to the published projection, as tools/web_fit_plays.py does. Chrome runs muted, every URL carries
?mute=1, nothing is recorded, the account is signed out, and the browser and server stop on the way out.

    python3 tools/web_fit_scene.py --shots DIR

Negative control (2026-11-26): js/plays-store.js `script(p)` returning `whole` instead of `C.scoped(cur, whole)`
fails with "the cast sheet lists parts outside the scene" and "a studio line outside the scene".
"""
import json, os, re, shutil, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
from web_fit_label import launch  # noqa: E402
from web_fit_plays import FRAME, serve  # noqa: E402

DOC = "(() => { const f = document.querySelector('iframe#fit'); return f ? f.contentDocument : document; })()"
WIN = "(() => { const f = document.querySelector('iframe#fit'); return f ? f.contentWindow : window; })()"


def main():
    shots = sys.argv[sys.argv.index('--shots') + 1] if '--shots' in sys.argv else None
    data = sys.argv[sys.argv.index('--data') + 1] if '--data' in sys.argv else 'https://eardrama.org/data/'
    library = sys.argv[sys.argv.index('--library') + 1] if '--library' in sys.argv else os.path.join(ROOT, 'catalog', 'out', 'plays-library')
    widths = [int(w) for w in sys.argv[sys.argv.index('--widths') + 1].split(',')] if '--widths' in sys.argv else [375, 1440]
    index = json.load(open(os.path.join(library, 'index.json')))
    if not any(s.get('to') for r in index['plays'] for s in r.get('scenes') or []):
        print('FAIL: the library has no scenes[].to: rebuild it (catalog/tools/build_play_library.py --no-phonemes)')
        return 1
    if shots:
        os.makedirs(shots, exist_ok=True)
    work = tempfile.mkdtemp(prefix='fit-scene-')
    for f in os.listdir(ROOT):
        if f not in ('.git', 'build', 'android', 'apple', 'catalog', 'docs', 'worker', 'windows', 'data'):
            os.symlink(os.path.join(ROOT, f), os.path.join(work, f))
    srv, port = serve(work, library, data, {'on': False})
    profile = tempfile.mkdtemp(prefix='fit-scene-chrome-')
    proc = None
    problems = 0
    try:
        proc, cdp = launch(profile)
        cdp.call('Page.enable')

        def ev(expr, awaitp=False):
            r = cdp.call('Runtime.evaluate', {'expression': expr, 'returnByValue': True, 'awaitPromise': awaitp}, timeout=30)
            return r.get('result', {}).get('value')

        def wait(rx, secs=60):
            t0 = time.time()
            while time.time() - t0 < secs:
                if re.search(rx, ev(f"{DOC}.body ? {DOC}.body.innerText : ''") or ''):
                    time.sleep(1.5)
                    return True
                time.sleep(0.3)
            return False

        def shot(name, w, dark):
            ev(f"{DOC}.fonts.ready.then(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))))", True)
            if not shots:
                return
            import base64
            png = cdp.call('Page.captureScreenshot', {'format': 'png'})['data']
            open(os.path.join(shots, f'scene-{name}-{w}-{"d" if dark else "l"}.png'), 'wb').write(base64.b64decode(png))

        for dark in (False, True):
            for w in widths:
                bad = []
                h = 1100 if w < 600 else 1000
                url = f'http://127.0.0.1:{port}/?view=record&scenes=2&mute=1&fresh={int(time.time() * 1000)}'
                if w < 600:
                    fn = f'frame-scene-{w}-{"d" if dark else "l"}.html'
                    open(os.path.join(work, fn), 'w').write(FRAME % (url, w, h))
                    url = f'http://127.0.0.1:{port}/{fn}'
                cdp.call('Emulation.setDeviceMetricsOverride', {'width': w if w > 600 else 600, 'height': h, 'deviceScaleFactor': 1, 'mobile': False})
                cdp.call('Emulation.setEmulatedMedia', {'features': [{'name': 'prefers-color-scheme', 'value': 'dark' if dark else 'light'}]})
                cdp.call('Page.navigate', {'url': url}, timeout=30)
                if not ev(f"new Promise(r => {{ const t0 = Date.now(); (function k() {{ const d = {DOC}; if (d && d.querySelector('.pl-scard-rec')) return r(true); if (Date.now() - t0 > 60000) return r(false); setTimeout(k, 300); }})(); }})", True):
                    bad.append('no recording scene card')
                    print(f'FAIL scene {w} {"dark" if dark else "light"}: {bad}')
                    problems += 1
                    continue
                time.sleep(2)
                shot('cards', w, dark)
                card = json.loads(ev(f"(() => {{ const b = {DOC}.querySelector('.pl-scard-rec'); const read = b.parentElement.querySelector('.g-tile-read'); const out = {{ label: b.getAttribute('aria-label'), read: read ? read.getAttribute('href') : null }}; b.click(); return JSON.stringify(out); }})()"))
                if not card['read'] or 'line=' not in card['read']:
                    bad.append('no Read on the card\'s corner opening the reader at the line')
                if not wait(r'Take part'):
                    bad.append('the card did not open a cast sheet')
                rec = json.loads(ev(f"{WIN}.eval('PlaysUI').openStore().then(s => {{ const p = s.productions[0]; return s.wholeScript(p).then(x => {{ const ids = x.lines.map(l => l.id); const r = p.range || {{}}; const a = ids.indexOf(r.from), z = ids.indexOf(r.to); return JSON.stringify({{ p, lines: a >= 0 && z >= a ? ids.slice(a, z + 1) : [] }}); }}); }})", True) or '{}')
                p = rec.get('p') or {}
                rng = p.get('range')
                if not rng:
                    bad.append('the production has no range')
                title = ev(f"{DOC}.querySelector('#plays-h') ? {DOC}.querySelector('#plays-h').textContent : ''") or ''
                if ', ' not in title:
                    bad.append(f'the cast sheet title is not the play\'s with the heading: {title!r}')
                inrange = set(rec.get('lines') or [])
                names = json.loads(ev(f"JSON.stringify([...{DOC}.querySelectorAll('.pl-grid .pl-part-name')].map(n => n.textContent))") or '[]')
                speaking = [n for n in names if n not in ('Sound', 'Stage directions')]
                if not (2 <= len(speaking) <= 4) or len(speaking) != len([k for k in (p.get('parts') or {}) if k.startswith('role:')]):
                    bad.append(f'the cast sheet lists parts outside the scene: {len(speaking)} speaking parts')
                if ev(f"{DOC}.documentElement.scrollWidth > {WIN}.innerWidth"):
                    bad.append('the cast sheet scrolls sideways')
                shot('sheet', w, dark)
                ev(f"(() => {{ const b = [...{DOC}.querySelectorAll('form.take-form button[type=submit]')][0]; if (b) b.click(); }})()")
                if not wait(r'Start recording|Headphones|headphones'):
                    bad.append('Take part did not land in the studio')
                lines = ev(f"JSON.stringify([...{DOC}.querySelectorAll('.rd-line[data-line]')].map(n => n.dataset.line))")
                ids = json.loads(lines or '[]')
                out = [i for i in ids if i not in inrange]
                if not ids:
                    bad.append('the studio drew no lines')
                if out:
                    bad.append(f'a studio line outside the scene: {out[:3]}')
                if ev(f"{DOC}.documentElement.scrollWidth > {WIN}.innerWidth"):
                    bad.append('the studio scrolls sideways')
                shot('studio', w, dark)
                print(f'{"FAIL" if bad else "ok  "} scene {w} {"dark" if dark else "light"}: {title!r}, {len(speaking)} voices, '
                      f'{len(ids)} studio lines of {len(inrange)} in range {rng}' + (f' :: {bad}' if bad else ''))
                problems += bool(bad)
                ev(f"{WIN}.indexedDB.databases ? {WIN}.indexedDB.databases().then(ds => Promise.all(ds.map(d => new Promise(r => {{ const q = {WIN}.indexedDB.deleteDatabase(d.name); q.onsuccess = q.onerror = q.onblocked = () => r(); }})))) : null", True)
    finally:
        if proc:
            proc.terminate()
            proc.wait(timeout=10)
        srv.shutdown()
        shutil.rmtree(profile, ignore_errors=True)
        shutil.rmtree(work, ignore_errors=True)
    print(f'{"FAIL" if problems else "PASS"}: {problems} problem frames')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
