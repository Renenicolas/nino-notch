import SwiftUI

/// Vellum assistant placeholder. Chat-style panel, nothing connected.
struct VellumAssistantModule: NinoModule {
    let id = "nino.vellum"
    let displayName = "Vellum"
    let summary = "Nino Assistant, chat in the notch."
    let systemImage = "sparkles"
    let isStub = true

    var panel: AnyView {
        AnyView(VellumAssistantPanel())
    }
}

private struct VellumAssistantPanel: View {
    @State private var draft = ""

    var body: some View {
        NinoStubPanel(note: "Connect to Vellum runtime here. Input is not sent anywhere.") {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(NinoTheme.gold)
                Text("Nino Assistant")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NinoTheme.text)
            }
            Text("Hi, I'm Nino. Once Vellum is connected, ask me anything here.")
                .font(.caption)
                .foregroundStyle(NinoTheme.sub)
                .padding(6)
                .background(NinoTheme.bg)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack(spacing: 6) {
                TextField("Ask Nino…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(NinoTheme.text)
                    .padding(5)
                    .background(NinoTheme.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Button {
                    // TODO: wire real integration here
                    // Send `draft` to the Vellum runtime, append the reply above,
                    // and set isStub = false on VellumAssistantModule.
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(NinoTheme.dim)
                }
                .buttonStyle(.plain)
                .disabled(true)
            }
        }
    }
}
