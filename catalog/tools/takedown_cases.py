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
"""
import argparse
import datetime
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import takedown_check as C

API = "https://eardrama-api.benwilkoff.workers.dev/v1/takedown"
ENV_FILE = os.path.expanduser("~/.config/eardrama/takedown.env")
MAX_REMOVALS = 5     # a run removes at most this many on its own; the rest wait

REASONS = {
    "title_word_only": "The claim names only a word of this title, which is how a notice matched on a word reads.",
    "old_recording": "The record shows nothing modern, and the recording is old enough to have no recording right.",
    "not_copyright": "This request is not a copyright notice, so it is yours to decide.",
    "incomplete_notice": "This notice is missing an element the law requires.",
    "unread_link": "A link in this request names nothing the check could read.",
    "run_limit": "This run reached its limit on automatic removals.",
}


def token() -> str:
    t = os.environ.get("TAKEDOWN_TOKEN")
    if not t and os.path.exists(ENV_FILE):
        for line in open(ENV_FILE).read().splitlines():
            if line.startswith("TAKEDOWN_TOKEN="):
                t = line.split("=", 1)[1].strip()
    if not t:
        sys.exit("No TAKEDOWN_TOKEN in the environment or " + ENV_FILE)
    return t


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
        print(call("/cases", {
            "kind": "copyright", "links": a.links, "work": a.work, "source": a.source,
            "external_ref": a.ref, "name": a.name, "org": a.org, "complete": a.complete})["ref"])
    elif a.cmd == "list":
        for c in call("/cases?status=open,approved,held")["cases"]:
            print(c["ref"], c["status"], c["source"])
    elif a.cmd == "show":
        print(json.dumps(call("/cases/" + a.ref), indent=1))
    elif a.cmd == "decide":
        status = "approved" if a.word == "remove" else "declined"
        call("/cases/" + a.ref, {"status": status, "note": a.note})
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
