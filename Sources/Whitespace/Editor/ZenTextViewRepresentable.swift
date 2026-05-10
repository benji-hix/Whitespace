// Sources/Whitespace/Editor/ZenTextViewRepresentable.swift
import AppKit
import SwiftUI

struct ZenTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    let themeStore: ThemeStore
    let preferences: PreferencesStore
    let keybindingStore: KeybindingStore

    private var theme: Theme { themeStore.current }

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
        textView.applyColors(
            text: themeStore.displayedTextColor,
            cursor: themeStore.displayedCursorColor,
            selection: themeStore.displayedSelectionColor
        )
        textView.applyFont(
            size: CGFloat(preferences.fontSize),
            lineHeightMultiple: preferences.lineHeightMultiple
        )
        textView.scrollSpeed = preferences.scrollSpeed
        textView.string = text
        wire(textView)

        // Sync coordinator tracking state to avoid redundant calls on first updateNSView
        context.coordinator.lastFontSize = CGFloat(preferences.fontSize)
        context.coordinator.lastLineHeight = preferences.lineHeightMultiple
        context.coordinator.lastProgress = themeStore.transitionProgress
        context.coordinator.lastTheme = theme
        context.coordinator.lastScrollSpeed = preferences.scrollSpeed

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
        // Apply colors any time the displayed values change — either because
        // the logical theme switched, or because we're mid-transition.
        let progress = themeStore.transitionProgress
        if context.coordinator.lastTheme != theme ||
           context.coordinator.lastProgress != progress {
            textView.applyColors(
                text: themeStore.displayedTextColor,
                cursor: themeStore.displayedCursorColor,
                selection: themeStore.displayedSelectionColor
            )
            context.coordinator.lastTheme = theme
            context.coordinator.lastProgress = progress
        }
        if context.coordinator.lastScrollSpeed != preferences.scrollSpeed {
            textView.scrollSpeed = preferences.scrollSpeed
            context.coordinator.lastScrollSpeed = preferences.scrollSpeed
        }

        // Only sync text if changed externally (e.g. file switch)
        if textView.string != text {
            // The cached scroll target refers to the previous content's
            // layout. After replacing the entire string, invalidate so the
            // next recenter snaps unconditionally.
            textView.invalidateScrollAnchor()
            textView.string = text
            // Setting .string resets all attributed string attributes, so reapply
            textView.applyFont(size: CGFloat(preferences.fontSize), lineHeightMultiple: preferences.lineHeightMultiple)
            textView.applyColors(
                text: themeStore.displayedTextColor,
                cursor: themeStore.displayedCursorColor,
                selection: themeStore.displayedSelectionColor
            )
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
        var lastProgress: Double = .nan
        var lastScrollSpeed: Double = .nan

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
