"""Builds the prototype's model folder: the voice table (28 English voices, VOICES order, fp32),
a manifest with sizes, SHA-256s and licenses, and a phoneme file for some plays.

usage: python -I make_lab.py <model dir> <lab dir> <lib dir> <oov2.py> <script id>...
"""
import hashlib, json, os, shutil, sys, urllib.request, glob
import numpy as np
mdir, lab, lib, oov2 = sys.argv[1:5]
ids = sys.argv[5:]
REV = '1939ad2a8e416c0acfeecc08a694d14ef25f2231'
B = f'https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/{REV}/voices/'
ORDER = ['af_heart', 'af_alloy', 'af_aoede', 'af_bella', 'af_jessica', 'af_kore', 'af_nicole', 'af_nova', 'af_river', 'af_sarah', 'af_sky',
         'am_adam', 'am_echo', 'am_eric', 'am_fenrir', 'am_liam', 'am_michael', 'am_onyx', 'am_puck', 'am_santa',
         'bf_alice', 'bf_emma', 'bf_isabella', 'bf_lily', 'bm_daniel', 'bm_fable', 'bm_george', 'bm_lewis']
os.makedirs(os.path.join(mdir, 'voices'), exist_ok=True)
os.makedirs(lab, exist_ok=True)
table = []
for v in ORDER:
    p = os.path.join(mdir, 'voices', f'{v}.bin')
    if not os.path.exists(p):
        urllib.request.urlretrieve(B + f'{v}.bin', p)
    a = np.fromfile(p, dtype=np.float32)
    assert a.size == 510 * 256, (v, a.size)
    table.append(a)
np.concatenate(table).astype(np.float32).tofile(os.path.join(lab, 'voices-en.bin'))
shutil.copy(os.path.join(mdir, 'onnx', 'model_q8f16.onnx'), os.path.join(lab, 'model_q8f16.onnx'))
shutil.copy(os.path.join(mdir, 'tokenizer.json'), os.path.join(lab, 'tokenizer.json'))
def entry(path, role):
    b = open(os.path.join(lab, path), 'rb').read()
    return {'path': path, 'role': role, 'bytes': len(b), 'sha256': hashlib.sha256(b).hexdigest(), 'license': 'Apache-2.0'}
man = {'format': 1, 'name': 'Kokoro-82M v1.0', 'source': f'https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/tree/{REV}',
       'files': [entry('model_q8f16.onnx', 'model'), entry('voices-en.bin', 'voices'), entry('tokenizer.json', 'vocab')]}
json.dump(man, open(os.path.join(lab, 'manifest.json'), 'w'), indent=1)
print('manifest', sum(f['bytes'] for f in man['files']), [(f['path'], f['bytes']) for f in man['files']])

# Phonemes for the asked plays, US and GB, through the measured pipeline (misaki + rules + neural fallback).
src = open(oov2).read()
ns = {}
exec('import re, unicodedata, json\nfrom misaki import en\n' + src[src.index('def raw_text'):src.index('lines = [')], ns)
exec(src[src.index('# ---- neural fallback'):src.index('# ---- rules ----')], ns)
exec(src[src.index('# ---- rules ----'):src.index('STAGE = 0')], ns)
from misaki import en
def make(british):
    g = en.G2P(trf=False, british=british, fallback=None)
    ctx = en.TokenContext()
    known = lambda w: g.lexicon.get_word(w, 'NN', None, ctx)[0]
    def fb(tk):
        w = tk.text
        for c in ns['elision'](w):
            if c in ns['EXTRA']:
                return ns['EXTRA'][c], 2
            ps = [known(p) for p in c.split(' ')]
            if all(ps):
                return ' '.join(ps), 2
        if w.isalpha():
            for c in ns['spelling_variants'](w):
                ps = known(c)
                if ps:
                    return ps, 2
        return ns['neural_ps'](w), 1
    g.fallback = fb
    return g
us, gb = make(False), make(True)
os.makedirs(os.path.join(lab, 'phonemes'), exist_ok=True)
by_id = {}
for f in glob.glob(os.path.join(lib, 'scripts', '*.json')):
    for s in json.load(open(f))['scripts']:
        by_id[s['id']] = s
for sid in ids:
    s = by_id[sid]
    rows = []
    for l in s['lines']:
        if l['kind'] != 'speech':
            continue
        t = ns['raw_text'](l)
        if not t:
            continue
        n = ns['normalize'](t)
        rows.append({'id': l['id'], 't': t, 'us': us(n)[0].replace('❓', ''), 'gb': gb(n)[0].replace('❓', '')})
    out = {'format': 1, 'id': sid, 'revision': s['revision'], 'g2p': 'misaki 0.9.4 + rules + g2p_en fallback (spike)', 'lines': rows}
    p = os.path.join(lab, 'phonemes', f'{sid}.json')
    json.dump(out, open(p, 'w'), ensure_ascii=False, separators=(',', ':'))
    raw = sum(len(r['t'].encode()) for r in rows)
    print(sid, len(rows), 'lines', os.path.getsize(p), 'bytes; text alone', raw)
