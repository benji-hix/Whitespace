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

    /// The hosted test bundle launches the real app. Under XCTest it must not
    /// open an untitled window or restore (or save) the owner's windows.
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

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        !Self.isRunningTests
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func application(_ app: NSApplication, shouldSaveSecureApplicationState coder: NSCoder) -> Bool {
        !Self.isRunningTests
    }

    func application(_ app: NSApplication, shouldRestoreSecureApplicationState coder: NSCoder) -> Bool {
        !Self.isRunningTests
    }

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

    @objc func showSettingsWindow(_ sender: Any?) {
        let controller = settingsWindowController ?? SettingsWindowController(
            keybindingStore: keybindingStore,
            preferencesStore: preferencesStore,
            themeStore: themeStore
        )
        settingsWindowController = controller
        controller.showWindow(sender)
    }
}
