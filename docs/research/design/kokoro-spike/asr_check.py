"""Intelligibility by transcription: render real play lines with Kokoro at each precision, transcribe
with a local Whisper (faster-whisper base.en, CPU), and score word error rate against the text.
Nothing is played; WAVs go to the scratch dir only.

usage: python -I asr_check.py <lib dir> <model dir> <oov2.py> <wav dir> <out json> [n_lines]
"""
import json, os, random, re, sys, glob
import numpy as np, onnxruntime as ort, soundfile as sf
from misaki import en

lib, mdir, oov2, wdir, out_path = sys.argv[1:6]
n_lines = int(sys.argv[6]) if len(sys.argv) > 6 else 60
os.makedirs(wdir, exist_ok=True)

src = open(oov2).read()
ns = {}
exec('import re, unicodedata, json\nfrom misaki import en\n' + src[src.index('def raw_text'):src.index('lines = [')], ns)
exec(src[src.index('# ---- neural fallback'):src.index('# ---- rules ----')], ns)
exec(src[src.index('# ---- rules ----'):src.index('STAGE = 0')], ns)
normalize, raw_text, neural_ps, elision, spelling_variants, EXTRA = (ns[k] for k in
    ('normalize', 'raw_text', 'neural_ps', 'elision', 'spelling_variants', 'EXTRA'))

g2p = en.G2P(trf=False, british=False, fallback=None)
CTX = en.TokenContext()
known = lambda w: g2p.lexicon.get_word(w, 'NN', None, CTX)[0]
guessed = []
def fallback(tk):
    w = tk.text
    for c in elision(w):
        if c in EXTRA:
            return EXTRA[c], 2
        ps = [known(p) for p in c.split(' ')]
        if all(ps):
            return ' '.join(ps), 2
    if w.isalpha():
        for c in spelling_variants(w):
            ps = known(c)
            if ps:
                return ps, 2
    guessed.append(w)
    return neural_ps(w), 1
g2p.fallback = fallback

scripts = []
for f in sorted(glob.glob(os.path.join(lib, 'scripts', '*.json'))):
    scripts += json.load(open(f))['scripts']
lines = [raw_text(l) for s in scripts for l in s['lines'] if l['kind'] == 'speech' and raw_text(l)]
random.seed(1115)
# Lines a listener can judge: 2 to 60 words (Kokoro's sweet spot is 100-200 tokens; short lines are its weak spot).
pick = [t for t in random.sample(lines, 4000) if 2 <= len(t.split()) <= 60][:n_lines]

vocab = json.load(open(os.path.join(mdir, 'tokenizer.json')))['model']['vocab']
def style(name, n):
    v = np.fromfile(os.path.join(mdir, 'voices', f'{name}.bin'), dtype=np.float32).reshape(-1, 1, 256)
    return v[min(n, len(v) - 1)]

from faster_whisper import WhisperModel
asr = WhisperModel('base.en', device='cpu', compute_type='int8')

def words(t):
    t = t.lower().replace('’', "'")
    t = re.sub(r"[^a-z' ]", ' ', t)
    return [w.strip("'") for w in t.split() if w.strip("'")]
def wer(ref, hyp):
    r, h = words(ref), words(hyp)
    d = list(range(len(h) + 1))
    for i, a in enumerate(r, 1):
        prev, d[0] = d[0], i
        for j, b in enumerate(h, 1):
            prev, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, prev + (a != b))
    return d[-1], len(r)

phon = []
for t in pick:
    guessed.clear()
    ps, _ = g2p(normalize(t))
    phon.append((t, ps.replace('❓', ''), list(guessed)))

models = ['model', 'model_fp16', 'model_q8f16', 'model_quantized']
voices = ['af_heart', 'am_michael']
report = {'lines': len(pick), 'models': {}}
for m in models:
    sess = ort.InferenceSession(os.path.join(mdir, 'onnx', f'{m}.onnx'), providers=['CPUExecutionProvider'])
    names = [i.name for i in sess.get_inputs()]
    res = {}
    for v in voices:
        E = N = 0
        short_E = short_N = 0
        per_line = []
        for i, (t, ps, g) in enumerate(phon):
            ids = [vocab[c] for c in ps if c in vocab][:510]
            audio = sess.run(None, {names[0]: np.array([[0, *ids, 0]], dtype=np.int64), names[1]: style(v, len(ids)),
                                    names[2]: np.array([1.0], dtype=np.float32)})[0].reshape(-1)
            p = os.path.join(wdir, f'{m}_{v}_{i}.wav')
            sf.write(p, audio, 24000)
            a16 = np.nan_to_num(np.interp(np.arange(0, len(audio), 1.5), np.arange(len(audio)), audio)).astype(np.float32)
            segs, _ = asr.transcribe(a16, beam_size=1, language='en')
            hyp = ' '.join(s.text for s in segs)
            e, n = wer(t, hyp)
            E += e; N += n
            if len(ids) < 20:
                short_E += e; short_N += n
            per_line.append({'i': i, 'tokens': len(ids), 'wer': round(e / max(1, n), 2), 'ref': t[:90], 'hyp': hyp[:90], 'guessed': g})
        res[v] = {'wer_pct': round(100 * E / N, 1), 'short_lines_wer_pct': round(100 * short_E / max(1, short_N), 1) if short_N else None,
                  'worst': sorted(per_line, key=lambda x: -x['wer'])[:5]}
        print(m, v, res[v]['wer_pct'], 'short', res[v]['short_lines_wer_pct'], flush=True)
    report['models'][m] = res
    del sess
json.dump(report, open(out_path, 'w'), ensure_ascii=False, indent=1)
for m, r in report['models'].items():
    for v, x in r.items():
        for w in x['worst'][:3]:
            print(m, v, w)
