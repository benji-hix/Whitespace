// Sources/Whitespace/ShortcutOverlay/ShortcutOverlayView.swift
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

    private var labelColor: Color { Color(nsColor: theme.textColor).opacity(0.50) }
    private var dimColor: Color   { Color(nsColor: theme.textColor).opacity(0.28) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Shortcuts")
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(dimColor)
                .padding(.horizontal, 30)
                .padding(.top, 28)
                .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 1) {
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
            .padding(.horizontal, 30)
            .padding(.bottom, 28)
        }
        .frame(width: 220)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: theme.backgroundColor).opacity(0.88))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color(nsColor: theme.textColor).opacity(0.08), lineWidth: 0.5)
                }
        }
        .shadow(color: .black.opacity(0.02), radius: 6, y: 1)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 8, weight: .regular))
            .foregroundStyle(dimColor)
            .padding(.top, 14)
            .padding(.bottom, 3)
    }

    private func shortcutRow(label: String, binding: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(labelColor)
            Spacer()
            Text(binding)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(dimColor)
        }
        .padding(.vertical, 3)
    }
}
