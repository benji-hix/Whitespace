// Tests/FolioTests/KeybindingStoreTests.swift
import XCTest
@testable import Folio

@MainActor
final class KeybindingStoreTests: XCTestCase {
    var store: KeybindingStore!

    override func setUp() {
        super.setUp()
        store = KeybindingStore(defaults: UserDefaults(suiteName: "test-keybindings")!)
    }

    override func tearDown() {
        UserDefaults(suiteName: "test-keybindings")?.removePersistentDomain(forName: "test-keybindings")
        super.tearDown()
    }

    func testDefaultBindingExists() {
        let binding = store.binding(for: .deleteWordLeft)
        XCTAssertEqual(binding.keyCode, 51)  // ⌫
    }

    func testCustomBindingRoundTrips() throws {
        let custom = ShortcutBinding(keyCode: 10, modifiers: 0x100000)
        try store.setBinding(custom, for: .killLine)
        XCTAssertEqual(store.binding(for: .killLine), custom)
    }

    func testConflictDetected() {
        let binding = store.binding(for: .deleteWordLeft)
        XCTAssertThrowsError(try store.setBinding(binding, for: .deleteWordRight))
    }

    func testDisplayString() {
        let binding = ShortcutBinding(keyCode: 51, modifiers: 0x80000)  // ⌥⌫
        XCTAssertEqual(binding.displayString, "⌥⌫")
    }
}
