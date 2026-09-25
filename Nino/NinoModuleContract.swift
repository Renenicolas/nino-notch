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

        // Instant rules: everyday commands never touch a model.
        func acts(_ t: String) -> [String]? { QuickCommand.parse(t)?.map(\.action) }
        expect(acts("pause the music") == ["pause"], "instant: pause the music")
        expect(acts("Play") == ["play"], "instant: play")
        expect(acts("skip this song") == ["next_track"], "instant: skip this song")
        expect(acts("next track please") == ["next_track"], "instant: next track please")
        expect(acts("go back") == ["previous_track"], "instant: go back")
        expect(acts("turn it up") == ["volume_up"], "instant: turn it up")
        expect(acts("make it quieter") == ["volume_down"], "instant: make it quieter")
        expect(acts("mute") == ["mute"], "instant: mute")
        expect(acts("open Safari") == ["open_app"], "instant: open Safari (in the background)")
        expect(acts("switch to Safari") == ["focus_app"], "instant: switch to Safari (brings it forward)")
        expect(!NinoScreenControl.asksForFocus("open Slack") && !NinoScreenControl.asksForFocus("play Blinding Lights") && !NinoScreenControl.asksForFocus("open espn.com"), "focus: no 'take me there' words, nothing comes forward")
        expect(NinoScreenControl.asksForFocus("switch to Slack") && NinoScreenControl.asksForFocus("show me espn.com") && NinoScreenControl.asksForFocus("take me to Spotify") && NinoScreenControl.asksForFocus("bring up Safari"), "focus: only Rene's words bring something forward")
        expect(QuickCommand.parse("play Blinding Lights by The Weeknd")?.first?.query == "blinding lights by the weeknd", "instant: play a specific song")
        expect(acts("put on Drake") == ["play_song"], "instant: put on an artist")
        expect(acts("play some music") == ["play"] || acts("play some music") == nil, "instant: 'play some music' is not a song search")
        expect(SpotifyLookup.uri(from: "Here: https://open.spotify.com/track/0VjIjW4GlUZAMYd2vXMi3b?si=x") == "spotify:track:0VjIjW4GlUZAMYd2vXMi3b", "lookup: Spotify track link becomes a URI")
        expect(SpotifyLookup.uri(from: "https://open.spotify.com/intl-de/artist/1Xyo4u8uXC1ZmMpatF05PJ") == "spotify:artist:1Xyo4u8uXC1ZmMpatF05PJ", "lookup: artist link, localized")
        expect(SpotifyLookup.uri(from: "no link here") == nil, "lookup: no link, no guess")
        let drake: [String: Any] = ["artists": ["items": [["name": "Drake", "uri": "spotify:artist:3TVXtAsR1Inumwj472S9r4"]]],
                                    "tracks": ["items": [["name": "God's Plan", "uri": "spotify:track:6DCZcSspjsKoFjzjrWoCdn"]]]]
        expect(SpotifyWebSearch.pick(drake, query: "drake") == "spotify:artist:3TVXtAsR1Inumwj472S9r4", "search: an artist name plays the artist")
        expect(SpotifyWebSearch.pick(drake, query: "gods plan drake") == "spotify:track:6DCZcSspjsKoFjzjrWoCdn", "search: a song plays the song")
        expect(QuickCommand.parse("play the album Rumours")?.first?.query == "album rumours", "instant: album hint kept for search")
        expect(acts("Open Spotify and play my Liked Songs.") == ["play_liked_songs"], "instant: open Spotify and play my Liked Songs")
        expect(acts("Hey Nino, play my liked songs") == ["play_liked_songs"], "instant: hey Nino, play my liked songs")
        expect(acts("open Notes and turn it down") == ["open_app", "volume_down"], "instant: two clauses")
        expect(acts("open Safari and go to espn.com") == nil, "instant: unusual command goes to the AI")
        expect(acts("what should I play tonight?") == nil, "instant: a question is not a command")
        expect(acts("open the pod bay doors") == nil, "instant: unknown app is not guessed")
        expect(acts("Open Spotify and play my") == nil, "instant: a half-heard command is not guessed")
        expect(acts("play the music") == ["play"] && acts("pause my music") == ["pause"], "instant: the/my with a noun still counts")

        // Quick answers: time here, short questions to Haiku, tasks to the full agent.
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let noonUTC = cal.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 12, minute: 0))!
        expect(QuickAnswer.route("what time is it in Beirut", now: noonUTC) == .local("It's 2:00 PM in Beirut (Thursday)."), "quick: Beirut time computed locally")
        expect(QuickAnswer.route("What's the time in Tokyo?", now: noonUTC) == .local("It's 9:00 PM in Tokyo (Thursday)."), "quick: Tokyo time")
        expect(QuickAnswer.route("what's the weather in Beirut?") == .fast, "quick: weather goes to Haiku")
        expect(QuickAnswer.route("who wrote Dune?") == .fast, "quick: a fact goes to Haiku")
        expect(QuickAnswer.route("email Marco the Kinnect deck") == .agent, "quick: a task goes to the full agent")
        expect(QuickAnswer.route("what's on my calendar tomorrow?") == .agent, "quick: my calendar needs the full agent")

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
