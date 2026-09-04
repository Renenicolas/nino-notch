// Sparkle API stub for this fork.
// The real Sparkle auto-updater is not linked: a Nino fork must not
// download upstream Boring Notch builds. Types exist so existing
// Settings/About call sites still compile.

import Foundation
import Combine
import SwiftUI

public final class SPUUpdater: NSObject {
    @objc public dynamic var canCheckForUpdates: Bool = false
    @objc public dynamic var automaticallyChecksForUpdates: Bool = false
    @objc public dynamic var automaticallyDownloadsUpdates: Bool = false

    public func checkForUpdates() {
        // no-op: this fork does not phone home
    }
}

public final class SPUStandardUpdaterController {
    public let updater = SPUUpdater()

    public init(
        startingUpdater: Bool,
        updaterDelegate: Any?,
        userDriverDelegate: Any?
    ) {
        _ = startingUpdater
        _ = updaterDelegate
        _ = userDriverDelegate
    }
}
