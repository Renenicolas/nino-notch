import Foundation

/// The only file you edit to add a real module later.
///
/// Append one line to `all`. The shell already reads this list.
enum ModuleCatalog {
    static var all: [any NinoModule] {
        [
            NinoVoiceModule(),
            VellumAssistantModule(),
            AISearchModule(),
            ScreenControlModule(),
        ]
    }

    @MainActor
    static func install(into registry: NinoModuleRegistry) {
        for module in all {
            registry.register(module)
        }
    }
}
