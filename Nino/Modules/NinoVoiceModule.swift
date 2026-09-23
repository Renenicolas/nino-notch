import SwiftUI

/// Nino Voice, live. The engine (hotkeys, Parakeet speech-to-text, Claude CLI
/// polish, paste at the cursor) runs headless in Nino Voice.app; this tab and the
/// closed-notch indicator are its only screen.
struct NinoVoiceModule: NinoModule {
    let id = "nino.voice"
    let displayName = "Nino Voice"
    let summary = "Talk anywhere. Transcribed on this Mac and pasted where you type."
    let systemImage = "mic.fill"
    let isStub = false

    var panel: AnyView { AnyView(NinoVoicePanel()) }
}

struct NinoVoicePanel: View {
    @ObservedObject private var link = NinoVoiceLink.shared

    var body: some View {
        NinoCard {
            if let state = link.state {
                connected(state)
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Starting the Nino Voice engine…")
                        .font(.caption)
                        .foregroundStyle(NinoTheme.sub)
                }
            }
        }
    }

    @ViewBuilder
    private func connected(_ state: NinoVoiceState) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.recording == "recording" ? NinoTheme.gold : (state.isCapturing ? NinoTheme.gold2 : NinoTheme.dim))
                .frame(width: 8, height: 8)
            Text(Self.statusText(state))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NinoTheme.text)
            Spacer()
            Text([state.modeName, state.modelName].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(NinoTheme.dim)
                .lineLimit(1)
        }

        if !state.setup.isComplete {
            setupRow(state.setup)
        } else if state.recording == "recording" {
            HStack(spacing: 10) {
                NinoVoiceMeter(level: link.level, bars: 18, height: 18)
                Text(state.partial.isEmpty ? "Listening…" : state.partial)
                    .font(.caption)
                    .foregroundStyle(NinoTheme.sub)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        } else {
            Text(state.lastText.isEmpty ? "Nothing dictated yet." : state.lastText)
                .font(.caption)
                .foregroundStyle(state.lastText.isEmpty ? NinoTheme.dim : NinoTheme.sub)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        HStack(spacing: 6) {
            Button {
                link.send("toggleRecord")
            } label: {
                Label(state.recording == "recording" ? "Stop" : "Talk",
                      systemImage: state.recording == "recording" ? "stop.fill" : "mic.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NinoTheme.bg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(NinoTheme.gold)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(state.isCapturing && state.recording != "recording")

            NinoChipButton(title: "Settings", systemImage: "gearshape") { link.send("openSettings") }
            NinoChipButton(title: "History", systemImage: "clock") { link.send("openHistory") }
            Spacer()
            Text(Self.keyHint(state))
                .font(.caption2)
                .foregroundStyle(NinoTheme.dim)
                .lineLimit(1)
        }
    }

    private func setupRow(_ setup: NinoVoiceState.Setup) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(NinoTheme.gold)
            Text("Finish setup —" + (setup.onboarded ? "" : " welcome") + (setup.microphone ? "" : " · microphone") + (setup.accessibility ? "" : " · accessibility"))
                .font(.caption)
                .foregroundStyle(NinoTheme.sub)
                .lineLimit(1)
            Spacer()
            NinoChipButton(title: "Finish setup", systemImage: "checkmark.seal") {
                link.send(setup.onboarded ? "requestPermissions" : "openOnboarding")
            }
        }
    }

    static func statusText(_ state: NinoVoiceState) -> String {
        switch state.recording {
        case "starting": return "Starting…"
        case "recording": return "Listening"
        case "transcribing": return "Transcribing"
        case "enhancing": return "Polishing"
        case "busy": return "Busy"
        default: return "Ready"
        }
    }

    static func keyHint(_ state: NinoVoiceState) -> String {
        var parts: [String] = []
        if !state.recordKey.isEmpty { parts.append("\(state.recordKey): talk") }
        if !state.askKey.isEmpty { parts.append("\(state.askKey): ask") }
        return parts.joined(separator: " · ")
    }
}

/// Gold level bars, shared by the tab and the closed-notch indicator.
struct NinoVoiceMeter: View {
    let level: Double
    var bars = 12
    var height: CGFloat = 14

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<bars, id: \.self) { index in
                // Middle bars move most, like a voice.
                let shape = 1 - abs(Double(index) - Double(bars - 1) / 2) / Double(bars)
                Capsule()
                    .fill(NinoTheme.gold)
                    .frame(width: 2, height: max(2, height * CGFloat(min(1, level * 1.6 * shape + 0.08))))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.08), value: level)
    }
}

struct NinoChipButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(NinoTheme.sub)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(NinoTheme.bg)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Closed-notch indicator while Nino Voice listens or works. Replaces the old
/// Nino Voice pill: same job, drawn by Nino Notch.
struct NinoVoiceLiveActivity: View {
    @ObservedObject private var link = NinoVoiceLink.shared
    let notchWidth: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "mic.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NinoTheme.gold)
                .frame(width: 44)

            Rectangle()
                .fill(NinoTheme.bg)
                .frame(width: notchWidth)

            Group {
                if link.state?.recording == "recording" {
                    NinoVoiceMeter(level: link.level, bars: 8, height: 12)
                } else {
                    ProgressView().controlSize(.mini).tint(NinoTheme.gold)
                }
            }
            .frame(width: 44)
        }
        .frame(height: height)
    }
}
