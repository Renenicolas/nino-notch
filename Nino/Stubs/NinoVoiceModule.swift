import SwiftUI

/// Nino Voice placeholder. No microphone access, no audio, no network.
struct NinoVoiceModule: NinoModule {
    let id = "nino.voice"
    let displayName = "Nino Voice"
    let summary = "Talk to Nino from the notch."
    let systemImage = "mic.fill"
    let isStub = true

    var panel: AnyView {
        AnyView(
            NinoStubPanel(note: "Not wired: no microphone, no audio, no network.") {
                HStack(spacing: 12) {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(NinoTheme.gold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tap to talk to Nino")
                            .font(.headline)
                            .foregroundStyle(NinoTheme.text)
                        Text("Hold to record, release to send.")
                            .font(.caption)
                            .foregroundStyle(NinoTheme.sub)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    // TODO: wire real integration here
                    // Start the Nino Voice session (mic capture -> Nino Voice runtime),
                    // stream the transcript into this panel, and set isStub = false.
                }
            }
        )
    }
}
