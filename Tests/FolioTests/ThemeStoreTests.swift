import XCTest
@testable import Folio

@MainActor
final class ThemeStoreTests: XCTestCase {
    var store: ThemeStore!

    override func setUp() {
        super.setUp()
        store = ThemeStore(defaults: UserDefaults(suiteName: "test-theme")!)
    }

    override func tearDown() {
        UserDefaults(suiteName: "test-theme")?.removePersistentDomain(forName: "test-theme")
        super.tearDown()
    }

    func testDefaultIsPaper() {
        XCTAssertEqual(store.current, .paper)
    }

    func testToggleSwitchesToDark() {
        store.toggle()
        XCTAssertEqual(store.current, .dark)
    }

    func testToggleTwiceReturnsToPaper() {
        store.toggle()
        store.toggle()
        XCTAssertEqual(store.current, .paper)
    }

    func testPersistsAcrossInstances() {
        store.toggle()
        let store2 = ThemeStore(defaults: UserDefaults(suiteName: "test-theme")!)
        XCTAssertEqual(store2.current, .dark)
    }
}
