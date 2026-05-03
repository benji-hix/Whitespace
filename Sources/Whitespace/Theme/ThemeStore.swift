import Foundation
import Observation

@Observable
@MainActor
final class ThemeStore {
    private(set) var current: Theme
    private let defaults: UserDefaults
    private let key = "whitespace.theme"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: key),
           let saved = Theme(rawValue: raw) {
            self.current = saved
        } else {
            self.current = .paper
        }
    }

    func toggle() {
        current = current == .paper ? .dark : .paper
        defaults.set(current.rawValue, forKey: key)
    }

    func set(_ theme: Theme) {
        current = theme
        defaults.set(theme.rawValue, forKey: key)
    }
}
