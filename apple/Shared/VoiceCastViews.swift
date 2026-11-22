#if os(iOS) || os(macOS)
import SwiftUI
import AVFoundation

// Casting the device voices on screen (PLAYS-DESIGN §2.8, iOS-DESIGN §4.12c, macOS-DESIGN §4.5c; Decision 076
// S2): the chip on a part card, the picker, and the reader's Voices list. Every change is kept at once.

extension View {
    /// A voice downloaded in Settings appears on return (`availableVoicesDidChangeNotification`).
    func repaintsOnVoiceChange(_ model: VoiceCastModel) -> some View {
        onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in
            model.refresh()
        }
    }
}

// MARK: - The chip

/// The voice a part is read in: its name, a warning glyph when the device lacks the chosen voice, and
/// how it is tuned. "Not read" for directions and sound until given a voice; "No Voice" when the device has none.
struct VoiceChipLabel: View {
    let model: VoiceCastModel
    let part: PartID

    var body: some View {
        let r = model.resolve(part)
        HStack(spacing: Spacing.s1) {
            if r.missing != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.semanticWarning)
            }
            Text(verbatim: VoiceChipText.title(r)).lineLimit(1)
            if r.isDefault, r.read { Text("Default").foregroundStyle(Color.brandTextMuted).lineLimit(1) }
            if let tuning = VoiceChipText.tuning(r) {
                Text(verbatim: tuning).foregroundStyle(Color.brandTextMuted).lineLimit(1)
            }
            Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
        }
        .font(TypeRamp.caption)
        .foregroundStyle(Color.brandSecondary)
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VoiceChipText.accessibility(r, part: part))
    }
}

#if os(iOS)
/// Opens the picker (a push on the iPhone, a sheet on the iPad).
struct VoiceChip: View {
    let model: VoiceCastModel
    let part: PartID
    let open: () -> Void

    var body: some View {
        Button(action: open) { VoiceChipLabel(model: model, part: part) }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
    }
}
#else
/// A pop-up of the device's voices in the row, and Voice Settings... for speed, pitch and a preview (macOS-DESIGN §4.5c).
struct VoiceChip: View {
    let model: VoiceCastModel
    let script: PlayScript
    let part: PartID
    @State private var settings = false

    var body: some View {
        let current = model.resolve(part)
        Menu {
            Button { model.reset(part) } label: {
                let name = model.defaultVoiceName(part).map { "Default (\($0))" } ?? "Default"
                if current.isDefault { Label(name, systemImage: "checkmark") } else { Text(verbatim: name) }
            }
            if !part.isSpeaking {
                Button { model.chooseNotRead(part) } label: {
                    if current.entry.engine == .none, !current.isDefault { Label("Not Read", systemImage: "checkmark") } else { Text("Not Read") }
                }
            }
            ForEach(model.downloaded + model.voices) { voice in
                Button { model.choose(part, voice) } label: {
                    if current.read, !current.isDefault, current.voice?.id == voice.id {
                        Label(voice.displayName, systemImage: "checkmark")
                    } else {
                        Text(verbatim: voice.displayName)
                    }
                }
            }
            Divider()
            Button("Voice Settings\u{2026}") { settings = true }
            BetterVoicesLink()
        } label: {
            VoiceChipLabel(model: model, part: part)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onAppear { if LaunchDoors.current.picker == part.rawValue { settings = true } }
        .popover(isPresented: $settings, arrowEdge: .bottom) {
            VoicePickerForm(model: model, script: script, part: part).frame(width: 360, height: 480)
        }
    }
}
#endif

// MARK: - The picker

/// The picker's first row: Default, naming the voice it reads now (PLAYS-DESIGN §2.8 rule 4).
struct DefaultChoiceRow: View {
    let name: String?
    let selected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Default").foregroundStyle(Color.brandText)
                if let name { Text(verbatim: name).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted) }
            }
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(Color.brandSecondary) }
        }
        .contentShape(Rectangle())
    }
}

/// Speed, pitch, and the voices on this device, each with a preview of the part's own first line.
struct VoicePickerForm: View {
    let model: VoiceCastModel
    let script: PlayScript
    let part: PartID
    @State private var preview = VoicePreview()
    @State private var playing: String?
    @State private var kokoro = KokoroModelStore.shared
    /// Whether this play has published phonemes (nil until asked): a play without them is not read by Kokoro.
    @State private var phonemes: Bool?
    @Environment(\.openURL) private var openURL

    var body: some View {
        let r = model.resolve(part)
        let notRead = r.entry.engine == .none && !r.isDefault
        let line = script.lines(for: part).first?.spokenText ?? ""
        Form {
            if let missing = r.missing {
                Section {
                    Label("\(missing) is not on this device.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.semanticWarning)
                }
            }
            Section {
                Stepper(value: Binding(get: { r.entry.rate }, set: { x in model.set(part) { $0.rate = x } }),
                        in: VoiceCasting.rateRange, step: 0.1) {
                    LabeledContent("Speed", value: VoiceChipText.rate(r.entry.rate))
                }
                Stepper(value: Binding(get: { VoiceChipText.pitchStep(r.entry.pitch) },
                                       set: { n in model.set(part) { $0.pitch = 1 + Double(n) / 10 } }),
                        in: -5...5) {
                    LabeledContent("Pitch", value: VoiceChipText.pitch(VoiceChipText.pitchStep(r.entry.pitch)))
                }
            }
            .disabled(notRead)
            Section {
                Button { model.reset(part) } label: {
                    DefaultChoiceRow(name: model.defaultVoiceName(part), selected: r.isDefault)
                }
                .buttonStyle(.plain)
                if !part.isSpeaking {
                    Button { model.chooseNotRead(part) } label: {
                        HStack {
                            Text("Not Read")
                            Spacer()
                            if notRead { Image(systemName: "checkmark").foregroundStyle(Color.brandSecondary) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if KokoroFlag.enabled, kokoro.ready, !model.downloaded.isEmpty {
                Section {
                    if phonemes == false {
                        Text("Not available for this play.").foregroundStyle(Color.brandTextMuted)
                    } else {
                        ForEach(model.downloaded) { voice in
                            row(voice, current: r.read && !r.isDefault && r.voice?.id == voice.id, line: line, rate: r.entry.rate, pitch: r.entry.pitch)
                        }
                    }
                } header: {
                    Text("Downloaded")
                }
            }
            Section {
                ForEach(model.voices) { voice in
                    row(voice, current: r.read && !r.isDefault && r.voice?.id == voice.id, line: line, rate: r.entry.rate, pitch: r.entry.pitch)
                }
            } header: {
                Text("On This Device")
            } footer: {
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Text(Self.addVoices)
                    #if os(iOS)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    #else
                    Button("Open Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension") { openURL(url) }
                    }
                    #endif
                    BetterVoicesLink()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(part.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(Haptic.selection.feedback, trigger: r.entry.voice)
        #endif
        .repaintsOnVoiceChange(model)
        .onAppear {
            model.refresh()
            preview.onChange = { playing = $0 }
        }
        .onDisappear { preview.stop() }
        .task(id: kokoro.ready) {
            model.refresh()
            if kokoro.ready, KokoroFlag.enabled { phonemes = await KokoroReader.shared.prepare(script.id) }
        }
    }

    static let attribution = "Kokoro-82M by hexgrad, Apache-2.0. Trained in part on Koniwa (CC BY 3.0) and SIWIS (CC BY 4.0)."

    static var addVoices: String {
        #if os(iOS)
        "Add voices in Settings > Accessibility > Spoken Content > Voices."
        #else
        "Add voices in System Settings > Accessibility > Spoken Content > System Voice > Manage Voices."
        #endif
    }

    private func row(_ voice: CastVoice, current: Bool, line: String, rate: Double, pitch: Double) -> some View {
        HStack(spacing: Spacing.s2) {
            Button { model.choose(part, voice) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: voice.displayName).foregroundStyle(Color.brandText)
                        Text(verbatim: Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language)
                            .font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                    }
                    Spacer(minLength: 0)
                    if current { Image(systemName: "checkmark").foregroundStyle(Color.brandSecondary) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                preview.toggle(line, voice: voice, rate: rate, pitch: pitch, playID: script.id)
            } label: {
                Image(systemName: playing == voice.id ? "stop.circle" : "play.circle")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(Color.brandSecondary)
            }
            .buttonStyle(.borderless)
            .disabled(line.isEmpty)
            .accessibilityLabel(playing == voice.id ? "Stop preview of \(voice.displayName)" : "Preview \(voice.displayName)")
        }
        .accessibilityElement(children: .contain)
    }
}

#if os(iOS)
/// The picker as a screen of its own: pushed on the iPhone, presented with detents on the iPad.
struct VoicePickerScreen: View {
    let model: VoiceCastModel
    let script: PlayScript
    let part: PartID
    var dismiss: (() -> Void)?

    var body: some View {
        VoicePickerForm(model: model, script: script, part: part)
            .toolbar {
                if let dismiss { ToolbarItem(placement: .confirmationAction) { Button("Done", action: dismiss) } }
            }
    }
}
#endif

// MARK: - The reader's Voices

/// Every part with its chip, and Recast All (the play's own cast: `s:<script>`).
struct ReaderVoices: View {
    let model: VoiceCastModel
    let script: PlayScript
    var dismiss: (() -> Void)?
    #if os(iOS)
    @State private var picking: PartID?
    #endif

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(script.castParts) { part in
                        HStack {
                            Text(verbatim: part.title).font(TypeRamp.bodyStrong).lineLimit(2)
                            Spacer(minLength: Spacing.s2)
                            chip(part.id)
                        }
                    }
                }
                Section {
                    Button("Recast All") { model.recast() }
                    BetterVoicesLink()
                }
            }
            .navigationTitle("Voices")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $picking) { part in
                VoicePickerScreen(model: model, script: script, part: part)
            }
            .toolbar {
                if let dismiss { ToolbarItem(placement: .confirmationAction) { Button("Done", action: dismiss) } }
            }
            #endif
            .repaintsOnVoiceChange(model)
            .onAppear { model.refresh() }
        }
    }

    @ViewBuilder private func chip(_ part: PartID) -> some View {
        #if os(iOS)
        VoiceChip(model: model, part: part) { picking = part }
        #else
        VoiceChip(model: model, script: script, part: part)
        #endif
    }
}
#endif
