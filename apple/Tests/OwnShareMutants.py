#!/usr/bin/env python3
"""Broken controls for the R4-5 Apple rules: each mutant edits one line of the Swift source in a scratch clone, runs the focused
suites, and wants a failure ("caught"). A mutant that leaves the suites green "survived", which is a test that does not test.

    python3 apple/Tests/OwnShareMutants.py <clone> [only-this-name]

`<clone>` is a /private/tmp clone with `xcodegen generate` run (never ~/Documents: a standing privacy prompt hangs xctest there).
The clone's apple/ is restored from this checkout before each mutant and after the last.
"""
import os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CLONE = sys.argv[1]
ONLY = sys.argv[2] if len(sys.argv) > 2 else None
SUITES = ["OwnShareTests", "ReadLeaveTests", "ReadCoreTests", "PartColorRuleTests", "LabelSpecTests", "NoveltyVoiceTests", "EarTests"]

P = "apple/Core/Plays/"
MUTANTS = [
    ("passes treats a 4xx as passing", P + "OwnShare.swift", "return !(400...499 ~= r.status)", "return (400...499 ~= r.status)"),
    ("passes treats 401 and 429 as final", P + "OwnShare.swift", "if r.kind == .unauthorized || r.status == 429 { return true }", "if false { return true }"),
    ("sendOrUndo does not freeze after a passing failure", P + "OwnShare.swift", "            await freeze()\n            return error", "            return error"),
    ("arrived skips the digest", P + "OwnShare.swift", 'guard digest == revision else { throw damaged("digest") }', ""),
    ("arrived skips the canonical-form check", P + "OwnShare.swift", "OwnScript.canonicalBytes(tree) == [UInt8](got.bytes)", "true"),
    ("arrived skips the core's refusal", P + "OwnShare.swift", 'if OwnScript.refusalOf(shaped) != nil { throw damaged("core") }', ""),
    ("arrived skips x-script's names", P + "OwnShare.swift", "meta.id == id, meta.revision == revision", "true"),
    ("arrived skips the fit", P + "OwnShare.swift", 'guard fit(script) else { throw damaged("cast sheet") }', ""),
    ("Fit.invite ignores a part's line count", P + "OwnShare.swift", "(w.lines == nil || $0.lineCount == w.lines)", "true"),
    ("Fit.room ignores the claims", P + "OwnShare.swift", "{ holdsLines($0, [snap.cursor]) && holdsParts($0, Array(snap.claims.keys)) }", "{ holdsLines($0, [snap.cursor]) }"),
    ("Fit.seat ignores `to`", P + "OwnShare.swift", "assignments.flatMap { [$0.from, $0.to] }", "assignments.map { $0.from }"),
    ("scriptOf asks the Worker before the production's copy", P + "OwnShare.swift", "let kept = local.kept(pid), kept.id == id, kept.revision == revision", 'let kept = local.kept(pid), kept.id == "x"'),
    ("scriptOf forgets what it fetched", P + "OwnShare.swift", "await fetched.put(key, script)", ""),
    ("publishable is true for every record", P + "OwnShare.swift", "rec.publishable != false", "true"),
    ("a removal by anyone is held", P + "OwnShare.swift", 'held: own.state == "removed" && own.by != nil', 'held: own.state == "removed"'),
    ("a transcript's episode is not sent", P + "OwnShare.swift", "episodeID: own ? script.episode : nil", "episodeID: nil"),
    ("a refused share is not undone here", P + "PlaysShare.swift", "try? store.unshare(local.id)", ""),
    ("an own script's text already there is an error", P + "OwnShare.swift", 'PlaysRefusal.from(error).code != "already_there"', "true"),
    ("parse reads a boolean as a number", P + "OwnShare.swift", "if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }", ""),
    ("keep ignores a frozen script", P + "OwnStore.swift", "if row(snap.id)?.shared != nil, snap.shared == nil { throw Failure.shared }", ""),
    ("a copy keeps the shared mark", P + "OwnStore.swift", "        rec.shared = nil\n", ""),
    ("leave says nothing", P + "ReadSession.swift", "Task { _ = try? await wire.send(code: code, key: key, message: data) }", ""),
    ("a pause says goodbye", P + "ReadSession.swift", "func pause() { stopTransport() }", "func pause() { leave() }"),
    ("a class's leading student may remove", P + "ReadCore.swift", 'memberID == room.owner || (room.kind == "adult" && memberID == room.leader)', "memberID == room.owner || memberID == room.leader"),
    ("not_a_member has no words", P + "ReadCore.swift", '"not_a_member": "You are no longer in this reading.",', ""),
    ("the casting page colors by the order named", P + "EarCore.swift", ".sorted { $0.element.lines != $1.element.lines ? $0.element.lines > $1.element.lines : $0.offset < $1.offset }", ".sorted { $0.offset < $1.offset }"),
    ("the label's +N ignores its room", "apple/Core/Catalog/LabelSpec.swift", "let room = more > 0 ?", "let room = more > 99 ?"),
    ("a novelty voice by name is a default", P + "VoiceCast.swift", "noveltyNames.contains(identifier", "false && noveltyNames.contains(identifier"),
]


def sync():
    subprocess.run(["rsync", "-a", "--delete", f"{ROOT}/apple/", f"{CLONE}/apple/"], check=True)


def run():
    only = [f"-only-testing:EarDramaTests/{s}" for s in SUITES]
    env = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
    out = subprocess.run(["nice", "-n", "15", "xcodebuild", "test", "-scheme", "EarDrama", "-destination", "platform=macOS", "-jobs", "4",
                          "CODE_SIGNING_ALLOWED=NO", "-derivedDataPath", "/private/tmp/ed-dd-mac", *only],
                         cwd=CLONE, env=env, capture_output=True, text=True).stdout
    failed = re.search(r"Test run with \d+ tests? in \d+ suites? failed", out) is not None
    built = "Test run with" in out
    return built, failed, out


def main():
    sync()
    results = []
    for name, path, old, new in MUTANTS:
        if ONLY and ONLY not in name:
            continue
        sync()
        target = f"{CLONE}/{path}"
        src = open(target).read()
        if old not in src:
            results.append((name, "NOT APPLIED"))
            print(f"NOT APPLIED  {name}", flush=True)
            continue
        open(target, "w").write(src.replace(old, new, 1))
        built, failed, out = run()
        verdict = "caught" if built and failed else ("SURVIVED" if built else "DID NOT BUILD")
        results.append((name, verdict))
        print(f"{verdict:13} {name}", flush=True)
    sync()
    bad = [r for r in results if r[1] != "caught"]
    print(f"\n{len(results) - len(bad)} of {len(results)} caught")
    sys.exit(1 if bad else 0)


main()
