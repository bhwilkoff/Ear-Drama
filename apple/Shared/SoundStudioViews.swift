#if os(iOS) || os(macOS)
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

// The Sound part's studio and the sound board (B32 §3, binding; iOS-DESIGN §4.15 "The sound board", macOS-DESIGN §4.7;
// web sibling WEB-DESIGN §4.16 item 14a; Decision 091 on the mix). The studio's own reader and engine, with the Sound
// part's slots in place of lines: each cue row is a slot, any line can take one (Add a Sound Here), a slot is never filled
// for the person, and the board chooses, places and levels what sits in it. Logic is Core (`SoundBoard`); this file only
// draws it and passes the person's acts on.

// MARK: - The model

@Observable
final class SoundStudio {
    unowned let model: StudioModel
    let own: OwnSoundStore
    let pack: SoundPackStore
    /// The slot being worked on (its `key`).
    var currentKey: String?
    /// The sound selected in In This Cue.
    var selected: String?
    var query = ""
    /// A pack category, or nil for every category.
    var category: String?
    /// A bed whose Until waits for a tap on the page.
    var pickingUntil: String?
    var detent: PresentationDetent = .medium
    var refusal: String?
    var importing = false
    var recordingOwn = false
    var ownStarted: Date?
    @ObservationIgnored let audition = SoundAudition()
    @ObservationIgnored private var ownLimit: Task<Void, Never>?

    init(model: StudioModel, own: OwnSoundStore, pack: SoundPackStore) {
        self.model = model
        self.own = own
        self.pack = pack
        currentKey = slots.first { $0.sounds.isEmpty && !$0.silent }?.key ?? slots.first?.key
        query = seedQuery
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["APP_SOUND_DEMO"] == "1", LaunchDoors.scratchRoot != nil { seedDemo() }
        if env["APP_SOUND_BOARD"] == "1" { model.sheet = true; model.inspector = true }
        #endif
    }

    #if DEBUG
    /// APP_SOUND_DEMO=1, scratch launches only (APP_SCRATCH, never the person's own data): two own sounds made of tones,
    /// one placed in the first cue and one as a bed from the second cue, so frames show a board in use. Silent under
    /// APP_MUTE like every listen.
    private func seedDemo() {
        guard own.sounds.isEmpty, slots.count >= 2 else { return }
        let rate = TakeAudio.sampleRate
        let knock = (0..<Int(rate * 0.6)).map { i -> Float in
            let t = Double(i) / rate
            return Float(sin(2 * .pi * 180 * t) * exp(-t * 18) * 0.5)
        }
        let far = (0..<Int(rate * 4)).map { i -> Float in
            let t = Double(i) / rate
            return Float(sin(2 * .pi * 220 * t + sin(2 * .pi * 3 * t)) * 0.08)
        }
        guard let a = try? own.save(knock, name: "Knock on the table", from: "recorded"),
              let b = try? own.save(far, name: "Hoofbeats, far", from: "recorded") else { return }
        let first = slots[0].key, second = slots[1].key
        currentKey = first
        add(.own(a.id, name: a.name), kind: "effect")
        currentKey = slots.first { $0.line == slots[1].line && $0.piece == slots[1].piece }?.key ?? second
        add(.own(b.id, name: b.name), kind: "ambience")
        let from = script.lines.firstIndex { $0.id == current?.line } ?? 0
        if let id = selected, let line = script.lines.dropFirst(from + 6).first?.id {
            update(id, SoundBoard.Patch(at: "bed", until: line))
        }
    }
    #endif

    var script: PlayScript { model.script }
    var production: Production { model.session.production }
    var slots: [SoundBoard.Slot] { SoundBoard.slots(script, production) }
    var current: SoundBoard.Slot? { slots.first { $0.key == currentKey } ?? slots.first }
    var place: (at: Int, of: Int) {
        let cues = slots.filter { !$0.added }
        let at = current.flatMap { c in cues.firstIndex { $0.key == c.key } }
        return ((at ?? 0) + 1, cues.count)
    }

    /// The script line indexes that hold a slot.
    var slotLines: Set<Int> {
        let index = Dictionary(script.lines.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        return Set(slots.compactMap { index[$0.line] })
    }

    var seedQuery: String { SoundBoard.seedQuery(current?.text ?? "", cues: pack.cues) }

    private func apply(_ p: Production) {
        model.store.update(p)
        model.session.reload()
    }

    /// The slot's record id, writing a cue row's slot on first touch.
    private func ensured() -> String? {
        guard let slot = current else { return nil }
        let (p, id) = SoundBoard.ensure(production, slot)
        if p != production { apply(p) }
        currentKey = id
        return id
    }

    /// Moving off a slot drops added or touched slots left empty (§3.1 item 3).
    func select(_ key: String) {
        guard key != currentKey else { return }
        audition.stop()
        let keep = slots.first { $0.key == key }?.recordID
        let pruned = SoundBoard.prune(production, keep: keep)
        if pruned != production { apply(pruned) }
        currentKey = key
        selected = nil
        pickingUntil = nil
        query = seedQuery
        model.studio.onFollow?(current?.line ?? "")
    }

    @discardableResult
    func move(_ delta: Int) -> Bool {
        let all = slots
        guard !all.isEmpty, !model.session.isBusy else { return false }
        let i = all.firstIndex { $0.key == current?.key } ?? 0
        let to = max(0, min(all.count - 1, i + delta))
        guard to != i else { return false }
        select(all[to].key)
        return true
    }

    /// A tap on a line in the Sound part: its slot (the next one on that line when one is already current).
    func tapLine(_ lineID: String) -> Bool {
        if let until = pickingUntil {
            setUntil(until, lineID)
            return true
        }
        let here = slots.filter { $0.line == lineID }
        guard !here.isEmpty else { return false }
        if let c = current, let i = here.firstIndex(where: { $0.key == c.key }) {
            select(here[(i + 1) % here.count].key)
        } else {
            select(here[0].key)
        }
        return true
    }

    /// Add a Sound Here (§3.1 item 3): a slot at the line's end, current; removed again if it is left empty.
    func addHere(_ lineID: String) {
        let (p, id) = SoundBoard.addSlot(SoundBoard.prune(production), line: lineID)
        apply(p)
        currentKey = id
        selected = nil
        query = ""
        model.sheet = true
    }

    func leaveSilent(_ on: Bool) {
        guard let id = ensured() else { return }
        apply(SoundBoard.setSilent(production, id, on))
    }

    /// Adds a source to the slot, as the person chose it; the new sound becomes the selected one.
    func add(_ src: SoundSource, kind: String) {
        guard let id = ensured() else { return }
        let take = current.flatMap { production.usableTake(for: $0.line) }
        let (p, sound) = SoundBoard.addSound(production, script, slotID: id, src: src, kind: kind, take: take)
        apply(p)
        selected = sound
    }

    func update(_ soundID: String, _ patch: SoundBoard.Patch) {
        guard let id = current?.recordID else { return }
        apply(SoundBoard.updateSound(production, slotID: id, soundID: soundID, patch))
    }

    func remove(_ soundID: String) {
        guard let id = current?.recordID else { return }
        audition.stop()
        apply(SoundBoard.removeSound(production, slotID: id, soundID: soundID))
        if selected == soundID { selected = nil }
    }

    func setUntil(_ soundID: String, _ lineID: String) {
        pickingUntil = nil
        update(soundID, SoundBoard.Patch(until: lineID))
        detent = .large
    }

    func inCue(_ src: SoundSource) -> Bool { current?.sounds.contains { $0.src == src } ?? false }

    // MARK: What a sound is

    struct Described {
        let title: String
        let ms: Double
        let missing: Bool
    }

    func describe(_ src: SoundSource) -> Described {
        switch src {
        case let .pack(_, id):
            guard let c = pack.cue(id) else { return Described(title: id, ms: 0, missing: true) }
            return Described(title: c.title, ms: c.ms, missing: !pack.isHere(c))
        case let .own(id, name):
            guard let o = own.sound(id) else { return Described(title: name ?? "On another device", ms: 0, missing: true) }
            return Described(title: o.name, ms: o.seconds * 1000, missing: false)
        case let .take(id):
            guard let t = production.take(id) else { return Described(title: "Your take", ms: 0, missing: true) }
            let k = production.takes.filter { $0.cue != nil && $0.lineID == t.lineID }.firstIndex { $0.id == id }
            return Described(title: k.map { "Your take \($0 + 1)" } ?? "Your take", ms: t.seconds * 1000, missing: false)
        }
    }

    /// "Thunder, close · After", the dock's words for the slot's first sound.
    var statusWords: String {
        guard let slot = current else { return "" }
        if slot.silent { return "Left silent" }
        guard let first = slot.sounds.first else { return "No sound" }
        let more = slot.sounds.count > 1 ? " +\(slot.sounds.count - 1)" : ""
        return "\(describe(first.src).title) \u{00B7} \(SoundBoard.placementLabel(first.at))\(more)"
    }

    /// "Line 180", for a bed's Until.
    func lineLabel(_ lineID: String) -> String {
        let i = script.lines.firstIndex { $0.id == lineID } ?? 0
        return "line \(i + 1)"
    }

    func url(_ src: SoundSource) -> URL? {
        if case let .take(id) = src { return production.take(id).map { model.store.takeURL(production, $0) } }
        return SoundSources(own: own, pack: pack).url(src)
    }

    // MARK: Recording

    /// The round control on a slot (§3.1 item 6): a take of the Sound part, kept in the slot, never a line's chosen take.
    func recordCue(player: AudioPlayer) {
        audition.stop()
        if model.session.isBusy { model.session.cancel(); if model.isListening { model.session.stopListening() }; return }
        Task { [weak self] in
            guard let self else { return }
            if !model.started {
                await model.begin(echoCancelled: false, player: player)
                guard model.started else { return }
            }
            guard let slot = current, let id = ensured() else { return }
            let script = script
            await model.session.recordCue(slot.line) { p, take in
                SoundBoard.addPerformed(p, script, slotID: id, take: take)
            }
            selected = current?.sounds.last?.id
        }
    }

    /// Record a Sound for Mine (§3.2 item 6): up to 30 s, nothing playing, so no headphones gate.
    func toggleOwnRecording(name: String = "") {
        if recordingOwn { finishOwn(name: name); return }
        audition.stop()
        Task { [weak self] in
            guard let self else { return }
            if !model.stubbed {
                guard await AVAudioApplication.requestRecordPermission() else { refusal = "Ear Drama needs the microphone to record a sound."; return }
            }
            guard model.session.beginOwnSound() else { return }
            recordingOwn = true
            ownStarted = .now
            ownLimit = Task { [weak self] in
                try? await Task.sleep(for: .seconds(SoundBoard.ownRecordMaxSeconds))
                guard !Task.isCancelled else { return }
                self?.finishOwn(name: name)
            }
        }
    }

    private func finishOwn(name: String) {
        ownLimit?.cancel()
        recordingOwn = false
        ownStarted = nil
        let samples = model.session.endOwnSound(maxSeconds: SoundBoard.ownRecordMaxSeconds)
        guard !samples.isEmpty else { return }
        do {
            let n = own.sounds.filter { $0.from == "recorded" }.count + 1
            let s = try own.save(samples, name: name.isEmpty ? "My sound \(n)" : name, from: "recorded")
            if current != nil { add(.own(s.id, name: s.name), kind: "effect") }
        } catch {
            refusal = "This sound was not saved."
        }
    }

    func bring(_ result: Result<URL, any Error>) {
        guard case let .success(url) = result else { return }
        do {
            let s = try own.bring(url)
            if current != nil { add(.own(s.id, name: s.name), kind: "effect") }
            refusal = nil
        } catch OwnSoundStore.Refusal.tooLarge {
            refusal = "This file is larger than 50 MB."
        } catch OwnSoundStore.Refusal.tooLong {
            refusal = "This file is longer than 10 minutes."
        } catch {
            refusal = "This file could not be read as audio."
        }
    }

    // MARK: Listening

    /// The live cues for a plan (§4.4): the sounds at their entries, ducked under each.
    func cues(for plan: [ListenEntry]) -> ListenCues {
        let sources = SoundSources(own: own, pack: pack)
        let p = production, store = model.store
        return ListenCues(entries: SoundBoard.listenCues(script, p, plan: plan), url: { src in
            if case let .take(id) = src { return p.take(id).map { store.takeURL(p, $0) } }
            return sources.url(src)
        }, player: SystemCuePlayer())
    }

    /// Hear It in Place (§3.2 item 2): from the line before the slot to the line after, mixed live as it will sound.
    func hearInPlace() {
        let listen = model.listen
        if listen.isRunning { listen.stop(); return }
        guard let slot = current else { return }
        audition.stop()
        let p = production
        let plan = Relay.listenPlan(p, script, reads: listen.reads)
        guard let range = SoundBoard.inPlace(script, plan: plan, line: slot.line) else { return }
        let cues = cues(for: plan)
        let store = model.store
        Task { await listen.run(plan, takeURL: { store.takeURL(p, $0) }, cues: cues, range: range) }
    }
}

/// Audition (§3.2 item 5): the raw file through the device's output, at the cue's level, only while nothing records.
@Observable
final class SoundAudition: NSObject, AVAudioPlayerDelegate {
    private(set) var playing: String?
    @ObservationIgnored private var player: AVAudioPlayer?

    func toggle(_ key: String, url: URL?, gainDb: Double = 0) {
        if playing == key { stop(); return }
        stop()
        guard let url, let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.volume = Float(pow(10, gainDb / 20)) * SpeechMute.volume
        p.delegate = self
        p.play()
        player = p
        playing = key
    }

    func stop() {
        player?.stop()
        player = nil
        playing = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            self.playing = nil
        }
    }
}

// MARK: - The dock and the transport

/// The Sound part's controls (§3.1 item 5): no mode control; one status row ("Cue 13 of 34 · Thunder, close · After");
/// Sounds, Previous slot, the round record control, Next slot, Listen From Here. The gate shows here when a press asks it.
struct SoundControls: View {
    let model: StudioModel
    let sound: SoundStudio
    var compact = true
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        VStack(spacing: Spacing.s2) {
            if model.gate != .ready || model.isRoomTone {
                StudioGate(model: model)
            }
            status
            transport
        }
        #if os(iOS)
        .sensoryFeedback(Haptic.selection.feedback, trigger: sound.currentKey)
        #endif
        .task { await sound.pack.load() }
    }

    @ViewBuilder private var status: some View {
        let session = model.session
        Group {
            if case .listening = session.phase {
                HStack(spacing: Spacing.s3) {
                    Circle().fill(StudioPalette.record).frame(width: 10, height: 10)
                    Text("Recording").font(TypeRamp.bodyStrong)
                    SoundMeter(levels: session.levels)
                }
                .foregroundStyle(StudioPalette.record)
                .accessibilityElement(children: .combine)
            } else {
                let place = sound.place
                HStack(spacing: Spacing.s2) {
                    Text(verbatim: sound.current?.added == true ? "Added" : "Cue \(place.at) of \(place.of)")
                        .font(TypeRamp.tabular).foregroundStyle(Color.brandTextMuted)
                    Text(verbatim: sound.statusWords).font(TypeRamp.body).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
    }

    private var transport: some View {
        let hearing = model.listen.isRunning
        let busy = model.session.isBusy
        return HStack {
            Button { model.sheet = true } label: {
                Label("Sounds", systemImage: "speaker.wave.2").labelStyle(.iconOnly).frame(width: 44, height: 44)
            }
            .disabled(!compact)
            .opacity(compact ? 1 : 0)
            .accessibilityIdentifier("sound-board-button")
            Button { sound.move(-1) } label: {
                Label("Previous Cue", systemImage: "backward.end").labelStyle(.iconOnly).frame(width: 44, height: 44)
            }
            .disabled(busy || sound.current?.key == sound.slots.first?.key)
            Spacer()
            VStack(spacing: 2) {
                let red = !model.isCue
                let title = model.isListening ? "Stop" : model.isCue ? "Cancel" : "Record"
                Button { sound.recordCue(player: player) } label: {
                    Image(systemName: model.isListening ? "stop.fill" : model.isCue ? "xmark" : "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(red ? StudioPalette.onRecord : Color.brandOnPrimary)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(red ? StudioPalette.record : Color.brandPrimary))
                }
                .buttonStyle(.plain)
                .disabled(sound.current == nil || sound.recordingOwn || model.isRoomTone)
                .accessibilityLabel(model.isListening || model.isCue ? title : "Record This Cue")
                .accessibilityIdentifier("studio-record")
                Text(verbatim: title).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
            }
            Spacer()
            Button { sound.move(1) } label: {
                Label("Next Cue", systemImage: "forward.end").labelStyle(.iconOnly).frame(width: 44, height: 44)
            }
            .disabled(busy || sound.current?.key == sound.slots.last?.key)
            Button { model.listenFromHere() } label: {
                Label(hearing ? "Stop" : "Listen From Here", systemImage: hearing ? "stop.fill" : "play.fill")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(hearing ? Color.brandSurfaceAlt : Color.clear))
            }
            .disabled(!hearing && busy)
            .accessibilityIdentifier("studio-listen")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.brandSecondary)
        .padding(.bottom, Spacing.s2)
    }
}

private struct SoundMeter: View {
    let levels: [Float]

    var body: some View {
        let shown = Array(levels.suffix(24))
        HStack(spacing: 2) {
            ForEach(0..<24, id: \.self) { i in
                let slot = i - (24 - shown.count)
                Capsule().fill(StudioPalette.record).frame(width: 3, height: slot >= 0 ? max(3, 22 * CGFloat(shown[slot])) : 3)
            }
        }
        .frame(height: 24)
        .accessibilityHidden(true)
    }
}

// MARK: - The board

/// The board (§3.2): the slot, In This Cue with the selected sound's placement, Start, Level and Fades, Until and Hear It
/// in Place; search; the pack's categories; the results; Mine. A sheet with detents on a phone, the studio's pane from
/// 860 pt, the Mac inspector. `full` (the pane and the inspector) adds the status and transport, since there is no dock.
struct SoundBoardView: View {
    let model: StudioModel
    @Bindable var sound: SoundStudio
    var full = false
    var close: (() -> Void)?

    var body: some View {
        List {
            slotSection
            if full {
                Section { SoundControls(model: model, sound: sound, compact: false) }
                    .listRowSeparator(.hidden)
            }
            inCueSection
            #if os(macOS)
            Section {
                TextField("Search sounds", text: $sound.query, prompt: Text("Search sounds"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("sound-search")
            }
            #endif
            librarySections
            mineSection
            partSection
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        .pageMargins()
        .searchable(text: $sound.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search sounds")
        .navigationTitle("Sounds")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } }
        }
        #else
        .listStyle(.sidebar)
        #endif
        .fileImporter(isPresented: $sound.importing, allowedContentTypes: [.audio]) { sound.bring($0) }
        .onDisappear { sound.audition.stop() }
        .accessibilityIdentifier("sound-board")
    }

    // MARK: The slot

    @ViewBuilder private var slotSection: some View {
        if let slot = sound.current {
            let place = sound.place
            let speaker = sound.script.lines.first { $0.id == slot.line }?.role
            Section {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(verbatim: (slot.added ? "Added \u{00B7} \(sound.lineLabel(slot.line))" : "Cue \(place.at) of \(place.of)")
                        + (speaker.map { " \u{00B7} \($0)" } ?? ""))
                        .font(TypeRamp.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(Color.brandTextMuted)
                    if !slot.text.isEmpty {
                        Text(verbatim: slot.text).font(TypeRamp.body)
                    } else if let line = sound.script.lines.first(where: { $0.id == slot.line }) {
                        Text(verbatim: line.spokenText).font(TypeRamp.body).foregroundStyle(Color.brandTextMuted).lineLimit(2)
                    }
                }
                .accessibilityElement(children: .combine)
                if slot.sounds.isEmpty {
                    Toggle("Leave Silent", isOn: Binding(get: { slot.silent }, set: { sound.leaveSilent($0) }))
                        .accessibilityIdentifier("sound-silent")
                }
            }
        } else {
            Section {
                Text("Right-click or hold a line to add a sound.").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
            }
        }
    }

    // MARK: In this cue

    @ViewBuilder private var inCueSection: some View {
        if let slot = sound.current, !slot.sounds.isEmpty {
            Section("In This Cue") {
                ForEach(slot.sounds, id: \.id) { x in
                    InCueRow(sound: sound, cue: x, selected: (sound.selected ?? slot.sounds.first?.id) == x.id)
                }
            }
        }
    }

    // MARK: The library

    @ViewBuilder private var librarySections: some View {
        let pack = sound.pack
        switch pack.state {
        case .absent:
            EmptyView()
        case .loading:
            Section { ForEach(0..<3, id: \.self) { _ in SkeletonRow() } }
                .accessibilityLabel("Loading")
        case .unreachable, .offline:
            Section {
                Text(pack.state == .offline ? "Offline" : "The sounds could not be reached.")
                    .font(TypeRamp.body).foregroundStyle(Color.brandTextMuted)
                Button("Try Again") { Task { await pack.load() } }
            }
        case .ready:
            if !pack.cues.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.s2) {
                            chip(nil, "All")
                            ForEach(pack.manifest?.categories ?? []) { c in chip(c.id, c.title) }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: Spacing.s1, leading: Spacing.s3, bottom: Spacing.s1, trailing: Spacing.s3))
                    let found = SoundBoard.search(pack.cues, sound.query, category: sound.category)
                    if found.isEmpty, !sound.query.isEmpty {
                        noMatch
                    }
                    ForEach(pack.manifest?.categories.filter { c in found.contains { $0.category == c.id } } ?? []) { c in
                        if !pack.categoryHere(c.id) { CategoryHeader(pack: pack, category: c) }
                        ForEach(found.filter { $0.category == c.id }) { cue in PackRow(sound: sound, cue: cue) }
                    }
                }
            }
        }
    }

    private func chip(_ id: String?, _ title: String) -> some View {
        Button(title) { sound.category = id }
            .buttonStyle(OwnChipStyle(selected: sound.category == id))
            .accessibilityAddTraits(sound.category == id ? .isSelected : [])
    }

    private var noMatch: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(verbatim: "No sound called \u{201C}\(sound.query)\u{201D}.").font(TypeRamp.body)
            Button { sound.toggleOwnRecording(name: sound.query) } label: { Label("Record It", systemImage: "mic") }
                .disabled(sound.recordingOwn || model.session.isBusy)
        }
    }

    // MARK: Mine

    private var mineSection: some View {
        let own = sound.own
        let shown = sound.query.isEmpty ? own.sounds.map(\.id)
            : SoundBoard.searchMine(own.sounds.map { ($0.id, $0.name) }, sound.query)
        return Section {
            if own.sounds.isEmpty {
                Text("No sounds of your own yet.").font(TypeRamp.body).foregroundStyle(Color.brandTextMuted)
            } else if shown.isEmpty, sound.pack.state != .ready {
                noMatch
            }
            ForEach(shown, id: \.self) { id in
                if let s = own.sound(id) { OwnSoundRow(sound: sound, own: s) }
            }
            Button { sound.toggleOwnRecording() } label: {
                if sound.recordingOwn, let since = sound.ownStarted {
                    TimelineView(.periodic(from: since, by: 1)) { context in
                        let s = max(0, Int(context.date.timeIntervalSince(since)))
                        Label("Stop \u{00B7} 0:\(String(format: "%02d", s))", systemImage: "stop.fill")
                            .foregroundStyle(StudioPalette.record).monospacedDigit()
                    }
                } else {
                    Label("Record a Sound", systemImage: "mic")
                }
            }
            .disabled(model.session.isBusy)
            .accessibilityIdentifier("sound-record-own")
            Button { sound.importing = true } label: { Label("Bring a File", systemImage: "doc.badge.plus") }
                .disabled(sound.recordingOwn)
                .accessibilityIdentifier("sound-bring")
            if let refusal = sound.refusal {
                Text(verbatim: refusal).font(TypeRamp.caption).foregroundStyle(Color.semanticError)
            }
        } header: {
            Text("Mine")
        } footer: {
            Text("On this device only.")
        }
    }

    // MARK: The part

    @ViewBuilder private var partSection: some View {
        Section {
            Button {
                model.listenFromHere()
            } label: {
                Label(model.listen.isRunning ? "Stop Listening" : "Listen Through From Here",
                      systemImage: model.listen.isRunning ? "stop.fill" : "play.fill")
            }
            .disabled(model.session.isBusy)
            if !model.shared {
                Button("Done With This Part") { model.finish() }
                    .disabled(model.studio.locked || sound.recordingOwn)
            }
            if let refusal = model.refusal {
                Text(verbatim: refusal).font(TypeRamp.caption).foregroundStyle(Color.semanticError)
            }
        }
    }
}

/// A chosen sound: play, its title, its length and placement, Remove; selected, its settings beneath.
private struct InCueRow: View {
    @Bindable var sound: SoundStudio
    let cue: SoundCue
    let selected: Bool

    var body: some View {
        let d = sound.describe(cue.src)
        let playing = sound.audition.playing == "in:\(cue.id)"
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s3) {
                Button {
                    sound.audition.toggle("in:\(cue.id)", url: sound.url(cue.src), gainDb: cue.gainDb)
                } label: {
                    Label(playing ? "Stop" : "Play \(d.title)", systemImage: playing ? "stop.fill" : "play.fill").labelStyle(.iconOnly)
                }
                .disabled(d.missing)
                Button { sound.selected = cue.id } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: d.title).font(TypeRamp.bodyStrong).foregroundStyle(Color.brandText)
                        Text(verbatim: d.missing ? "On another device"
                             : "\(SoundBoard.clock(d.ms)) \u{00B7} \(SoundBoard.placeLine(cue, untilLabel: cue.at == "bed" ? sound.lineLabel(cue.until ?? sound.current?.line ?? "") : nil))")
                            .font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .accessibilityAddTraits(selected ? .isSelected : [])
                Button(role: .destructive) { sound.remove(cue.id) } label: { Label("Remove", systemImage: "minus.circle") }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("sound-remove")
            }
            if selected { SoundSettings(sound: sound, cue: cue) }
        }
        .buttonStyle(.borderless)
        #if os(iOS)
        .swipeActions { Button("Remove", role: .destructive) { sound.remove(cue.id) } }
        #endif
        .contextMenu { Button("Remove", role: .destructive) { sound.remove(cue.id) } }
    }
}

/// Before · Under · After · Bed, Start, Level and Fades, Until, Hear It in Place (§3.2 item 2, §3.3).
private struct SoundSettings: View {
    @Bindable var sound: SoundStudio
    let cue: SoundCue

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Picker("Placement", selection: Binding(get: { cue.at }, set: { sound.update(cue.id, SoundBoard.Patch(at: $0)) })) {
                ForEach(SoundBoard.placements, id: \.self) { Text(SoundBoard.placementLabel($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("sound-placement")
            if cue.at == "bed" {
                HStack {
                    Text("Until").font(TypeRamp.body)
                    Spacer()
                    Button(sound.pickingUntil == cue.id ? "Tap the last line it sits under." : sound.lineLabel(cue.until ?? sound.current?.line ?? "").capitalized) {
                        sound.pickingUntil = sound.pickingUntil == cue.id ? nil : cue.id
                        if sound.pickingUntil != nil { sound.detent = .medium }
                    }
                }
            } else {
                Stepper(value: Binding(get: { cue.startMs }, set: { sound.update(cue.id, SoundBoard.Patch(startMs: $0)) }),
                        in: SoundMix.startMinMs...600_000, step: SoundBoard.startStepMs) {
                    HStack {
                        Text("Start").font(TypeRamp.body)
                        Spacer()
                        Text(verbatim: "\(cue.startMs < 0 ? "\u{2212}" : "+")\(String(format: "%.1f", abs(cue.startMs) / 1000)) s")
                            .font(TypeRamp.tabular).foregroundStyle(Color.brandTextMuted)
                    }
                }
            }
            DisclosureGroup("Level and Fades") {
                Stepper(value: Binding(get: { cue.gainDb }, set: { sound.update(cue.id, SoundBoard.Patch(gainDb: $0)) }),
                        in: SoundMix.gainMinDb...SoundMix.gainMaxDb, step: 1) {
                    HStack {
                        Text("Level")
                        Spacer()
                        Text(verbatim: "\(cue.gainDb > 0 ? "+" : cue.gainDb < 0 ? "\u{2212}" : "")\(Int(abs(cue.gainDb))) dB")
                            .font(TypeRamp.tabular).foregroundStyle(Color.brandTextMuted)
                    }
                }
                fadePicker("Fade In", value: cue.fadeInMs, choices: cue.at == "bed" ? SoundBoard.fadesMs + [SoundBoard.bedFadeInMs] : SoundBoard.fadesMs) {
                    sound.update(cue.id, SoundBoard.Patch(fadeInMs: $0))
                }
                fadePicker("Fade Out", value: cue.fadeOutMs, choices: SoundBoard.fadesMs) {
                    sound.update(cue.id, SoundBoard.Patch(fadeOutMs: $0))
                }
                if cue.at == "under" {
                    Picker("Length", selection: Binding(get: { cue.loop }, set: { sound.update(cue.id, SoundBoard.Patch(loop: $0)) })) {
                        Text("Whole").tag(false)
                        Text("Loop to the End of the Line").tag(true)
                    }
                }
                Picker("Under Voices", selection: Binding(get: { cue.duckDb }, set: { sound.update(cue.id, SoundBoard.Patch(duckDb: .some($0))) })) {
                    Text(verbatim: "Lane \u{00B7} \(Int(cue.at == "bed" ? SoundMix.musicDuckDb : SoundMix.effectsDuckDb)) dB").tag(Double?.none)
                    Text("Off").tag(Double?.some(0))
                    ForEach([-3.0, -6, -12, -18], id: \.self) { Text(verbatim: "\u{2212}\(Int(-$0)) dB").tag(Double?.some($0)) }
                }
            }
            .font(TypeRamp.body)
            Button {
                sound.hearInPlace()
            } label: {
                Label(sound.model.listen.isRunning ? "Stop" : "Hear It in Place", systemImage: sound.model.listen.isRunning ? "stop.fill" : "play.circle")
            }
            .disabled(sound.model.session.isBusy)
            .accessibilityIdentifier("sound-hear")
        }
        .padding(.leading, 28)
    }

    private func fadePicker(_ title: String, value: Double, choices: [Double], set: @escaping @MainActor @Sendable (Double) -> Void) -> some View {
        Picker(title, selection: Binding(get: { value }, set: set)) {
            ForEach(choices, id: \.self) { ms in
                Text(verbatim: ms == 0 ? "None" : "\(ms.truncatingRemainder(dividingBy: 1000) == 0 ? String(Int(ms / 1000)) : String(format: "%.1f", ms / 1000)) s").tag(ms)
            }
        }
    }
}

/// One pack cue (§3.2 item 5): audition, title, "0:06 · OpenGameArt · CC0", Add / In Cue; its record from the title.
private struct PackRow: View {
    @Bindable var sound: SoundStudio
    let cue: SoundBoard.PackCue
    @State private var record = false

    var body: some View {
        let here = sound.pack.isHere(cue)
        let src = SoundSource.pack(pack: sound.pack.manifest?.pack ?? "", cue: cue.id)
        let playing = sound.audition.playing == "pack:\(cue.id)"
        HStack(spacing: Spacing.s3) {
            Button { sound.audition.toggle("pack:\(cue.id)", url: sound.pack.fileURL(cue)) } label: {
                Label(playing ? "Stop" : "Play \(cue.title)", systemImage: playing ? "stop.fill" : "play.fill").labelStyle(.iconOnly)
            }
            .disabled(!here)
            Button { record = true } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: cue.title).font(TypeRamp.bodyStrong).foregroundStyle(Color.brandText)
                    Text(verbatim: SoundBoard.cueLine(cue)).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted).monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if sound.inCue(src) {
                Text("In Cue").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
            } else {
                Button { sound.add(src, kind: cue.kind) } label: { Label("Add", systemImage: "plus") }
                    .disabled(!here || sound.current == nil)
            }
        }
        .buttonStyle(.borderless)
        .frame(minHeight: 44)
        .opacity(here ? 1 : 0.5)
        .sheet(isPresented: $record) { CueRecord(cue: cue) }
    }
}

/// A pack cue's record: source page, license and its evidence, the date checked (§3.2 item 5).
private struct CueRecord: View {
    let cue: SoundBoard.PackCue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                LabeledContent("Source", value: cue.source.name)
                if let page = URL(string: cue.source.page) { Link("Source Page", destination: page) }
                LabeledContent("License", value: SoundBoard.licenseLabel(cue))
                if let evidence = URL(string: cue.license.evidence) { Link("Evidence", destination: evidence) }
                LabeledContent("Checked", value: cue.license.checked)
            }
            .navigationTitle(cue.title)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// A category not downloaded: "Weather · 1.3 MB" and Download (offline, "Offline"); failed, Try Again.
private struct CategoryHeader: View {
    let pack: SoundPackStore
    let category: SoundBoard.Category

    var body: some View {
        HStack {
            Text(verbatim: "\(category.title) \u{00B7} \(SoundBoard.megabytes(category.bytes))").font(TypeRamp.bodyStrong)
            Spacer()
            if pack.downloading.contains(category.id) {
                ProgressView()
            } else {
                Button(pack.failed.contains(category.id) ? "Try Again" : "Download") { Task { await pack.download(category.id) } }
                    .buttonStyle(.bordered)
            }
        }
    }
}

/// One own sound: audition, its name, "0:04 · Mine", Add / In Cue; Delete by swipe or menu.
private struct OwnSoundRow: View {
    @Bindable var sound: SoundStudio
    let own: OwnSound

    var body: some View {
        let src = SoundSource.own(own.id, name: own.name)
        let playing = sound.audition.playing == "own:\(own.id)"
        HStack(spacing: Spacing.s3) {
            Button { sound.audition.toggle("own:\(own.id)", url: sound.own.url(own.id)) } label: {
                Label(playing ? "Stop" : "Play \(own.name)", systemImage: playing ? "stop.fill" : "play.fill").labelStyle(.iconOnly)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: own.name).font(TypeRamp.bodyStrong)
                Text(verbatim: "\(SoundBoard.clock(own.seconds * 1000)) \u{00B7} \(own.from == "file" ? "Brought" : "Recorded")")
                    .font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if sound.inCue(.own(own.id)) || sound.current?.sounds.contains(where: { if case let .own(id, _) = $0.src { id == own.id } else { false } }) == true {
                Text("In Cue").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
            } else {
                Button { sound.add(src, kind: "effect") } label: { Label("Add", systemImage: "plus") }
                    .disabled(sound.current == nil)
            }
        }
        .buttonStyle(.borderless)
        .frame(minHeight: 44)
        #if os(iOS)
        .swipeActions { Button("Delete", role: .destructive) { sound.own.delete(own.id) } }
        #endif
        .contextMenu { Button("Delete", role: .destructive) { sound.own.delete(own.id) } }
    }
}

/// The manifest loading: a row in the results' shape (§7).
private struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: Spacing.s3) {
            Circle().fill(Color.brandSurfaceAlt).frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(Color.brandSurfaceAlt).frame(width: 140, height: 12)
                RoundedRectangle(cornerRadius: 3).fill(Color.brandSurfaceAlt).frame(width: 90, height: 10)
            }
        }
        .frame(minHeight: 44)
        .accessibilityHidden(true)
    }
}

/// A mix or export that needs sounds this device lacks (B32 §7): the names, Export Without Them, Cancel.
struct MissingSounds: Identifiable {
    let id = UUID()
    let names: [String]
    let retry: () -> Void

    var message: String { SoundBoard.missingLine(names) }

    /// The names a production's missing sounds go by, from their ids.
    @MainActor
    static func names(_ ids: [String], in p: Production, plays: PlaysLibrary) -> [String] {
        let all = (p.sound?.slots ?? []).flatMap(\.sounds)
        return ids.map { id in
            guard let x = all.first(where: { $0.id == id }) else { return id }
            switch x.src {
            case let .own(oid, name): return plays.ownSounds.sound(oid)?.name ?? name ?? "Your sound"
            case let .pack(_, cue): return plays.soundPack.cue(cue)?.title ?? cue
            case .take: return "Your take"
            }
        }
    }
}
#endif
