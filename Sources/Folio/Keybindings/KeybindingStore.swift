// Sources/Folio/Keybindings/KeybindingStore.swift
import Foundation

enum KeybindingError: Error, LocalizedError {
    case conflict(KeybindingAction)
    var errorDescription: String? {
        if case .conflict(let a) = self { return "Already used by: \(a.displayName)" }
        return nil
    }
}

@Observable
@MainActor
final class KeybindingStore {
    private let defaults: UserDefaults
    private var cache: [KeybindingAction: ShortcutBinding] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for action in KeybindingAction.allCases {
            cache[action] = loadOrDefault(action)
        }
    }

    func binding(for action: KeybindingAction) -> ShortcutBinding {
        cache[action] ?? action.defaultBinding
    }

    func setBinding(_ binding: ShortcutBinding, for action: KeybindingAction) throws {
        for other in KeybindingAction.allCases where other != action {
            if cache[other] == binding { throw KeybindingError.conflict(other) }
        }
        cache[action] = binding
        let data = try JSONEncoder().encode(binding)
        defaults.set(data, forKey: key(for: action))
    }

    func resetToDefaults() {
        for action in KeybindingAction.allCases {
            defaults.removeObject(forKey: key(for: action))
            cache[action] = action.defaultBinding
        }
    }

    private func loadOrDefault(_ action: KeybindingAction) -> ShortcutBinding {
        guard let data = defaults.data(forKey: key(for: action)),
              let binding = try? JSONDecoder().decode(ShortcutBinding.self, from: data)
        else { return action.defaultBinding }
        return binding
    }

    private func key(for action: KeybindingAction) -> String {
        "folio.keybinding.\(action.rawValue)"
    }
}
