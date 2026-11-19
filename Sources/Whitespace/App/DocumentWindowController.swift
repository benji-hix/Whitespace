// Sources/Whitespace/App/DocumentWindowController.swift
import AppKit
import SwiftUI

/// One window per document, styled once at creation: no title bar, no traffic
/// lights, no tabs. It hosts the SwiftUI canvas and owns that window's overlay
/// state, which the View menu reaches through the responder chain.
final class DocumentWindowController: NSWindowController, NSWindowDelegate {
    let ui = CanvasUIState()

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

    // MARK: - View menu

    @objc func toggleCommandPalette(_ sender: Any?) {
        ui.showCommandPalette.toggle()
    }

    @objc func toggleShortcutOverlay(_ sender: Any?) {
        ui.showShortcutOverlay.toggle()
    }

    @objc func maximizeWindow(_ sender: Any?) {
        window?.zoom(sender)
    }

    /// AppKit's own Enter Full Screen item is bound to the Globe key on
    /// macOS 26, and Globe does not exist on most external keyboards. An
    /// NSMenuItem holds one key equivalent, so ⌃⌘F needs a second item. It has
    /// its own action because AppKit retitles every `toggleFullScreen:` item
    /// to Enter/Exit Full Screen, and would then not add its own Globe item.
    @objc func toggleFullScreenFromMenu(_ sender: Any?) {
        window?.toggleFullScreen(sender)
    }
}
