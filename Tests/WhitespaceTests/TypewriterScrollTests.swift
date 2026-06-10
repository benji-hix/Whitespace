// Tests/WhitespaceTests/TypewriterScrollTests.swift
import XCTest
@testable import Whitespace

/// Characterization of the typewriter-scroll decision math, extracted from
/// ZenTextView. Constants under test: paragraph placement at 45% of the
/// viewport, caret safety clamp to the middle 70% (15%...85%), and the
/// same-paragraph deadzone at the middle 40% (30%...70%).
final class TypewriterScrollTests: XCTestCase {

    private func input(
        caretMinY: CGFloat = 500,
        caretMaxY: CGFloat = 520,
        paragraphMidY: CGFloat = 510,
        paragraphOffset: Int = 100,
        anchoredParagraphOffset: Int? = 100,
        viewportY: CGFloat = 300,
        viewportHeight: CGFloat = 600
    ) -> TypewriterScroll.Input {
        TypewriterScroll.Input(
            caretMinY: caretMinY,
            caretMaxY: caretMaxY,
            paragraphMidY: paragraphMidY,
            paragraphOffset: paragraphOffset,
            anchoredParagraphOffset: anchoredParagraphOffset,
            viewportY: viewportY,
            viewportHeight: viewportHeight
        )
    }

    // MARK: - Paragraph change regime

    func testParagraphChangePlacesMidpointAt45Percent() {
        // anchored 50 ≠ current 100 → paragraph changed
        let t = TypewriterScroll.target(for: input(anchoredParagraphOffset: 50))
        // 510 - 600*0.45 = 240
        XCTAssertEqual(t, 240)
    }

    func testNilAnchorIsTreatedAsParagraphChange() {
        let t = TypewriterScroll.target(for: input(anchoredParagraphOffset: nil))
        XCTAssertEqual(t, 240)
    }

    func testParagraphChangeClampsTallParagraphCaretBelowSafeZone() {
        // Tall paragraph: midpoint placement would leave the caret below 85%.
        // caret at 1000...1020, paragraphMidY 600:
        // naive target = 600 - 270 = 330; caretMaxAtTarget = 1020-330 = 690 > 510 (0.85*600)
        // → target = caretMaxY - 0.85h = 1020 - 510 = 510
        let t = TypewriterScroll.target(for: input(
            caretMinY: 1000, caretMaxY: 1020, paragraphMidY: 600,
            anchoredParagraphOffset: 50
        ))
        XCTAssertEqual(t, 510)
    }

    func testParagraphChangeClampsTallParagraphCaretAboveSafeZone() {
        // caret at 100...120, paragraphMidY 800:
        // naive target = 800 - 270 = 530; caretMinAtTarget = 100-530 = -430 < 90 (0.15*600)
        // → target = caretMinY - 0.15h = 100 - 90 = 10
        let t = TypewriterScroll.target(for: input(
            caretMinY: 100, caretMaxY: 120, paragraphMidY: 800,
            anchoredParagraphOffset: 50
        ))
        XCTAssertEqual(t, 10)
    }

    func testParagraphChangeNeverReturnsNegativeTarget() {
        // paragraph near document top: 50 - 270 < 0 → clamp to 0
        let t = TypewriterScroll.target(for: input(
            caretMinY: 40, caretMaxY: 60, paragraphMidY: 50,
            anchoredParagraphOffset: 50
        ))
        XCTAssertEqual(t, 0)
    }

    func testParagraphChangeRoundsTarget() {
        let t = TypewriterScroll.target(for: input(
            paragraphMidY: 510.4, anchoredParagraphOffset: 50
        ))
        // 510.4 - 270 = 240.4 → 240
        XCTAssertEqual(t, 240)
    }

    // MARK: - Same paragraph (deadzone) regime

    func testCaretInsideDeadzoneHoldsPosition() {
        // deadzone: 300+180=480 ... 300+420=720; caret 500...520 inside
        let t = TypewriterScroll.target(for: input())
        XCTAssertNil(t)
    }

    func testCaretBelowDeadzoneScrollsCaretToDeadzoneTop() {
        // caret 750...770 exceeds bottom 720 → target = caretMinY - 0.30h = 750-180 = 570
        let t = TypewriterScroll.target(for: input(caretMinY: 750, caretMaxY: 770))
        XCTAssertEqual(t, 570)
    }

    func testCaretAboveDeadzoneScrollsCaretToDeadzoneBottom() {
        // caret 400...420; 400 < 480 → target = caretMaxY - 0.70h = 420-420 = 0
        let t = TypewriterScroll.target(for: input(caretMinY: 400, caretMaxY: 420))
        XCTAssertEqual(t, 0)
    }

    func testSameParagraphNeverReturnsNegativeTarget() {
        // caret above deadzone near document top: 420*0.7 → 100-420 < 0 → 0
        let t = TypewriterScroll.target(for: input(caretMinY: 80, caretMaxY: 100))
        XCTAssertEqual(t, 0)
    }

    func testCaretExactlyOnDeadzoneEdgeHolds() {
        // boundary inclusive: caretMinY == top (480), caretMaxY == bottom (720)
        let t = TypewriterScroll.target(for: input(caretMinY: 480, caretMaxY: 720))
        XCTAssertNil(t)
    }
}
