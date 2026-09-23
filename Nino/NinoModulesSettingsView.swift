import SwiftUI

/// Settings list of every registered module. Off by default.
struct NinoModulesSettingsView: View {
    @ObservedObject var registry = NinoModuleRegistry.shared

    var body: some View {
        Form {
            Section {
                Text(NinoTheme.positioning)
                    .foregroundStyle(NinoTheme.sub)
                Text("The Nino tab in the notch always lists every module. On/Off is the module’s activation state. A stub does nothing either way: no login, no network, no secrets.")
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
                Text("Modules (all off until you flip them)")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Nino modules")
    }
}
