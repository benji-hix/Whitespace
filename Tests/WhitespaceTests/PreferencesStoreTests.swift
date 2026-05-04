import XCTest
@testable import Whitespace

@MainActor
final class PreferencesStoreTests: XCTestCase {
    var store: PreferencesStore!

    override func setUp() {
        super.setUp()
        store = PreferencesStore(defaults: UserDefaults(suiteName: "test-prefs")!)
    }

    override func tearDown() {
        UserDefaults(suiteName: "test-prefs")?.removePersistentDomain(forName: "test-prefs")
        super.tearDown()
    }

    func testDefaults() {
        XCTAssertEqual(store.fontSize, 18)
        XCTAssertEqual(store.lineHeightMultiple, 1.6)
        XCTAssertEqual(store.columnWidth, .medium)
    }

    func testFontSizeClampedOnSave() {
        store.fontSize = 5
        XCTAssertEqual(store.fontSize, 12)
        store.fontSize = 99
        XCTAssertEqual(store.fontSize, 28)
    }

    func testPersists() {
        store.fontSize = 22
        let store2 = PreferencesStore(defaults: UserDefaults(suiteName: "test-prefs")!)
        XCTAssertEqual(store2.fontSize, 22)
    }

    func testColumnWidthPersists() {
        store.columnWidth = .wide
        let store2 = PreferencesStore(defaults: UserDefaults(suiteName: "test-prefs")!)
        XCTAssertEqual(store2.columnWidth, .wide)
    }

}
