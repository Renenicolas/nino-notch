import AppKit
import ApplicationServices

/// Screen Control: a spoken or typed command ("open Spotify and play my Liked
/// Songs") becomes real actions on this Mac.
///
/// 1. Decide: Jev (TypeSafe System One model) answers typed Choice/Noul questions
///    in ~100 ms. Anything it is not confident about, or anything that needs free
///    text (Jev does not generate strings), goes to the Claude CLI (`claude -p`).
///    Without a Jev key, a keyword gate keeps plain questions away from Claude.
/// 2. Do: open apps, drive Spotify / Music (AppleScript), system volume, and, for
///    what scripting cannot do, press buttons through Accessibility.
@MainActor
final class NinoScreenControl: ObservableObject {
    static let shared = NinoScreenControl()

    struct Step: Codable, Equatable {
        var action: String      // see Action
        var app: String?
        var query: String?
    }

    enum Action: String, CaseIterable {
        case open_app, focus_app, play_liked_songs, play_song, play, pause, next_track, previous_track,
             volume_up, volume_down, mute, open_url
    }

    struct Entry: Identifiable {
        let id = UUID()
        let text: String
        var decidedBy = ""
        var plan: [Step] = []
        var result = "Thinking…"
        var ok: Bool?
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var busy = false
    /// One line for the notch: "Done: Spotify: playing Liked Songs".
    @Published private(set) var lastResult = ""
    private static var askedForAccessibility = false

    var hasAccessibility: Bool { AXIsProcessTrusted() }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    // MARK: Entry point

    /// Returns true if `text` was a screen command (and was run).
    /// False means "not for me": the caller sends it to Ask Nino instead.
    @discardableResult
    func handle(_ text: String) async -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return false }
        let started = Date()
        busy = true
        defer { busy = false }

        var entry = Entry(text: text)
        let decision = await Self.decide(text)
        guard let decision, !decision.steps.isEmpty else { return false }

        // Clicking/pressing in other apps needs Accessibility; ask the first time a
        // real command runs so the prompt appears when it matters.
        if !AXIsProcessTrusted() && !Self.askedForAccessibility {
            Self.askedForAccessibility = true
            requestAccessibility()
        }

        entry.decidedBy = decision.by
        entry.plan = decision.steps
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(8))

        // Stay where Rene is working: only "switch to X" may change the front app.
        let frontBefore = NSWorkspace.shared.frontmostApplication
        let wantsFront = decision.steps.contains { $0.action == "focus_app" || $0.action == "open_url" }
        var notes: [String] = []
        var allOK = true
        for step in decision.steps {
            let (ok, note) = await Self.run(step)
            notes.append(note)
            allOK = allOK && ok
            if !ok { break }
        }
        if let i = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[i].result = notes.joined(separator: " · ")
            entries[i].ok = allOK
        }
        NSLog("NINO screen: %@ -> %@ [%@] %@", text, decision.steps.map(\.action).joined(separator: ","), decision.by, notes.joined(separator: " | "))
        if !wantsFront, let frontBefore, NSWorkspace.shared.frontmostApplication != frontBefore {
            frontBefore.activate()  // something (an app's own launch) jumped in front: put Rene back
        }
        lastResult = (allOK ? "Done: " : "Couldn't: ") + (notes.last ?? "")
        Self.recordLast(text: text, decision: decision, notes: notes, ok: allOK, seconds: Date().timeIntervalSince(started))
        return true
    }

    /// Last result, for diagnosis: ~/Library/Application Support/com.meetnino.notch/screen-control-last.json
    private static func recordLast(text: String, decision: Decision, notes: [String], ok: Bool, seconds: Double) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.meetnino.notch", isDirectory: true)
        let record: [String: Any] = [
            "at": ISO8601DateFormatter().string(from: Date()), "text": text, "decidedBy": decision.by,
            "steps": decision.steps.map(\.action), "results": notes, "ok": ok,
            "seconds": (seconds * 100).rounded() / 100,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted]) {
            try? data.write(to: dir.appendingPathComponent("screen-control-last.json"))
        }
    }

    // MARK: Decide

    struct Decision {
        let steps: [Step]
        let by: String
    }

    /// Verbs and apps a screen command almost always contains. Only used when Jev
    /// is unavailable, so ordinary questions never wait on a Claude call.
    nonisolated static func looksLikeCommand(_ text: String) -> Bool {
        let t = text.lowercased()
        let pattern = #"\b(open|launch|start|play|pause|resume|stop|skip|next|previous|volume|louder|quieter|mute|unmute|turn (it )?(up|down)|switch to|go to)\b"#
        return t.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated static func decide(_ text: String) async -> Decision? {
        // Common commands never touch a model: plain rules, instant.
        if let steps = QuickCommand.parse(text) {
            return Decision(steps: steps, by: "instant")
        }
        if let key = await TypeSafeJev.apiKey() {
            switch await TypeSafeJev.classify(text, apiKey: key) {
            case .notCommand:
                return nil
            case .steps(let steps, let confidence):
                return Decision(steps: steps, by: String(format: "Jev %.0f%%", confidence * 100))
            case .unsure, .failed:
                break // Claude takes it
            }
        } else if !looksLikeCommand(text) {
            return nil
        }
        guard let steps = await ClaudeCommandParser.parse(text) else { return nil }
        return steps.isEmpty ? nil : Decision(steps: steps, by: "Claude")
    }

    // MARK: Do

    nonisolated static func run(_ step: Step) async -> (Bool, String) {
        guard let action = Action(rawValue: step.action) else { return (false, "can't do \(step.action) yet") }
        let app = AppTarget(step.app)
        switch action {
        case .open_app:
            return await AppTarget.open(step.app ?? "", inFront: false) ? (true, "opened \(step.app ?? "") in the background") : (false, "couldn't find \(step.app ?? "that app")")
        case .focus_app:
            return await AppTarget.open(step.app ?? "", inFront: true) ? (true, "switched to \(step.app ?? "")") : (false, "couldn't find \(step.app ?? "that app")")
        case .play_song:
            guard let query = step.query, !query.isEmpty else { return (false, "which song?") }
            return await SpotifyControl.play(search: query)
        case .open_url:
            // Web links only: a misheard command must not open file:// or app URL schemes.
            guard let s = step.query, let url = URL(string: s.contains("://") ? s : "https://\(s)"),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return (false, "only web links") }
            return NSWorkspace.shared.open(url) ? (true, "opened \(url.host ?? s)") : (false, "couldn't open link")
        case .play_liked_songs:
            return await SpotifyControl.playLikedSongs()
        case .play, .pause, .next_track, .previous_track:
            return await app.player(action)
        case .volume_up:
            return AppleScript.run("set volume output volume ((output volume of (get volume settings)) + 12)") != nil ? (true, "volume up") : (false, "volume failed")
        case .volume_down:
            return AppleScript.run("set volume output volume ((output volume of (get volume settings)) - 12)") != nil ? (true, "volume down") : (false, "volume failed")
        case .mute:
            return AppleScript.run("set volume output muted (not output muted of (get volume settings))") != nil ? (true, "toggled mute") : (false, "mute failed")
        }
    }
}

// MARK: - Apps

struct AppTarget {
    let bundleID: String?

    static let known: [String: String] = [
        "spotify": "com.spotify.client", "music": "com.apple.Music", "apple music": "com.apple.Music",
        "apple_music": "com.apple.Music", "safari": "com.apple.Safari", "chrome": "com.google.Chrome",
        "google chrome": "com.google.Chrome", "finder": "com.apple.finder", "messages": "com.apple.MobileSMS",
        "notes": "com.apple.Notes", "calendar": "com.apple.iCal", "mail": "com.apple.mail",
        "terminal": "com.apple.Terminal", "slack": "com.tinyspeck.slackmacgap",
    ]

    init(_ name: String?) {
        bundleID = name.flatMap { Self.known[$0.lowercased()] }
    }

    /// Open by known name, then by any installed app's name. `inFront: false`
    /// launches it without taking the screen away from the app Rene is in.
    static func open(_ name: String, inFront: Bool = false) async -> Bool {
        let workspace = NSWorkspace.shared
        let config = NSWorkspace.OpenConfiguration()
        config.activates = inFront
        if let id = known[name.lowercased()], let url = workspace.urlForApplication(withBundleIdentifier: id) {
            return (try? await workspace.openApplication(at: url, configuration: config)) != nil
        }
        for dir in ["/Applications", "/System/Applications", "\(NSHomeDirectory())/Applications"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).app")
            if FileManager.default.fileExists(atPath: url.path) {
                return (try? await workspace.openApplication(at: url, configuration: config)) != nil
            }
        }
        return false
    }

    /// play / pause / next / previous on Spotify or Music (whichever is asked, else whichever runs).
    func player(_ action: NinoScreenControl.Action) async -> (Bool, String) {
        let running = { (id: String) in !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty }
        let target = bundleID ?? (running("com.spotify.client") ? "com.spotify.client" : "com.apple.Music")
        let name = target == "com.spotify.client" ? "Spotify" : "Music"
        let verb: String, said: String
        switch action {
        case .play: (verb, said) = ("play", "playing \(name)")
        case .pause: (verb, said) = ("pause", "paused \(name)")
        case .next_track: (verb, said) = ("next track", "next song")
        case .previous_track: (verb, said) = ("previous track", "previous song")
        default: return (false, "not a player action")
        }
        return AppleScript.run("tell application \"\(name)\" to \(verb)") != nil ? (true, said) : (false, "\(name) didn't respond")
    }
}

// MARK: - Spotify

enum SpotifyControl {
    static let bundleID = "com.spotify.client"

    /// The signed-in Spotify username, from Spotify's own prefs file.
    static var username: String? {
        let prefs = "\(NSHomeDirectory())/Library/Application Support/Spotify/prefs"
        guard let text = try? String(contentsOfFile: prefs, encoding: .utf8) else { return nil }
        for key in ["autologin.canonical_username", "autologin.username"] {
            if let line = text.split(separator: "\n").first(where: { $0.hasPrefix(key + "=") }) {
                let name = line.split(separator: "=", maxSplits: 1).last.map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
                // Spotify usernames are short and plain; anything else is ignored.
                return name.flatMap { $0.range(of: "^[A-Za-z0-9._-]{1,64}$", options: .regularExpression) != nil ? $0 : nil }
            }
        }
        return nil
    }

    static func playLikedSongs() async -> (Bool, String) {
        guard await ensureRunning() else { return (false, "Spotify didn't start") }

        // 1. Scripting: play the Liked Songs collection directly.
        var uris = ["spotify:collection:tracks"]
        if let user = username { uris.insert("spotify:user:\(user):collection", at: 0) }
        for uri in uris {
            // The URI goes in as an argument, never spliced into script source.
            guard AppleScript.run("on run argv\ntell application \"Spotify\" to play track (item 1 of argv)\nend run", args: [uri]) != nil else { continue }
            if await isPlaying() { return (true, "playing Liked Songs") }
            // Spotify 1.3 can load the collection paused: press play once.
            AppleScript.run("tell application \"Spotify\" to play")
            if await isPlaying() { return (true, "playing Liked Songs") }
        }

        // 2. Accessibility: open Liked Songs and press Spotify's own Play button.
        guard AXIsProcessTrusted() else {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            return (false, "needs Accessibility for Nino Notch (prompt shown)")
        }
        let quiet = NSWorkspace.OpenConfiguration()
        quiet.activates = false
        _ = try? await NSWorkspace.shared.open(URL(string: "spotify:collection:tracks")!, configuration: quiet)
        try? await Task.sleep(for: .seconds(3))
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier else {
            return (false, "Spotify not running")
        }
        if AXPress.firstButton(inApp: pid, named: ["Play", "Play Liked Songs"]), await isPlaying() {
            return (true, "playing Liked Songs")
        }
        return (false, "couldn't start Liked Songs")
    }

    /// Play a song / artist / album / playlist by name, without bringing Spotify forward.
    /// Spotify's scripting can play any Spotify link but cannot search, so the link
    /// is found first (web search on Haiku, the subscription), then played.
    static func play(search query: String) async -> (Bool, String) {
        guard await ensureRunning() else { return (false, "Spotify didn't start") }
        guard let uri = await SpotifyLookup.find(query) else { return (false, "couldn't find \(query) on Spotify") }
        guard AppleScript.run("on run argv\ntell application \"Spotify\" to play track (item 1 of argv)\nend run", args: [uri]) != nil else {
            return (false, "Spotify didn't respond")
        }
        if !(await isPlaying()) { AppleScript.run("tell application \"Spotify\" to play") }
        guard await isPlaying() else { return (false, "found it, but it didn't start") }
        let name = AppleScript.run("tell application \"Spotify\" to get name of current track") ?? query
        let artist = AppleScript.run("tell application \"Spotify\" to get artist of current track") ?? ""
        return (true, "playing \(name)" + (artist.isEmpty ? "" : " by \(artist)"))
    }

    static func ensureRunning() async -> Bool {
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            guard await AppTarget.open("spotify") else { return false }
        }
        for _ in 0..<40 {  // up to ~10 s for a cold start
            if AppleScript.run("tell application \"Spotify\" to get player state") != nil { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    static func isPlaying() async -> Bool {
        for _ in 0..<12 {
            if AppleScript.run("tell application \"Spotify\" to get player state as string") == "playing" { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }
}

// MARK: - Accessibility

enum AXPress {
    /// Breadth-first search of an app's windows for a button by title/description; press it.
    static func firstButton(inApp pid: pid_t, named names: [String]) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        // Spotify is Chromium-based: its accessibility tree stays empty until an
        // assistive app asks for it with AXManualAccessibility.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        usleep(800_000)
        var queue: [AXUIElement] = [app]
        var visited = 0
        while !queue.isEmpty, visited < 4000 {
            let element = queue.removeFirst()
            visited += 1
            if string(element, kAXRoleAttribute) == kAXButtonRole as String {
                let label = string(element, kAXDescriptionAttribute) ?? string(element, kAXTitleAttribute) ?? ""
                if names.contains(where: { label.caseInsensitiveCompare($0) == .orderedSame }) {
                    return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
                }
            }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let list = children as? [AXUIElement] {
                queue.append(contentsOf: list)
            }
        }
        return false
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}

// MARK: - AppleScript

enum AppleScript {
    /// Runs through /usr/bin/osascript so a hung target app never blocks the notch.
    /// macOS attributes the Apple Event to Nino Notch (the responsible app).
    @discardableResult
    /// `args` reach the script as `argv` (use `on run argv`), so outside values are
    /// data, never code.
    static func run(_ source: String, args: [String] = [], timeout: TimeInterval = 8) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source] + args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { usleep(20_000) }
        if process.isRunning { process.terminate(); return nil }
        guard process.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

// MARK: - Jev (TypeSafe)

enum TypeSafeJev {
    static let keychainService = "com.meetnino.notch.typesafe"

    enum Result {
        case notCommand
        case steps([NinoScreenControl.Step], confidence: Double)
        case unsure
        case failed
    }

    /// TYPESAFE_API_KEY from the environment, else the login keychain item
    /// `com.meetnino.notch.typesafe` / `api-key`. Read through /usr/bin/security
    /// so a rebuilt Nino Notch never triggers a keychain password prompt.
    static func apiKey() async -> String? {
        if let env = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !env.isEmpty { return env }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-a", "api-key", "-w"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let key = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return key?.isEmpty == false ? key : nil
    }

    /// Only fixed-shape commands are decided here; anything with a free-text
    /// target (a song name, a URL) goes to Claude.
    static let simpleActions: [String: String] = [
        "play_liked_songs": "Play the user's Liked Songs (saved/favorite tracks) in Spotify",
        "open_app": "Open or switch to an app, nothing else",
        "play": "Resume or start music playback",
        "pause": "Pause or stop music playback",
        "next_track": "Skip to the next song",
        "previous_track": "Go back to the previous song",
        "volume_up": "Make the Mac louder",
        "volume_down": "Make the Mac quieter",
        "mute": "Mute or unmute the Mac",
        "other": "Anything else, several different steps, or a specific song/playlist/website",
    ]

    static let apps: [String: String] = [
        "spotify": "Spotify", "music": "Apple Music", "safari": "Safari", "chrome": "Google Chrome",
        "finder": "Finder", "messages": "Messages", "notes": "Notes", "calendar": "Calendar",
        "mail": "Mail", "slack": "Slack", "none": "No specific app, or the whole Mac (like volume)",
        "other": "Some other app",
    ]

    static func classify(_ text: String, apiKey: String) async -> Result {
        let body: [String: Any] = [
            "state": text,
            "model": "jev-latest",
            "questions": [
                "is_command": ["type": "noul",
                               "instructions": "This asks the computer to DO something on the Mac right now (open an app, control music, change volume), rather than asking a question or asking for information"],
                "action": ["type": "choice", "instructions": "Which single action does this ask for", "criteria": simpleActions],
                "app": ["type": "choice", "instructions": "Which app is this about", "criteria": apps],
            ],
        ]
        var request = URLRequest(url: URL(string: "https://api.typesafe.ai/v1/systemone")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answers = json["answers"] as? [String: Any] else { return .failed }
        return interpret(answers)
    }

    /// Pure decision rule over Jev's answers (unit-checked in NinoModuleContract).
    static func interpret(_ answers: [String: Any]) -> Result {
        let isCommand = (answers["is_command"] as? [String: Any])?["noul"] as? Double ?? 0
        guard isCommand >= 0.5 else { return .notCommand }
        guard let action = answers["action"] as? [String: Any], let app = answers["app"] as? [String: Any],
              let a = action["choice"] as? String, let appName = app["choice"] as? String else { return .unsure }
        let confidence = min(action["confidence"] as? Double ?? 0, app["confidence"] as? Double ?? 0)
        guard confidence >= 0.75, a != "other", appName != "other" else { return .unsure }
        if a == "open_app" && appName == "none" { return .unsure }
        return .steps([NinoScreenControl.Step(action: a, app: appName == "none" ? nil : appName)], confidence: confidence)
    }
}

// MARK: - Claude fallback

enum ClaudeCommandParser {
    static let candidates = ["/usr/local/bin/claude", "/opt/homebrew/bin/claude", "\(NSHomeDirectory())/.local/bin/claude"]

    static let instructions = """
    You turn one spoken command for a Mac into JSON. Reply with JSON only, no prose, no code fence.
    Shape: {"is_command": true|false, "steps": [{"action": "...", "app": "...", "query": "..."}]}
    Allowed actions: open_app, focus_app, play_liked_songs, play_song, play, pause, next_track, previous_track, volume_up, volume_down, mute, open_url.
    - is_command is false for questions, chat, or anything that is not a request to do something on the Mac now.
    - "play my liked songs" / "my favorites" / "saved songs" -> play_liked_songs (it opens Spotify itself).
    - open_app needs "app" (the app's name as installed, e.g. "Spotify", "Safari"); it starts the app in the background.
    - focus_app is for "switch to / show me / bring up X": it brings the app to the front. Needs "app".
    - play_song needs "query" = what to play on Spotify: a song (with the artist if said), an artist, an album or a playlist, e.g. "Blinding Lights The Weeknd".
    - open_url needs "query" = the URL.
    - play/pause/next_track/previous_track may set "app" to "spotify" or "music".
    - If it asks for something none of these actions can do, return is_command true and steps [].
    Command:
    """

    static func parse(_ text: String) async -> [NinoScreenControl.Step]? {
        guard let claude = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: claude)
                // haiku: a fixed-schema parse, and speed matters; the words go in on stdin.
                // Haiku (fastest on the subscription). No tools, no user settings (hooks,
                // plugins), no MCP servers, no skills, no saved session, empty folder:
                // a parse must never read files, and it starts ~2 s faster this way.
                // (--bare would be faster still but needs a paid API key.)
                process.arguments = ["-p", "--model", "haiku", "--output-format", "text",
                                     "--setting-sources", "", "--strict-mcp-config", "--tools", "",
                                     "--disable-slash-commands", "--no-session-persistence",
                                     "--system-prompt", instructions]
                let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("nino-screen-claude", isDirectory: true)
                try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                process.currentDirectoryURL = scratch
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
                process.environment = env
                let input = Pipe(), output = Pipe()
                process.standardInput = input
                process.standardOutput = output
                process.standardError = Pipe()
                guard (try? process.run()) != nil else { continuation.resume(returning: nil); return }
                input.fileHandleForWriting.write(Data(text.utf8))
                try? input.fileHandleForWriting.close()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: decode(data))
            }
        }
    }

    static func decode(_ data: Data) -> [NinoScreenControl.Step]? {
        guard var text = String(data: data, encoding: .utf8) else { return nil }
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            text = String(text[start...end])
        }
        struct Reply: Decodable { let is_command: Bool; let steps: [NinoScreenControl.Step] }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: Data(text.utf8)), reply.is_command else { return nil }
        return reply.steps.filter { NinoScreenControl.Action(rawValue: $0.action) != nil }
    }
}

// MARK: - Instant rules (no AI)

/// The everyday commands, matched by plain rules so they run instantly with no
/// model call. Every clause ("open Spotify", "and play my Liked Songs") must
/// match, or the whole sentence goes to the AI path instead.
enum QuickCommand {
    static func parse(_ text: String) -> [NinoScreenControl.Step]? {
        var t = text.lowercased()
        t = t.replacingOccurrences(of: #"[^a-z0-9 .'+-]"#, with: " ", options: .regularExpression)
        for filler in [#"^(hey |ok |okay )?nino,? "#, #"\b(please|for me|can you|could you|would you|will you)\b"#] {
            t = t.replacingOccurrences(of: filler, with: " ", options: .regularExpression)
        }
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        guard !t.isEmpty else { return nil }

        let clauses = t.replacingOccurrences(of: #",? and then |,? and |,? then |, "#, with: "|", options: .regularExpression)
            .split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var steps: [NinoScreenControl.Step] = []
        for clause in clauses {
            guard let step = one(clause) else { return nil }
            steps.append(step)
        }
        // "open Spotify and play my Liked Songs": Liked Songs opens Spotify itself.
        if steps.contains(where: { $0.action == "play_liked_songs" }) {
            steps.removeAll { $0.action == "open_app" && $0.app?.lowercased() == "spotify" }
        }
        return steps.isEmpty ? nil : steps
    }

    private static func matches(_ s: String, _ pattern: String) -> Bool {
        s.range(of: "^(" + pattern + ")$", options: .regularExpression) != nil
    }

    static func one(_ c: String) -> NinoScreenControl.Step? {
        // "the/my/this" only counts with a noun after it: a half-heard "play my" is not "play".
        let music = #"( (the |my |this |that )?(music|song|track|tune|spotify|playback|it))?( on spotify| in spotify)?"#
        if matches(c, #"(play|put on|start|shuffle)?( my)? (liked|saved|favou?rite|favou?rited|like)( songs| tracks| music| playlist)?( on spotify| in spotify)?"#) {
            return .init(action: "play_liked_songs", app: "spotify")
        }
        if matches(c, "(play|resume|unpause|continue)" + music) { return .init(action: "play", app: app(in: c)) }
        if matches(c, "(pause|stop)" + music) { return .init(action: "pause", app: app(in: c)) }
        if matches(c, #"(next|skip)( this| the)?( song| track| one)?|(play |go to )?(the )?next( song| track| one)?|skip it"#) {
            return .init(action: "next_track", app: app(in: c))
        }
        if matches(c, #"(previous|last|go back|back)( song| track| one)?|(play |go to )?(the )?previous( song| track| one)?|play (that|the last) (song|track) again"#) {
            return .init(action: "previous_track", app: app(in: c))
        }
        if matches(c, #"(turn|crank) (it|the (volume|music|sound)) up|turn up( the)?( volume| music| sound)?|volume up|louder|(make it |a bit |little )?louder|raise( the)? volume"#) {
            return .init(action: "volume_up")
        }
        if matches(c, #"(turn) (it|the (volume|music|sound)) down|turn down( the)?( volume| music| sound)?|volume down|(make it |a bit |little )?(quieter|softer)|lower( the)? volume"#) {
            return .init(action: "volume_down")
        }
        if matches(c, #"(mute|unmute)( the)?( sound| audio| mac| computer| music| volume)?"#) { return .init(action: "mute") }
        if let r = c.range(of: #"^(open|launch|start|switch to|bring up|pull up|show me|show|go to)( the)? (.+?)( app)?$"#, options: .regularExpression) {
            let clause = String(c[r])
            let front = clause.range(of: #"^(switch to|bring up|pull up|show me|show|go to) "#, options: .regularExpression) != nil
            var name = clause.replacingOccurrences(of: #"^(open|launch|start|switch to|bring up|pull up|show me|show|go to)( the)? "#, with: "", options: .regularExpression)
            name = name.replacingOccurrences(of: #" app$"#, with: "", options: .regularExpression)
            if let installed = installedApp(named: name) { return .init(action: front ? "focus_app" : "open_app", app: installed) }
        }
        // "play Blinding Lights by The Weeknd", "put on Drake", "play the album Rumours on Spotify"
        if let r = c.range(of: #"^(play|put on|queue up|listen to)( the song| the track| the album| the playlist| some| me)? (.+?)( on spotify| in spotify)?$"#, options: .regularExpression) {
            var query = String(c[r])
            query = query.replacingOccurrences(of: #"^(play|put on|queue up|listen to)( the song| the track| the album| the playlist| some| me)? "#, with: "", options: .regularExpression)
            query = query.replacingOccurrences(of: #" (on|in) spotify$"#, with: "", options: .regularExpression)
            let vague: Set<String> = ["music", "something", "anything", "a song", "songs", "it", "my", "the", "my music", "some music", "something good"]
            if query.count >= 2, !vague.contains(query) { return .init(action: "play_song", app: "spotify", query: query) }
        }
        return nil
    }

    private static func app(in c: String) -> String? {
        c.contains("spotify") ? "spotify" : (c.contains("apple music") || c.contains(" music app") ? "music" : nil)
    }

    /// The real app name for "slack" -> "Slack", only if it is installed.
    static func installedApp(named raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.count < 40 else { return nil }
        if AppTarget.known[name] != nil { return name }
        for dir in ["/Applications", "/System/Applications", "/System/Applications/Utilities", "\(NSHomeDirectory())/Applications"] {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            if let hit = items.first(where: { $0.lowercased() == name + ".app" }) {
                return String(hit.dropLast(4))
            }
        }
        return nil
    }
}

// MARK: - Spotify link lookup

/// Finds the Spotify link for a spoken request ("Blinding Lights by The Weeknd").
/// Uses Haiku with web search on the existing subscription; no Spotify developer
/// app needed. Returns a Spotify URI like `spotify:track:0VjIjW4GlUZAMYd2vXMi3b`.
enum SpotifyLookup {
    static func find(_ query: String) async -> String? {
        guard let claude = ClaudeCommandParser.candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        let prompt = "Find the Spotify link for this request: \"\(query)\". Prefer the original studio track (or the artist / album / playlist if that is what was asked). Reply with ONLY one open.spotify.com URL."
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: claude)
                process.arguments = ["-p", "--model", "haiku", "--output-format", "text",
                                     "--setting-sources", "", "--strict-mcp-config",
                                     "--tools", "WebSearch", "--allowedTools", "WebSearch",
                                     "--disable-slash-commands", "--no-session-persistence"]
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
                process.environment = env
                let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("nino-spotify-lookup", isDirectory: true)
                try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                process.currentDirectoryURL = scratch
                let input = Pipe(), output = Pipe()
                process.standardInput = input
                process.standardOutput = output
                process.standardError = Pipe()
                guard (try? process.run()) != nil else { continuation.resume(returning: nil); return }
                input.fileHandleForWriting.write(Data(prompt.utf8))
                try? input.fileHandleForWriting.close()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: uri(from: String(data: data, encoding: .utf8) ?? ""))
            }
        }
    }

    /// First Spotify track/album/playlist/artist link in `text`, as a `spotify:` URI.
    static func uri(from text: String) -> String? {
        let pattern = #"(?:open\.spotify\.com/(?:intl-[a-z]{2}/)?|spotify:)(track|album|playlist|artist)[/:]([A-Za-z0-9]{22})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let kind = Range(m.range(at: 1), in: text), let id = Range(m.range(at: 2), in: text) else { return nil }
        return "spotify:\(text[kind]):\(text[id])"
    }
}

