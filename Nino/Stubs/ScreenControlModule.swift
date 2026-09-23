import SwiftUI

/// Screen Control placeholder. Disabled media-style buttons, nothing driven.
struct ScreenControlModule: NinoModule {
    let id = "nino.screen"
    let displayName = "Screen Control"
    let summary = "Drive media and screen from the notch."
    let systemImage = "play.rectangle"
    let isStub = true

    var panel: AnyView {
        AnyView(
            NinoStubPanel(note: "Wire to Spotify/media API here. Buttons do nothing yet.") {
                HStack(spacing: 18) {
                    ForEach(["backward.fill", "play.fill", "forward.fill", "speaker.wave.2.fill"], id: \.self) { symbol in
                        Button {
                            // TODO: wire real integration here
                            // Map each symbol to a media/screen command (Spotify, Apple Music,
                            // system volume, display control) and set isStub = false.
                        } label: {
                            Image(systemName: symbol)
                                .font(.title3)
                                .foregroundStyle(NinoTheme.dim)
                                .frame(width: 28, height: 28)
                                .background(NinoTheme.bg)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(true)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        )
    }
}
