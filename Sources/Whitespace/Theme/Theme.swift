import AppKit
import SwiftUI

enum Theme: String, Codable, CaseIterable {
    case paper
    case dark

    var backgroundColor: NSColor {
        switch self {
        case .paper: return NSColor(red: 0.843, green: 0.808, blue: 0.804, alpha: 1)  // #D7CECD
        case .dark:  return NSColor(red: 0.090, green: 0.063, blue: 0.071, alpha: 1)  // #171012
        }
    }

    var textColor: NSColor {
        switch self {
        case .paper: return NSColor(red: 0.118, green: 0.059, blue: 0.067, alpha: 1)  // #1E0F11
        case .dark:  return NSColor(red: 0.420, green: 0.357, blue: 0.369, alpha: 1)  // #6B5B5E
        }
    }

    var cursorColor: NSColor {
        switch self {
        case .paper: return NSColor(red: 0.118, green: 0.059, blue: 0.067, alpha: 1)  // #1E0F11
        case .dark:  return NSColor(red: 0.420, green: 0.357, blue: 0.369, alpha: 1)  // #6B5B5E
        }
    }

    var selectionColor: NSColor {
        switch self {
        case .paper: return NSColor(red: 0.545, green: 0.451, blue: 0.333, alpha: 0.25)
        case .dark:  return NSColor(red: 0.769, green: 0.659, blue: 0.510, alpha: 0.25)
        }
    }

    /// Ink for the shortcuts panel. Deliberately brighter than textColor in
    /// dark mode so the panel reads against the page.
    var panelInkColor: NSColor {
        switch self {
        case .paper: return NSColor(srgbRed: 0x1E/255, green: 0x0F/255, blue: 0x11/255, alpha: 1)
        case .dark:  return NSColor(srgbRed: 0x7D/255, green: 0x6D/255, blue: 0x6C/255, alpha: 1)
        }
    }

    var grainIsLight: Bool { self == .dark }

    @ViewBuilder
    var gradientOverlay: some View {
        switch self {
        case .paper:
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.05)],
                center: .center,
                startRadius: 250,
                endRadius: 900
            )
        case .dark:
            Color.clear
        }
    }
}
