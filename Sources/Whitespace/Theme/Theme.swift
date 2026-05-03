import AppKit
import SwiftUI

enum Theme: String, Codable, CaseIterable {
    case paper
    case dark

    var backgroundColor: NSColor {
        switch self {
        case .paper: return NSColor(red: 0.961, green: 0.941, blue: 0.910, alpha: 1)  // #F5F0E8
        case .dark:  return NSColor(red: 0.094, green: 0.067, blue: 0.078, alpha: 1)  // #181114
        }
    }

    var textColor: NSColor {
        switch self {
        case .paper: return NSColor(red: 0.110, green: 0.090, blue: 0.075, alpha: 1)  // #1C1713
        case .dark:  return NSColor(red: 0.910, green: 0.878, blue: 0.835, alpha: 1)  // #E8E0D5
        }
    }

    var cursorColor: NSColor {
        switch self {
        case .paper: return NSColor(red: 0.545, green: 0.451, blue: 0.333, alpha: 0.5)  // #8B7355 at 50%
        case .dark:  return NSColor(red: 0.769, green: 0.659, blue: 0.510, alpha: 0.5)  // #C4A882 at 50%
        }
    }

    var selectionColor: NSColor {
        switch self {
        case .paper: return NSColor(red: 0.545, green: 0.451, blue: 0.333, alpha: 0.25)
        case .dark:  return NSColor(red: 0.769, green: 0.659, blue: 0.510, alpha: 0.25)
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
