import Foundation
import SwiftUI

/// Shared checks for the module contract.
/// Used by `NinoTests` and by `--nino-module-self-test`.
/// Keep this the single list so the two runners cannot drift.
enum NinoModuleContract {
    static let expectedIDs: Set<String> = ["nino.voice", "nino.vellum", "nino.search", "nino.screen"]

    @MainActor
    static func run() -> (failed: Int, lines: [String]) {
        var failed = 0
        var lines: [String] = []

        func expect(_ condition: Bool, _ message: String) {
            if condition {
                lines.append("ok  \(message)")
            } else {
                failed += 1
                lines.append("FAIL  \(message)")
            }
        }

        let suiteName = "nino.notch.module-contract"
        guard let suite = UserDefaults(suiteName: suiteName) else {
            return (1, ["FAIL  could not open isolated defaults suite"])
        }
        suite.removePersistentDomain(forName: suiteName)

        let registry = NinoModuleRegistry(defaults: suite)
        ModuleCatalog.install(into: registry)

        expect(registry.modules.count == expectedIDs.count, "catalog installs \(expectedIDs.count) modules")
        expect(Set(registry.modules.map(\.id)) == expectedIDs, "stable ids match the stubs")
        expect(registry.modules.allSatisfy(\.isStub), "every catalog module is a stub")
        expect(
            registry.modules.allSatisfy { !$0.displayName.isEmpty && !$0.summary.isEmpty && !$0.systemImage.isEmpty },
            "names, summaries and icons are non-empty"
        )

        expect(registry.selected?.id == "nino.voice", "first module is selected by default")
        registry.select("nino.search")
        expect(registry.selected?.id == "nino.search", "select switches the shown module")
        registry.select("nino.nope")
        expect(registry.selected?.id == "nino.search", "selecting an unknown id is ignored")

        expect(registry.enabledModules.isEmpty, "all modules off by default")
        registry.setEnabled("nino.voice", enabled: true)
        expect(registry.isEnabled("nino.voice"), "enable flip sticks")
        expect(registry.enabledModules.map(\.id) == ["nino.voice"], "only the flipped module is enabled")
        registry.setEnabled("nino.voice", enabled: false)
        expect(!registry.hasEnabledModules, "disable flip sticks")

        struct Extra: NinoModule {
            let id = "nino.test.extra"
            let displayName = "Extra"
            let summary = "Test only"
            let systemImage = "plus"
            let isStub = true
            var panel: AnyView { AnyView(Text("extra")) }
        }
        registry.register(Extra())
        expect(registry.modules.count == expectedIDs.count + 1, "registering a new module needs no core edit")
        expect(!registry.isEnabled("nino.test.extra"), "new modules are off until enabled")
        registry.register(Extra())
        expect(registry.modules.count == expectedIDs.count + 1, "duplicate id is ignored")

        return (failed, lines)
    }
}
