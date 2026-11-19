// Sources/Whitespace/App/AppDelegate.swift
import AppKit
import CoreText

/// Owns the app-wide stores and the launch order. AppKit owns the lifecycle
/// directly: there is no SwiftUI `App`, so every delegate method here is
/// actually called.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let keybindingStore  = KeybindingStore()
    let themeStore       = ThemeStore()
    let preferencesStore = PreferencesStore()

    private var settingsWindowController: SettingsWindowController?

    /// The hosted test bundle launches the real app with the owner's bundle
    /// id. Under XCTest it opens no untitled window and marks its windows
    /// unrestorable; restoring the owner's session is switched off by the
    /// scheme's `-ApplePersistenceIgnoreState YES` (see `TestHostTests`).
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Fonts first: bold and italic are recognised by font name, so a
        // document read before Crimson Pro is registered (restoration,
        // open-at-launch) would flatten silently and then save flat.
        Self.registerFonts()
        // The first document controller instantiated becomes `shared`.
        _ = WhitespaceDocumentController()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The View menu has two full-screen items: AppKit's own, on the Globe
        // key, and ours on ⌃⌘F for keyboards without Globe. Both chords are set
        // here rather than in MainMenu.xib, because AppKit rewrites a nib's
        // ⌃⌘F to Globe-F while loading the menu, and an item that still
        // answers ⌃⌘F takes the chord from ours.
        let items = NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items) ?? []
        if let system = items.first(where: { $0.action == #selector(NSWindow.toggleFullScreen(_:)) }) {
            system.keyEquivalent = "f"
            system.keyEquivalentModifierMask = [.function]
        }
        if let ours = items.first(where: { $0.action == #selector(toggleFullScreenFromMenu(_:)) }) {
            ours.keyEquivalent = "f"
            ours.keyEquivalentModifierMask = [.control, .command]
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        !Self.isRunningTests
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    static func registerFonts() {
        let names = [WhitespaceFont.regular, WhitespaceFont.italic, WhitespaceFont.bold, WhitespaceFont.boldItalic]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    // MARK: - Menu actions (nil-targeted from MainMenu.xib)

    @objc func toggleDarkMode(_ sender: Any?) {
        themeStore.toggle()
    }

    @objc func maximizeWindow(_ sender: Any?) {
        NSApp.mainWindow?.zoom(sender)
    }

    /// AppKit's own Enter Full Screen item is bound to the Globe key on
    /// macOS 26, and Globe does not exist on most external keyboards. An
    /// NSMenuItem holds one key equivalent, so ⌃⌘F needs a second item. It has
    /// its own action because AppKit retitles every `toggleFullScreen:` item
    /// to Enter/Exit Full Screen.
    @objc func toggleFullScreenFromMenu(_ sender: Any?) {
        NSApp.mainWindow?.toggleFullScreen(sender)
    }

    @objc func showSettingsWindow(_ sender: Any?) {
        let controller = settingsWindowController ?? SettingsWindowController(
            keybindingStore: keybindingStore,
            preferencesStore: preferencesStore,
            themeStore: themeStore
        )
        settingsWindowController = controller
        if let window = controller.window,
           SettingsWindowController.shouldClose(isVisible: window.isVisible, isKey: window.isKeyWindow) {
            window.performClose(sender)
        } else {
            controller.showWindow(sender)
        }
    }
}
