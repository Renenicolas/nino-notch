import AppKit
import Foundation

/// Dev preview: `NinoNotch.app --args --nino-preview nino.search` selects that
/// module, switches to the Nino tab and holds the notch open for the first
/// 8 seconds after launch. Handy while wiring a module, and for screenshots.
/// Does nothing without the flag.
enum NinoModulePreview {
    @MainActor
    static func applyIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--nino-preview"), i + 1 < args.count else { return }
        pin(args[i + 1], ticks: 16)
    }

    /// The shell resets the tab and closes the notch while it sets up its
    /// windows, so re-assert every half second instead of firing once.
    @MainActor
    private static func pin(_ id: String, ticks: Int) {
        guard ticks > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NinoModuleRegistry.shared.select(id)
            BoringViewCoordinator.shared.currentView = .modules
            if let vm = AppDelegate.shared?.vm, vm.notchState != .open {
                vm.open()
            }
            pin(id, ticks: ticks - 1)
        }
    }
}
