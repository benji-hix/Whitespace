// Sources/Folio/ShortcutOverlay/ShortcutOverlayView.swift
import SwiftUI

struct ShortcutOverlayView: View {
    @Environment(KeybindingStore.self) private var keybindingStore
    let theme: Theme

    private let appShortcuts: [(String, String)] = [
        ("Open Command Palette", "⌘P"),
        ("Toggle Shortcut Overlay", "⌘/"),
        ("Toggle Dark Mode", "⌘⇧D"),
        ("New File", "⌘N"),
        ("Open File", "⌘O"),
        ("Save", "⌘S"),
        ("Save As", "⌘⇧S"),
        ("Preferences", "⌘,"),
        ("Increase Font", "⌘+"),
        ("Decrease Font", "⌘–"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Shortcuts")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sectionHeader("Editor")
                    ForEach(KeybindingAction.allCases, id: \.rawValue) { action in
                        shortcutRow(
                            label: action.displayName,
                            binding: keybindingStore.binding(for: action).displayString
                        )
                    }

                    sectionHeader("App")
                    ForEach(appShortcuts, id: \.0) { label, shortcut in
                        shortcutRow(label: label, binding: shortcut)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 240)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: theme.backgroundColor).opacity(0.1))
                )
        }
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func shortcutRow(label: String, binding: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(binding)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }
}
