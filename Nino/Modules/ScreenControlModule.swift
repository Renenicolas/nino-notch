import SwiftUI

/// Screen Control, live: say or type what you want done on the Mac.
/// Jev decides fast; Claude takes anything Jev can't; the actions are real.
struct ScreenControlModule: NinoModule {
    let id = "nino.screen"
    let displayName = "Screen Control"
    let summary = "Say what to do: open apps, play music, change volume."
    let systemImage = "play.rectangle"
    let isStub = false

    var panel: AnyView { AnyView(ScreenControlPanel()) }
}

struct ScreenControlPanel: View {
    @ObservedObject private var screen = NinoScreenControl.shared
    @ObservedObject private var link = NinoVoiceLink.shared
    @State private var command = ""
    @State private var jevReady: Bool?

    var body: some View {
        NinoCard {
            HStack(spacing: 8) {
                Label(screen.hasAccessibility ? "Accessibility on" : "Accessibility needed",
                      systemImage: screen.hasAccessibility ? "checkmark.shield" : "exclamationmark.shield")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(screen.hasAccessibility ? NinoTheme.sub : NinoTheme.gold)
                if !screen.hasAccessibility {
                    NinoChipButton(title: "Grant", systemImage: "hand.raised") { screen.requestAccessibility() }
                }
                Spacer()
                Text(jevReady == true ? "Jev decides · Claude backup" : "Claude decides (no Jev key)")
                    .font(.caption2)
                    .foregroundStyle(NinoTheme.dim)
            }

            if let last = screen.entries.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text("“\(last.text)”")
                        .font(.caption)
                        .foregroundStyle(NinoTheme.text)
                        .lineLimit(1)
                    Text("\(last.decidedBy) → \(last.plan.map(\.action).joined(separator: ", ")) · \(last.result)")
                        .font(.caption2)
                        .foregroundStyle(last.ok == false ? NinoTheme.gold : NinoTheme.sub)
                        .lineLimit(2)
                }
            } else {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(NinoTheme.dim)
            }

            HStack(spacing: 6) {
                TextField("", text: $command, prompt: Text("Open Spotify and play my Liked Songs").foregroundStyle(NinoTheme.dim))
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(NinoTheme.text)
                    .onSubmit(run)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(NinoTheme.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Button(action: run) {
                    Group {
                        if screen.busy { ProgressView().controlSize(.mini) } else { Image(systemName: "play.fill").font(.system(size: 10, weight: .bold)) }
                    }
                    .foregroundStyle(NinoTheme.bg)
                    .frame(width: 24, height: 24)
                    .background(NinoTheme.gold)
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(screen.busy || command.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            BoringNotchSkyLightWindow.ninoAllowsKeyFocus = true
            Task { jevReady = await TypeSafeJev.apiKey() != nil }
        }
        .onDisappear {
            if !NinoVoiceLink.holdsNotchOpen { link.releaseKeyFocus() }
        }
    }

    private var hint: String {
        let ask = link.state?.askKey ?? "Right ⌘"
        let talk = link.state?.recordKey ?? "Right ⌥"
        return "Press \(ask), hold \(talk) and say it — or type it below."
    }

    private func run() {
        let text = command
        command = ""
        Task {
            if !(await screen.handle(text)) {
                link.sendTypedAsk(text)  // not a screen command: Ask Nino answers it
            }
        }
    }
}
