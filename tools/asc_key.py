"""The App Store Connect API key for local tools: the environment (CI) first, then the login Keychain, never a
file left on disk. No value is printed here.

One Apple-team key serves every app. This app's own items (`<SECRETS_NAME>:ASC_KEY_P8`, `:ASC_KEY_ID`,
`:ASC_ISSUER_ID`, written by `tools/secrets.sh keychain-import-asc`, one base64 token each) win; when they are
absent the shared items that Archive Watch's tools/secrets.sh keeps are used: account `archivewatch`, services
`archivewatch:ASC_KEY_P8`, `archivewatch:ASC_KEY_ID`, `archivewatch:ASC_ISSUER_ID`, each a chunk count with the
base64 pieces at `archivewatch:<NAME>.0 ... .n-1`. CI never reaches the Keychain: its key arrives as ASC_KEY_P8 or
as the file the workflow writes.
"""
import base64
import os
import subprocess
import sys


OWN = "eardrama"

SHARED_ACCOUNT = "archivewatch"


def _find(account, service):
    try:
        r = subprocess.run(["security", "find-generic-password", "-a", account, "-s", service, "-w"],
                           capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else None


def _own(name):
    return _find(OWN, f"{OWN}:{name}")


def _shared(name):
    count = _find(SHARED_ACCOUNT, f"{SHARED_ACCOUNT}:{name}")
    if not count or not count.isdigit():
        return None
    parts = [_find(SHARED_ACCOUNT, f"{SHARED_ACCOUNT}:{name}.{i}") for i in range(int(count))]
    return None if any(p is None for p in parts) else "".join(parts)


def b64_item(name):
    """The base64 text of a Keychain value (ASC_KEY_P8 holds the .p8, the others a plain string), or None."""
    own = _own(name)
    if own:
        return own if name == "ASC_KEY_P8" else base64.b64encode(own.encode()).decode()
    return _shared(name)


def value(name):
    """ASC_KEY_ID or ASC_ISSUER_ID: the environment, then the Keychain."""
    v = os.environ.get(name)
    if v:
        return v
    b = b64_item(name)
    if not b:
        return None
    try:
        return base64.b64decode(b).decode().strip()
    except ValueError:
        return None


def key_pem(kid):
    """The .p8 as text: ASC_KEY_PATH, ASC_KEY_P8 (base64, CI), the Keychain, then the file a CI runner writes."""
    path = os.environ.get("ASC_KEY_PATH")
    if path:
        return open(path).read()
    b = os.environ.get("ASC_KEY_P8") or b64_item("ASC_KEY_P8")
    if b:
        return base64.b64decode(b).decode()
    return open(os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{kid}.p8")).read()
