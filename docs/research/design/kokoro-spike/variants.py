import hashlib, json, os, sys
S = sys.argv[1]
lab = os.path.join(S, 'lab')
base = json.load(open(os.path.join(lab, 'manifest.json')))
for m in ['model_quantized', 'model', 'model_fp16']:
    dst = os.path.join(lab, f'{m}.onnx')
    if not os.path.exists(dst):
        os.link(os.path.join(S, 'models', 'kokoro', 'onnx', f'{m}.onnx'), dst)
    b = open(dst, 'rb').read()
    man = dict(base)
    man['files'] = [{'path': f'{m}.onnx', 'role': 'model', 'bytes': len(b), 'sha256': hashlib.sha256(b).hexdigest(), 'license': 'Apache-2.0'}] + base['files'][1:]
    json.dump(man, open(os.path.join(lab, f'manifest_{m}.json'), 'w'), indent=1)
    print(m, len(b))
