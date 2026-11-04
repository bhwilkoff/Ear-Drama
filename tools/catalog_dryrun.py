#!/usr/bin/env python3
"""Run catalog-publish.yml's build steps over the real data, publishing nothing.

The steps are read out of the workflow itself (never copied), so the dry run
cannot drift from the publish. They run in a scratch copy of the working tree:
catalog/out, catalog/.cache and catalog/dist are NOT copied, so a stale local
build is never trusted; the restore step pulls the newest dated Release.
Usage: python3 tools/catalog_dryrun.py [--keep] [--with-suites] [--workdir DIR]
"""
import argparse, os, shutil, subprocess, sys, tempfile, time
import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW = os.path.join(ROOT, ".github", "workflows", "catalog-publish.yml")
STEPS = [
    "Restore the research database and caches (newest dated catalog Release)",
    "Rebuild (build_db, then every enrich step)",
    "Every catalog suite (a red test blocks publish)",
    "Restore the loudness measurements (loudness-latest)",
    "Restore the transcripts (transcripts-latest)",
    "Fetch the live projection (the ids this publish forwards)",
    "Build the served, clean-only, and web projections",
    "Contract tests over the real artifacts",
]
SKIP_UNLESS_SUITES = {STEPS[2]}


def copy_tree(dst):
    def ignore(d, names):
        rel = os.path.relpath(d, ROOT)
        skip = {"__pycache__", ".DS_Store"}
        if rel == ".":
            skip |= {".git", "apple", "android", "node_modules", ".claude", "worker", "windows"}
        if rel == "catalog":
            skip |= {"out", ".cache", "dist"}
        return [n for n in names if n in skip]
    shutil.copytree(ROOT, dst, ignore=ignore, dirs_exist_ok=True)


def sh(*a):
    r = subprocess.run(a, capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--with-suites", action="store_true", help="also run catalog/tests/run_all.sh (the publish does)")
    ap.add_argument("--workdir")
    a = ap.parse_args()
    wf = yaml.safe_load(open(WORKFLOW))
    steps = {s.get("name"): s for s in wf["jobs"]["build"]["steps"]}
    work = a.workdir or tempfile.mkdtemp(prefix="catalog-dryrun-")
    os.makedirs(work, exist_ok=True)
    copy_tree(work)
    print(f"dry run in {work} (nothing is published; catalog/out not trusted)", flush=True)
    env = dict(os.environ)
    token = env.get("GH_TOKEN") or sh("gh", "auth", "token")
    repo = env.get("REPO") or sh("gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner")
    if not token or not repo:
        sys.exit("needs gh auth (or GH_TOKEN and REPO)")
    env.update(GH_TOKEN=token, REPO=repo, SHRINK_REASON="", PYTHONHASHSEED="0",
               DMCA_AGENT_REGISTERED=env.get("DMCA_AGENT_REGISTERED") or sh("gh", "variable", "get", "DMCA_AGENT_REGISTERED", "-R", repo))
    for k, v in wf.get("env", {}).items():
        if "${{" not in str(v):
            env.setdefault(k, str(v))
    env["GITHUB_OUTPUT"] = os.path.join(work, ".gh_output")
    env["GITHUB_STEP_SUMMARY"] = os.path.join(work, ".gh_summary")
    t0 = time.time()
    for name in STEPS:
        if name in SKIP_UNLESS_SUITES and not a.with_suites:
            print(f"--- skipped (--with-suites): {name}")
            continue
        s = steps.get(name)
        if s is None or "run" not in s:
            sys.exit(f"catalog-publish.yml has no step named {name!r}; update tools/catalog_dryrun.py")
        senv = dict(env)
        senv.update({k: str(v) for k, v in (s.get("env") or {}).items() if "${{" not in str(v)})
        cwd = os.path.join(work, s.get("working-directory", "."))
        t = time.time()
        print(f"--- {name}", flush=True)
        r = subprocess.run(["bash", "-eo", "pipefail", "-c", s["run"]], cwd=cwd, env=senv)
        print(f"--- {name}: exit {r.returncode} in {time.time() - t:.0f}s", flush=True)
        if r.returncode:
            print(f"DRY RUN RED at step {name!r} after {time.time() - t0:.0f}s", flush=True)
            sys.exit(1)
    print(f"DRY RUN GREEN: the publish's contract tests pass over the real data ({time.time() - t0:.0f}s)")
    if not a.keep and not a.workdir:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
