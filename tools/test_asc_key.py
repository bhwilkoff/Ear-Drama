#!/usr/bin/env python3
"""tools/asc_key.py and tools/with_asc.sh read the ASC key from the login Keychain: this app's own items first,
then Archive Watch's shared chunked items, with the environment ahead of both. `security` is a stand-in on PATH
holding planted items; no real value is read. Run: python3 tools/test_asc_key.py"""
import base64
import os
import stat
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)


OWN = "eardrama"
PEM = "-----BEGIN PRIVATE KEY-----\nPLANTEDpemBODY0123456789\n-----END PRIVATE KEY-----\n"
OWN_PEM = PEM.replace("PLANTED", "OWNPLANT")
b64 = lambda t: base64.b64encode(t.encode()).decode()


def shared_items(pem):
    out = {}
    for name, text in [("ASC_KEY_P8", pem), ("ASC_KEY_ID", "SHAREDKID1"), ("ASC_ISSUER_ID", "11111111-2222-3333-4444-555555555555")]:
        b = b64(text)
        pieces = [b[i:i + 40] for i in range(0, len(b), 40)]
        out["archivewatch:" + name] = str(len(pieces))
        out.update({f"archivewatch:{name}.{i}": p for i, p in enumerate(pieces)})
    return out


def own_items(pem):
    return {f"{OWN}:ASC_KEY_P8": b64(pem), f"{OWN}:ASC_KEY_ID": "OWNKID0001", f"{OWN}:ASC_ISSUER_ID": "99999999-2222-3333-4444-555555555555"}


def fake_security(d, store):
    path = os.path.join(d, "security")
    open(path, "w").write("#!" + sys.executable + "\nimport sys\nS = " + repr(store) +
                          "\na = sys.argv[1:]\ns = a[a.index('-s') + 1]\nif s in S: print(S[s])\nelse: sys.exit(44)\n")
    os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)


def env_for(d):
    e = {k: v for k, v in os.environ.items() if not k.startswith("ASC_")}
    e["PATH"] = d + os.pathsep + e["PATH"]
    e["HOME"] = d
    return e


def py(env, code, mod_dir=HERE):
    return subprocess.run([sys.executable, "-c", f"import sys; sys.path.insert(0, {mod_dir!r}); import asc_key as k\n" + code],
                          env=env, capture_output=True, text=True)


def main():
    fails = []
    # 1. shared items only (the state today: Archive Watch imported the key, this app has not)
    d = tempfile.mkdtemp(); fake_security(d, shared_items(PEM)); env = env_for(d)
    r = py(env, f"assert k.value('ASC_KEY_ID') == 'SHAREDKID1'\nassert k.value('ASC_ISSUER_ID').startswith('11111111-')\n"
                f"assert k.key_pem('SHAREDKID1') == {PEM!r}, 'shared chunked .p8'\n")
    if r.returncode: fails.append("shared items: " + r.stderr[-300:])
    # 2. own items win over the shared ones
    d2 = tempfile.mkdtemp(); fake_security(d2, {**shared_items(PEM), **own_items(OWN_PEM)}); env2 = env_for(d2)
    r = py(env2, f"assert k.value('ASC_KEY_ID') == 'OWNKID0001' and k.value('ASC_ISSUER_ID').startswith('99999999-')\n"
                 f"assert k.key_pem('OWNKID0001') == {OWN_PEM!r}, 'own beats shared'\n")
    if r.returncode: fails.append("own items: " + r.stderr[-300:])
    # 3. the environment beats the Keychain, ASC_KEY_PATH beats ASC_KEY_P8
    pf = os.path.join(d, "k.p8"); open(pf, "w").write("path-pem")
    r = py({**env2, "ASC_KEY_ID": "CIKID", "ASC_KEY_P8": b64("ci-pem")},
           "assert k.value('ASC_KEY_ID') == 'CIKID'\nassert k.key_pem('CIKID') == 'ci-pem'\n")
    if r.returncode: fails.append("env first: " + r.stderr[-300:])
    r = py({**env2, "ASC_KEY_P8": b64("ci-pem"), "ASC_KEY_PATH": pf}, "assert k.key_pem('X') == 'path-pem'\n")
    if r.returncode: fails.append("ASC_KEY_PATH first: " + r.stderr[-300:])
    # 4. nothing anywhere: no value, and the key falls to the runner's file (absent here) rather than inventing one
    d3 = tempfile.mkdtemp(); fake_security(d3, {}); env3 = env_for(d3)
    r = py(env3, "assert k.value('ASC_KEY_ID') is None\ntry:\n    k.key_pem('NOPE'); raise SystemExit('no key must raise')\nexcept OSError: pass\n")
    if r.returncode: fails.append("no items: " + r.stderr[-300:])
    # 5. with_asc.sh: the exported key id, issuer and a private .p8 that is gone after the command
    for label, e, want_kid, want_pem in [("shared", env, "SHAREDKID1", PEM), ("own", env2, "OWNKID0001", OWN_PEM)]:
        probe = os.path.join(e["HOME"], "probe.txt")
        cmd = ('echo "$ASC_KEY_ID $ASC_ISSUER_ID" > "%s"; stat -f %%Lp "$ASC_KEY_PATH" >> "%s"; cat "$ASC_KEY_PATH" >> "%s"; '
               'echo "$ASC_KEY_PATH" >> "%s"' % ((probe,) * 4))
        r = subprocess.run(["bash", os.path.join(HERE, "with_asc.sh"), "bash", "-c", cmd], env=e, capture_output=True, text=True)
        lines = open(probe).read().split("\n") if os.path.exists(probe) else []
        ok = (r.returncode == 0 and lines and lines[0].split()[0] == want_kid and lines[1] == "600"
              and "\n".join(lines[2:-2]) + "\n" == want_pem and not os.path.exists(lines[-2]))
        if not ok:
            fails.append(f"with_asc.sh ({label}): exit {r.returncode} {r.stderr[-200:]}")
        if want_pem.splitlines()[1] in (r.stdout + r.stderr):
            fails.append(f"with_asc.sh ({label}) printed key material")
    r = subprocess.run(["bash", os.path.join(HERE, "with_asc.sh"), "true"], env=env3, capture_output=True, text=True)
    if r.returncode == 0:
        fails.append("with_asc.sh ran the command with no key in the Keychain")
    # 6. negative control: a copy of asc_key.py that skips the shared items must fail check 1
    bad = tempfile.mkdtemp()
    src = open(os.path.join(HERE, "asc_key.py")).read()
    assert "return _shared(name)" in src
    open(os.path.join(bad, "asc_key.py"), "w").write(src.replace("return _shared(name)", "return None"))
    open(os.path.join(bad, "app_config.py"), "w").write(open(os.path.join(HERE, "app_config.py")).read())
    r = py(env, "assert k.value('ASC_KEY_ID') == 'SHAREDKID1'\n", mod_dir=bad)
    if r.returncode == 0:
        fails.append("negative control: a reader without the shared fallback passed")
    print(("FAIL " + "; ".join(fails)) if fails else "PASS asc_key.py + with_asc.sh: own then shared items, env first, private .p8 removed, negative control")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
