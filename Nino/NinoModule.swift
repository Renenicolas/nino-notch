import SwiftUI

/// A plug-in feature for Nino Notch.
///
/// Add a feature: make one type that conforms to this, add it to
/// `ModuleCatalog.all`. The notch's Nino tab lists every module in the
/// catalog and shows the selected one's `panel`. Core shell files
/// (ContentView, BoringHeader, TabSelectionView, SettingsView) never change.
///
/// Activation state (on/off) is not on the module. It lives in
/// `NinoModuleRegistry.isEnabled(id)` so a module type stays a plain value.
protocol NinoModule {
    /// Stable id, also the UserDefaults key suffix. Never change it after ship.
    var id: String { get }
    var displayName: String { get }
    var summary: String { get }
    /// SF Symbol name for the switcher chip.
    var systemImage: String { get }
    /// True for placeholders. A stub must never look like a live integration.
    var isStub: Bool { get }
    /// The content shown in the notch when this module is selected.
    var panel: AnyView { get }
}

/// The framed box every module panel sits in.
struct NinoCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NinoTheme.panel)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(NinoTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// A stub's placeholder UI plus one honest note about what is not wired yet.
struct NinoStubPanel<Content: View>: View {
    let note: String
    @ViewBuilder let content: Content

    var body: some View {
        NinoCard {
            content
            Text(note)
                .font(.caption2)
                .foregroundStyle(NinoTheme.dim)
        }
    }
}
