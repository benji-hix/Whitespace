// Tests/WhitespaceTests/EdgeFadeTests.swift
import XCTest
@testable import Whitespace

final class EdgeFadeTests: XCTestCase {
    /// The app's own defaults: 18pt Crimson Pro at 1.6 line spacing.
    private var line: CGFloat { EdgeFade.lineHeight(fontSize: 18, lineHeightMultiple: 1.6) }

    func testLineHeightMatchesTypeSettings() {
        // CrimsonPro-Light 18pt has a 20pt natural line, so 1.6 gives 32pt.
        XCTAssertEqual(EdgeFade.lineHeight(fontSize: 18, lineHeightMultiple: 1.6), 32, accuracy: 0.5)
        XCTAssertEqual(EdgeFade.lineHeight(fontSize: 18, lineHeightMultiple: 1.0), 20, accuracy: 0.5)
        // Scales with type size rather than being pinned to points.
        XCTAssertGreaterThan(
            EdgeFade.lineHeight(fontSize: 24, lineHeightMultiple: 1.6),
            EdgeFade.lineHeight(fontSize: 18, lineHeightMultiple: 1.6)
        )
    }

    /// The requested depth: 7–8 lines visibly dissolve at each edge on a large
    /// window, rather than the ~2 the original bands gave. Measured on the ramp
    /// alone, since the fully-clear band is invisible and is not what is judged.
    func testRampCoversTheRequestedNumberOfLinesOnLargeWindows() {
        for height in [1000.0, 1200.0, 1440.0] as [CGFloat] {
            let stops = EdgeFade.stops(forHeight: height, lineHeight: line)
            let rampLines = (stops.opaque - stops.clear) * height / line
            XCTAssertGreaterThanOrEqual(rampLines, 7.0, "only \(rampLines) lines dissolve at height \(height)")
            XCTAssertLessThanOrEqual(rampLines, 8.0, "\(rampLines) lines dissolve at height \(height)")
        }
    }

    /// Depth is a count of lines, so a bigger type size fades a proportionally
    /// deeper band rather than fewer lines.
    func testFadeDepthFollowsTypeSize() {
        let height: CGFloat = 1440
        let small = EdgeFade.lineHeight(fontSize: 14, lineHeightMultiple: 1.6)
        let large = EdgeFade.lineHeight(fontSize: 24, lineHeightMultiple: 1.6)
        let smallStops = EdgeFade.stops(forHeight: height, lineHeight: small)
        let largeStops = EdgeFade.stops(forHeight: height, lineHeight: large)
        let smallLines = (smallStops.opaque - smallStops.clear) * height / small
        let largeLines = (largeStops.opaque - largeStops.clear) * height / large
        XCTAssertEqual(smallLines, largeLines, accuracy: 0.3, "line count should not depend on type size")
        XCTAssertGreaterThan(
            EdgeFade.stops(forHeight: height, lineHeight: large).opaque,
            EdgeFade.stops(forHeight: height, lineHeight: small).opaque,
            "larger type should fade a deeper band in points"
        )
    }

    func testReadableAreaStillGrowsWithHeight() {
        let small = 1 - 2 * EdgeFade.stops(forHeight: 450, lineHeight: line).opaque
        let large = 1 - 2 * EdgeFade.stops(forHeight: 1440, lineHeight: line).opaque
        XCTAssertGreaterThan(large, small)
        XCTAssertGreaterThan(large, 0.60, "fullscreen should still be mostly readable text")
    }

    /// 7.5 lines at each edge is 480pt, more than a short window has. The
    /// proportional ceiling has to take over instead of swallowing the window.
    func testShortWindowsFallBackToProportionalBands() {
        for height in [400.0, 450.0, 700.0] as [CGFloat] {
            let stops = EdgeFade.stops(forHeight: height, lineHeight: line)
            XCTAssertLessThanOrEqual(stops.opaque, 0.30, "height \(height) lost too much to the fade")
            XCTAssertGreaterThanOrEqual(1 - 2 * stops.opaque, 0.40,
                                        "height \(height) should keep at least 40% readable")
        }
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
