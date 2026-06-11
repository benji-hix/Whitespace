// Sources/Whitespace/Editor/ZenTextViewRepresentable.swift
import AppKit
import SwiftUI

struct ZenTextViewRepresentable: NSViewRepresentable {
    @Binding var runs: [StyledRun]
    let themeStore: ThemeStore
    let preferences: PreferencesStore
    let keybindingStore: KeybindingStore

    private var theme: Theme { themeStore.current }

    /// Incremented by the owner to ask the editor to take first responder
    /// back (e.g. after the command palette is dismissed).
    var focusRequestID: Int = 0

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
        textView.textStorage?.setAttributedString(
            PasteNormalizer.attributedString(runs: runs, baseAttributes: textView.typingAttributes)
        )
        wire(textView)

        // Sync coordinator tracking state to avoid redundant calls on first updateNSView
        context.coordinator.lastFontSize = CGFloat(preferences.fontSize)
        context.coordinator.lastLineHeight = preferences.lineHeightMultiple
        context.coordinator.lastProgress = themeStore.transitionProgress
        context.coordinator.lastTheme = theme
        context.coordinator.lastScrollSpeed = preferences.scrollSpeed

        scrollView.documentView = textView
        // The window doesn't exist yet; claim first responder once it does
        // so the user can type immediately on launch.
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
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
        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            textView.window?.makeFirstResponder(textView)
        }

        // Only sync content if changed externally (e.g. document revert,
        // restoration). Rebuilding from runs applies the current font,
        // colors and paragraph style via the typing attributes.
        if textView.currentStyledRuns() != runs {
            // The cached scroll target refers to the previous content's
            // layout. After replacing the content, invalidate so the next
            // recenter snaps unconditionally.
            textView.invalidateScrollAnchor()
            // The undo stack refers to the previous content; undo after a
            // wholesale replacement must not resurrect it.
            textView.undoManager?.removeAllActions()
            textView.textStorage?.setAttributedString(
                PasteNormalizer.attributedString(runs: runs, baseAttributes: textView.typingAttributes)
            )
        }

        wire(textView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private func wire(_ textView: ZenTextView) {
        let prefs = preferences
        textView.onIncreaseFontSize = { prefs.setFontSize(prefs.fontSize + 1) }
        textView.onDecreaseFontSize = { prefs.setFontSize(prefs.fontSize - 1) }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ZenTextViewRepresentable
        var lastFontSize: CGFloat = 0
        var lastLineHeight: CGFloat = 0
        var lastTheme: Theme? = nil
        var lastProgress: Double = .nan
        var lastScrollSpeed: Double = .nan
        var lastFocusRequestID: Int = 0

        init(_ parent: ZenTextViewRepresentable) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? ZenTextView else { return }
            let current = textView.currentStyledRuns()
            if parent.runs != current {
                parent.runs = current
            }
        }
    }
}
