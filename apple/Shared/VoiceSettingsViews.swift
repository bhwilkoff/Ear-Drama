#if os(iOS) || os(macOS)
import SwiftUI
import AVFoundation

// The Voices section of Library (Decision 086; PLAYS-DESIGN §2.8 rule 11; owner 2026-11-22: Library carries it, there is no Settings page): the device's voice
// defaults, which every part nobody cast reads. Three parts: the high-fidelity (Kokoro) download, the Default speed,
// and the voices in the Default order, each with a Use switch, its quality, and Hear. Kept in UserDefaults on this
// device only (`ed.voices`), never synced. Hear speaks live and keeps nothing (§5).

/// What Hear reads: the opening line of today's scene, with its play so Kokoro finds the phonemes.
struct VoiceSample: Equatable, Sendable {
    let playID: String
    let text: String
}

/// The quality a row states: Kokoro's own grade, or the device voice's tier.
nonisolated enum VoiceQualityText {
    static func of(_ v: CastVoice) -> String {
        if let grade = v.grade { return "Grade \(grade.replacingOccurrences(of: "-", with: "\u{2212}"))" }
        let tier = ["Standard", "Enhanced", "Premium"][min(2, max(0, v.tier))]
        let lang = Locale.current.localizedString(forIdentifier: v.language) ?? v.language
        return "\(tier) \u{00B7} \(lang)"
    }

    /// The voice's name without its quality suffix ("Ava (Premium)" reads "Ava").
    static func plain(_ v: CastVoice) -> String {
        guard v.name.hasSuffix(")"), let open = v.name.lastIndex(of: "(") else { return v.name }
        let name = v.name[..<open].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? v.name : name
    }
}

/// The Kokoro download's controls for each state (rule 10's words): one refusal, Download Voices with its size, progress and
/// Cancel, a failure with Try Again, and Delete. Stateless, so a render can show every state.
struct KokoroControls: View {
    let state: KokoroDownloadState
    var done: Int64 = 0
    var total: Int64 = 0
    let bytes: Int64
    var download: () -> Void = {}
    var cancel: () -> Void = {}
    var retry: () -> Void = {}
    var delete: () -> Void = {}

    var body: some View {
        switch state {
        case .unsupported:
            Text("This device can\u{2019}t run Kokoro voices yet.").foregroundStyle(Color.brandTextMuted)
        case .absent:
            Button("Download Voices (\(Kokoro.megabytes(bytes)))", action: download)
        case .downloading:
            VStack(alignment: .leading, spacing: Spacing.s1) {
                ProgressView(value: Double(min(done, total)), total: Double(max(total, 1)))
                Text(verbatim: "\(Kokoro.megabytes(done)) of \(Kokoro.megabytes(total))")
                    .font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
            }
            Button("Cancel", role: .cancel, action: cancel)
        case .failed:
            Label("The download failed.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.semanticWarning)
            Button("Try Again", action: retry)
        case .ready:
            Button("Delete Downloaded Voices (\(Kokoro.megabytes(bytes)))", role: .destructive, action: delete)
        }
    }
}

/// One voice in the Default order: its name and quality, Hear, and the Use switch.
struct VoiceDefaultRow: View {
    let voice: CastVoice
    @Binding var used: Bool
    var playing = false
    var canHear = true
    var hear: () -> Void = {}

    var body: some View {
        let name = VoiceQualityText.plain(voice)
        HStack(spacing: Spacing.s2) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: name).foregroundStyle(Color.brandText)
                Text(verbatim: VoiceQualityText.of(voice)).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
            }
            Spacer(minLength: 0)
            Button(action: hear) {
                Image(systemName: playing ? "stop.circle" : "play.circle")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(Color.brandSecondary)
            }
            .buttonStyle(.borderless)
            .disabled(!canHear)
            .accessibilityLabel(playing ? "Stop \(name)" : "Hear \(name)")
            Toggle("Use \(name)", isOn: $used).labelsHidden()
        }
        .accessibilityElement(children: .contain)
    }
}

/// Library's Voices sections (rows of a Library `List`).
struct VoicesSection: View {
    @Environment(PlaysLibrary.self) private var plays
    @State private var kokoro = KokoroModelStore.shared
    @State private var defaults = VoiceDefaultsStore.load()
    @State private var preview = VoicePreview()
    @State private var playing: String?
    @State private var sample: VoiceSample?
    @State private var revision = 0
    @Environment(\.openURL) private var openURL

    var body: some View {
        let _ = revision
        let all = Self.voices(ready: kokoro.ready && KokoroFlag.enabled)
        let ordered = VoiceCasting.ordered(all, defaults)
        let hifi = ordered.filter { $0.engine == .kokoro }
        let device = ordered.filter { $0.engine == .system }
        Group {
            kokoroSection.id("voices")
            Section {
                Stepper(value: Binding(get: { defaults.rate }, set: { x in
                    defaults.rate = x
                    VoiceDefaultsStore.save(defaults)
                }), in: VoiceCasting.rateRange, step: 0.1) {
                    LabeledContent("Speed", value: VoiceChipText.rate(defaults.rate))
                }
            }
            if !hifi.isEmpty {
                Section("Downloaded") {
                    ForEach(hifi) { row($0) }
                        .onMove { move(hifi, .kokoro, $0, $1) }
                }
            }
            Section {
                ForEach(device) { row($0) }
                    .onMove { move(device, .system, $0, $1) }
            } header: {
                Text("On This Device")
            } footer: {
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Text(VoicePickerForm.addVoices)
                    Button("Open Settings") { openURL(Self.systemVoicesURL) }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in revision += 1 }
        .onAppear {
            defaults = VoiceDefaultsStore.load()
            preview.onChange = { playing = $0 }
        }
        .onDisappear { preview.stop() }
        .task(id: plays.rows.count) { sample = await Self.sample(plays) }
    }

    static var systemVoicesURL: URL {
        #if os(iOS)
        URL(string: UIApplication.openSettingsURLString)!
        #else
        URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension")!
        #endif
    }

    /// Every voice this device would cast: the downloaded Kokoro voices when the model is here, then its own.
    static func voices(ready: Bool) -> [CastVoice] { Kokoro.castable(ready: ready) + DeviceVoices.castable() }

    static func sample(_ plays: PlaysLibrary) async -> VoiceSample? {
        guard let row = PlayScript.todaysScene(plays.rows, dateKey: RadioClock.localDate()) else { return nil }
        guard let script = (try? await plays.script(id: row.id)) ?? nil, let first = script.opening(n: 1).first else { return nil }
        return VoiceSample(playID: script.id, text: first.text)
    }

    // MARK: Kokoro

    @ViewBuilder private var kokoroSection: some View {
        let state = KokoroDownloadState.of(kokoro.state, supported: KokoroFlag.enabled)
        let progress: (Int64, Int64) = { if case let .downloading(d, t) = kokoro.state { return (d, t) } else { return (0, 0) } }()
        Section {
            KokoroControls(state: state, done: progress.0, total: progress.1, bytes: kokoro.downloadBytes,
                           download: { kokoro.download() }, cancel: { kokoro.cancel() },
                           retry: { kokoro.clearFailure(); kokoro.download() },
                           delete: {
                               Task {
                                   preview.stop()
                                   await kokoro.delete()
                                   revision += 1
                               }
                           })
        } header: {
            Text("Voices")
        } footer: {
            if state == .ready { Text(VoicePickerForm.attribution) }
        }
    }

    // MARK: A voice's row

    private func row(_ v: CastVoice) -> some View {
        VoiceDefaultRow(voice: v, used: Binding(
            get: { VoiceCasting.uses(v, defaults) },
            set: { on in
                defaults.off[v.key] = !on
                VoiceDefaultsStore.save(defaults)
            }), playing: playing == v.id, canHear: sample != nil) {
            guard let sample else { return }
            preview.toggle(sample.text, voice: v, rate: defaults.rate, pitch: 1, playID: sample.playID)
        }
    }

    private func move(_ group: [CastVoice], _ engine: VoiceEngine, _ from: IndexSet, _ to: Int) {
        defaults = VoiceCasting.reorder(group, defaults, from: from, to: to)
        VoiceDefaultsStore.save(defaults)
    }
}

/// "Better voices": one quiet link that opens Library at its Voices section while Kokoro could run here and is not downloaded (PLAYS-DESIGN §2.8 rule 11).
struct BetterVoicesLink: View {
    @State private var kokoro = KokoroModelStore.shared
    @Environment(AppStore.self) private var app

    var body: some View {
        if KokoroDownloadState.offersBetterVoices(ready: kokoro.ready, flag: KokoroFlag.enabled) {
            Button("Better Voices") { app.openLibraryVoices() }
        }
    }
}
#endif
