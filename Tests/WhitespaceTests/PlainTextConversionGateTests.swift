// Tests/WhitespaceTests/PlainTextConversionGateTests.swift
import XCTest
@testable import Whitespace

@MainActor
final class PlainTextConversionGateTests: XCTestCase {
    var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "test-conversion-gate")!
        PlainTextConversionGate.approvedNextWrite = false
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "test-conversion-gate")
        PlainTextConversionGate.approvedNextWrite = false
        super.tearDown()
    }

    private let formatted = [
        StyledRun(text: "plain ", bold: false, italic: false),
        StyledRun(text: "loud", bold: true, italic: false),
    ]
    private let plain = [StyledRun(text: "just words", bold: false, italic: false)]

    func testWarnsWhenFormattingWouldFlatten() {
        XCTAssertTrue(PlainTextConversionGate.shouldWarn(runs: formatted, defaults: defaults))
    }

    func testNoWarningWithoutFormatting() {
        XCTAssertFalse(PlainTextConversionGate.shouldWarn(runs: plain, defaults: defaults))
    }

    func testSuppressionSilencesTheWarning() {
        defaults.set(true, forKey: PlainTextConversionGate.suppressKey)
        XCTAssertFalse(PlainTextConversionGate.shouldWarn(runs: formatted, defaults: defaults))
    }

    func testApprovalIsConsumedByExactlyOneWrite() {
        PlainTextConversionGate.approvedNextWrite = true
        XCTAssertFalse(PlainTextConversionGate.shouldWarn(runs: formatted, defaults: defaults))
        XCTAssertTrue(PlainTextConversionGate.shouldWarn(runs: formatted, defaults: defaults))
    }
}
