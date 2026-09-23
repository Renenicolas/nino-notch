import Foundation
import Combine

/// Holds every registered Nino module, which one is selected in the notch,
/// and each module's on/off state.
///
/// Enable flags live in UserDefaults under `nino.module.enabled.<id>`.
/// Live modules default on, stubs default off.
@MainActor
final class NinoModuleRegistry: ObservableObject {
    static let shared = NinoModuleRegistry()

    private let defaults: UserDefaults
    @Published private(set) var modules: [any NinoModule] = []
    @Published private(set) var selectedID: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func enabledKey(for id: String) -> String {
        "nino.module.enabled.\(id)"
    }

    func register(_ module: any NinoModule) {
        guard !modules.contains(where: { $0.id == module.id }) else { return }
        defaults.register(defaults: [Self.enabledKey(for: module.id): !module.isStub])
        modules.append(module)
    }

    // MARK: Selection (which module the Nino tab shows)

    var selected: (any NinoModule)? {
        modules.first { $0.id == selectedID } ?? modules.first
    }

    func select(_ id: String) {
        guard modules.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    // MARK: Activation state

    func isEnabled(_ id: String) -> Bool {
        defaults.bool(forKey: Self.enabledKey(for: id))
    }

    func setEnabled(_ id: String, enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey(for: id))
        objectWillChange.send()
    }

    var enabledModules: [any NinoModule] {
        modules.filter { isEnabled($0.id) }
    }

    var hasEnabledModules: Bool {
        !enabledModules.isEmpty
    }
}
