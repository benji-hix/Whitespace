// Sources/Whitespace/Editor/ZenTextViewRepresentable.swift
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
    var onIncreaseFontSize: () -> Void = {}
    var onDecreaseFontSize: () -> Void = {}

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.wantsLayer = true
        scrollView.contentView.wantsLayer = true

        let textView = ZenTextView(frame: .zero)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.keybindingStore = keybindingStore
        textView.applyTheme(theme)
        textView.applyFont(
            size: CGFloat(preferences.fontSize),
            lineHeightMultiple: preferences.lineHeightMultiple
        )
        textView.string = text
        wire(textView)

        // Sync coordinator tracking state to avoid redundant calls on first updateNSView
        context.coordinator.lastFontSize = CGFloat(preferences.fontSize)
        context.coordinator.lastLineHeight = preferences.lineHeightMultiple
        context.coordinator.lastTheme = theme

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ZenTextView else { return }

        // Issue 5: Keep coordinator's parent reference fresh
        context.coordinator.parent = self

        textView.keybindingStore = keybindingStore

        // Issue 2: Only apply font/theme when values actually changed
        let newSize = CGFloat(preferences.fontSize)
        let newLH   = preferences.lineHeightMultiple
        if context.coordinator.lastFontSize != newSize || context.coordinator.lastLineHeight != newLH {
            textView.applyFont(size: newSize, lineHeightMultiple: newLH)
            context.coordinator.lastFontSize = newSize
            context.coordinator.lastLineHeight = newLH
        }
        if context.coordinator.lastTheme != theme {
            textView.applyTheme(theme)
            context.coordinator.lastTheme = theme
        }

        // Only sync text if changed externally (e.g. file switch)
        if textView.string != text {
            // The line anchor tracks a character index in the *previous*
            // text. After replacing the entire string, that index no longer
            // refers to the same logical line — invalidate so the next
            // scrollToCurrentLine recomputes from scratch.
            textView.invalidateScrollAnchor()
            textView.string = text
            // Setting .string resets all attributed string attributes, so reapply
            textView.applyFont(size: CGFloat(preferences.fontSize), lineHeightMultiple: preferences.lineHeightMultiple)
            textView.applyTheme(theme)
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
        textView.onIncreaseFontSize      = onIncreaseFontSize
        textView.onDecreaseFontSize      = onDecreaseFontSize
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ZenTextViewRepresentable
        var lastFontSize: CGFloat = 0
        var lastLineHeight: CGFloat = 0
        var lastTheme: Theme? = nil

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
