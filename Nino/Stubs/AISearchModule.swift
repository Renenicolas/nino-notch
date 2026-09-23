import SwiftUI

/// AI Search placeholder. Search bar plus an empty results state. No queries leave this Mac.
struct AISearchModule: NinoModule {
    let id = "nino.search"
    let displayName = "AI Search"
    let summary = "Search Nino's knowledge from the notch."
    let systemImage = "magnifyingglass"
    let isStub = true

    var panel: AnyView {
        AnyView(AISearchPanel())
    }
}

private struct AISearchPanel: View {
    @State private var query = ""

    var body: some View {
        NinoStubPanel(note: "Not wired: nothing is searched yet.") {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(NinoTheme.gold)
                TextField("Search…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(NinoTheme.text)
                    .onSubmit {
                        // TODO: wire real integration here
                        // Run `query` against the AI search backend, render the hits
                        // in place of the empty state below, and set isStub = false.
                    }
            }
            .padding(6)
            .background(NinoTheme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("Results will appear here")
                .font(.caption)
                .foregroundStyle(NinoTheme.dim)
                .frame(maxWidth: .infinity, minHeight: 24)
        }
    }
}
