"""Mutants of the originality search: each is one changed line that the tests must notice.

    python3 -I tools/originality/mutants.py

Copies the package to a temporary folder, applies one mutation at a time, runs test_originality.py there, and
fails if any mutant survives (the tests still pass) or a mutation no longer applies (the source moved).
"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

M = [
    # thresholds
    ("judge.py", "RUN_WORDS = 40 ", "RUN_WORDS = 400 "),
    ("judge.py", "RUN_WORDS = 40 ", "RUN_WORDS = 41 "),
    ("judge.py", "SHARE = 0.02 ", "SHARE = 0.2 "),
    ("judge.py", "SHARE = 0.02 ", "SHARE = 0.002 "),
    ("judge.py", "PHRASES_MIN = 2 ", "PHRASES_MIN = 3 "),
    ("judge.py", "PHRASES_MIN = 2 ", "PHRASES_MIN = 1 "),
    ("judge.py", "PHRASES_NEEDED = 3 ", "PHRASES_NEEDED = 1 "),
    ("titles.py", "MAX_NAMED = 3", "MAX_NAMED = 4"),
    ("titles.py", "COMMON_WORD_CAP = 4", "COMMON_WORD_CAP = 5"),
    ("titles.py", "COMMON_WORD_CAP = 4", "COMMON_WORD_CAP = 3"),
    ("titles.py", "named.sort(key=lambda c: not c[\"author\"])", "pass"),
    ("phrases.py", "COUNT = 6", "COUNT = 3"),
    ("phrases.py", "COUNT = 6", "COUNT = 7"),
    ("phrases.py", "LENGTHS = (8, 7)", "LENGTHS = (9, 8)"),
    ("phrases.py", "SEEN_MIN = 2", "SEEN_MIN = 1"),
    ("phrases.py", "w in names or freq", "freq"),
    ("services.py", "\"archive_fts\": 3.0", "\"archive_fts\": 0.5"),
    ("services.py", "if self.calls >= self.max_calls:", "if False:"),
    ("services.py", "if self.fixtures is not None:", "if False:"),
    ("fingerprint.py", "dq[0] <= i - w", "dq[0] <= i - w + 1"),
    ("fingerprint.py", "K = 5", "K = 4"),
    ("index.py", "if h in seen:", "if False:"),
    ("index.py", "REQUIRED = (\"gut\", \"tr\")", "REQUIRED = (\"gut\",)"),
    ("index.py", "if verify and sha256(p) != ent[\"sha256\"]:", "if False:"),
    ("index.py", "ent[\"docs\"] <= 0 or ", ""),
    # a search that did not run never clears; a title never holds; nothing is judged before the gate
    ("judge.py", "if \"failed\" in state.values():", "if False:"),
    ("judge.py", "elif state == \"failed\":", "elif False:"),
    ("judge.py", "verdict = \"asks\" if asks else \"clear\"", "verdict = \"held\" if asks else \"clear\""),
    ("judge.py", "if gate is None or not gate.passed or gate.index_id != index.id:", "if False:"),
    ("judge.py", "or gate.index_id != index.id", ""),
    ("judge.py", "    if not reasons:\n        found", "    if True:\n        found"),
    ("selftest.py", "results.append((control, \"shuffled_control\", not ctrl[\"held\"]))", "results.append((control, \"shuffled_control\", True))"),
    ("selftest.py", "if len(names) < 4:", "if len(names) < 1:"),
    ("selftest.py", "w[\"copied\"] >= J.RUN_WORDS", "True"),
    # privacy: the verdict, the log, the request
    ("judge.py", "\"findings\": findings}", "\"findings\": findings, \"text\": text}"),
    ("judge.py", "findings[\"archive\"] = items", "findings[\"archive\"] = items + found"),
    ("judge.py", "\"phrases\": len(found), \"words\": c[\"words\"]}", "\"phrases\": found, \"words\": c[\"words\"]}"),
    ("judge.py", "\"spans\": [list(s) for s in r[\"spans\"][:MAX_SPANS]]}", "\"spans\": [list(s) for s in r[\"spans\"][:MAX_SPANS]], \"text\": r[\"doc\"]}"),
    ("publiclog.py", "if word not in VERDICTS:", "if False:"),
    ("publiclog.py", "if name not in SERVICES or not isinstance(ok, bool):", "if False:"),
    ("publiclog.py", "if not isinstance(date, str) or not re.fullmatch(r\"\\d{4}-\\d\\d-\\d\\d\", date):", "if False:"),
    ("publiclog.py", "if not isinstance(n, int) or not 0 <= n <= 1000:", "if False:"),
    ("publiclog.py", "self._say(\"error \" + (name if name in KNOWN_ERRORS else \"other\"))", "self._say(\"error \" + name + \" \" + str(exc))"),
    ("publiclog.py", "self._say(\"error \" + (name if name in KNOWN_ERRORS else \"other\"))", "self._say(\"error \" + name)"),
    ("publiclog.py", "raise LogRefused(\"verdict\")", "raise LogRefused(repr(word))"),
    ("cli.py", "        log.checked(1)\n", "        log.checked(1)\n        print(job[\"title\"])\n"),
    ("cli.py", "        log.checked(1)\n","        log.checked(1)\n        sys.stderr.write(job[\"text\"][:20])\n"),
    ("cli.py", "    except BaseException as e:  # noqa: BLE001  nothing but the class is printed\n        log.failed(e)",
     "    except BaseException as e:  # noqa: BLE001  nothing but the class is printed\n        print(e)\n        log.failed(e)"),
    ("cli.py", "        if not gate.passed:\n            return 2\n", ""),
    ("services.py", "AGENT = \"EarDrama-originality/1.0 (+https://eardrama.org)\"", "AGENT = \"EarDrama-originality/1.0 (+https://eardrama.org) ben@example.org\""),
    ("services.py", "raise ServiceDown(\"no_answer\")", "return {}"),
]


def run(tests):
    return subprocess.run([sys.executable, "-I", tests], capture_output=True, text=True, cwd=os.path.dirname(tests)).returncode


def main():
    killed, bad = 0, []
    for i, (f, old, new) in enumerate(M):
        tmp = tempfile.mkdtemp(prefix="originality-mutant-")
        try:
            dst = os.path.join(tmp, "originality")
            shutil.copytree(HERE, dst, ignore=shutil.ignore_patterns("__pycache__", "mutants.py"))
            p = os.path.join(dst, f)
            src = open(p).read()
            if src.count(old) != 1:
                bad.append((i, f, old, "does not apply exactly once"))
                continue
            with open(p, "w") as o:
                o.write(src.replace(old, new))
            if run(os.path.join(dst, "test_originality.py")) != 0:
                killed += 1
            else:
                bad.append((i, f, old, "SURVIVED"))
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    print(f"{killed} of {len(M)} mutants killed")
    for b in bad:
        print(*b)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
