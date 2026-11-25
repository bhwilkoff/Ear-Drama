#!/usr/bin/env python3
"""Reports, read and answered by the owner (docs/runbooks/reports.md, Decision 088.6).

    list                       the reports waiting
    show ID                    one report, with everything needed to answer it
    dismiss ID --yes           nothing is wrong; what it held may publish
    remove-take ID --yes       the reported take leaves the production, and archive.org if it is there
    read-script ID             the reported script's words, to judge it by
    remove-script ID --yes     the production's script leaves our server; nobody new comes in and nothing more is recorded
    remove-member ID --yes     the reported person leaves the production with their takes; its invites close
    unshare ID --yes           every invite closes and every published line leaves archive.org

Without --yes an answer only says what it would do. An answer closes the report.

Reads and writes the private record in D1 through the owner's own wrangler login, as the take-down commands do
(catalog/tools/takedown_cases.py): no token, and it refuses to run in CI, whose log is public. It prints to this
terminal and writes no file. The statements are worker/ops/reports.json, which the Worker's suite runs against the
Worker's own rules.

    --local DIR                a local `wrangler dev --persist-to DIR` bench instead of the real record
"""
import argparse
import datetime
import json
import os
import pathlib
import re
import subprocess
import sys
import zoneinfo

WORKER = pathlib.Path(__file__).resolve().parent.parent / "worker"
OPS = json.loads((WORKER / "ops" / "reports.json").read_text())
ID = re.compile(r"^[A-Za-z0-9_-]{8,64}$")
ANSWERS = ("dismiss", "remove-take", "remove-script", "remove-member", "unshare")


def q(v) -> str:
    """One SQL literal. wrangler d1 execute takes no bound parameters, so every value is quoted here."""
    if v is None:
        return "NULL"
    if isinstance(v, (bool, int)):
        return str(int(v))
    return "'" + str(v).replace("'", "''") + "'"


def fill(sql: str, values: dict) -> str:
    return re.sub(r":([a-z]+)", lambda m: q(values[m[1]]), sql)


def d1(sql: str, local=None) -> list:
    where = ["--local", "--persist-to", local] if local else ["--remote"]
    # -- before nothing: the statement is one argument, never a shell string.
    r = subprocess.run(["npx", "--no-install", "wrangler", "d1", "execute", "eardrama", *where, "--json", "--command=" + sql],
                       cwd=WORKER, capture_output=True, text=True)
    if r.returncode:
        sys.exit("wrangler could not reach the record (`npx wrangler login` in worker/):\n" + clean(r.stderr or r.stdout)[-600:])
    return json.loads(r.stdout)[-1].get("results", [])


def clean(v) -> str:
    """A person's words, safe on a terminal: no escape sequence, no direction trick, one line."""
    return re.sub(r"[\x00-\x1f\x7f-\x9f​-‏ -‮⁦-⁩]+", " ", str(v)) if v is not None else "-"


def when(ms) -> str:
    return datetime.datetime.fromtimestamp(ms / 1000, zoneinfo.ZoneInfo("America/Denver")).strftime("%Y-%m-%d %H:%M %Z") if ms else "-"


def plan(op: str, r: dict):
    """(the statements' name, what it will do) or a refusal."""
    if op == "dismiss":
        return op, "close this report; nothing else changes"
    if op == "unshare":
        return op, (f"close {r['live_invites']} live invite(s) and take every published line off archive.org; "
                    "the people already in it keep it")
    if op == "remove-script":
        if not r["script"]:
            sys.exit("this report names a " + ("take" if r["take_id"] else "person") + ", not the script")
        if not r["script_bytes"]:
            sys.exit("that script is already gone: dismiss the report")
        return op, "remove the script's words; nobody new can come in and nothing more is recorded; the people in it keep their copies"
    if r["script"]:
        sys.exit("this report names the script: remove-script, unshare or dismiss")
    if op == "remove-take":
        if not r["take_id"]:
            sys.exit("this report names a person, not a take: remove-member, unshare or dismiss")
        if not r["line_id"]:
            sys.exit("that take is already gone: dismiss the report")
        return op, f"remove one take of {clean(r['part'])}" + (" and its file on archive.org" if r["file_state"] not in (None, "removed") else "")
    if r["credit"] or r["seat"]:
        return "remove-maker", f"remove every take by {clean(r['credit']) if r['credit'] else 'that class seat'} in this production"
    if not r["target_user_id"]:
        sys.exit("that account is already deleted: dismiss the report")
    if r["names_director"]:
        sys.exit("that is the director, whose production this is: unshare, or remove-take")
    return op, f"remove {clean(r['target_name'])} with {r['their_takes']} take(s), open their parts, and close every invite"


def main(argv=None):
    if os.environ.get("GITHUB_ACTIONS") or os.environ.get("CI"):
        sys.exit("reports.py prints private records; it never runs in CI")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--local", metavar="DIR")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list")
    sub.add_parser("show").add_argument("id")
    sub.add_parser("read-script").add_argument("id")
    for op in ANSWERS:
        s = sub.add_parser(op)
        s.add_argument("id")
        s.add_argument("--yes", action="store_true")
    a = ap.parse_args(argv)
    now = int(datetime.datetime.now().timestamp() * 1000)

    if a.cmd == "list":
        rows = d1(OPS["list"], a.local)
        for r in rows:
            print(f"{r['id']}  {when(r['created_at'])}  {r['kind']}: {r['reason']}  {clean(r['title'])}"
                  + ("  (class)" if r["class"] else "") + (f"  ({r['archive']} on archive.org)" if r["archive"] else ""))
        print(f"{len(rows)} waiting")
        return
    if not ID.match(a.id):
        sys.exit("a report id comes from `list`")
    rows = d1(fill(OPS["show"], {"id": a.id, "now": now}), a.local)
    if not rows:
        sys.exit("no report with that id (its reporter's account may be deleted)")
    r = rows[0]
    if a.cmd == "show":
        for label, v in [
            ("Report", f"{r['id']}, {r['status']}, {when(r['created_at'])}"),
            ("Reason", r["reason"]), ("Note", r["note"]), ("From", r["reporter_name"]),
            ("About", (r["credit"] or r["target_name"] or "-") + (" (the director)" if r["names_director"] else "")),
            ("Play", r["title"]), ("Script", r["script"] and ((f"{r['script_bytes']} bytes, read-script prints it" if r["script_bytes"] else "already gone")
                                                                + (f"; the transcript of {r['episode_id']}" if r["episode_id"] else ""))),
            ("Take", r["take_id"] and f"{r['part']}, line {r['line_id']}, {when(r['uploaded_at'])}"),
            ("Class", r["class_id"] and "a class production: its teacher can act too"),
            ("Invites", f"{r['live_invites']} live"), ("archive.org", r["item_url"] or r["archive"]),
            ("File", r["file_name"]),
        ]:
            if v:
                print(f"{label + ':':<13}{clean(v)}")
        print("The audio is on its makers' devices and, if published, archive.org; the Worker keeps none.")
        return
    if a.cmd == "read-script":
        if not r["script"]:
            sys.exit("this report is not of a script")
        rows = d1(fill(OPS["read-script"], {"production": r["production_id"]}), a.local)
        print(clean(rows[0]["body"]) if rows and rows[0]["body"] else "that script is already gone")
        return
    if r["status"] != "open":
        sys.exit(f"already {r['status']}")
    name, what = plan(a.cmd, r)
    if not a.yes:
        print(f"Would {what}. Run again with --yes.")
        return
    values = {"id": a.id, "production": r["production_id"], "take": r["take_id"], "target": r["target_user_id"],
              "seat": r["seat"], "credit": r["credit"], "reason": r["reason"], "now": now}
    d1("; ".join(fill(s, values) for s in OPS[name]), a.local)
    after = d1(fill(OPS["show"], {"id": a.id, "now": now}), a.local)
    print(f"Done: {what}. Report {after[0]['status'] if after else 'gone'}; {d1(OPS['count'], a.local)[0]['n']} still waiting.")


if __name__ == "__main__":
    main()
