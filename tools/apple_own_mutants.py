#!/usr/bin/env python3
"""Broken controls for own scripts and casting by ear on Apple (Decision 088.3): each line below is one rule broken
in one Swift file; the macOS Core tests (OwnStoreTests, OwnPartsModelTests, OwnDoorTests, EarTests) must fail on it.
The file is put back after each, whatever happens. Run it alone: it edits the working tree.

    python3 tools/apple_own_mutants.py            # every mutant (about a minute each)
    python3 tools/apple_own_mutants.py 3 7        # those only
    MUTANT_DERIVED=/path  a derived data folder already built
    python3 tools/apple_own_mutants.py --list     # check every text is in its file once, run nothing
"""
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
P = "apple/Core/Plays/"
SUITES = ["OwnStoreTests", "OwnPartsModelTests", "OwnDoorTests", "EarSessionTests", "EarCuesTests", "EarModelTests"]

MUTANTS = [
    # js/ear.test.js's own, over EarCore.swift
    (P + "EarCore.swift", "        lit = k\n        guard playing", "        lit = k == 0 ? 1 : k\n        guard playing", "before the first line none is lit"),
    (P + "EarCore.swift", "let moved = k != lit", "let moved = true", "a tick says when the line changes"),
    (P + "EarCore.swift", "        from = k\n        if next", "        from = 0\n        if next", "lines between ticks are heard"),
    (P + "EarCore.swift", "named: who != nil && who != before", "named: who != nil", "a name is printed where the speaker changes"),
    (P + "EarCore.swift", "take(OwnScript.tap(doc, lit, .out, env))", "take(OwnScript.leaveOutHeard(doc, lit, env))", "Leave Out carries"),
    (P + "EarCore.swift", "mutating func jumped() { from = 0 }", "mutating func jumped() {}", "a seek hands nothing to anyone"),
    (P + "EarCore.swift", "guard playing, k != 0 else", "guard k != 0 else", "a place moved while paused is not heard"),
    (P + "EarCore.swift", "take(OwnScript.tap(doc, lit, .role(name), env))", "take(OwnScript.apply(doc, OwnOp(op: .assign, line: lit, to: .role(name)), env))", "a tap carries"),
    (P + "EarCore.swift", "if r.refusal == nil { doc = r.doc }", "if r.refusal == nil { doc = r.doc; doc.undo = [] }", "Undo"),
    (P + "EarCore.swift", "let refusal = lit != 0 ? give(name) : nil", "let refusal: OwnRefusal? = nil", "+ Part is the lit line's"),
    (P + "EarCore.swift", "if refusal == nil, !known { names.append(name) }", "if refusal == nil { names.insert(name, at: 0) }", "the order named"),
    (P + "EarCore.swift", "let l = mine[(i + 1) % mine.count]", "let l = mine[0]", "Hear plays the next line"),
    (P + "EarCore.swift", "max(at.end, at.start + leastMs)", "at.end", "the shortest a line plays"),
    (P + "EarCore.swift", "private var env: OwnEnv { OwnEnv(takes: takes) }", "private var env: OwnEnv { OwnEnv() }", "a recorded line is never moved"),
    (P + "EarCore.swift", "        if !takes.isEmpty {\n            let was = OwnScript.castOf(doc), now = OwnScript.castOf(next)", "        if false {\n            let was = OwnScript.castOf(doc), now = OwnScript.castOf(next)", "a carry never reaches a recorded line"),
    (P + "EarCore.swift", "c.isASCII, n >= 1 {", "c.isASCII {", "0 is no part"),
    (P + "EarCore.swift", "        if option || shift { return nil }\n", "", "keys held with another"),
    (P + "EarCore.swift", "guard let p = ear?.place, p > 0, p < last else { return 0 }\n        return p", "_ = last\n        return ear?.place ?? 0", "never past the last line"),
    (P + "EarCore.swift", "\\($0.at?.start ?? 0)-\\($0.at?.end ?? 0) \\($0.text)", "\\($0.text)", "other times are another transcript"),
    (P + "EarCore.swift", "return doc.lines.count > OwnScript.maxLines ? .too_many_lines : nil", "return nil", "too many lines"),
    (P + "EarCore.swift", "if status == 404 || status == 403 { throw Failure.missing }", "", "a 404 is no times"),
    (P + "EarCore.swift", "        kept[url] = cues\n", "", "read once"),
    # the page's model
    (P + "EarModel.swift", "        if audio.jumps != seenJumps {\n            seenJumps = audio.jumps\n            session.jumped()\n        }\n", "", "a seek by anyone"),
    (P + "EarModel.swift", "if abs(s * 1000 - Double(place)) > 1500 { move(Double(place) / 1000) }", "", "a copy that reads 0 is moved"),
    (P + "EarModel.swift", "            move(Double(s.back.ms) / 1000)\n", "", "Hear It goes back"),
    (P + "EarModel.swift", "        if mine { audio.release() }\n", "", "the player is let go"),
    (P + "EarModel.swift", "if let rec { session.takes = store.takes(rec.id) }\n        let before = session.doc.undo.count\n        if let why = does(&session) {\n            refuse(why)", "let before = session.doc.undo.count\n        if let why = does(&session) {\n            refuse(why)", "a take is seen by the next tap"),
    (P + "EarModel.swift", "        if here, !loading, audio.settledSeconds == nil { transport(); return }\n", "", "a seek in flight has no place"),
    (P + "EarModel.swift", "if resumeAfterSheet { audio.pause(); transport() }", "", "the episode waits while a sheet is open"),
    # what is kept
    (P + "OwnStore.swift", "            _ = try fm.replaceItemAt(folder, withItemAt: stage)\n", "            for (name, data) in files { try data.write(to: folder.appending(path: name)) }\n", None),
    (P + "OwnStore.swift", "        let stage = root.appending(path: staged + UUID().uuidString, directoryHint: .isDirectory)\n", "        let stage = folder\n", "nothing of a failed change is kept"),
    (P + "OwnStore.swift", "            await before?.value\n", "", "two changes end as the second"),
    (P + "OwnStore.swift", "guard rec.format <= OwnRecord.formatNow, rec.id == id else", "guard rec.id == id else", "a newer file is left alone"),
    (P + "OwnStore.swift", "        if let script = made.script { try plays?.adopt(script) }\n", "", "a change reaches its productions"),
    (P + "OwnStore.swift", "guard taken.contains(line.id), let old", "guard let old", None),
    (P + "OwnStore.swift", "first(where: { take.created < $0.until })", "first(where: { _ in true })", "a take of the new words"),
    (P + "OwnStore.swift", "return OwnScript.wordsChanged(said.text, text(line))", "return said.text != text(line)", "a changed comma"),
    (P + "OwnStore.swift", "let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxBytes", "let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 0", "refused by its size, unread"),
    (P + "OwnStore.swift", "            if b.contains(0) { throw Refusal.not_text }\n", "", "a binary"),
    (P + "OwnStore.swift", "capital ? \"\" : \"@\"", "capital ? \"\" : \"\"", None),
    (P + "PlayFiles.swift", "for production in productions(of: script.id) where shares[production.id] == nil {", "for production in productions(of: script.id) {", "a shared production keeps its text"),
    (P + "PlayFiles.swift", "$0.takes.map(\\.lineID)", "$0.chosen.map(\\.key)", "an unchosen take locks"),
    (P + "Production.swift", "parts[$0.id] ?? PartState()", "PartState()", None),
    (P + "Production.swift", "        if lines {\n            listenedThrough = false", "        if true {\n            listenedThrough = false", "words alone leave it finished"),
    (P + "PlaysLibrary.swift", "        if PlayScript.isOwnID(id) { return own.script(id) }\n", "", "the network is never asked"),
    (P + "KokoroEngine.swift", "        if PlayScript.isOwnID(playID) { return false }  // an own script has none to ask for\n", "", "no phonemes asked for"),
    (P + "PlayPage.swift", "guard emphasis, case let .direction(text)", "guard case let .direction(text)", "brackets are the person's own"),
    (P + "OwnPartsModel.swift", "        undoManager?.removeAllActions(withTarget: self)\n        if !finished { flush() }", "        undoManager?.removeAllActions(withTarget: self)", "what was waiting when the page closed"),
    (P + "OwnPartsModel.swift", "            rec = before\n            refresh()\n            return false", "            return false", "the page keeps the work"),
    (P + "OwnPartsModel.swift", "if !fromManager, let undoManager, undoManager.canUndo {", "if !fromManager, let undoManager, undoManager.canUndo, undoManager.canRedo {", "one Undo, not two"),
    ("apple/Core/Store/LaunchDoors.swift", "environment[\"APP_START_OWN\"] != nil || environment[\"APP_START_CAST\"] != nil ? \"1\" : nil", "nil", "a door is always scratch"),
    ("apple/Core/Store/AppStore.swift", "if url.deletingLastPathComponent().lastPathComponent == \"Inbox\" {", "if false {", "the system's copy does not stay"),
    ("apple/Resources/EarDrama-Info.plist", "<string>Alternate</string>", "<string>Owner</string>", "never a default handler"),
]


def run():
    cmd = ["nice", "-n", "15", "xcodebuild", "test", "-project", str(ROOT / "EarDrama.xcodeproj"), "-scheme", "EarDrama",
           "-destination", "platform=macOS,arch=arm64", "-derivedDataPath", os.environ.get("MUTANT_DERIVED", str(ROOT / "build/dd-mac")), "-jobs", "4",
           "CODE_SIGNING_ALLOWED=NO"] + [f"-only-testing:EarDramaTests/{s}" for s in SUITES]
    env = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
    r = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True)
    out = r.stdout + r.stderr
    built = "Testing failed" in out or "Test run" in out or "TEST SUCCEEDED" in out
    return r.returncode == 0, built and "error: " in out and ": error:" in out, out


def main():
    want = [int(a) for a in sys.argv[1:] if a.isdigit()]
    bad = [i for i, (f, a, _, _) in enumerate(MUTANTS) if (ROOT / f).read_text().count(a) != 1]
    for i in bad:
        print(f"FAIL {i}: the mutant's text is not in {MUTANTS[i][0]} once: {MUTANTS[i][1][:70]!r}")
    if "--list" in sys.argv or bad:
        print(f"{len(MUTANTS)} mutants, {len(bad)} stale")
        return 1 if bad else 0
    ok, _, out = run()
    if not ok:
        print("FAIL the suites do not pass unbroken\n" + out[-2000:])
        return 1
    print("ok   the suites pass unbroken")
    lived = 0
    for i, (f, a, b, what) in enumerate(MUTANTS):
        if want and i not in want:
            continue
        path = ROOT / f
        was = path.read_text()
        try:
            path.write_text(was.replace(a, b))
            passed, _, out = run()
        finally:
            path.write_text(was)
        compiled = "** TEST BUILD FAILED" not in out and "** BUILD FAILED" not in out and "SwiftCompile" not in out.split("Failing tests")[0][-1500:]
        first = next((ln.strip()[:150] for ln in out.splitlines() if "recorded an issue" in ln or ": error:" in ln), "")
        if passed and what is None:
            print(f"     {i} equivalent: {f} {a[:60]!r}")
        elif passed:
            lived += 1
            print(f"FAIL {i} lived: {what} ({f})")
        else:
            print(f"ok   {i} caught: {what or a[:40]!r}  {'' if compiled else '(check it compiled) '}{first}")
        sys.stdout.flush()
    print(f"{'FAIL' if lived else 'ok'}: {lived} lived")
    return 1 if lived else 0


if __name__ == "__main__":
    sys.exit(main())
