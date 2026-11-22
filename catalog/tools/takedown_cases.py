#!/usr/bin/env python3
"""Take-down cases: the owner's commands and the takedown-check workflow's
(catalog/DECISIONS.md 029).

    open --links URL --work "NAME" [--source google --ref ID --complete]
    list                      open, held and approved cases, no personal details
    show TD-XXXXXXXX          the whole private record; for a person, never CI
    decide TD-XXXXXXXX remove|keep [--note TEXT]
    judge --out FILE          the workflow: read cases, check records, write the list
    report --updates FILE     the workflow, after the list is pushed

The workflow's log and the issues it opens are public. Nothing it prints or
files comes from a requester's own words, and that includes the links and the
name of the work: it says only a case number, a key the catalog itself serves,
and a reason from REASONS below.

No stored token: judge and report call the Worker with takedown-check.yml's
GitHub OIDC token, and the owner's open, list, show and decide read and write
the private record in D1 through their own wrangler login.
"""
import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import takedown_check as C

ORIGIN = "https://eardrama-api.benwilkoff.workers.dev"
API = ORIGIN + "/v1/takedown"
WORKER = os.path.join(os.path.dirname(os.path.dirname(HERE)), "worker")
ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
REF = re.compile(r"^TD-[0-9A-Z]{8}$")
MAX_REMOVALS = 5     # a run removes at most this many on its own; the rest wait

REASONS = {
    "title_word_only": "The claim names only a word of this title, which is how a notice matched on a word reads.",
    "old_recording": "The record shows nothing modern, and the recording is old enough to have no recording right.",
    "not_copyright": "This request is not a copyright notice, so it is yours to decide.",
    "incomplete_notice": "This notice is missing an element the law requires.",
    "unread_link": "A link in this request names nothing the check could read.",
    "run_limit": "This run reached its limit on automatic removals.",
}


_token = []


def token() -> str:
    """takedown-check.yml's GitHub OIDC token for the Worker (worker/src/github-oidc.js): no stored secret.

    Only that workflow, on main, can get one the Worker accepts; the owner's own
    commands (open, list, show, decide) read the private record through D1 instead.
    """
    if _token:
        return _token[0]
    url = os.environ.get("ACTIONS_ID_TOKEN_REQUEST_URL")
    bearer = os.environ.get("ACTIONS_ID_TOKEN_REQUEST_TOKEN")
    if not url or not bearer:
        sys.exit("judge and report run only in takedown-check.yml (gh workflow run takedown-check.yml)")
    sep = "&" if "?" in url else "?"
    req = urllib.request.Request(url + sep + "audience=" + urllib.parse.quote(ORIGIN, safe=""),
                                 headers={"Authorization": "bearer " + bearer, "User-Agent": "EarDrama-takedown"})
    with urllib.request.urlopen(req, timeout=30) as r:
        value = json.load(r).get("value")
    if not value:
        sys.exit("no OIDC token: the job needs permissions id-token: write")
    _token.append(value)
    return value


def call(path, body=None):
    req = urllib.request.Request(
        API + path, data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json",
                 "User-Agent": "EarDrama-takedown"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit(f"{path}: HTTP {e.code}")


def q(v) -> str:
    """One SQL literal. wrangler d1 execute takes no bound parameters, so every value is quoted here."""
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "1" if v else "0"
    if isinstance(v, int):
        return str(v)
    return "'" + str(v).replace("'", "''") + "'"


def d1(sql: str) -> list:
    """The owner's read and write of the private record, through their own wrangler login (in the
    Keychain since `wrangler login --use-keyring`). Nothing is printed unless the command prints it."""
    out = subprocess.run(["npx", "--no-install", "wrangler", "d1", "execute", "eardrama", "--remote", "--json",
                          "--command", sql], cwd=WORKER, check=True, capture_output=True, text=True).stdout
    return json.loads(out)[0].get("results", [])


def check_ref(ref: str) -> str:
    if not REF.match(ref):
        sys.exit("a case number looks like TD-XXXXXXXX")
    return ref


def new_ref() -> str:
    return "TD-" + "".join(ALPHABET[b % 32] for b in os.urandom(8))


def gh(*args) -> str:
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout


def owner_decision(ref):
    """The owner's newest `remove` or `keep` on the case's issue, and the issue."""
    found = json.loads(gh("issue", "list", "--state", "open", "--search", f"{ref} in:title",
                          "--json", "number,title"))
    issue = next((i for i in found if ref in i["title"]), None)
    if not issue:
        return None, None
    data = json.loads(gh("issue", "view", str(issue["number"]), "--json", "comments"))
    for c in reversed(data["comments"]):
        if c.get("authorAssociation") == "OWNER":
            word = (c.get("body") or "").strip().split()[:1]
            if word and word[0].lower() in ("remove", "keep"):
                return word[0].lower(), issue["number"]
    return None, issue["number"]


def judge_case(case, cat, read=None):
    """[{scope, key, action, reason}], one per link. `read` fetches the archive.org record."""
    read = read or (lambda url: C.read_record(C.archive_record(url)))
    out = []
    for t in C.targets(case.get("links")):
        if "unread" in t:
            out.append({"key": None, "action": "hold", "reason": "unread_link"})
            continue
        item = cat.find(t["scope"], t["id"])
        ev = read(item.get("url")) if item else {"read": False}
        v = C.verdict({"kind": case.get("kind"), "complete": bool(case.get("complete")),
                       "work": case.get("work")}, item, ev)
        out.append({"scope": item["scope"] if item else None, "key": item["key"] if item else None, **v})
    return out or [{"key": None, "action": "hold", "reason": "unread_link"}]


def cmd_judge(a, cat=None, read=None, today=None):
    cases = call("/cases?status=open,approved,held")["cases"]
    today = today or datetime.date.today().isoformat()
    updates, removed = [], 0
    cat = cat or C.Catalog()
    for case in cases:
        ref = case["ref"]
        number = None
        if case["status"] == "held":
            word, number = owner_decision(ref)
            if word == "keep":
                updates.append({"ref": ref, "status": "declined", "issue": number})
                print(f"{ref}: declined by the owner")
                continue
            if word != "remove":
                continue
            case["status"] = "approved"
            print(f"{ref}: approved by the owner")
        elif case["status"] == "approved":
            number = owner_decision(ref)[1]
        if case["status"] == "approved":
            hits = [cat.find(t["scope"], t["id"]) for t in C.targets(case.get("links")) if "id" in t]
            hits = [h for h in hits if h]
            C.add_lines([(h["scope"], h["key"]) for h in hits], ref, today)
            updates.append({"ref": ref, "status": "removed", "issue": number})
            print(f"{ref}: removing {' '.join(h['key'] for h in hits)}")
            continue
        results = judge_case(case, cat, read)
        go = [r for r in results if r["action"] == "remove"]
        room = max(0, MAX_REMOVALS - removed)
        for r in go[room:]:
            r.update(action="hold", reason="run_limit")
        go = go[:room]
        removed += len(go)
        C.add_lines([(r["scope"], r["key"]) for r in go], ref, today)
        holds = [r for r in results if r["action"] == "hold"]
        status = "held" if holds else ("removed" if go else "closed")
        updates.append({"ref": ref, "status": status, "verdict": results})
        for r in results:
            # A link's own text is the requester's; only a key the catalog serves is named.
            print(f"{ref}: {r['key'] or '-'} {r['action']} {r['reason']}")
    with open(a.out, "w") as f:
        json.dump(updates, f)
    print(f"{len(cases)} cases read, {len(updates)} changed")


def issue_body(u):
    lines = [f"Case `{u['ref']}` needs your decision. Reply `remove` or `keep`.", ""]
    for r in u["verdict"]:
        if r["action"] != "hold":
            continue
        where = f"https://eardrama.org/{r['scope']}/{r['key']} " if r.get("key") else ""
        lines.append(f"- {where}{REASONS[r['reason']]}")
    lines += ["", f"The request itself: `python3 catalog/tools/takedown_cases.py show {u['ref']}`"]
    return "\n".join(lines)


def cmd_report(a):
    for u in json.load(open(a.updates)):
        call(f"/cases/{u['ref']}",
             {"status": u["status"], **({"verdict": u["verdict"]} if "verdict" in u else {})})
        if u["status"] == "held":
            gh("issue", "create", "--title", f"Take-down case {u['ref']}", "--body", issue_body(u))
        if u.get("issue"):
            gh("issue", "close", str(u["issue"]), "--comment", f"Case is now {u['status']}.")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    o = sub.add_parser("open")
    o.add_argument("--links", required=True)
    o.add_argument("--work", default="")
    o.add_argument("--source", default="email", choices=["email", "google"])
    o.add_argument("--ref", default="")
    o.add_argument("--name", default="")
    o.add_argument("--org", default="")
    o.add_argument("--complete", action="store_true")
    sub.add_parser("list")
    s = sub.add_parser("show")
    s.add_argument("ref")
    d = sub.add_parser("decide")
    d.add_argument("ref")
    d.add_argument("word", choices=["remove", "keep"])
    d.add_argument("--note", default="")
    j = sub.add_parser("judge")
    j.add_argument("--out", required=True)
    r = sub.add_parser("report")
    r.add_argument("--updates", required=True)
    a = ap.parse_args()
    if a.cmd == "open":
        ref = new_ref()
        d1("INSERT INTO takedown_cases (ref, created_ms, status, kind, complete, source, external_ref, links, work, "
           "name, org) VALUES (" + ", ".join(q(v) for v in (
               ref, int(datetime.datetime.now().timestamp() * 1000), "open", "copyright", a.complete, a.source,
               a.ref[:200] or None, a.links[:4000], a.work[:1000] or None, a.name[:200] or None,
               a.org[:200] or None)) + ")")
        print(ref)
    elif a.cmd == "list":
        for c in d1("SELECT ref, status, source FROM takedown_cases WHERE status IN ('open','approved','held') "
                    "ORDER BY created_ms LIMIT 50"):
            print(c["ref"], c["status"], c["source"])
    elif a.cmd == "show":
        rows = d1("SELECT * FROM takedown_cases WHERE ref = " + q(check_ref(a.ref)))
        print(json.dumps(rows[0], indent=1) if rows else "unknown case")
    elif a.cmd == "decide":
        status = "approved" if a.word == "remove" else "declined"
        closed = int(datetime.datetime.now().timestamp() * 1000) if status == "declined" else None
        d1(f"UPDATE takedown_cases SET status = {q(status)}, closed_ms = {q(closed)}, "
           f"note = COALESCE({q(a.note[:2000] or None)}, note) WHERE ref = {q(check_ref(a.ref))}")
        if a.word == "keep":
            number = owner_decision(a.ref)[1]
            if number:
                gh("issue", "close", str(number), "--comment", "Case is now declined.")
        print(a.ref, status)
    elif a.cmd == "judge":
        cmd_judge(a)
    elif a.cmd == "report":
        cmd_report(a)


if __name__ == "__main__":
    main()
