#if os(iOS) || os(macOS)
import SwiftUI
import AVFoundation

// The Better Voices step (PLAYS-DESIGN §2.8 rule 13, Decision 090; iOS-DESIGN §4.6b, macOS-DESIGN §4.1b): one sheet,
// skippable, never forced, whose control is Library > Voices' own `KokoroControls` over the one `KokoroModelStore`.
// Offered by `VoicesOffer`: at launch (`voicesStepAtLaunch`) and, if skipped, at the first read, cast or record
// (`voicesStepAtFirstUse`). Apple TV has no Kokoro and no step.

struct VoicesStepSheet: View {
    @State private var kokoro = KokoroModelStore.shared
    @State private var free: Int64?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        let state = KokoroDownloadState.of(kokoro.state, supported: KokoroFlag.enabled)
        let progress: (Int64, Int64) = { if case let .downloading(d, t) = kokoro.state { return (d, t) } else { return (0, 0) } }()
        let short = VoicesSpace.short(free: free, size: kokoro.downloadBytes) && (state == .absent || state == .failed)
        Form {
            Section {
                KokoroControls(state: state, done: progress.0, total: progress.1, bytes: kokoro.downloadBytes,
                               download: { begin() }, cancel: { kokoro.cancel() },
                               retry: { kokoro.clearFailure(); begin() },
                               delete: { Task { await kokoro.delete() } })
                    .disabled(short)
                if short, let free {
                    Label(VoicesSpace.warning(free: free), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.semanticWarning)
                }
            } header: {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text("Better Voices").font(TypeRamp.sectionHeader).foregroundStyle(Color.brandText)
                    Text(Self.fact).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                }
                .textCase(nil)
            } footer: {
                if state == .ready { Text(VoicePickerForm.attribution) }
            }
            #if os(macOS)
            if !Self.hasEnhancedSystemVoice {
                Section {
                    LabeledContent(Self.systemLine) {
                        Button("Open Settings") { openURL(VoicesSection.systemVoicesURL) }
                    }
                }
            }
            #endif
            #if os(iOS)
            Section {
                Button(state == .ready ? "Done" : "Not Now") { dismiss() }
            }
            #endif
        }
        #if os(macOS)
        .formStyle(.grouped)
        .frame(width: 420)
        .toolbar {
            ToolbarItem(placement: state == .ready ? .confirmationAction : .cancellationAction) {
                Button(state == .ready ? "Done" : "Not Now") { dismiss() }
            }
        }
        #else
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        #endif
        .task { free = VoicesSpace.free() }
    }

    static let fact = "Downloaded voices read the parts nobody has cast."
    static let systemLine = "Better system voices are added in Settings."

    private func begin() {
        VoicesOffer.current.downloadBegan()
        kokoro.download()
    }

    /// Whether an enhanced or premium English system voice is installed (rule 13: the Mac's system-voices line).
    static var hasEnhancedSystemVoice: Bool {
        AVSpeechSynthesisVoice.speechVoices().contains { $0.language.hasPrefix("en") && $0.quality != .default }
    }
}

/// At launch: the step over the first screen, once it is drawn.
private struct VoicesStepAtLaunch: ViewModifier {
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .task {
                try? await Task.sleep(for: .seconds(1))
                if VoicesOffer.current.atLaunch(eligible: VoicesOffer.eligible()) { shown = true }
            }
            .sheet(isPresented: $shown) { VoicesStepSheet() }
    }
}

/// The first read, cast or record: the step once more if it was skipped (or could not be offered at launch).
private struct VoicesStepAtFirstUse: ViewModifier {
    let on: Bool
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .task {
                guard on else { return }
                try? await Task.sleep(for: .seconds(0.5))
                if VoicesOffer.current.atFirstUse(eligible: VoicesOffer.eligible()) { shown = true }
            }
            .sheet(isPresented: $shown) { VoicesStepSheet() }
    }
}

extension View {
    func voicesStepAtLaunch() -> some View { modifier(VoicesStepAtLaunch()) }
    /// `on` is false where a sheet would interrupt others (a read room).
    func voicesStepAtFirstUse(_ on: Bool = true) -> some View { modifier(VoicesStepAtFirstUse(on: on)) }
}
#endif
