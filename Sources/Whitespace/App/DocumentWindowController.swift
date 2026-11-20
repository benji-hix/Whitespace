// Sources/Whitespace/App/DocumentWindowController.swift
import AppKit
import SwiftUI

/// One window per document, styled once at creation: no title bar, no traffic
/// lights, no tabs. It hosts the SwiftUI canvas and owns that window's overlay
/// state, which the View menu reaches through the responder chain.
final class DocumentWindowController: NSWindowController, NSWindowDelegate {
    let ui = CanvasUIState()
    private static var cascadePoint = NSPoint.zero

    init(document: WhitespaceDocument, themeStore: ThemeStore,
         preferences: PreferencesStore, keybindingStore: KeybindingStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.tabbingMode = .disallowed
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentMinSize = NSSize(width: 600, height: 400)
        window.isRestorable = !AppDelegate.isRunningTests
        window.center()
        // Code-built windows don't cascade on their own; without this every
        // new document opens exactly on top of the last.
        Self.cascadePoint = window.cascadeTopLeft(from: Self.cascadePoint)

        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView:
            CanvasView(document: document, ui: ui)
                .environment(keybindingStore)
                .environment(themeStore)
                .environment(preferences)
        )
    }

    required init?(coder: NSCoder) {
        fatalError("DocumentWindowController is built in code")
    }

    // MARK: - Fullscreen

    func window(_ window: NSWindow,
                willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions = []
    ) -> NSApplication.PresentationOptions {
        FullscreenPresentation.options
    }

    // Fullscreen slides the title bar down with the menu bar. The buttons hidden
    // at creation were still hidden there on macOS 27, but that is AppKit's
    // choice to keep, not ours; re-assert it so a release can't bring them back.
    func windowWillEnterFullScreen(_ notification: Notification) {
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window?.standardWindowButton(type)?.isHidden = true
        }
    }

    // MARK: - View menu

    @objc func toggleCommandPalette(_ sender: Any?) {
        ui.showCommandPalette.toggle()
    }

    @objc func toggleShortcutOverlay(_ sender: Any?) {
        ui.showShortcutOverlay.toggle()
    }
}
