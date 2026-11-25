#!/usr/bin/env python3
"""Broken controls for R4-5 on Android (own scripts shared; PLAYS-DESIGN section 13): each line below breaks one rule in one Kotlin
file, and the named JUnit test must fail on it. Mutants that name the same test run in different batches, so one never hides another;
a batch is one Gradle run with every mutant of it applied at once. The files are put back after each batch, whatever happens.
Run it alone, from anywhere: it edits the working tree.

    python3 android/scripts/own_share_mutants.py            # every mutant (about four Gradle runs)
    python3 android/scripts/own_share_mutants.py --list     # check every text is in its file once, run nothing
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
A = "android/app/src/main/java/com/example/appname/"
SUITES = ["OwnShareTest", "OwnShareWireTest", "OwnScriptsTest", "EarCoreTest", "LabelSpecTest", "OwnColorsAndVoicesTest"]

# (file, text, becomes, test method (a substring of its name), what the rule is)
M = [
    (A + "plays/OwnShare.kt", '            put("own", true)\n', "", "Share makes an own production", "the body says own"),
    (A + "plays/OwnShare.kt", '            put("title", script.title)\n', "", "Share makes an own production", "the body carries the title"),
    (A + "plays/OwnShare.kt", "JsonArray(PlaysShare.castSheet(script).map {", "JsonArray(PlaysShare.castSheet(script).take(0).map {", "Share makes an own production", "the body carries the cast sheet"),
    (A + "plays/OwnShare.kt", "OwnScript.canonicalLines(linesOf(script))", "linesOf(script).toString()", "Share makes an own production", "the text is canonical"),
    (A + "plays/OwnShare.kt", 'if (e.code != "already_there") throw e', "throw e", "a text already there is the same text", "already_there is success"),
    (A + "plays/OwnShare.kt", "PlaysException.Kind.Refused -> e.status >= 500", "PlaysException.Kind.Refused -> true", "can never pass undoes the share", "a refusal that is final does not pass"),
    (A + "plays/OwnShare.kt", "            else -> true\n        }\n    }\n\n    /** Sends a production", "            else -> false\n        }\n    }\n\n    /** Sends a production", "may pass later leaves it owed", "no answer passes"),
    (A + "plays/OwnShare.kt", "            freeze()\n            return e\n", "            return e\n", "may pass later leaves it owed", "what is owed is frozen"),
    (A + "plays/OwnShare.kt", "        store.unshare(local.id)\n        throw unsent", "        throw unsent", "can never pass undoes the share", "the share is undone here"),
    (A + "plays/OwnShare.kt", "                try { api.deleteProduction(pid) }", "                try { Unit }", "can never pass undoes the share", "and on the Worker"),
    (A + "plays/OwnShare.kt", "try { scripts?.freeze(script.id) } catch (e: CancellationException) { throw e } catch (_: Exception) { }", "scripts?.freeze(script.id)", "a disk that will not keep the freeze", "a freeze failure loses nothing"),
    (A + "plays/OwnShare.kt", '        if (sha12(got.bytes) != revision) throw damaged("digest")\n', "", "what did not arrive whole", "the digest is the revision"),
    (A + "plays/OwnShare.kt", '            if (OwnScript.canonicalLines(parsed) != text) throw damaged("text")\n', "", "what did not arrive whole", "the bytes are canonical"),
    (A + "plays/OwnShare.kt", "        OwnScript.refusalOf(map)?.let { throw damaged(it) }\n", "", "what did not arrive whole", "the core keeps it"),
    (A + "plays/OwnShare.kt", '        if (!fit(script)) throw damaged("cast sheet")\n', "", "the lines match the cast sheet", "it matches the cast sheet"),
    (A + "plays/OwnShare.kt", 'field("id") != id || field("revision") != revision', 'field("revision") != revision', "what did not arrive whole", "x-script names this script"),
    (A + "plays/OwnShare.kt", "device(id)?.takeIf { it.revision == revision }?.let { return it }\n", "", "what is here comes first", "the device's script is here"),
    (A + "plays/OwnShare.kt", "            fetched[key] = script\n", "", "a script is fetched once a page", "fetched once"),
    (A + "plays/OwnShare.kt", "kept(pid)?.takeIf { it.id == id && it.revision == revision }", "kept(pid)?.takeIf { false }", "what is here comes first", "the production's own copy"),
    (A + "plays/OwnShare.kt", 'held = s.state == "removed" && s.by != null', 'held = s.state == "removed"', "the text's state", "a removal with the account gone holds nobody"),
    (A + "plays/OwnScripts.kt", 'if (snap.shared == null && read(', 'if (false && read(', "sharing freezes the script", "a frozen script is not written over"),
    (A + "plays/OwnScripts.kt", "base.copy(id = newId(),", "base.copy(id = script.id,", "Edit a copy - a new script", "a copy has its own id"),
    (A + "plays/OwnScripts.kt", "done = true, shared = null)", "done = true)", "Edit a copy - a new script", "a copy is not frozen"),
    (A + "plays/OwnScripts.kt", "script.title.take(OwnScript.MAX_TITLE - COPY.length) + COPY", "script.title + COPY", "Edit a copy - a new script", "a copy's title stays inside the cap"),
    (A + "plays/OwnScripts.kt", '            rec.shared?.let { put("shared", JsonPrimitive(java.time.Instant.ofEpochMilli(it).toString())) }\n', "", "sharing freezes the script", "Export my data says when it was shared"),
    (A + "plays/OwnScripts.kt", "(why ?: parsed?.let { OwnScript.builtRefusal(it.lines) })", "why", "Next asks what Done would keep", "Next judges the built size"),
    (A + "plays/PlaysShare.kt", "isDirector(rec, me) && rec.archive == null && rec.publishable && complete(rec, script)", "isDirector(rec, me) && rec.archive == null && complete(rec, script)", "Publish is absent", "Publish is absent for an own script"),
    (A + "plays/PlaysShare.kt", "me != null && rec.archive == null && rec.publishable && rec.director != me", "me != null && rec.archive == null && rec.director != me", "Publish is absent", "no consent is asked for what never publishes"),
    (A + "plays/ClassExport.kt", '(script["state"] as? JsonPrimitive)?.contentOrNull != "kept"', "false", "the class export gains", "only a kept script gains lines"),
    (A + "plays/ReadSession.kt", '.getOrNull() } ?: throw ReadFailure("error")', ".getOrNull() } ?: return@guarded null", "a take whose fields cannot be read", "an unreadable x-take is an error"),
    (A + "account/WorkerApi.kt", "return r.bodyAsBytes() to r.headers[header]\n    }\n\n    /** The `wss://`", 'return r.bodyAsBytes() to r.headers["x-take"]\n    }\n\n    /** The `wss://`', "each door asks its own route", "x-script comes with the bytes"),
    (A + "data/LabelSpec.kt", "val room = if (more > 0) ", "val room = if (more > 99) ", "aPlaysPlusNNeverStandsOnItsBars", "+N never stands on its bars"),
    (A + "plays/EarCore.kt", "while (why == null && renames.isNotEmpty()", "while (false && renames.isNotEmpty()", "rename", "one Undo takes a rename back, the order with it"),
    (A + "plays/EarCore.kt", "if (name in order) order.filter { it != from } else", "if (false) order.filter { it != from } else", "rename", "a name another part has joins the two"),
    (A + "plays/EarCore.kt", 'OwnOp("rename", part = from, rename = name), env())', 'OwnOp("rename", part = from, rename = name))', "rename", "a take on a carried line keeps its part's name"),
    (A + "ui/TabLabels.kt", "screenWidthPx / items - PADDING_DP * density", "screenWidthPx / items", "a bar's labels show only", "a label fits its tab less its padding"),
    (A + "plays/VoiceCast.kt", "offByDefault = isNovelty(v.name)", "offByDefault = false", "Defaults never pick a novelty voice", "Defaults leave novelty voices out"),
    (A + "ui/screens/OwnSheets.kt", "mapIndexed { i, p -> p.first to hueKeyAt(i) }.toMap()\n\n", "mapIndexed { i, p -> p.first to hueKeyAt(i + 1) }.toMap()\n\n", "a part's color is the same", "the parts page's colors are the script page's"),
]


def batches():
    seen, out = {}, []
    for m in M:
        n = seen.get(m[3], 0)
        seen[m[3]] = n + 1
        while len(out) <= n:
            out.append([])
        out[n].append(m)
    return out


def check():
    bad = 0
    for f, a, b, t, why in M:
        s = (ROOT / f).read_text()
        if s.count(a) != 1:
            print(f"NOT ONCE ({s.count(a)}): {f}: {a[:60]!r}")
            bad += 1
    return bad


def failures():
    names = set()
    for x in (ROOT / "android/app/build/test-results/testDebugUnitTest").glob("*.xml"):
        text = x.read_text()
        for m in re.finditer(r'<testcase name="([^"]*)"[^>]*?(?:/>|>(.*?)</testcase>)', text, re.S):
            if m.group(2) and "<failure" in m.group(2):
                names.add(m.group(1))
    return names


def run(batch):
    files = {}
    try:
        for f, a, b, t, why in batch:
            p = ROOT / f
            files.setdefault(f, p.read_text())
            p.write_text(p.read_text().replace(a, b, 1))
        cmd = ["nice", "-n", "15", "./gradlew", "--max-workers=2", ":app:testDebugUnitTest"] + [x for s in SUITES for x in ("--tests", f"*{s}*")]
        subprocess.run(cmd, cwd=ROOT / "android", stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
        failed = failures()
    finally:
        for f, text in files.items():
            (ROOT / f).write_text(text)
    missed = 0
    for f, a, b, t, why in batch:
        hit = any(t in n for n in failed)
        print(f"{'caught' if hit else 'MISSED'}  {why}  [{t}]")
        missed += 0 if hit else 1
    return missed


if __name__ == "__main__":
    if "--list" in sys.argv:
        sys.exit(1 if check() else 0)
    if check():
        sys.exit(1)
    missed = 0
    for i, batch in enumerate(batches(), 1):
        print(f"-- batch {i}: {len(batch)} mutants")
        missed += run(batch)
    subprocess.run(["./gradlew", "--stop"], cwd=ROOT / "android", stdout=subprocess.DEVNULL)
    print(f"{len(M)} mutants, {missed} missed")
    sys.exit(1 if missed else 0)
