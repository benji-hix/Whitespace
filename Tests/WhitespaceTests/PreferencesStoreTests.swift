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

    func testNewDocumentTypeDefaultsToMarkdown() {
        XCTAssertEqual(store.newDocumentType, .markdown)
    }

    func testNewDocumentTypePersists() {
        store.newDocumentType = .plainText
        let store2 = PreferencesStore(defaults: UserDefaults(suiteName: "test-prefs")!)
        XCTAssertEqual(store2.newDocumentType, .plainText)
    }

    // MARK: - Flatten warning
    //
    // Stored inverted against the gate's *suppress* key, so an off-by-one in
    // the negation would silently disable the warning for everyone.

    func testFlattenWarningIsOnByDefault() {
        XCTAssertTrue(store.warnBeforeFlatteningFormatting)
        XCTAssertFalse(UserDefaults(suiteName: "test-prefs")!
            .bool(forKey: PlainTextConversionGate.suppressKey))
    }

    func testTurningTheWarningOffSuppressesTheGate() {
        store.warnBeforeFlatteningFormatting = false
        XCTAssertTrue(UserDefaults(suiteName: "test-prefs")!
            .bool(forKey: PlainTextConversionGate.suppressKey))

        let reopened = PreferencesStore(defaults: UserDefaults(suiteName: "test-prefs")!)
        XCTAssertFalse(reopened.warnBeforeFlatteningFormatting)
    }

    func testTurningTheWarningBackOnClearsSuppression() {
        store.warnBeforeFlatteningFormatting = false
        store.warnBeforeFlatteningFormatting = true
        XCTAssertFalse(UserDefaults(suiteName: "test-prefs")!
            .bool(forKey: PlainTextConversionGate.suppressKey))
    }

    /// The alert's suppression checkbox writes the key behind the store's back.
    /// Settings has to re-read it or it shows the previous session's answer.
    func testReloadPicksUpSuppressionWrittenByTheAlert() {
        XCTAssertTrue(store.warnBeforeFlatteningFormatting)

        UserDefaults(suiteName: "test-prefs")!
            .set(true, forKey: PlainTextConversionGate.suppressKey)
        XCTAssertTrue(store.warnBeforeFlatteningFormatting, "stale until reloaded — the bug this guards")

        store.reloadFlattenWarning()
        XCTAssertFalse(store.warnBeforeFlatteningFormatting)
    }

    func testReloadIsANoOpWhenNothingChanged() {
        store.reloadFlattenWarning()
        XCTAssertTrue(store.warnBeforeFlatteningFormatting)
        XCTAssertFalse(UserDefaults(suiteName: "test-prefs")!
            .bool(forKey: PlainTextConversionGate.suppressKey))
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
