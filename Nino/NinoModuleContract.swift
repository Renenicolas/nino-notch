import Foundation
import SwiftUI

/// The module contract, run inside the real app by `--nino-module-self-test`
/// (scripts/test-modules.sh does that after a build).
enum NinoModuleContract {
    static let expectedIDs: Set<String> = ["nino.voice", "nino.search", "nino.screen"]
    static let liveIDs: Set<String> = ["nino.voice", "nino.search"]

    /// One real state line as the Nino Voice engine sends it (NinoNotchBridge).
    /// If the engine's shape changes, this decode fails here first.
    static let sampleEngineState = #"{"type":"state","recording":"recording","panelVisible":true,"hostedInNotch":true,"partial":"hello","lastText":"","modeName":"Dictation","modelName":"Parakeet V3","recordKey":"Right ⌥","askKey":"Right ⌘","pasteKey":"Fn","ask":{"visible":true,"busy":false,"canSend":true,"status":"Done","failed":null,"draft":"","messages":[{"id":"1","role":"user","text":"hi"},{"id":"2","role":"assistant","text":"**yo**"}]},"setup":{"onboarded":true,"microphone":true,"accessibility":false}}"#

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
        expect(Set(registry.modules.map(\.id)) == expectedIDs, "stable ids: voice, search, screen (no vellum)")
        expect(Set(registry.modules.filter { !$0.isStub }.map(\.id)) == liveIDs, "voice and Ask Nino are live, screen is a stub")
        expect(
            registry.modules.allSatisfy { !$0.displayName.isEmpty && !$0.summary.isEmpty && !$0.systemImage.isEmpty },
            "names, summaries and icons are non-empty"
        )

        expect(registry.selected?.id == "nino.voice", "first module is selected by default")
        registry.select("nino.search")
        expect(registry.selected?.id == "nino.search", "select switches the shown module")
        registry.select("nino.vellum")
        expect(registry.selected?.id == "nino.search", "vellum id is unknown now and ignored")

        expect(Set(registry.enabledModules.map(\.id)) == liveIDs, "live modules default on, stubs default off")
        registry.setEnabled("nino.voice", enabled: false)
        expect(!registry.isEnabled("nino.voice"), "voice can be switched off")
        registry.setEnabled("nino.voice", enabled: true)
        expect(registry.isEnabled("nino.voice"), "and back on")

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
        expect(!registry.isEnabled("nino.test.extra"), "new stub modules are off until enabled")
        registry.register(Extra())
        expect(registry.modules.count == expectedIDs.count + 1, "duplicate id is ignored")

        let state = try? JSONDecoder().decode(NinoVoiceState.self, from: Data(sampleEngineState.utf8))
        expect(state != nil, "engine state line decodes")
        expect(state?.isCapturing == true && state?.ask.messages.count == 2, "decoded recording + ask messages")
        expect(state?.setup.isComplete == false, "missing accessibility shows as setup incomplete")

        return (failed, lines)
    }
}
