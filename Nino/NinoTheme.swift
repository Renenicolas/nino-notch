import SwiftUI
import AppKit

/// Nino brand palette. Gold on near-black. Used by the notch chrome and the Nino modules.
enum NinoTheme {
    static let gold = Color(red: 212 / 255, green: 168 / 255, blue: 83 / 255) // #d4a853 accent
    static let bg = Color(red: 5 / 255, green: 5 / 255, blue: 5 / 255) // #050505 notch background
    static let panel = Color(red: 10 / 255, green: 10 / 255, blue: 8 / 255) // #0a0a08 panels, buttons
    static let text = Color(red: 230 / 255, green: 225 / 255, blue: 211 / 255) // #e6e1d3 primary text
    static let sub = Color(red: 194 / 255, green: 188 / 255, blue: 171 / 255) // #c2bcab secondary text
    static let dim = Color(red: 143 / 255, green: 138 / 255, blue: 122 / 255) // #8f8a7a tertiary / disabled

    static let productName = "Nino Notch"
    static let positioning = "The AI that runs your growth."

    static var nsGold: NSColor {
        NSColor(srgbRed: 212 / 255, green: 168 / 255, blue: 83 / 255, alpha: 1)
    }
}
