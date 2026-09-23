import SwiftUI

/// Settings list of every registered module. Off by default.
struct NinoModulesSettingsView: View {
    @ObservedObject var registry = NinoModuleRegistry.shared

    var body: some View {
        Form {
            Section {
                Text(NinoTheme.positioning)
                    .foregroundStyle(NinoTheme.sub)
                Text("The Nino tab lists every module. Nino Voice: On runs the voice engine (hotkeys, dictation, paste). Ask Nino: On shows answers in the notch. Stubs do nothing either way.")
                    .font(.caption)
                    .foregroundStyle(NinoTheme.sub)
            } header: {
                Text("Nino modules")
            }

            Section {
                ForEach(registry.modules, id: \.id) { module in
                    Toggle(isOn: Binding(
                        get: { registry.isEnabled(module.id) },
                        set: { registry.setEnabled(module.id, enabled: $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(module.displayName)
                                if module.isStub {
                                    Text("STUB")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(NinoTheme.gold)
                                }
                            }
                            Text(module.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(NinoTheme.gold)
                }
            } header: {
                Text("Modules")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Nino modules")
    }
}
