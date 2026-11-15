import json, os, subprocess, sys
S = sys.argv[1]
for m in ['manifest_model.json', 'manifest_model_fp16.json']:
    url = f'http://127.0.0.1:8763/lab/harness.html?m={m}&ep=webgpu&n=1'
    r = subprocess.run([sys.executable, '-I', os.path.join(S, 'tools', 'run_chrome.py'), S, url, '400'], capture_output=True, text=True).stdout
    d = json.loads(r[r.index('{'):]) if '{' in r else {}
    print(m, {k: d.get(k) for k in ['ep', 'engine_read', 'engine_first_line_ms', 'engine_unknown_line', 'error']}, flush=True)
