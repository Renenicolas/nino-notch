import AppKit

/// Nino Notch has no window and no dock icon, and every copy shares the bundle id
/// com.meetnino.notch. Two things went wrong because of that (2026-09-24):
/// - Double-clicking a second copy (e.g. ~/Applications while /Applications runs)
///   made macOS just re-activate the running one: nothing visible happened.
/// - Copies launched from different paths ran side by side, stacking notches.
enum NinoSingleInstance {
    static func otherCopies() -> [NSRunningApplication] {
        guard let id = Bundle.main.bundleIdentifier else { return [] }
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != getpid() }
    }

    /// Newest launch wins: a rebuilt or reinstalled copy replaces the old one.
    static func retireOlderCopies() {
        for app in otherCopies() {
            NSLog("NINO single instance: retiring older copy pid %d at %@", app.processIdentifier, app.bundleURL?.path ?? "?")
            if !app.terminate() { app.forceTerminate() }
        }
    }

    /// Open the notch for a few seconds unless the pointer is in it.
    @MainActor
    static func flashNotch(vm: BoringViewModel, window: NSWindow?) {
        vm.open()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if let frame = window?.frame, frame.contains(NSEvent.mouseLocation) { return }
            vm.close()
        }
    }
}
