//
//  LottieView.swift
//  boringNotch
//
//  Local placeholder. The upstream view loaded Lottie JSON from the
//  network; this fork does not.
//

import SwiftUI
import AppKit

enum LottieLoopMode {
    case loop
    case playOnce
    case autoReverse
}

struct LottieView: NSViewRepresentable {
    let url: URL
    let speed: Double
    let loopMode: LottieLoopMode

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
