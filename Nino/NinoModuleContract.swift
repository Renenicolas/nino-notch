import Foundation
import SwiftUI

/// The module contract, run inside the real app by `--nino-module-self-test`
/// (scripts/test-modules.sh does that after a build).
enum NinoModuleContract {
    static let expectedIDs: Set<String> = ["nino.voice", "nino.search", "nino.screen"]
    static let liveIDs: Set<String> = ["nino.voice", "nino.search", "nino.screen"]

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
        expect(Set(registry.modules.filter { !$0.isStub }.map(\.id)) == liveIDs, "voice, Ask Nino and Screen Control are live")
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

        // Screen Control decision rules (no network: Jev answers are canned).
        expect(NinoScreenControl.looksLikeCommand("open Spotify and play my Liked Songs"), "gate: a command passes")
        expect(!NinoScreenControl.looksLikeCommand("what is the capital of France?"), "gate: a question stays with Ask Nino")
        let jevYes: [String: Any] = [
            "is_command": ["noul": 0.97],
            "action": ["choice": "play_liked_songs", "confidence": 0.91],
            "app": ["choice": "spotify", "confidence": 0.95],
        ]
        if case .steps(let steps, _) = TypeSafeJev.interpret(jevYes) {
            expect(steps == [.init(action: "play_liked_songs", app: "spotify")], "Jev: confident answer becomes a step")
        } else { expect(false, "Jev: confident answer becomes a step") }
        let jevUnsure: [String: Any] = [
            "is_command": ["noul": 0.9],
            "action": ["choice": "play", "confidence": 0.4],
            "app": ["choice": "spotify", "confidence": 0.9],
        ]
        if case .unsure = TypeSafeJev.interpret(jevUnsure) { expect(true, "Jev: low confidence goes to Claude") } else { expect(false, "Jev: low confidence goes to Claude") }
        if case .notCommand = TypeSafeJev.interpret(["is_command": ["noul": 0.1]]) { expect(true, "Jev: not a command goes to Ask Nino") } else { expect(false, "Jev: not a command goes to Ask Nino") }
        let claude = ClaudeCommandParser.decode(Data(#"Sure! {"is_command": true, "steps": [{"action": "open_app", "app": "Spotify"}, {"action": "play_liked_songs"}, {"action": "fly"}]}"#.utf8))
        expect(claude?.map(\.action) == ["open_app", "play_liked_songs"], "Claude: JSON parsed, unknown actions dropped")
        expect(ClaudeCommandParser.decode(Data(#"{"is_command": false, "steps": []}"#.utf8)) == nil, "Claude: not a command")

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

        // One-press Right ⌘: only the second press (or the 2-minute cap) stops it.
        var stops = 0
        let t0 = Date()
        let session = AskListenSession(onFinished: { stops += 1 })
        session.start(now: t0)
        for i in 0..<100 { session.tick(now: t0.addingTimeInterval(Double(i))) }   // 99 s, quiet or not
        expect(stops == 0 && session.active, "listen: never stops on its own before 2 minutes")
        session.tick(now: t0.addingTimeInterval(120))
        expect(stops == 1 && !session.active, "listen: 2-minute safety cap")

        let state = try? JSONDecoder().decode(NinoVoiceState.self, from: Data(sampleEngineState.utf8))
        expect(state != nil, "engine state line decodes")
        expect(state?.isCapturing == true && state?.ask.messages.count == 2, "decoded recording + ask messages")
        expect(state?.setup.isComplete == false, "missing accessibility shows as setup incomplete")

        return (failed, lines)
    }
}
