#!/usr/bin/env python3
"""
test_workflow_health.py — the auditor must never be blind to a FAILURE, and
must never fail itself.

The regression this exists for: the workflow that shipped an app's catalog sat
on the auditor's exemption list (then NOT_PRODUCERS) because it prints no yield
summary, and the list was read as "never look at it". It then failed every hour
for two days, entirely unreported, while the daily audit said nothing needed
attention.

Also held here: job-granularity displacement (a split writer's queued `apply`
job destroyed with zero steps is DROPPED, not KILLED), self-cancelling
workflows (cancel-in-progress is the rule working), the auditor exiting 0 with
urgent findings (reporters never fail), and check_workflow_gates' reporter and
GH_TOKEN checks against negative controls.

No network: `api` and `gh` are stubbed throughout.

Run: python3 tools/test_workflow_health.py
"""
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audit_workflow_health as A  # noqa: E402
import check_workflow_gates as G  # noqa: E402

ok = fail = 0


def check(name, cond, detail=""):
    global ok, fail
    if cond:
        ok += 1
        print(f"  PASS  {name}")
    else:
        fail += 1
        print(f"  FAIL  {name}  {detail}")


def run(concl, mins=20, rid=1, event="schedule", started="2026-09-08T00:00:00Z"):
    t0 = A.datetime.fromisoformat(started.replace("Z", "+00:00"))
    return {"id": rid, "conclusion": concl, "status": "completed", "event": event,
            "run_started_at": started,
            "updated_at": (t0 + A.timedelta(minutes=mins)).strftime("%Y-%m-%dT%H:%M:%SZ")}


A.api = lambda path: {"jobs": [{"steps": []}]}
A.gh = lambda *a: "ran fine\n"

print("a failure is a failure whoever produced it")
for name in sorted(A.NO_YIELD_LINE):
    v = A.judge(name, run("failure"), yield_ok=False)
    check(f"{name[:34]}: FAILED is reported", v and v[0] == "FAILED", str(v))

print("\nthe yield analysis is still skipped for them")
check("a green no-yield run is not called SILENT",
      A.judge("App Store build (cloud)", run("success"), yield_ok=False) is None)
check("a green PRODUCER with no yield line IS silent",
      (A.judge("Some producer", run("success"), yield_ok=True) or ("",))[0] == "SILENT")

print("\nthe exemption lists say different things")
check("only the auditor itself is exempt from judgement", A.SELF == {"Workflow health"})
check("a shipping workflow is NOT exempt from judgement",
      "App Store build (cloud)" not in A.SELF)
check("...only from the yield analysis",
      "App Store build (cloud)" in A.NO_YIELD_LINE)
check("the old blanket skip list is gone", not hasattr(A, "NOT_PRODUCERS"))


print("\ndisplacement carries no information")


def jobs_reply(probe_steps, apply_concl, apply_steps):
    return lambda path: {"jobs": [
        {"conclusion": "success", "steps": [{"name": "s", "conclusion": "success"}] * probe_steps},
        {"conclusion": apply_concl, "steps": [{"name": "s", "conclusion": "success"}] * apply_steps},
    ]}


_api = A.api
A._DISPLACED.clear()
A.api = jobs_reply(10, "cancelled", 0)
check("a displaced APPLY job counts as displaced, not killed",
      A.displaced(run("cancelled", rid=101)))
A._DISPLACED.clear()
check("...and is reported DROPPED",
      (A.judge("Split writer", run("cancelled", rid=101)) or ("",))[0] == "DROPPED")

# A human or a timeout cancelling a RUNNING job always leaves steps behind.
A._DISPLACED.clear()
A.api = jobs_reply(10, "cancelled", 4)
check("a job cancelled MID-RUN is still KILLED, never dropped",
      not A.displaced(run("cancelled", rid=102)))
A._DISPLACED.clear()
check("...and reports KILLED",
      (A.judge("X", run("cancelled", rid=102)) or ("",))[0] == "KILLED")

# The auditor and the sweeper must not disagree about what displacement is.
sweeper = (Path(A.__file__).parent / "retry_infra_failures.py").read_text()
check("the sweeper uses the same zero-steps-on-bad-jobs test",
      'not any(j.get("steps") for j in bad)' in sweeper)
check("and so does the auditor",
      'not any(j.get("steps") for j in bad)' in Path(A.__file__).read_text())
A.api = _api
A._DISPLACED.clear()

check("a cancelled run with no steps is displaced", A.displaced(run("cancelled", rid=7)))
check("and is reported DROPPED, not KILLED",
      (A.judge("X", run("cancelled", rid=7)) or ("",))[0] == "DROPPED")
check("a success is never displaced", not A.displaced(run("success", rid=8)))
calls = []
A.api = lambda p: (calls.append(p), {"jobs": [{"steps": []}]})[1]
A._DISPLACED.clear()
A.displaced(run("cancelled", rid=9))
A.displaced(run("cancelled", rid=9))
check("the jobs call is made once per run, not per question", len(calls) == 1, str(calls))
A.api = _api

check("DROPPED is reported, never raised twice", "DROPPED" not in A.URGENT_SEVERITIES)
check("a real break still raises the issue", set(A.URGENT_SEVERITIES) == {"BROKEN", "KILLED"})


# ── a workflow that ASKS to be superseded is not KILLED ─────────────────────
print("\nself-cancelling workflows (read from the workflow files)")
with tempfile.TemporaryDirectory() as d:
    wf = Path(d)
    (wf / "deploy.yml").write_text(
        "name: Deploy Pages\nconcurrency:\n  group: pages\n  cancel-in-progress: true\n"
        "on: push\njobs:\n  d:\n    runs-on: ubuntu-latest\n    steps: []\n")
    (wf / "job-level.yml").write_text(
        "name: Job level\non: push\njobs:\n  d:\n    runs-on: ubuntu-latest\n"
        "    concurrency:\n      group: x\n      cancel-in-progress: true\n    steps: []\n")
    (wf / "pulse.yml").write_text(
        "name: Pulse\nconcurrency:\n  group: pulse\n  cancel-in-progress: false\n"
        "on: push\njobs:\n  d:\n    runs-on: ubuntu-latest\n    steps: []\n")
    saved_dir = A.WORKFLOWS_DIR
    A.WORKFLOWS_DIR = wf
    A._SELF_CANCELLING.clear()
    try:
        import yaml  # noqa: F401
        have_yaml = True
    except ImportError:
        have_yaml = False
    if have_yaml:
        check("a workflow-level cancel-in-progress is self-cancelling",
              A.self_cancelling("Deploy Pages") is True)
        check("a job-level one is too", A.self_cancelling("Job level") is True)
        check("cancel-in-progress: false is not", A.self_cancelling("Pulse") is False)
        check("an unknown workflow is not", A.self_cancelling("No Such Workflow") is False)
        _run = {"id": 1, "conclusion": "cancelled",
                "run_started_at": "2026-09-09T12:00:00Z", "updated_at": "2026-09-09T12:01:00Z"}
        check("a cancelled self-cancelling run is not a finding",
              A.judge("Deploy Pages", _run) is None)
        check("a cancelled run of a workflow that did NOT ask for it still is",
              (A.judge("Pulse", dict(_run, id=2)) or ("", ""))[0] in ("KILLED", "DROPPED"))
    else:
        print("  SKIP  self-cancelling checks: pyyaml not installed (the auditor degrades "
              "to 'not self-cancelling', which only re-enables an alert)")
    A.WORKFLOWS_DIR = saved_dir
    A._SELF_CANCELLING.clear()


# ── judge the newest SCHEDULED run that actually ran; never fail the auditor ─
print("\nrun selection and exit code")
NOW = A.datetime.now(A.timezone.utc)


def iso(hours_ago):
    return (NOW - A.timedelta(hours=hours_ago)).strftime("%Y-%m-%dT%H:%M:%SZ")


def fleet(runs_by_wf, jobs_by_run):
    wfs = [{"id": i, "name": n, "state": "active", "path": f".github/workflows/w{i}.yml"}
           for i, n in enumerate(runs_by_wf)]

    def api(path):
        if path.startswith("actions/workflows?"):
            return {"workflows": wfs}
        if path.startswith("actions/workflows/"):
            wid = int(path.split("/")[2])
            return {"workflow_runs": runs_by_wf[wfs[wid]["name"]]}
        if path.startswith("actions/runs/"):
            return {"jobs": jobs_by_run.get(int(path.split("/")[2]), [])}
        return {}
    return api


saved = (A.api, A.gh, A.REPO)
A.REPO = "owner/repo"
A._DISPLACED.clear()
# Newest scheduled run was displaced (no steps); the one before it FAILED. The
# verdict must come from the one that ran.
A.api = fleet(
    {"Nightly": [dict(run("cancelled", rid=201, started=iso(2)), event="schedule"),
                 dict(run("failure", rid=202, started=iso(5)), event="schedule")]},
    {201: [{"conclusion": "cancelled", "steps": []}],
     202: [{"conclusion": "failure", "steps": [{"name": "s", "conclusion": "failure"}]}]})
A.gh = lambda *a: ""
import contextlib  # noqa: E402
import io  # noqa: E402
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rc = A.main()
out = buf.getvalue()
check("a displaced newest run does not hide the failed one before it",
      "FAILED" in out and "Nightly" in out, out)
check("...and is not itself the verdict", "DROPPED" not in out, out)

# A BROKEN producer (green, 30 minutes, zero yield) is URGENT — and the
# auditor still exits 0: the finding goes to the issue, not a red X.
A._DISPLACED.clear()
A.api = fleet({"Producer": [dict(run("success", mins=30, rid=301, started=iso(3)))]}, {})
A.gh = lambda *a: "job\tstep\t2026Z [producer] done: +0 items\n"
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rc = A.main()
out = buf.getvalue()
check("a zero-yield 30-minute run is BROKEN", "BROKEN" in out, out)
check("reporters never fail: exit 0 even with an urgent finding", rc == 0, f"rc={rc}")
A.api, A.gh, A.REPO = saved
A._DISPLACED.clear()


# ── check_workflow_gates: negative controls ────────────────────────────────
print("\ncheck_workflow_gates")
with tempfile.TemporaryDirectory() as d:
    wf = Path(d)
    (wf / "workflow-health.yml").write_text(
        "name: Workflow health\non: workflow_dispatch\njobs:\n  audit:\n"
        "    runs-on: ubuntu-latest\n    steps:\n"
        "      - name: Fail if something is broken\n"
        "        run: |\n          echo bad; exit 1\n")
    (wf / "pusher.yml").write_text(
        "name: Pusher\non: workflow_dispatch\njobs:\n  p:\n    runs-on: ubuntu-latest\n"
        "    steps:\n      - name: Release\n        run: gh release create v1\n"
        "      - name: Prose only\n        run: |\n          # high enough, through\n"
        "          echo through\n")
    check("a reporter that exits 1 on its findings is caught",
          len(G.reporting_fails(sorted(wf.glob("*.yml")))) == 1)
    check("a gh step with no GH_TOKEN is caught (and prose is not)",
          len(G.untokened(sorted(wf.glob("*.yml")))) == 1,
          str(G.untokened(sorted(wf.glob("*.yml")))))
    with contextlib.redirect_stdout(io.StringIO()):
        rc = G.main(wf)
    check("the checker exits 1 on them", rc == 1)
    (wf / "workflow-health.yml").write_text(
        "name: Workflow health\non: workflow_dispatch\njobs:\n  audit:\n"
        "    runs-on: ubuntu-latest\n    steps:\n"
        "      - name: Push the report\n"
        "        run: |\n          # reporter-may-fail: could not push its own file\n"
        "          git push || exit 1\n")
    (wf / "pusher.yml").write_text(
        "name: Pusher\non: workflow_dispatch\nenv:\n  GH_TOKEN: x\njobs:\n  p:\n"
        "    runs-on: ubuntu-latest\n    steps:\n      - name: Release\n"
        "        run: bash tools/gh_retry.sh release create v1\n")
    with contextlib.redirect_stdout(io.StringIO()):
        rc = G.main(wf)
    check("a stated reporter-may-fail and a workflow-level token pass", rc == 0)
with contextlib.redirect_stdout(io.StringIO()):
    rc = G.main()
check("this repo's own workflows pass", rc == 0)

print(f"\n{ok} passed, {fail} failed")
sys.exit(1 if fail else 0)
