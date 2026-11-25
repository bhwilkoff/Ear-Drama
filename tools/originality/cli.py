"""The originality search, as a tool (R4-9b/c). Standard library only; no Worker, no upload.

    python3 -I tools/originality/cli.py build    --cache DIR --transcripts T.json.gz --out DIR --date YYYY-MM-DD [--without grw]
    python3 -I tools/originality/cli.py selftest --index DIR --plays-dir DIR
    python3 -I tools/originality/cli.py judge    --index DIR --plays-dir DIR --job job.json --out verdict.json (--live | --fixtures F.json)

`--plays-dir` holds <document name>.txt for three or more plays that are in the index and one more as the control
(from our own site in a job; from the Gutenberg cache by hand). `job.json` is {key, title, parts, text}. The
verdict goes to --out; stdout is the public log and says nothing about the script (publiclog.py).
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from originality import index as I  # noqa: E402
from originality import judge as J  # noqa: E402
from originality import selftest as ST  # noqa: E402
from originality import services as S  # noqa: E402
from originality.publiclog import PublicLog  # noqa: E402


def load_plays(d):
    out = {}
    for f in sorted(os.listdir(d)):
        if f.endswith(".txt"):
            out[f[:-4]] = I.read(os.path.join(d, f))
    return out


def run_gate(ix, plays_dir, log):
    gate = ST.run(ix, load_plays(plays_dir))
    log.selftest(gate.passed)
    return gate


def main(argv=None, log=None):
    log = log or PublicLog()
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("--cache", required=True)
    b.add_argument("--transcripts", required=True)
    b.add_argument("--out", required=True)
    b.add_argument("--date", required=True)
    b.add_argument("--without", action="append", default=[], choices=list(I.OPTIONAL))
    for name in ("selftest", "judge"):
        p = sub.add_parser(name)
        p.add_argument("--index", required=True)
        p.add_argument("--plays-dir", required=True)
    j = sub.choices["judge"]
    j.add_argument("--job", required=True)
    j.add_argument("--out", required=True)
    g = j.add_mutually_exclusive_group(required=True)
    g.add_argument("--live", action="store_true")
    g.add_argument("--fixtures")
    a = ap.parse_args(argv)
    try:
        if a.cmd == "build":
            man = I.build(a.cache, a.transcripts, a.out, a.date, tuple(a.without))
            log.index(man["date"])
            return 0
        ix = I.Index(a.index, verify=True)
        log.index(ix.date)
        log.service("index", True)
        gate = run_gate(ix, a.plays_dir, log)
        if a.cmd == "selftest":
            return 0 if gate.passed else 2
        if not gate.passed:
            return 2
        job = I.jload(a.job)
        http = S.Http(None if a.live else I.jload(a.fixtures))
        log.checked(1)
        verdict = J.judge(ix, gate, http, job)
        for name, state in verdict["searched"]["services"].items():
            if state != "skipped" and name != "index":
                log.service(name, state == "ok")
        with open(a.out, "w") as f:
            json.dump(verdict, f)
        log.verdict(verdict["verdict"])
        return 0
    except BaseException as e:  # noqa: BLE001  nothing but the class is printed
        log.failed(e)
        return 1


if __name__ == "__main__":
    sys.exit(main())
