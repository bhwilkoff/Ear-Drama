import json, os, subprocess, sys
S = sys.argv[1]
runs = [('manifest_model_quantized.json', 'wasm', 5), ('manifest.json', 'webgpu', 6), ('manifest_model.json', 'webgpu', 6),
        ('manifest_model_fp16.json', 'webgpu', 6), ('manifest_model_quantized.json', 'webgpu', 6)]
allr = []
for m, ep, n in runs:
    url = f'http://127.0.0.1:8763/lab/harness.html?m={m}&ep={ep}&n={n}&engine=0'
    subprocess.run([sys.executable, '-I', os.path.join(S, 'tools', 'run_chrome.py'), S, url, '400'], capture_output=True)
    p = os.path.join(S, 'web_result.json')
    r = json.load(open(p)) if os.path.exists(p) else {'manifest': m, 'ep_asked': ep, 'error': 'no result'}
    allr.append(r)
    print(m, ep, '->', r.get('ep'), 'rtf_after_first', r.get('rtf_after_first'), 'load_ms', r.get('session_load_ms'),
          'first', r.get('steps', [{}])[0] if r.get('steps') else None, r.get('error', ''), flush=True)
json.dump(allr, open(os.path.join(S, 'web_variants.json'), 'w'), indent=1)
