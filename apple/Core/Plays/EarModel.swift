#if os(iOS) || os(macOS)
import Foundation
import Observation

/// What a casting asks of the app's own player (never a second one): the seam EarTests stand a fake in.
@MainActor
protocol EarAudio: AnyObject {
    /// The player is on this episode's own copy: its clock is the page's.
    func isOn(episode: String, copy: URL) -> Bool
    var isPlaying: Bool { get }
    /// A Listen Together guest: the room drives the player.
    var isFollowing: Bool { get }
    var hasItem: Bool { get }
    /// Nil while a load or a seek has not landed.
    var settledSeconds: Double? { get }
    /// Counts every move of the place by hand.
    var jumps: Int { get }
    var speed: Float { get }
    var errorMessage: String? { get }
    func hold(speed: Float)
    func release()
    func start(_ detail: EpisodeDetail, copy: Recording, at seconds: Double)
    func resume()
    func pause()
    func seek(to seconds: Double)
}

extension AudioPlayer: EarAudio {
    func isOn(episode: String, copy: URL) -> Bool { item?.episode.id == episode && item?.recording.url == copy }
    var hasItem: Bool { item != nil }
    func start(_ detail: EpisodeDetail, copy: Recording, at seconds: Double) {
        play(detail, recording: copy, from: seconds, queue: false)
    }
}

/// Casting an episode by ear (PLAYS-DESIGN §13 item 10, iOS-DESIGN §4.22): the automatic transcript in lines, the
/// episode playing in the app's own player, the line being said lit, and a tap on a part for who is saying it. What a
/// tap does is EarCore's; what is kept is OwnScripts'. It proposes no speaker, and keeps and reads no sound.
@Observable
final class EarModel {
    static let speedKey = "ed.ear.speed"

    /// A line to bring into view; `n` tells one asking from the next.
    struct Bring: Equatable {
        let k: Int
        let n: Int
    }

    let detail: EpisodeDetail
    let title: String
    private(set) var session: EarSession
    private(set) var rows: [EarCore.Row] = []
    private(set) var parts: [OwnPart] = []
    private(set) var count: (cast: Int, lines: Int) = (0, 0)
    /// The line outlined: the one being said, or the one played on its own.
    private(set) var lit = 0
    /// Who the line being said is cast to, for the pressed part.
    private(set) var who: OwnWho?
    private(set) var isPlaying = false
    /// The place, in whole seconds (the page redraws for it once a second).
    private(set) var seconds = 0
    private(set) var speed: Float
    /// Whether the person scrolled away (Back to the Line), and the line to bring into view.
    private(set) var backToLine = false
    private(set) var bring: Bring?
    /// A failed write or recording, with the way on; a caption that the transcript or the copy was made again.
    private(set) var problem: (words: String, audio: Bool)?
    var note: String?
    /// A refusal shown for a moment in place of the count.
    private(set) var refusal: String?
    /// Moves on every change of cast, for the haptic.
    private(set) var changes = 0
    /// A sheet is open: the episode waits and the keys are the sheet's.
    private(set) var sheetOpen = false
    private(set) var done = false

    @ObservationIgnored private(set) var rec: OwnRecord?
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored var announce: (String) -> Void = { _ in }
    @ObservationIgnored private let store: OwnScripts
    @ObservationIgnored private let audio: any EarAudio
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let copy: Recording
    @ObservationIgnored private let cues: [OwnCue]
    @ObservationIgnored private var place: Int64
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var mine = false
    @ObservationIgnored private var seenJumps: Int
    @ObservationIgnored private var follow = ReadAlong.Follow()
    @ObservationIgnored private var sample: (k: Int, until: Int64, back: (ms: Int64, playing: Bool), heard: Bool)?
    @ObservationIgnored private var resumeAfterSheet = false
    @ObservationIgnored private var refusing: Task<Void, Never>?
    @ObservationIgnored private lazy var save = OwnLater(.milliseconds(350)) { [weak self] in _ = await self?.write() }

    init(detail: EpisodeDetail, copy: Recording, title: String, rec: OwnRecord?, cues: [OwnCue], doc: OwnDoc, store: OwnScripts,
         audio: any EarAudio, defaults: UserDefaults = .standard) {
        self.detail = detail
        self.copy = copy
        self.title = title
        self.rec = rec
        self.cues = cues
        self.store = store
        self.audio = audio
        self.defaults = defaults
        session = EarSession(doc: rec?.doc ?? doc, names: rec?.extras ?? [], takes: rec.map { store.takes($0.id) } ?? [])
        place = EarCore.place(rec?.ear, rec?.doc ?? doc)
        let kept = Float(defaults.double(forKey: Self.speedKey))
        speed = kept > 0 ? kept : EarCore.speed
        seenJumps = audio.jumps
    }

    /// The page is shown. Nothing plays before a press; another episode playing is paused.
    func appear() {
        if here {
            place = nowMs
            mine = true
            audio.hold(speed: speed)
        } else if audio.isPlaying, !audio.isFollowing {
            audio.pause()
        }
        _ = session.tick(place, playing: false)
        paint()
        transport()
        bringLit()
    }

    private var here: Bool { audio.isOn(episode: detail.episode.id, copy: copy.url) }
    private var playing: Bool { here && audio.isPlaying }

    /// The place being cast; a line played on its own is not it.
    private var nowMs: Int64 {
        if let sample { return sample.back.ms }
        guard here, !loading, let s = audio.settledSeconds else { return place }
        return Int64((s * 1000).rounded())
    }

    // MARK: The audio: told where it is, many times a second while it plays

    func sync() {
        speedMoved()
        if let s = sample {
            if audio.isPlaying { sample?.heard = true }
            let past = audio.settledSeconds.map { Int64($0 * 1000) >= s.until } ?? false
            if !here || past || (s.heard && !audio.isPlaying) { endSample() }
            transport()
            return
        }
        if audio.jumps != seenJumps {
            seenJumps = audio.jumps
            session.jumped()
        }
        if loading, here, let s = audio.settledSeconds {
            loading = false
            // A copy just loaded may read 0, or a place AVPlayer rounded: it is moved to its own.
            if abs(s * 1000 - Double(place)) > 1500 { move(Double(place) / 1000) }
            session.jumped()
            transport()
            return
        }
        // A seek in flight has no place yet.
        if here, !loading, audio.settledSeconds == nil { transport(); return }
        let got = session.tick(nowMs, playing: playing)
        if here, !loading { place = nowMs }
        if got.heard {
            paint()
            save()
        } else if got.moved {
            light()
        }
        if got.moved, !playing, let l = session.line(session.lit) { announce(l.text) }
        transport()
    }

    private func speedMoved() {
        guard here, audio.speed != speed, mine else { return }
        speed = audio.speed
        defaults.set(Double(speed), forKey: Self.speedKey)
    }

    private func transport() {
        if isPlaying != playing { isPlaying = playing }
        let at = Int(nowMs / 1000)
        if seconds != at { seconds = at }
        if here, audio.errorMessage != nil, problem?.audio != true, mine { problem = ("This recording did not load.", true) }
        if problem?.audio == true, audio.errorMessage == nil { problem = nil }
    }

    /// A player that is not settled has no place to move: it is moved to this one when it lands.
    private func move(_ seconds: Double) {
        let to = max(0, seconds)
        if audio.settledSeconds == nil {
            place = Int64((to * 1000).rounded())
            loading = true
        } else {
            audio.seek(to: to)
            place = Int64((to * 1000).rounded())
        }
        seenJumps = audio.jumps
        session.jumped()
    }

    // MARK: Transport

    func start() {
        guard !audio.isFollowing else {
            problem = ("Leave SharePlay to play this.", false)
            return
        }
        mine = true
        audio.hold(speed: speed)
        if here, audio.errorMessage == nil {
            audio.resume()
        } else {
            loading = true
            audio.start(detail, copy: copy, at: Double(place) / 1000)
        }
        seenJumps = audio.jumps
        session.jumped()
        transport()
    }

    func toggle() {
        if sample != nil { endSample(); return }
        if playing {
            audio.pause()
            if rec != nil { save() }
            transport()
        } else {
            start()
        }
    }

    func back() {
        if sample != nil { endSample(); return }
        if here, !loading {
            move(Double(nowMs) / 1000 - EarCore.backSeconds)
        } else {
            place = max(0, place - Int64(EarCore.backSeconds * 1000))
            session.jumped()
        }
        sync()
    }

    func setSpeed(_ x: Float) {
        speed = x
        defaults.set(Double(x), forKey: Self.speedKey)
        if here { mine = true; audio.hold(speed: x) }
    }

    /// Plays one line on its own, then goes back to the place it left.
    func hear(_ line: OwnLine?) {
        guard let line, let at = line.at else { return }
        guard !audio.isFollowing else { problem = ("Leave SharePlay to play this.", false); return }
        if here, audio.settledSeconds == nil { return }
        let was = sample?.back ?? (ms: nowMs, playing: playing)
        let (from, until) = EarCore.span(at)
        sample = (line.k, until, was, false)
        mine = true
        audio.hold(speed: speed)
        if here {
            audio.seek(to: Double(from) / 1000)
            audio.resume()
        } else {
            audio.start(detail, copy: copy, at: Double(from) / 1000)
        }
        light()
        transport()
    }

    func hear(part name: String) { hear(session.sample(name)) }

    private func endSample(goOn: Bool = true) {
        guard let s = sample else { return }
        sample = nil
        if here {
            audio.pause()
            move(Double(s.back.ms) / 1000)
            if goOn, s.back.playing { audio.resume() }
        }
        place = s.back.ms
        light()
        transport()
    }

    // MARK: Casting

    /// One press: `does` answers a refusal or nil.
    @discardableResult
    private func press(_ does: (inout EarSession) -> OwnRefusal?) -> Bool {
        if sample != nil { endSample() } else { sync() }
        if let rec { session.takes = store.takes(rec.id) }
        let before = session.doc.undo.count
        if let why = does(&session) {
            refuse(why)
            return false
        }
        if session.doc.undo.count > before { registerUndo() }
        changes += 1
        paint()
        save()
        return true
    }

    func give(_ name: String) { press { $0.give(name) } }
    func leaveOut() { press { $0.leaveOut() } }

    func give(number n: Int) {
        guard parts.indices.contains(n) else { return }
        give(parts[n].name)
    }

    /// Names a voice; its refusal in essential words, or nil.
    func add(_ raw: String) -> String? {
        var why: OwnRefusal?
        if let rec { session.takes = store.takes(rec.id) }
        let before = session.doc.undo.count
        why = session.add(raw).refusal
        if let why { return OwnText.name(why) }
        if session.doc.undo.count > before { registerUndo() }
        changes += 1
        paint()
        save()
        return nil
    }

    private func registerUndo() {
        undoManager?.registerUndo(withTarget: self) { model in MainActor.assumeIsolated { model.undo(fromManager: true) } }
    }

    func undo(fromManager: Bool = false) {
        guard session.canUndo else { return }
        if !fromManager, let undoManager, undoManager.canUndo {
            undoManager.undo()
            return
        }
        press { $0.undo() }
    }

    /// A line sheet's step; its refusal in essential words, or nil. It gives that line alone.
    func change(_ does: (inout EarSession) -> OwnRefusal?) -> String? {
        if let rec { session.takes = store.takes(rec.id) }
        let before = session.doc.undo.count
        if let why = does(&session) { return OwnText.say(why) }
        if session.doc.undo.count > before { registerUndo() }
        changes += 1
        paint()
        save()
        return nil
    }

    private func refuse(_ why: OwnRefusal) {
        let words = OwnText.say(why)
        refusal = words
        announce(words)
        refusing?.cancel()
        refusing = Task { [weak self] in
            guard (try? await Task.sleep(for: .seconds(2.5))) != nil else { return }
            self?.refusal = nil
        }
    }

    func isLocked(_ line: OwnLine) -> Bool { line.id.map(session.takes.contains) ?? false }

    /// The parts keep the order they were named in, which is their number and their hue here.
    func hue(_ name: String?) -> String? {
        guard let name, let i = parts.firstIndex(where: { $0.name == name }), i < PlayScript.partHues.count else { return nil }
        return PlayScript.partHues[i]
    }

    // MARK: Sheets: the audio waits while one is open

    func openSheet() {
        guard !sheetOpen else { return }
        sheetOpen = true
        resumeAfterSheet = playing && sample == nil
        if resumeAfterSheet { audio.pause(); transport() }
    }

    func closeSheet(playOn: Bool = true) {
        guard sheetOpen else { return }
        sheetOpen = false
        if sample != nil { endSample(goOn: false) }
        if resumeAfterSheet, playOn { start() }
        resumeAfterSheet = false
    }

    /// Play From Here: the sheet closes and the episode plays from the line.
    func play(from line: OwnLine) {
        guard let at = line.at else { return }
        if sample != nil { endSample(goOn: false) }
        resumeAfterSheet = false
        place = at.start
        session.jumped()
        if here, !loading { move(Double(at.start) / 1000) }
        refollow()
        closeSheet(playOn: false)
        start()
        sync()
    }

    // MARK: Drawing

    private func paint() {
        rows = EarCore.rows(session.doc)
        parts = session.parts
        count = session.count
        light()
    }

    private func light() {
        let now = sample?.k ?? session.lit
        let whose = session.lit == 0 ? nil : session.who(session.lit)
        if who != whose { who = whose }
        if lit != now { lit = now }
        let id = session.lit == 0 ? nil : String(session.lit)
        guard sample == nil, id != follow.now else { return }
        let step = follow.line(id)
        if backToLine != step.back { backToLine = step.back }
        if step.turn { bringLit() }
    }

    private func bringLit() {
        guard session.lit != 0 else { return }
        bring = Bring(k: session.lit, n: (bring?.n ?? 0) + 1)
    }

    /// The person's own scroll: the lines stop following.
    func away() {
        guard session.lit != 0, follow.following else { return }
        follow.away()
        backToLine = true
    }

    func refollow() {
        _ = follow.back()
        backToLine = false
        bringLit()
    }

    // MARK: What is kept: begun at the first change, never by looking

    private func record(_ doc: OwnDoc) -> OwnRecord {
        var out = rec ?? store.begin(title: title, doc: doc,
                                     episode: OwnRecord.Episode(id: detail.episode.id, url: SiteLinks.episode(detail.episode.id).absoluteString),
                                     ear: OwnRecord.Ear(sig: EarCore.signature(cues), copy: copy.url.absoluteString, place: 0))
        out.doc = doc
        out.extras = session.names
        out.ear?.place = nowMs
        return out
    }

    @discardableResult
    func write() async -> Bool {
        do {
            let now = record(session.doc)
            rec = now
            try await store.keep(now)
            if problem?.audio == false { problem = nil }
            return true
        } catch {
            problem = (OwnText.notKept(error), false)
            return false
        }
    }

    /// The failure's way on.
    func tryAgain() {
        if problem?.audio == true {
            problem = nil
            start()
        } else {
            Task { await write() }
        }
    }

    /// Done, any time: what is cast is the script, the rest are directions. The script's id, or nil when refused.
    func finish() async -> String? {
        if sample != nil { endSample(goOn: false) }
        let doc = OwnScript.done(session.doc, keepOpen: true)
        var next = record(doc)
        next.done = true
        if let why = OwnBuild.refusal(next) {
            refuse(why)
            return nil
        }
        let before = (session.doc, rec)
        session.replace(doc)
        rec = next
        save.flush()
        guard await write() else {
            session.replace(before.0)
            rec = before.1
            return nil
        }
        done = true
        undoManager?.removeAllActions(withTarget: self)
        paint()
        return next.id
    }

    /// The page is gone: the place is kept, the player let go, and what is playing plays on.
    func leave() {
        refusing?.cancel()
        if sample != nil { endSample(goOn: true) }
        undoManager?.removeAllActions(withTarget: self)
        if let rec, !done {
            if save.pending { save.flush() } else if abs((rec.ear?.place ?? 0) - nowMs) > 1000 { Task { await write() } }
        }
        if mine { audio.release() }
        mine = false
    }

    /// A take recorded in another window locks its line here too.
    func refreshTakes() {
        if let rec { session.takes = store.takes(rec.id) }
    }
}
#endif
