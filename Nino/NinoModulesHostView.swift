import SwiftUI

/// The Nino tab in the open notch: a chip row to pick a module, then that
/// module's panel. Same layout idea as the Home / Shelf tabs above it.
struct NinoModulesHostView: View {
    @ObservedObject var registry = NinoModuleRegistry.shared
    @ObservedObject private var voice = NinoVoiceLink.shared

    /// Ask Nino opened from its key gets the whole panel: answers need the room.
    private var focused: Bool {
        voice.state?.ask.visible == true && NinoVoiceLink.holdsNotchOpen && registry.selected?.id == "nino.search"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !focused {
            HStack(spacing: 4) {
                ForEach(registry.modules, id: \.id) { module in
                    let isSelected = registry.selected?.id == module.id
                    Button {
                        withAnimation(.smooth) { registry.select(module.id) }
                    } label: {
                        Label(module.displayName, systemImage: module.systemImage)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .foregroundStyle(isSelected ? NinoTheme.gold : NinoTheme.dim)
                            .background(isSelected ? NinoTheme.gold.opacity(0.15) : .clear)
                            .clipShape(Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            }

            if let module = registry.selected {
                if !focused {
                HStack(spacing: 6) {
                    Text(module.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NinoTheme.text)
                    if module.isStub {
                        Text("STUB")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(NinoTheme.bg)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(NinoTheme.gold)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Text(registry.isEnabled(module.id) ? "On" : "Off")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(registry.isEnabled(module.id) ? NinoTheme.gold : NinoTheme.dim)
                }
                }
                module.panel
            } else {
                Text("No Nino modules registered. Add one to ModuleCatalog.")
                    .font(.caption)
                    .foregroundStyle(NinoTheme.sub)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
