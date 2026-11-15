"""Opens the harness in a headless Chrome with a FRESH profile (no cached worker), waits for the posted
result, closes Chrome and removes the profile.
usage: python -I run_chrome.py <scratch> <url> <timeout s>"""
import os, subprocess, sys, time, json, shutil, tempfile
scratch, url, limit = sys.argv[1], sys.argv[2], int(sys.argv[3])
res = os.path.join(scratch, 'web_result.json')
if os.path.exists(res):
    os.remove(res)
prof = tempfile.mkdtemp(prefix='chrome-', dir=scratch)
chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
p = subprocess.Popen([chrome, '--headless=new', '--no-first-run', '--mute-audio', '--autoplay-policy=no-user-gesture-required',
                      '--enable-unsafe-webgpu', f'--user-data-dir={prof}', url],
                     stdout=open(os.path.join(scratch, 'chrome.log'), 'w'), stderr=subprocess.STDOUT)
t = time.time()
while time.time() - t < limit and not (os.path.exists(res) and os.path.getsize(res) > 0):
    time.sleep(1)
p.terminate()
try:
    p.wait(10)
except subprocess.TimeoutExpired:
    p.kill()
time.sleep(1)
shutil.rmtree(prof, ignore_errors=True)
print('elapsed', round(time.time() - t, 1), 'chrome exit', p.returncode)
print(json.dumps(json.load(open(res)), indent=1) if os.path.exists(res) else 'NO RESULT')
