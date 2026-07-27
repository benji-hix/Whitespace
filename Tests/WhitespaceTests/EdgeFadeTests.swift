// Tests/WhitespaceTests/EdgeFadeTests.swift
import XCTest
@testable import Whitespace

/// These assert the *structure* of the fade, never a particular depth.
/// `clearLines` and `fadeLines` are taste values that get tuned by eye against a
/// real screen; a test that pins them just breaks every time the dial moves and
/// tells you nothing. Every height below is derived from the configured bands,
/// so the suite stays green at any setting and still fails on a real defect —
/// inverted stops, a vanished writing area, depth that drifts with type size.
final class EdgeFadeTests: XCTestCase {
    /// The app's own defaults: 18pt Crimson Pro at 1.6 line spacing.
    private var line: CGFloat { EdgeFade.lineHeight(fontSize: 18, lineHeightMultiple: 1.6) }

    /// Total band the current settings ask for, in points, at a given line height.
    private func requestedBand(lineHeight lh: CGFloat) -> CGFloat {
        (EdgeFade.clearLines + EdgeFade.fadeLines) * lh
    }

    /// A height at which the requested band occupies `fraction` of the window.
    private func height(whereBandOccupies fraction: CGFloat, lineHeight lh: CGFloat) -> CGFloat {
        requestedBand(lineHeight: lh) / fraction
    }

    private func rampLines(height: CGFloat, lineHeight lh: CGFloat) -> CGFloat {
        let stops = EdgeFade.stops(forHeight: height, lineHeight: lh)
        return (stops.opaque - stops.clear) * height / lh
    }

    func testLineHeightMatchesTypeSettings() {
        // CrimsonPro-Light 18pt has a 20pt natural line, so 1.6 gives 32pt.
        XCTAssertEqual(EdgeFade.lineHeight(fontSize: 18, lineHeightMultiple: 1.6), 32, accuracy: 0.5)
        XCTAssertEqual(EdgeFade.lineHeight(fontSize: 18, lineHeightMultiple: 1.0), 20, accuracy: 0.5)
        XCTAssertGreaterThan(
            EdgeFade.lineHeight(fontSize: 24, lineHeightMultiple: 1.6),
            EdgeFade.lineHeight(fontSize: 18, lineHeightMultiple: 1.6)
        )
    }

    /// Given a window tall enough to afford the configured bands, the ramp
    /// dissolves exactly the number of lines asked for — whatever that is.
    func testRampReachesItsConfiguredDepthWhenThereIsRoom() {
        let roomy = height(whereBandOccupies: 0.20, lineHeight: line)
        XCTAssertEqual(rampLines(height: roomy, lineHeight: line), EdgeFade.fadeLines, accuracy: 0.3)
    }

    func testRampNeverShrinksAsTheWindowGrows() {
        let roomy = height(whereBandOccupies: 0.20, lineHeight: line)
        let heights = stride(from: 300.0, through: Double(roomy), by: 100.0).map { CGFloat($0) }
        let depths = heights.map { rampLines(height: $0, lineHeight: line) }
        for (a, b) in zip(depths, depths.dropFirst()) {
            XCTAssertLessThanOrEqual(a, b + 0.01, "ramp depth shrank as the window grew")
        }
        XCTAssertLessThan(depths.first!, depths.last!, "a taller window should dissolve more lines")
    }

    /// Depth is a count of lines, so type size changes the band in points while
    /// leaving the line count alone — as long as the band fits under the
    /// ceiling. Both heights here are derived, so this holds at any setting.
    func testLineCountIsIndependentOfTypeSizeWhileTheBandFits() {
        let small = EdgeFade.lineHeight(fontSize: 14, lineHeightMultiple: 1.6)
        let large = EdgeFade.lineHeight(fontSize: 24, lineHeightMultiple: 1.6)
        // Sized so the *larger* face is comfortably clear of the ceiling.
        let roomy = height(whereBandOccupies: 0.20, lineHeight: large)

        XCTAssertEqual(rampLines(height: roomy, lineHeight: small),
                       rampLines(height: roomy, lineHeight: large),
                       accuracy: 0.3,
                       "line count should not depend on type size while the band fits")
        XCTAssertGreaterThan(
            EdgeFade.stops(forHeight: roomy, lineHeight: large).opaque,
            EdgeFade.stops(forHeight: roomy, lineHeight: small).opaque,
            "larger type should fade a deeper band in points"
        )
    }

    /// The writing area is what the app is for. However deep the fade is set,
    /// the ceiling has to leave a majority of the window readable.
    func testAWindowAlwaysKeepsMostOfItselfReadable() {
        let heights: [CGFloat] = [300, 450, 700, 900, 1200, 1440, 2160]
        for h in heights {
            let readable = 1 - 2 * EdgeFade.stops(forHeight: h, lineHeight: line).opaque
            XCTAssertGreaterThanOrEqual(readable, 0.40,
                                        "only \(readable * 100)% of a \(h)pt window is readable")
        }
    }

    func testReadableAreaGrowsWithHeight() {
        let short = 1 - 2 * EdgeFade.stops(forHeight: 450, lineHeight: line).opaque
        let tall  = 1 - 2 * EdgeFade.stops(forHeight: 2160, lineHeight: line).opaque
        XCTAssertGreaterThan(tall, short, "a bigger window should buy readable text, not more vignette")
    }

    /// A window too short for the configured bands must degrade to the
    /// proportional ceiling instead of swallowing itself.
    func testShortWindowsFallBackToTheProportionalCeiling() {
        let cramped = height(whereBandOccupies: 0.60, lineHeight: line)
        let stops = EdgeFade.stops(forHeight: cramped, lineHeight: line)
        XCTAssertLessThanOrEqual(stops.opaque, 0.30 + 0.0001, "ceiling did not clamp a cramped window")
        XCTAssertGreaterThanOrEqual(1 - 2 * stops.opaque, 0.40)
    }

    func testStopsStayOrderedAtExtremeHeights() {
        for height in [1.0, 10.0, 100.0, 200.0, 300.0, 400.0, 4000.0] as [CGFloat] {
            let stops = EdgeFade.stops(forHeight: height, lineHeight: line)
            XCTAssertGreaterThanOrEqual(stops.clear, 0, "height \(height)")
            XCTAssertLessThan(stops.clear, stops.opaque, "clear must precede opaque at height \(height)")
            XCTAssertLessThan(stops.opaque, 1 - stops.opaque,
                              "top and bottom ramps must not cross at height \(height)")
        }
    }

    func testZeroAndNegativeInputsDoNotProduceInvalidStops() {
        for height in [0.0, -100.0] as [CGFloat] {
            let stops = EdgeFade.stops(forHeight: height, lineHeight: line)
            XCTAssertTrue(stops.clear.isFinite && stops.opaque.isFinite, "height \(height)")
            XCTAssertLessThan(stops.clear, stops.opaque, "height \(height)")
        }
        let stops = EdgeFade.stops(forHeight: 1440, lineHeight: 0)
        XCTAssertTrue(stops.clear.isFinite && stops.opaque.isFinite)
        XCTAssertLessThan(stops.clear, stops.opaque)
    }
}
