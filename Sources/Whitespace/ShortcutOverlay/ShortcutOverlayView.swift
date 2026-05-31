// Sources/Whitespace/ShortcutOverlay/ShortcutOverlayView.swift
import SwiftUI

struct ShortcutOverlayView: View {
    @Environment(KeybindingStore.self) private var keybindingStore
    let themeStore: ThemeStore

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

    private static let paperInk = NSColor(srgbRed: 0x1E/255, green: 0x0F/255, blue: 0x11/255, alpha: 1)
    private static let darkInk  = NSColor(srgbRed: 0x7D/255, green: 0x6D/255, blue: 0x6C/255, alpha: 1)

    private static func panelInk(for theme: Theme) -> NSColor {
        switch theme {
        case .paper: return paperInk
        case .dark:  return darkInk
        }
    }

    private var ink: Color {
        let from = Self.panelInk(for: themeStore.previous)
        let to   = Self.panelInk(for: themeStore.current)
        return Color(nsColor: ThemeStore.interpolate(from, to, themeStore.transitionProgress))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section(label: "Editor") {
                ForEach(KeybindingAction.allCases, id: \.rawValue) { action in
                    shortcutRow(
                        label: action.displayName,
                        binding: keybindingStore.binding(for: action).displayString
                    )
                }
            }

            section(label: "App") {
                ForEach(appShortcuts, id: \.0) { label, shortcut in
                    shortcutRow(label: label, binding: shortcut)
                }
            }
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 40)
        .frame(width: 344)
        .overlay(
            Rectangle().stroke(ink.opacity(0.4), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func section<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.custom(WhitespaceFont.bold, size: 9))
                .tracking(1.08)
                .foregroundStyle(ink.opacity(0.7))
                .padding(.bottom, 6)
            content()
        }
    }

    private func shortcutRow(label: String, binding: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.custom(WhitespaceFont.regular, size: 13))
                .foregroundStyle(ink.opacity(0.78))
            Spacer()
            Text(binding)
                .font(.system(size: 12, weight: .regular))
                .tracking(0.24)
                .foregroundStyle(ink.opacity(0.4))
        }
        .padding(.vertical, 2.5)
    }
}
