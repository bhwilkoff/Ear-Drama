#!/usr/bin/env python3
"""reports.yml's whole job (Decision 088.6): ask the Worker how many reports wait, and keep one issue saying so.

The issue and this log are public. They carry a number and how to read the reports, and nothing else: the Worker's
answer holds nothing else (worker/src/plays-retention.js reportsCount), and tools/test_reports_issue.py proves it
with planted data. GitHub emails the owner when the issue is opened and assigned, and on a comment, so a comment is
written only when the number rises. The owner reads and answers with tools/reports.py.

No stored key: the job's GitHub OIDC token, which the Worker takes from reports.yml on main alone.
"""
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import net_retry

ORIGIN = os.environ.get("REPORTS_ORIGIN", "https://eardrama-api.benwilkoff.workers.dev")
API = os.environ.get("GITHUB_API_URL", "https://api.github.com")
WAITS = tuple(int(w) for w in os.environ.get("REPORTS_WAITS", "5,15,30,60").split(","))
BOT = "github-actions[bot]"
MARK = re.compile(r"<!-- reports-waiting:(\d+) -->")
AGENT = "EarDrama-reports"


def ask(url, headers, body=None, method=None):
    req = urllib.request.Request(url, data=None if body is None else json.dumps(body).encode(), method=method,
                                 headers={"User-Agent": AGENT, "Content-Type": "application/json", **headers})
    with net_retry.urlopen(req, timeout=30, waits=WAITS) as r:
        return json.load(r)


def oidc():
    url = os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"]
    sep = "&" if "?" in url else "?"
    value = ask(url + sep + "audience=" + urllib.parse.quote(ORIGIN, safe=""),
                {"Authorization": "bearer " + os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]}).get("value")
    if not value:
        sys.exit("::error::no OIDC token: the job needs permissions id-token: write")
    print(f"::add-mask::{value}")
    return value


def waiting():
    n = ask(ORIGIN + "/v1/operator/reports/count", {"Authorization": "Bearer " + oidc()}).get("open")
    if type(n) is not int or n < 0:
        sys.exit("::error::the Worker's answer is not a count")
    return n


def github(path, body=None, method=None):
    return ask(f"{API}/repos/{os.environ['GITHUB_REPOSITORY']}{path}",
               {"Authorization": "Bearer " + os.environ["GH_TOKEN"], "Accept": "application/vnd.github+json"}, body, method)


def ours():
    """Our open issues, oldest first. Anyone may write the marker in an issue of their own, so the author decides."""
    found = []
    for page in range(1, 11):
        batch = github("/issues?state=open&per_page=100&creator=" + urllib.parse.quote(BOT, safe="") + f"&page={page}")
        found += [i for i in batch if i["user"]["login"] == BOT and "pull_request" not in i and MARK.search(i.get("body") or "")]
        if len(batch) < 100:
            break
    return sorted(found, key=lambda i: i["number"])


def title(n):
    return "1 report is waiting" if n == 1 else f"{n} reports are waiting"


def text(n, owner):
    return (f"@{owner}: {title(n)}.\n\nRead and answer on your Mac: `python3 tools/reports.py list` "
            f"(`docs/runbooks/reports.md`).\n\n<!-- reports-waiting:{n} -->")


def keep(n, owner):
    """One open issue while n > 0, none at 0. Returns what was done, for the log."""
    mine = ours()
    for extra in mine[1:]:
        github(f"/issues/{extra['number']}", {"state": "closed", "state_reason": "not_planned"}, "PATCH")
    issue = mine[0] if mine else None
    if n == 0:
        if issue:
            github(f"/issues/{issue['number']}", {"state": "closed", "state_reason": "completed"}, "PATCH")
        return "closed" if issue else "no issue needed"
    new = {"title": title(n), "body": text(n, owner)}
    if not issue:
        made = github("/issues", {**new, "assignees": [owner]}, "POST")
        if owner not in [a["login"] for a in made.get("assignees") or []]:
            print("::warning::the issue was not assigned; only its mention can send the email")
        return "opened"
    before = int(MARK.search(issue["body"]).group(1))
    if n == before:
        return "unchanged"
    # The comment is the email. Written first: a run that dies between the two says it twice, never not at all.
    if n > before:
        github(f"/issues/{issue['number']}/comments", {"body": f"@{owner}: {title(n)}."}, "POST")
    github(f"/issues/{issue['number']}", new, "PATCH")
    return "commented" if n > before else "lowered"


def main():
    try:
        n = waiting()
        did = keep(n, os.environ["GITHUB_REPOSITORY_OWNER"])
    except urllib.error.HTTPError as e:
        # The address without its query, and no answer body: both logs are public.
        sys.exit(f"::error::{urllib.parse.urlsplit(e.url or '').path}: HTTP {e.code}")
    except urllib.error.URLError as e:
        sys.exit(f"::error::no answer: {type(e.reason).__name__}")
    print(f"[reports] asked: open={n}, issue {did}")


if __name__ == "__main__":
    main()
