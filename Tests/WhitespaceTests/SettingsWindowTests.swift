// Tests/WhitespaceTests/SettingsWindowTests.swift
import XCTest
import AppKit
@testable import Whitespace

@MainActor
final class SettingsWindowTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "SettingsWindowTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func showSettings() throws -> (SettingsWindowController, NSWindow) {
        let controller = SettingsWindowController(
            keybindingStore: KeybindingStore(defaults: defaults),
            preferencesStore: PreferencesStore(defaults: defaults),
            themeStore: ThemeStore(defaults: defaults)
        )
        controller.showWindow(nil)
        let window = try XCTUnwrap(controller.window)
        addTeardownBlock { @MainActor in window.close() }
        XCTAssertTrue(window.isVisible)
        return (controller, window)
    }

    /// The real key path: an Escape no control handles travels up the
    /// responder chain to the window.
    func testEscapeKeyClosesSettings() throws {
        let (_, window) = try showSettings()
        let escape = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53))
        window.sendEvent(escape)
        XCTAssertFalse(window.isVisible)
    }

    /// Key status is unreliable in the test host, so the ⌘, toggle is tested
    /// as its decision; the menu path is checked in the running app.
    func testCommandCommaClosesOnlyTheWindowInFront() {
        XCTAssertTrue(SettingsWindowController.shouldClose(isVisible: true, isKey: true))
        XCTAssertFalse(SettingsWindowController.shouldClose(isVisible: true, isKey: false), "behind a document: bring forward")
        XCTAssertFalse(SettingsWindowController.shouldClose(isVisible: false, isKey: false), "closed: open")
    }
}
