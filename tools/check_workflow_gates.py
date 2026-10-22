#!/usr/bin/env python3
"""Static checks every workflow must pass. Exit 1 on any violation.

1. Every split workflow's apply job is fully gated.
   An `apply` job skips the catalog fetch when there are no deltas. Any step
   after that check which is NOT gated on it then runs against a catalog that
   is not there — remediating nothing, or publishing nothing over something.
   This slipped twice while converting workflows by script: once because a
   step had no `if:` at all, and once because it already had one
   (`dry_run != 'true'`) that neither the "add" nor the "replace" branch
   matched. So it is a check now rather than a habit.

2. Every step which RUNS `gh` has a GH_TOKEN in scope.
   A runner has no ambient credential, so `gh` fails with a message about
   setting GH_TOKEN — and when that step is a publish, everything after it is
   SKIPPED and the `if: always()` upload finds nothing to upload. A catalog
   publisher shipped nothing for two days on exactly that, with the run going
   red every hour in a way nobody read as "the pipeline is down".

3. A reporter workflow never fails on its findings (reporters never fail).
   A reporting step may exit non-zero only over its OWN mechanics, and says so
   in the step: `# reporter-may-fail: <why>`.

Run from anywhere: python3 tools/check_workflow_gates.py
"""
import pathlib
import re
import sys

import yaml

WORKFLOWS = pathlib.Path(__file__).resolve().parents[1] / ".github" / "workflows"
GATE = "steps.gate.outputs.go"

# Workflows whose job is to LOOK and REPORT. Add an app's own dashboards and
# auditors here.
REPORTERS = {"workflow-health", "pulse"}

# A COMMAND, not prose. Matching a bare "gh " anywhere finds "high enough" and
# "through" in comments, which is three false alarms out of four. The repo's gh
# wrappers count as gh.
GH_CMD = re.compile(r"(?:^|[|&;(]\s*|\$\(\s*)"
                    r"(?:gh|(?:bash\s+)?tools/gh_(?:retry|dispatch)\.sh)\s")
# A step exiting non-zero: `exit 1` anywhere on a line (the first version of
# this missed `echo ...; exit 1`), plus the two ways an inline python heredoc
# ends a run.
FAILS = re.compile(r"(?:(?:^|[;&\n])\s*exit [1-9]"
                   r"|sys\.exit\(\s*[1-9]"
                   r"|raise SystemExit\(\s*[1-9])", re.M)
MAY_FAIL = re.compile(r"#\s*reporter-may-fail:\s*(\S.*)")


def runs_gh(run: str) -> bool:
    for line in (run or "").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if GH_CMD.search(line):
            return True
    return False


def load(f: pathlib.Path) -> dict:
    return yaml.safe_load(f.read_text()) or {}


def ungated(files) -> list:
    bad = []
    for f in files:
        job = (load(f).get("jobs") or {}).get("apply")
        if not job:
            continue
        seen = False
        for step in job.get("steps", []):
            name = step.get("name", "") or step.get("uses", "")
            if "Stop if nothing changed" in name:
                seen = True
                continue
            if seen and GATE not in str(step.get("if", "")):
                bad.append(f"{f.stem}: '{name}' runs even with no deltas")
    return bad


def untokened(files) -> list:
    bad = []
    for f in files:
        doc = load(f)
        top = "GH_TOKEN" in (doc.get("env") or {})
        for jname, job in (doc.get("jobs") or {}).items():
            jenv = "GH_TOKEN" in (job.get("env") or {})
            for step in job.get("steps", []):
                if not runs_gh(step.get("run", "")):
                    continue
                if top or jenv or "GH_TOKEN" in (step.get("env") or {}):
                    continue
                bad.append(f"{f.stem} [{jname}]: '{step.get('name')}' "
                           f"runs gh with no GH_TOKEN in scope")
    return bad


def reporting_fails(files) -> list:
    """A workflow going red says IT could not do its job; failing a reporter to
    signal somebody ELSE's problem is a category error, and an alert channel
    that cries wolf gets muted. Findings belong in a report (the step summary,
    an issue), never in an exit code. Telling "failed over what it READ" from
    "failed over its own mechanics" is not something a regex can judge, so the
    AUTHOR states it in the step, in words — explicit, and impossible to add by
    accident."""
    bad = []
    for f in files:
        if f.stem not in REPORTERS:
            continue
        for jname, job in (load(f).get("jobs") or {}).items():
            for step in job.get("steps", []):
                run = step.get("run", "") or ""
                if step.get("continue-on-error"):
                    continue
                if not FAILS.search(run) or MAY_FAIL.search(run):
                    continue
                bad.append(f"{f.stem} [{jname}]: '{step.get('name')}' exits non-zero with no "
                           f"`# reporter-may-fail: <why>` — a reporter reports its findings, "
                           f"it does not fail on them")
    return bad


def main(workflows: pathlib.Path = WORKFLOWS) -> int:
    files = sorted(list(workflows.glob("*.yml")) + list(workflows.glob("*.yaml")))
    bad, notok, rep = ungated(files), untokened(files), reporting_fails(files)
    for b in bad + notok + rep:
        print("  " + b)
    print(f"{len(bad)} ungated step(s)" if bad else "every apply job is fully gated")
    print(f"{len(notok)} gh step(s) with no token" if notok else "every gh step has a token")
    print(f"{len(rep)} reporting step(s) that can fail a run"
          if rep else "no reporting workflow fails on its findings")
    return 1 if (bad or notok or rep) else 0


if __name__ == "__main__":
    sys.exit(main())
