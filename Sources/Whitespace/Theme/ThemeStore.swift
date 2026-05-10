import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class ThemeStore {
    private(set) var current: Theme
    private(set) var previous: Theme
    /// 0 = fully on `previous`, 1 = fully on `current`. Eased.
    private(set) var transitionProgress: Double = 1.0

    private let defaults: UserDefaults
    private let key = "whitespace.theme"
    private let transitionDuration: TimeInterval = 1.5
    private var animationTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let initial: Theme
        if let raw = defaults.string(forKey: key),
           let saved = Theme(rawValue: raw) {
            initial = saved
        } else {
            initial = .paper
        }
        self.current = initial
        self.previous = initial
    }

    func toggle() {
        set(current == .paper ? .dark : .paper)
    }

    func set(_ theme: Theme) {
        guard theme != current else { return }
        // If we're mid-transition, the snapshot of "previous" should reflect
        // what's currently on screen so the new fade starts from there.
        previous = current
        current = theme
        defaults.set(theme.rawValue, forKey: key)
        startTransition()
    }

    private func startTransition() {
        animationTask?.cancel()
        let start = Date()
        transitionProgress = 0
        animationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                let raw = min(1.0, elapsed / self.transitionDuration)
                self.transitionProgress = ThemeStore.easeInOut(raw)
                if raw >= 1.0 {
                    self.previous = self.current
                    break
                }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }

    private static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    // MARK: - Interpolated Colors

    var displayedBackgroundColor: NSColor {
        Self.lerp(previous.backgroundColor, current.backgroundColor, transitionProgress)
    }

    var displayedTextColor: NSColor {
        Self.lerp(previous.textColor, current.textColor, transitionProgress)
    }

    var displayedCursorColor: NSColor {
        Self.lerp(previous.cursorColor, current.cursorColor, transitionProgress)
    }

    var displayedSelectionColor: NSColor {
        Self.lerp(previous.selectionColor, current.selectionColor, transitionProgress)
    }

    /// Linearly interpolate between two NSColors in sRGB. Public so other
    /// views (e.g. the shortcuts panel) can ride the same transition.
    static func interpolate(_ a: NSColor, _ b: NSColor, _ t: Double) -> NSColor {
        lerp(a, b, t)
    }

    private static func lerp(_ a: NSColor, _ b: NSColor, _ t: Double) -> NSColor {
        let aRGB = a.usingColorSpace(.sRGB) ?? a
        let bRGB = b.usingColorSpace(.sRGB) ?? b
        let f = CGFloat(t)
        let r  = aRGB.redComponent   + (bRGB.redComponent   - aRGB.redComponent)   * f
        let g  = aRGB.greenComponent + (bRGB.greenComponent - aRGB.greenComponent) * f
        let bl = aRGB.blueComponent  + (bRGB.blueComponent  - aRGB.blueComponent)  * f
        let al = aRGB.alphaComponent + (bRGB.alphaComponent - aRGB.alphaComponent) * f
        return NSColor(srgbRed: r, green: g, blue: bl, alpha: al)
    }
}
