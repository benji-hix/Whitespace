// Sources/Whitespace/App/SettingsWindowController.swift
import AppKit
import SwiftUI

/// Hosts `PreferencesView` in a clear, title-less window at the pane's
/// designed size. The pane is not resizable and this window restores no saved
/// frame, so the size set here is the size shown. Escape and ⌘, close it, as
/// ⌘W does.
final class SettingsWindowController: NSWindowController {
    init(keybindingStore: KeybindingStore, preferencesStore: PreferencesStore, themeStore: ThemeStore) {
        let window = SettingsWindow(
            contentRect: NSRect(origin: .zero, size: PreferencesView.paneSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.title = "Whitespace Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.tabbingMode = .disallowed
        window.isRestorable = false
        window.contentView = NSHostingView(rootView:
            PreferencesView()
                .environment(keybindingStore)
                .environment(preferencesStore)
                .environment(themeStore)
        )
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("SettingsWindowController is built in code")
    }

    /// ⌘, opens Settings, brings it forward from behind a document window, or
    /// closes it when it is already the window in front.
    static func shouldClose(isVisible: Bool, isKey: Bool) -> Bool {
        isVisible && isKey
    }
}

/// Closes on an Escape that no control used. A plain NSWindow ignores it.
/// While a shortcut is being recorded, the recorder's event monitor swallows
/// Escape first, so it cancels only the recording.
private final class SettingsWindow: NSWindow {
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelOperation(self) } else { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}
