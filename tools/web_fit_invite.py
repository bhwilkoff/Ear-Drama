#!/usr/bin/env python3
"""Fit gate and frames for the invitation, the finished ear dramas and a finished drama's page (WEB-DESIGN 4.10c):
signed out and signed in, light and dark, at 320, 375, 390 and 430 px. Button rows stay on one line, the page never
scrolls sideways, no tile name overflows, a signed-out invitation shows every part, the play control of each held part
and Take part, and nothing sits in front of the page. The Worker is a stub inside the page (fetch is answered with
fixtures); the catalog reads are live. Muted; never presses Play.

    python3 tools/web_fit_invite.py              # exit 1 on any problem
    python3 tools/web_fit_invite.py --shots DIR  # also write a PNG per frame

Negative control: `--break` removes the Take part button's account check and the first held part's play control from
the fixture; the signed-out checks fail.
"""
import json, os, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import web_run  # noqa: E402

TOKEN = 'A' * 43
SCRIPT = 'gut-47826'
REVISION = 'd1bcacfd08c1'
PARTS = ['EBEN', 'CLAP', 'HOR', 'TIM', 'OAK', 'PIC', 'LOOP', 'directions']


def fixtures(scripts):
    s = next(x for x in scripts if x['id'] == SCRIPT)
    speech = [l for l in s['lines'] if l['kind'] == 'speech']
    held = {'EBEN': 'Pat', 'CLAP': 'Sam', 'HOR': 'Ada'}
    chosen, takes = {}, []
    for l in speech:
        if l['role'] in held:
            chosen[l['id']] = f"t-{l['id']}"
            takes.append({'id': f"t-{l['id']}", 'lineID': l['id'], 'part': 'role:' + l['role'], 'frames': 24000, 'sampleRate': 24000, 'audio': 'wav'})
    parts = []
    for p in PARTS:
        n = 24 if p == 'directions' else sum(1 for l in speech if l['role'] == p)
        parts.append({'id': p if p == 'directions' else 'role:' + p, 'lineCount': n, 'status': 'done' if p in held else 'open', **({'performer': held[p]} if p in held else {})})
    invite = {'id': 'p1', 'scriptID': SCRIPT, 'scriptRevision': REVISION, 'title': s['title'], 'parts': parts,
              'members': [{'name': 'Pat', 'director': True}, {'name': 'Sam', 'director': False}, {'name': 'Ada', 'director': False}],
              'takes': takes, 'chosen': chosen, 'next': 'TIM', 'archive': None, 'uploads': True}
    names = ['Pat', 'Sam', 'Ada', 'Lou', 'Kim', 'Jo']
    dramas = []
    for i, sid in enumerate(['gut-47826', 'gut-28051', 'gut-7364', 'gut-2265', 'gut-49295']):
        sc = next(x for x in scripts if x['id'] == sid)
        roles = [r['name'] for r in sc['roles']][:6]
        dramas.append({'id': f'd{i}', 'script_id': sid, 'title': sc['title'].strip(), 'source': sc['source'],
                       'credits': [{'part': 'role:' + r, 'name': names[(i + j) % len(names)] if j != 3 else ''} for j, r in enumerate(roles)],
                       'archive_url': f'https://archive.org/details/eardrama-d{i}', 'published_at': 1761800000000 - i * 86400000 * 9})
    return invite, {'productions': dramas, 'next_cursor': None}


STUB = r"""(() => {
  const F = %s;
  const orig = window.fetch.bind(window);
  const json = (o, status = 200) => Promise.resolve(new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } }));
  window.fetch = (input, init) => {
    const u = String(input && input.url ? input.url : input);
    if (u.includes('archive.org/metadata/')) return u.endsWith('eardrama-d1') ? json({ files: [{ name: 'eardrama-d1_meta.xml', format: 'Metadata' }] })
      : json({ files: [{ name: 'a.wav', format: 'WAV' }, { name: 'a_64kb.mp3', format: '64Kbps MP3' }, { name: 'a.mp3', format: 'VBR MP3' }, { name: 'p.mp3', format: 'VBR MP3', private: true }] });
    if (u.includes('/v1/plays/finished/')) { const id = decodeURIComponent(u.split('/finished/')[1].split('?')[0]); const d = F.finished.productions.find(x => x.id === id); return d ? json(d) : json({ error: 'not_found' }, 404); }
    if (u.includes('/v1/plays/finished')) return json(F.finished);
    if (u.includes('/v1/plays/open/invite/takes/')) return Promise.resolve(new Response(new ArrayBuffer(44)));
    if (u.includes('/v1/plays/open/invite')) return F.gone ? json({ error: 'invite_gone' }, 410) : json(F.invite);
    if (u.includes('/v1/plays/invites/view')) return json({ ...F.invite, member: false });
    if (u.endsWith('plays/castable-scripts.json')) return orig('/castable.json');
    return orig(input, init);
  };
  sessionStorage.setItem('ed.invite', %s);
  if (F.signed) { const t = setInterval(() => { if (typeof API !== 'undefined' && API.account) { API.account.signedIn = () => true; clearInterval(t); } }, 1); }
  %s
})()"""

CHECK = r"""(() => {
  const bad = [];
  document.querySelectorAll('.btn, .pl-play-dot').forEach(b => { const r = b.getBoundingClientRect(); if (r.width && r.height > 64) bad.push('button wraps: ' + b.textContent.slice(0, 20)); });
  const de = document.documentElement;
  if (de.scrollWidth > innerWidth) bad.push(`page scrolls sideways: ${de.scrollWidth} > ${innerWidth}`);
  document.querySelectorAll('.g-name').forEach(n => { if (n.scrollWidth > n.clientWidth + 1) bad.push('tile name overflows: ' + n.textContent.slice(0, 30)); });
  const q = (s) => document.querySelectorAll(s).length;
  const kind = %s, out = %s;
  const vis = (id) => { const e = document.getElementById(id); return e && !e.hidden; };
  if (kind === 'invite') {
    if (!vis('view-invite')) bad.push('invitation not shown');
    if (q('#invite-body .pl-part') !== 8) bad.push('parts drawn: ' + q('#invite-body .pl-part'));
    if (q('#invite-body .pl-play-dot') !== 3) bad.push('play controls: ' + q('#invite-body .pl-play-dot'));
    const take = [...document.querySelectorAll('#invite-body .pl-part-acts .btn')].filter(b => b.textContent.trim() === 'Take part').length;
    if (take !== 5) bad.push('Take part buttons: ' + take);
    if (q('dialog[open]')) bad.push('a dialog sits in front of the page');
    if (!document.querySelector('#invite-body .g-head-name')) bad.push('no head board');
    if (out && !document.querySelector('#invite-body .pl-part-acts .pl-play-dot')) bad.push('signed out lost the takes');
    if (!out && !document.getElementById('pl-performer')) bad.push('signed in has no name field');
  }
  if (kind === 'preparing' && document.querySelector('#drama-body .drama-listen .btn')) bad.push('a Play button with no file');
  if (kind === 'gone' && !/has ended/.test(document.getElementById('invite-body').textContent)) bad.push('gone not said');
  if (kind === 'dramas') {
    if (q('#browse-body .g-tile') !== 5) bad.push('tiles: ' + q('#browse-body .g-tile'));
    if (!document.querySelector('#browse-body .g-facts')) bad.push('no credits');
    if (document.getElementById('browse-filters').offsetParent) bad.push('filters shown on the dramas scope');
  }
  if (kind === 'home' && !document.querySelector('#dramas-h')) bad.push('Home has no New ear dramas shelf');
  if (kind === 'drama') {
    if (q('#drama-body .cast-row') !== 6) bad.push('bill rows: ' + q('#drama-body .cast-row'));
    if (!/Pat/.test(document.getElementById('drama-body').textContent)) bad.push('credits missing');
    if (q('#drama-body a[href*="archive.org"]') !== 1) bad.push('no View on archive.org link');
    if (!document.querySelector('#drama-body .drama-listen .btn-primary')) bad.push('no Play button');
    const pl = document.querySelector('#drama-body .drama-listen .btn-primary'), sh = document.querySelector('#drama-body .actions .btn-ghost');
    if (pl && sh && Math.abs(pl.getBoundingClientRect().top - sh.getBoundingClientRect().top) > 4) bad.push('Play and Share are on different rows');
  }
  return JSON.stringify(bad);
})()"""

FRAMES = [  # name, path, kind, ready, signed
    ('invite-out', '/?view=invite&mute=1', 'invite', r'Take part', False),
    ('invite-in', '/?view=invite&mute=1', 'invite', r'Take part', True),
    ('invite-gone', '/?view=invite&mute=1', 'gone', r'has ended', False),
    ('dramas', '/?view=browse&scope=dramas&mute=1', 'dramas', r'ear dramas', False),
    ('drama', '/?drama=d0&mute=1', 'drama', r'Play', False),
    ('drama-wait', '/?drama=d1&mute=1', 'preparing', r'still being prepared', False),
    ('home', '/?mute=1', 'home', r'New ear dramas', False),
]


def main():
    shots = sys.argv[sys.argv.index('--shots') + 1] if '--shots' in sys.argv else None
    broke = '--break' in sys.argv
    if shots:
        os.makedirs(shots, exist_ok=True)
    scripts = json.load(open(os.path.join(ROOT, 'catalog/plays/castable-scripts.json')))['scripts']
    invite, finished = fixtures(scripts)
    if broke:
        invite['chosen'] = {}
        invite['parts'] = invite['parts'][:3]
    work = tempfile.mkdtemp(prefix='fit-invite-')
    for f in os.listdir(ROOT):
        if f not in ('index.html', '.git', 'build', 'android', 'apple', 'catalog', 'docs', 'worker', 'windows'):
            os.symlink(os.path.join(ROOT, f), os.path.join(work, f))
    os.symlink(os.path.join(ROOT, 'catalog/plays/castable-scripts.json'), os.path.join(work, 'castable.json'))
    html = open(os.path.join(ROOT, 'index.html')).read().replace(
        '<head>', '<head><meta name="ed-data" content="https://eardrama.org/data/">', 1)
    open(os.path.join(work, 'index.html'), 'w').write(html)
    srv_code = ("import sys,http.server,functools\n"
                "class S(http.server.ThreadingHTTPServer):\n request_queue_size=256\n daemon_threads=True\n"
                "class H(http.server.SimpleHTTPRequestHandler):\n def log_message(self,*a): pass\n"
                "S(('127.0.0.1',int(sys.argv[1])),functools.partial(H,directory=sys.argv[2])).serve_forever()\n")
    port = 8300 + os.getpid() % 500
    srv = subprocess.Popen([sys.executable, '-c', srv_code, str(port), work], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)
    state = {'dark': False, 'out': [], 'kind': '', 'signed': False}
    orig = web_run.CDP.call

    def call(self, method, params=None, timeout=20):
        if method == 'Page.navigate':
            orig(self, 'Emulation.setEmulatedMedia', {'features': [
                {'name': 'prefers-color-scheme', 'value': 'dark' if state['dark'] else 'light'}]})
            account = "localStorage.setItem('ed.account', JSON.stringify({user_id:'u1'}));" if state['signed'] else ''
            data = {'invite': invite, 'finished': finished, 'gone': state['kind'] == 'gone', 'signed': state['signed']}
            orig(self, 'Page.addScriptToEvaluateOnNewDocument',
                 {'source': STUB % (json.dumps(data), json.dumps(TOKEN), account)})
        if method == 'Page.captureScreenshot':
            r = orig(self, 'Runtime.evaluate', {'expression': CHECK % (
                json.dumps(state['kind']), 'false' if state['signed'] else 'true'), 'returnByValue': True})
            state['out'] = json.loads(r['result']['value'])
        return orig(self, method, params, timeout)
    web_run.CDP.call = call
    problems = 0
    try:
        for name, path, kind, ready, signed in FRAMES:
            for dark in (False, True):
                for w in (320, 375, 390, 430):
                    state.update(dark=dark, kind=kind, signed=signed, out=['never measured'])
                    out = os.path.join(shots, f'{name}-{"dark" if dark else "light"}-{w}.png') if shots else os.path.join(work, 'fit.png')
                    web_run.shoot(f'http://127.0.0.1:{port}{path}', w, 900, out, ready)
                    problems += len(state['out'])
                    print(('FAIL ' if state['out'] else 'ok   ') + f"{name} {w} {'dark' if dark else 'light'} {state['out'] or ''}")
    finally:
        srv.terminate()
    print(f'{"FAIL" if problems else "PASS"}: {problems} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
