"""Kokoro-82M ONNX real-time factor on this Mac, per precision, CPU only.

usage: python -I bench.py <model dir> <wav out dir> <threads>
Nothing is played. Each WAV is written to the scratch dir and measured (duration, RMS,
voiced fraction, envelope correlation with the fp32 render of the same line).
"""
import json, os, sys, time, resource
import numpy as np, onnxruntime as ort, soundfile as sf
from misaki import en

mdir, wdir, threads = sys.argv[1], sys.argv[2], int(sys.argv[3])
os.makedirs(wdir, exist_ok=True)
vocab = json.load(open(os.path.join(mdir, 'tokenizer.json')))['model']['vocab']
g2p = en.G2P(trf=False, british=False, fallback=None)

LINES = [
    "Nothing will come of nothing: speak again.",
    "Come in.",
    "Well, Molly, I've been thinking it over, and I don't see why we shouldn't have the Doc over for supper on Sunday.",
    "The quality of mercy is not strain'd; it droppeth as the gentle rain from heaven upon the place beneath.",
    "I cannot wish the fault undone, the issue of it being so proper.",
    "But I have a son, sir, by order of law, some year elder than this, who yet is no dearer in my account: though this knave came something saucily to the world before he was sent for, yet was his mother fair; there was good sport at his making, and the whoreson must be acknowledged.",
    "Anybody home?",
    "Tea?",
]

def tokens(ps):
    ids = [vocab[c] for c in ps if c in vocab]
    return ids[:510]

def voice_style(name, n):
    v = np.fromfile(os.path.join(mdir, 'voices', f'{name}.bin'), dtype=np.float32).reshape(-1, 1, 256)
    return v[min(n, len(v) - 1)]

def envelope(x, sr=24000, hop=240):
    n = len(x) // hop
    return np.sqrt(np.mean(x[:n * hop].reshape(n, hop) ** 2, axis=1))

phon = [g2p(t)[0] for t in LINES]
models = ['model', 'model_fp16', 'model_quantized', 'model_q8f16']
report = {'threads': threads, 'ort': ort.__version__, 'models': {}}
ref = {}
for m in models:
    path = os.path.join(mdir, 'onnx', f'{m}.onnx')
    so = ort.SessionOptions()
    so.intra_op_num_threads = threads
    so.inter_op_num_threads = 1
    rss0 = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    t = time.perf_counter()
    sess = ort.InferenceSession(path, so, providers=['CPUExecutionProvider'])
    load = time.perf_counter() - t
    names = [i.name for i in sess.get_inputs()]
    def synth(ps, voice='af_heart'):
        ids = tokens(ps)
        style = voice_style(voice, len(ids))
        feed = {names[0]: np.array([[0, *ids, 0]], dtype=np.int64), names[1]: style.astype(np.float32),
                names[2]: np.array([1.0], dtype=np.float32)}
        t = time.perf_counter()
        audio = sess.run(None, feed)[0].reshape(-1)
        return audio.astype(np.float32), time.perf_counter() - t, len(ids)
    synth(phon[0])  # warm-up
    rows = []
    tot_s = tot_a = 0.0
    for i, ps in enumerate(phon):
        times = []
        for _ in range(3):
            audio, dt, n = synth(ps)
            times.append(dt)
        dt = sorted(times)[1]
        dur = len(audio) / 24000
        tot_s += dt
        tot_a += dur
        env = envelope(audio)
        voiced = float(np.mean(env > 0.02))
        corr = None
        if m == 'model':
            ref[i] = env
        else:
            r = ref[i]
            k = min(len(r), len(env))
            corr = float(np.corrcoef(r[:k], env[:k])[0, 1]) if k > 10 else None
        sf.write(os.path.join(wdir, f'{m}_{i}.wav'), audio, 24000)
        rows.append({'line': i, 'tokens': n, 'audio_s': round(dur, 2), 'synth_s': round(dt, 3), 'rtf': round(dt / dur, 3),
                     'rms': round(float(np.sqrt(np.mean(audio ** 2))), 4), 'voiced': round(voiced, 2),
                     'env_corr_vs_fp32': None if corr is None else round(corr, 3)})
    rss1 = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    report['models'][m] = {'file_mb': round(os.path.getsize(path) / 1e6, 1), 'load_s': round(load, 2),
                           'rtf_total': round(tot_s / tot_a, 3), 'first_short_line_s': rows[1]['synth_s'],
                           'max_rss_growth_mb': round((rss1 - rss0) / 1e6, 1), 'rows': rows}
    print(m, json.dumps({k: v for k, v in report['models'][m].items() if k != 'rows'}), flush=True)
    for r in rows:
        print('   ', r, flush=True)
    del sess
json.dump(report, open(os.path.join(wdir, f'bench_t{threads}.json'), 'w'), indent=1)
