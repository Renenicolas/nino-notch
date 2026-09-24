import AppKit
import Combine
import Darwin

/// Live state from the Nino Voice engine. Mirrors `NinoBridgeState` in
/// ~/dev/VoiceInk `Services/NinoNotchBridge.swift` — keep the two in step.
struct NinoVoiceState: Decodable, Equatable {
    let recording: String          // idle | starting | recording | transcribing | enhancing | busy
    let panelVisible: Bool
    let hostedInNotch: Bool
    let partial: String
    let lastText: String
    let modeName: String
    let modelName: String
    let recordKey: String
    let askKey: String
    let pasteKey: String
    let ask: Ask
    let setup: Setup

    struct Ask: Decodable, Equatable {
        let visible: Bool
        let busy: Bool
        let canSend: Bool
        let status: String?
        let failed: String?
        let draft: String
        let messages: [Message]
    }

    struct Message: Decodable, Equatable, Identifiable {
        let id: String
        let role: String
        let text: String
    }

    struct Setup: Decodable, Equatable {
        let onboarded: Bool
        let microphone: Bool
        let accessibility: Bool
        var isComplete: Bool { onboarded && microphone && accessibility }
    }

    var isCapturing: Bool { ["starting", "recording", "transcribing", "enhancing"].contains(recording) }
}

/// Nino Notch's end of the Nino Voice bridge.
///
/// Nino Voice (the engine: hotkeys, Parakeet/whisper speech-to-text, Claude CLI
/// polish, paste at cursor, OpenClaw answers) runs headless. Nino Notch starts
/// it, draws everything it shows, and sends it commands over a Unix socket that
/// only this user can open. Why a socket and not distributed notifications:
/// see the engine's `NinoNotchBridge`.
@MainActor
final class NinoVoiceLink: ObservableObject {
    static let shared = NinoVoiceLink()

    static let engineBundleID = "com.prakashjoshipax.VoiceInk"
    static let enginePath = "/Applications/Nino Voice.app"

    static var socketPath: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("com.meetnino.notch/voice.sock").path
    }

    /// nil = the engine is not connected.
    @Published private(set) var state: NinoVoiceState?
    /// 0...1 mic level while recording.
    @Published private(set) var level: Double = 0

    /// Ask Nino is up: hover-out must not close the notch (Esc or the close button does).
    /// Static + nonisolated so `BoringViewModel.close()` can check it from any context.
    nonisolated(unsafe) private(set) static var holdsNotchOpen = false

    private var fd: Int32 = -1
    private var readSource: DispatchSourceRead?
    private let ioQueue = DispatchQueue(label: "com.meetnino.notch.voicelink")
    private var retryTimer: Timer?
    private var lastLaunchAttempt = Date.distantPast
    private var started = false

    // MARK: Lifecycle

    private var registryObserver: AnyCancellable?

    /// The Nino Voice module's On/Off toggle is the engine's on/off switch.
    private var voiceEnabled: Bool { NinoModuleRegistry.shared.isEnabled("nino.voice") }
    private var askEnabled: Bool { NinoModuleRegistry.shared.isEnabled("nino.search") }

    func start() {
        guard !started else { return }
        started = true
        if voiceEnabled { connect() }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in
                let link = NinoVoiceLink.shared
                if link.fd < 0 && link.voiceEnabled { link.connect() }
            }
        }
        registryObserver = NinoModuleRegistry.shared.objectWillChange.sink { _ in
            DispatchQueue.main.async {
                let link = NinoVoiceLink.shared
                if !link.voiceEnabled && link.fd >= 0 {
                    link.stopEngine()
                    link.disconnect()
                }
            }
        }
    }

    /// One app, not two half-running: quitting Nino Notch stops its engine.
    func stopEngine() {
        // A newer Nino Notch copy is taking over: leave the engine running for it.
        guard NinoSingleInstance.otherCopies().isEmpty else { return }
        send("quit")
    }

    // MARK: Commands

    func send(_ cmd: String, text: String? = nil) {
        guard fd >= 0 else {
            if voiceEnabled { connect() }
            return
        }
        var payload: [String: String] = ["cmd": cmd]
        if let text { payload["text"] = text }
        guard var data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        data.append(0x0A)
        let socket = fd
        let ok = data.withUnsafeBytes { raw -> Bool in
            var offset = 0
            while offset < raw.count {
                let n = Darwin.write(socket, raw.baseAddress! + offset, raw.count - offset)
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
        if !ok { disconnect() }
    }

    // MARK: Socket

    private func connect() {
        let path = Self.socketPath
        let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(socketFD)
            return
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close(socketFD)
            launchEngineIfNeeded()
            return
        }
        var one: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

        fd = socketFD
        var buffer = Data()
        let source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: ioQueue)
        source.setEventHandler {
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            let n = Darwin.read(socketFD, &chunk, chunk.count)
            guard n > 0 else {
                Task { @MainActor in NinoVoiceLink.shared.disconnect(ifCurrent: socketFD) }
                return
            }
            buffer.append(contentsOf: chunk[0..<n])
            var lines: [Data] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                lines.append(Data(buffer[buffer.startIndex..<newline]))
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            guard !lines.isEmpty else { return }
            Task { @MainActor in
                for line in lines { NinoVoiceLink.shared.handle(line) }
            }
        }
        source.setCancelHandler { close(socketFD) }
        readSource = source
        source.resume()
        send("hello")
    }

    /// A late EOF from an old socket must not tear down a newer connection.
    private func disconnect(ifCurrent socketFD: Int32) {
        if fd == socketFD { disconnect() }
    }

    private func disconnect() {
        readSource?.cancel()
        readSource = nil
        fd = -1
        level = 0
        if state?.ask.visible == true { hideAsk() }
        state = nil
    }

    private func launchEngineIfNeeded() {
        guard Date().timeIntervalSince(lastLaunchAttempt) > 20 else { return }
        lastLaunchAttempt = Date()
        guard NSRunningApplication.runningApplications(withBundleIdentifier: Self.engineBundleID).isEmpty else { return }
        let url = FileManager.default.fileExists(atPath: Self.enginePath)
            ? URL(fileURLWithPath: Self.enginePath)
            : NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.engineBundleID)
        guard let url else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    // MARK: Incoming

    private struct Envelope: Decodable {
        let type: String
        let level: Double?
    }

    private func handle(_ line: Data) {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: line) else { return }
        switch envelope.type {
        case "meter":
            level = envelope.level ?? 0
        case "state":
            guard let new = try? JSONDecoder().decode(NinoVoiceState.self, from: line) else { return }
            let wasAsking = state?.ask.visible == true
            let oldDraft = state?.ask.draft ?? ""
            state = new
            if new.ask.visible, !new.ask.draft.isEmpty, new.ask.draft != oldDraft {
                routeSpokenDraft(new.ask.draft)
            }
            if !new.isCapturing { level = 0 }
            let isAsking = new.ask.visible && new.panelVisible && new.hostedInNotch
            if isAsking && !askEnabled {
                send("askClose")  // Ask Nino is switched off in Settings
                return
            }
            if isAsking && !wasAsking { showAsk() }
            if !isAsking && wasAsking { hideAsk() }
        default:
            break
        }
    }

    // MARK: Screen Control hand-off

    /// Words spoken into the Ask box: a screen command runs straight away
    /// (hands-free); anything else stays in the box for Return, as before.
    private func routeSpokenDraft(_ text: String) {
        Task {
            if await NinoScreenControl.shared.handle(text) { showScreenResult() }
        }
    }

    /// Close the ask box and leave Screen Control selected, showing what happened.
    func showScreenResult() {
        NinoModuleRegistry.shared.select("nino.screen")
        send("askClose")
    }

    // MARK: Notch focus (Ask Nino owns the keyboard, dictation never does)

    /// Right-Command (or typing into the tab) opened Ask Nino: show it in the notch and take the keyboard.
    private func showAsk() {
        NinoModuleRegistry.shared.select("nino.search")
        BoringViewCoordinator.shared.currentView = .modules
        Self.holdsNotchOpen = true
        BoringNotchSkyLightWindow.ninoAllowsKeyFocus = true
        guard let target = Self.notchTarget() else { return }
        target.vm.open()
        target.window?.makeKey()
    }

    private func hideAsk() {
        guard Self.holdsNotchOpen else { return }
        Self.holdsNotchOpen = false
        releaseKeyFocus()
        Self.notchTarget()?.vm.close()
    }

    /// Give the keyboard back to the app underneath. Dictation pastes there.
    func releaseKeyFocus() {
        BoringNotchSkyLightWindow.ninoAllowsKeyFocus = false
        for window in NSApp.windows where window is BoringNotchSkyLightWindow && window.isKeyWindow {
            window.resignKey()
        }
    }

    // ponytail: with "show on all displays", Ask Nino opens on the main display's notch only.
    private static func notchTarget() -> (vm: BoringViewModel, window: NSWindow?)? {
        guard let app = AppDelegate.shared else { return nil }
        if Defaults[.showOnAllDisplays], let uuid = NSScreen.main?.displayUUID, let vm = app.viewModels[uuid] {
            return (vm, app.windows[uuid])
        }
        return (app.vm, app.window)
    }
}
