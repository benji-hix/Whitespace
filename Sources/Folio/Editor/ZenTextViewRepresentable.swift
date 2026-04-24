// Sources/Folio/Editor/ZenTextViewRepresentable.swift
import AppKit
import SwiftUI

struct ZenTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    let theme: Theme
    let preferences: PreferencesStore
    let keybindingStore: KeybindingStore

    var onToggleCommandPalette: () -> Void = {}
    var onToggleShortcutOverlay: () -> Void = {}
    var onToggleTheme: () -> Void = {}
    var onSave: () -> Void = {}
    var onSaveAs: () -> Void = {}
    var onOpen: () -> Void = {}
    var onNew: () -> Void = {}

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = ZenTextView(frame: scrollView.bounds)
        textView.delegate = context.coordinator
        textView.keybindingStore = keybindingStore
        textView.applyTheme(theme)
        textView.applyFont(
            size: CGFloat(preferences.fontSize),
            lineHeightMultiple: preferences.lineHeightMultiple
        )
        textView.string = text
        wire(textView)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ZenTextView else { return }
        textView.keybindingStore = keybindingStore
        textView.applyTheme(theme)
        textView.applyFont(
            size: CGFloat(preferences.fontSize),
            lineHeightMultiple: preferences.lineHeightMultiple
        )
        // Only sync text if changed externally (e.g. file switch)
        if textView.string != text {
            textView.string = text
        }
        // Apply column width to textContainer
        if let container = textView.textContainer {
            container.size.width = preferences.columnWidth.maxPoints
        }
        wire(textView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private func wire(_ textView: ZenTextView) {
        textView.onToggleCommandPalette  = onToggleCommandPalette
        textView.onToggleShortcutOverlay = onToggleShortcutOverlay
        textView.onToggleTheme           = onToggleTheme
        textView.onSave                  = onSave
        textView.onSaveAs                = onSaveAs
        textView.onOpen                  = onOpen
        textView.onNew                   = onNew
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ZenTextViewRepresentable

        init(_ parent: ZenTextViewRepresentable) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string {
                parent.text = textView.string
            }
        }
    }
}
