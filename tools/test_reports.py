#!/usr/bin/env python3
"""tools/reports.py against the Worker's own schema: each command, its refusals, and that it prints nothing in CI.

    python3 tools/test_reports.py

`d1` runs on SQLite built from worker/migrations; what each answer does to the Worker's routes is
worker/test/reports.test.js and archive.test.js, over the same statements.
"""
import contextlib
import io
import os
import pathlib
import sqlite3
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
for k in ("CI", "GITHUB_ACTIONS"):
    os.environ.pop(k, None)
import reports as R

failed = []


def check(name, ok):
    if not ok:
        failed.append(name)
        print("FAIL", name)


db = sqlite3.connect(":memory:", isolation_level=None)
db.row_factory = sqlite3.Row
for f in sorted((HERE.parent / "worker" / "migrations").glob("*.sql")):
    db.executescript(f.read_text())
ran = []


def d1(sql, local=None):
    ran.append(sql)
    if sql.lstrip().upper().startswith("SELECT"):
        return [dict(r) for r in db.execute(sql)]
    db.executescript(sql)
    return []


R.d1 = d1
NOW = 4102444800000
db.executescript(f"""
INSERT INTO users (id, created_at) VALUES ('dir', 0), ('zoe', 0);
INSERT INTO play_productions (id, user_id, script_id, script_revision, title, cast_sheet, created_at, updated_at) VALUES ('PROD0001', 'dir', 's', 'r', 'O''Neill''s Play', '[]', 0, 0);
INSERT INTO play_members VALUES ('PROD0001', 'dir', 'Pat', 0), ('PROD0001', 'zoe', 'Zo' || char(27) || '[31me', 1);
INSERT INTO play_invites VALUES ('inv', 'PROD0001', 'dir', 'h', 0, {NOW}, 0);
""")


def take(id, user, seat=None, credit=None):
    db.execute("INSERT INTO play_takes (production_id, id, user_id, seat_id, line_id, part, file, content_type, bytes, frames, sample_rate, capture, created, uploaded_at, credit) "
               "VALUES ('PROD0001', ?, ?, ?, 'l1', 'role:A', 'f', 'audio/wav', 1, 1, 1, 'direct', 0, 1, ?)", (id, user, seat, credit))


def report(id, target, take_id=None, script=0):
    db.execute("INSERT INTO play_reports (id, user_id, production_id, target_user_id, take_id, reason, note, created_at, script) VALUES (?, 'dir', 'PROD0001', ?, ?, 'offensive', 'a note', 1, ?)", (id, target, take_id, script))


def run(*argv):
    out = io.StringIO()
    err = ""
    with contextlib.redirect_stdout(out):
        try:
            R.main(list(argv))
        except SystemExit as e:
            err = str(e)
    return out.getvalue(), err


status = lambda id: db.execute("SELECT status FROM play_reports WHERE id = ?", (id,)).fetchone()[0]
takes = lambda: sorted(r[0] for r in db.execute("SELECT id FROM play_takes"))

take("take-z", "zoe")
take("take-d", "dir")
report("rep-00001", "zoe", "take-z")
report("rep-00002", "zoe")
out, _ = run("list")
check("list counts and names the play", "2 waiting" in out and "O'Neill's Play" in out)
out, _ = run("show", "rep-00001")
check("show has the note, the people and the take", all(w in out for w in ("a note", "From:        Pat", "role:A, line l1", "1 live")))
check("a name cannot send the terminal an escape", "\x1b" not in out)
before = takes()
out, _ = run("remove-take", "rep-00001")
check("without --yes nothing changes", "Run again with --yes" in out and takes() == before and status("rep-00001") == "open")
out, _ = run("remove-take", "rep-00001", "--yes")
check("remove-take", takes() == ["take-d"] and status("rep-00001") == "acted" and "1 still waiting" in out)
check("an answered report is refused", "already acted" in run("dismiss", "rep-00001", "--yes")[1])
check("remove-take on a person is refused", "names a person" in run("remove-take", "rep-00002", "--yes")[1])
take("take-z2", "zoe")
out, _ = run("remove-member", "rep-00002", "--yes")
check("remove-member", takes() == ["take-d"] and db.execute("SELECT COUNT(*) FROM play_members WHERE user_id = 'zoe'").fetchone()[0] == 0
      and db.execute("SELECT revoked FROM play_invites").fetchone()[0] == 1)
report("rep-00003", "dir", "take-d")
check("the director is not removed", "the director" in run("remove-member", "rep-00003", "--yes")[1] and takes() == ["take-d"])
take("take-c", "dir", credit="Ann'); DROP TABLE play_takes;--")
take("take-s", "dir", seat="s1")
report("rep-00004", "dir", "take-c")
check("a credit is quoted, never run", run("remove-member", "rep-00004", "--yes")[1] == "" and takes() == ["take-d", "take-s"])
report("rep-00005", "dir", "take-s")
run("remove-member", "rep-00005", "--yes")
check("a class seat's takes, not the teacher's", takes() == ["take-d"])
report("rep-00006", None)
check("a deleted account is not removed", "already deleted" in run("remove-member", "rep-00006", "--yes")[1])
run("dismiss", "rep-00006", "--yes")
check("dismiss", status("rep-00006") == "dismissed")
run("unshare", "rep-00003", "--yes")
check("unshare", status("rep-00003") == "acted" and takes() == ["take-d"])

db.execute("INSERT INTO play_scripts (production_id, user_id, episode_id, created_at) VALUES ('PROD0001', 'dir', 'show|1949', 0)")
db.execute("UPDATE play_scripts SET body = '[\"O''Neill\" ' || char(27) || ']', bytes = 12 WHERE production_id = 'PROD0001'")
script = lambda: tuple(db.execute("SELECT body, bytes, held_at IS NOT NULL FROM play_scripts").fetchone())
report("rep-00007", "dir", script=1)
report("rep-00008", "zoe")
out, _ = run("list")
check("list says it is a script", "script: offensive" in out)
out, _ = run("show", "rep-00007")
check("show says how to read it and whose transcript it is", "12 bytes, read-script prints it; the transcript of show|1949" in out)
out, _ = run("read-script", "rep-00007")
check("read-script prints the words, with no escape", "O'Neill" in out and "\x1b" not in out)
check("read-script is for a script's report", "not of a script" in run("read-script", "rep-00008")[1])
for op in ("remove-take", "remove-member"):
    check(f"{op} on a script is refused", "names the script" in run(op, "rep-00007", "--yes")[1])
check("remove-script on a person is refused", "names a person" in run("remove-script", "rep-00008", "--yes")[1])
out, _ = run("remove-script", "rep-00007")
check("remove-script without --yes changes nothing", "Run again with --yes" in out and script()[1] == 12)
out, _ = run("remove-script", "rep-00007", "--yes")
check("remove-script", script() == (None, 0, 1) and status("rep-00007") == "acted" and status("rep-00008") == "open" and "Done" in out)
check("the total follows", db.execute("SELECT bytes FROM play_script_total").fetchone()[0] == 0)
check("the text is remembered as removed", [r[0] for r in db.execute("SELECT key FROM play_removed_scripts")] == ["revision:r"])
report("rep-00009", "dir", script=1)
check("a script already gone", "already gone" in run("remove-script", "rep-00009", "--yes")[1] and "already gone" in run("read-script", "rep-00009")[0])
run("dismiss", "rep-00008", "--yes")
run("dismiss", "rep-00009", "--yes")
n = len(ran)
check("an id that is not one is refused before any read", "comes from `list`" in run("show", "x' OR '1'='1")[1] and len(ran) == n)
for var in ("CI", "GITHUB_ACTIONS"):
    os.environ[var] = "true"
    out, err = run("list")
    check(f"never in CI ({var})", out == "" and "never runs in CI" in err and len(ran) == n)
    del os.environ[var]

print("FAIL" if failed else "PASS", "reports.py:", f"{len(failed)} failed" if failed else "every command")
sys.exit(1 if failed else 0)
