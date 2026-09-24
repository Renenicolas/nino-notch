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
        case open_app, play_liked_songs, play, pause, next_track, previous_track,
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
        busy = true
        defer { busy = false }

        var entry = Entry(text: text)
        let decision = await Self.decide(text)
        guard let decision, !decision.steps.isEmpty else { return false }

        entry.decidedBy = decision.by
        entry.plan = decision.steps
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(8))

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
        return true
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
            return await AppTarget.open(step.app ?? "") ? (true, "opened \(step.app ?? "")") : (false, "couldn't find \(step.app ?? "that app")")
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

    /// Open by known name, then by any installed app's name.
    static func open(_ name: String) async -> Bool {
        let workspace = NSWorkspace.shared
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
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
        let verb: String
        switch action {
        case .play: verb = "play"
        case .pause: verb = "pause"
        case .next_track: verb = "next track"
        case .previous_track: verb = "previous track"
        default: return (false, "not a player action")
        }
        return AppleScript.run("tell application \"\(name)\" to \(verb)") != nil ? (true, "\(name): \(verb)") : (false, "\(name) didn't respond")
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
            if AppleScript.run("on run argv\ntell application \"Spotify\" to play track (item 1 of argv)\nend run", args: [uri]) != nil,
               await isPlaying() {
                return (true, "Spotify: playing Liked Songs")
            }
        }

        // 2. Accessibility: open Liked Songs and press Spotify's own Play button.
        guard AXIsProcessTrusted() else {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            return (false, "needs Accessibility for Nino Notch (prompt shown)")
        }
        NSWorkspace.shared.open(URL(string: "spotify:collection:tracks")!)
        try? await Task.sleep(for: .seconds(2.5))
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier else {
            return (false, "Spotify not running")
        }
        if AXPress.firstButton(inApp: pid, named: ["Play", "Play Liked Songs"]), await isPlaying() {
            return (true, "Spotify: playing Liked Songs (pressed Play)")
        }
        return (false, "couldn't start Liked Songs")
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
    Allowed actions: open_app, play_liked_songs, play, pause, next_track, previous_track, volume_up, volume_down, mute, open_url.
    - is_command is false for questions, chat, or anything that is not a request to do something on the Mac now.
    - "play my liked songs" / "my favorites" / "saved songs" -> play_liked_songs (it opens Spotify itself).
    - open_app needs "app" (the app's name as installed, e.g. "Spotify", "Safari"). open_url needs "query" = the URL.
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
                process.arguments = ["-p", "--model", "haiku", "--output-format", "text"]
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
                process.environment = env
                let input = Pipe(), output = Pipe()
                process.standardInput = input
                process.standardOutput = output
                process.standardError = Pipe()
                guard (try? process.run()) != nil else { continuation.resume(returning: nil); return }
                input.fileHandleForWriting.write(Data((instructions + " " + text).utf8))
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
