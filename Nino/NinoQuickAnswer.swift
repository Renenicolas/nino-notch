import Foundation

/// Fast answers for Ask Nino, so quick questions do not wait on the full Nino
/// agent (OpenClaw). Nothing here stays running: each answer is one short-lived
/// process, or no process at all.
///
/// - Time in a city: computed on this Mac from the time-zone database. Instant.
/// - Short questions (facts, weather): Claude CLI on Haiku, streamed, with web search.
/// - Anything that asks Nino to DO something: the full agent, as before.
enum QuickAnswer {
    enum Route: Equatable {
        case local(String)       // answered right here
        case fast                // Haiku, streamed
        case agent               // full Nino agent (OpenClaw)
    }

    static func route(_ text: String, now: Date = Date()) -> Route {
        let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let answer = timeAnswer(t, now: now) { return .local(answer) }
        return isQuickQuestion(t) ? .fast : .agent
    }

    // MARK: Time in a city (no model)

    static let aliases: [String: String] = [
        "nyc": "America/New_York", "new york": "America/New_York", "new york city": "America/New_York",
        "la": "America/Los_Angeles", "san francisco": "America/Los_Angeles", "sf": "America/Los_Angeles",
        "miami": "America/New_York", "boston": "America/New_York", "washington": "America/New_York",
        "dc": "America/New_York", "seattle": "America/Los_Angeles", "austin": "America/Chicago",
        "dallas": "America/Chicago", "houston": "America/Chicago", "beijing": "Asia/Shanghai",
        "mumbai": "Asia/Kolkata", "delhi": "Asia/Kolkata", "new delhi": "Asia/Kolkata",
        "abu dhabi": "Asia/Dubai", "tel aviv": "Asia/Jerusalem", "rio": "America/Sao_Paulo",
        "rio de janeiro": "America/Sao_Paulo", "uk": "Europe/London", "england": "Europe/London",
        "japan": "Asia/Tokyo", "lebanon": "Asia/Beirut", "france": "Europe/Paris", "spain": "Europe/Madrid",
        "italy": "Europe/Rome", "germany": "Europe/Berlin", "hawaii": "Pacific/Honolulu",
    ]

    static func timeZone(for place: String) -> TimeZone? {
        let p = place.trimmingCharacters(in: CharacterSet(charactersIn: " ?.!"))
        if let id = aliases[p] { return TimeZone(identifier: id) }
        let key = p.replacingOccurrences(of: " ", with: "_")
        guard !key.isEmpty else { return nil }
        let id = TimeZone.knownTimeZoneIdentifiers.first { $0.split(separator: "/").last?.lowercased() == key }
        return id.flatMap(TimeZone.init(identifier:))
    }

    static func timeAnswer(_ t: String, now: Date) -> String? {
        let pattern = #"^(what(?:'s| is)? (?:the )?time(?: is it)?(?: right now| now)? in|what time is it(?: right now| now)? in|time in|current time in) (.+?)(?: right now| now)?\??$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let r = Range(m.range(at: 2), in: t),
              let zone = timeZone(for: String(t[r])) else { return nil }
        let place = String(t[r]).trimmingCharacters(in: CharacterSet(charactersIn: " ?.!")).capitalized
        let f = DateFormatter()
        f.timeZone = zone
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "h:mm a"
        let day = DateFormatter()
        day.timeZone = zone
        day.locale = Locale(identifier: "en_US")
        day.dateFormat = "EEEE"
        return "It's \(f.string(from: now)) in \(place) (\(day.string(from: now)))."
    }

    // MARK: Quick question or real task?

    /// Words that mean "do something for me": those always go to the full agent.
    static let taskWords = #"\b(send|email|e-mail|text|message|dm|reply|book|schedule|remind|reminder|create|draft|write|post|order|buy|pay|call|delete|remove|add|update|cancel|move|share|save|file|upload|download|my (email|inbox|calendar|files|notes|messages|texts|slack|drive|brain|tasks|clients?))\b"#

    static func isQuickQuestion(_ t: String) -> Bool {
        let words = t.split(separator: " ").count
        guard words > 0, words <= 20 else { return false }
        if t.range(of: taskWords, options: .regularExpression) != nil { return false }
        let asks = t.hasSuffix("?")
            || t.range(of: #"^(what|who|whom|whose|when|where|why|how|which|is|are|was|were|does|do|did|can|could|will|should|tell me|define|explain)\b"#, options: .regularExpression) != nil
        return asks
    }

    // MARK: Haiku, streamed

    static let systemPrompt = "You are Nino, Rene's assistant. Answer in one to three short sentences, plain words, no markdown headers. Use web search only when the answer depends on live data (weather, news, prices, scores)."

    /// Streams Haiku's answer. `onText` gets the whole answer so far, on the main actor.
    /// Returns the final text, or nil if the CLI failed.
    static func streamFast(_ question: String, onText: @escaping @MainActor (String) -> Void) async -> String? {
        guard let claude = ClaudeCommandParser.candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: claude)
                process.arguments = ["-p", "--model", "haiku",
                                     "--output-format", "stream-json", "--verbose", "--include-partial-messages",
                                     "--setting-sources", "", "--strict-mcp-config",
                                     "--tools", "WebSearch", "--allowedTools", "WebSearch",
                                     "--disable-slash-commands", "--no-session-persistence",
                                     "--system-prompt", systemPrompt]
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
                process.environment = env
                let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("nino-quick-answer", isDirectory: true)
                try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                process.currentDirectoryURL = scratch
                let input = Pipe(), output = Pipe()
                process.standardInput = input
                process.standardOutput = output
                process.standardError = Pipe()
                guard (try? process.run()) != nil else { continuation.resume(returning: nil); return }
                input.fileHandleForWriting.write(Data(question.utf8))
                try? input.fileHandleForWriting.close()

                var text = ""
                var final: String?
                var buffer = Data()
                let handle = output.fileHandleForReading
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    while let nl = buffer.firstIndex(of: 0x0A) {
                        let line = buffer[buffer.startIndex..<nl]
                        buffer.removeSubrange(buffer.startIndex...nl)
                        guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                        if event["type"] as? String == "stream_event",
                           let inner = event["event"] as? [String: Any],
                           let delta = inner["delta"] as? [String: Any],
                           delta["type"] as? String == "text_delta",
                           let piece = delta["text"] as? String {
                            text += piece
                            let snapshot = text
                            Task { @MainActor in onText(snapshot) }
                        } else if event["type"] as? String == "result" {
                            final = event["result"] as? String
                        }
                    }
                }
                process.waitUntilExit()
                let answer = (final ?? text).trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: answer.isEmpty ? nil : answer)
            }
        }
    }
}
