// Tests/WhitespaceTests/EdgeFadeTests.swift
import XCTest
@testable import Whitespace

final class EdgeFadeTests: XCTestCase {
    /// The point of the change: the fade is a fixed height, so the readable
    /// band grows with the window instead of staying a constant fraction.
    func testFadeBandsAreAbsoluteNotProportional() {
        for height in [450.0, 900.0, 1440.0] as [CGFloat] {
            let stops = EdgeFade.stops(forHeight: height)
            XCTAssertEqual(stops.clear * height, EdgeFade.clearBand, accuracy: 0.5,
                           "clear band should be \(EdgeFade.clearBand)pt at height \(height)")
            XCTAssertEqual(stops.opaque * height, EdgeFade.clearBand + EdgeFade.fadeBand, accuracy: 0.5,
                           "fade should end at a fixed point offset at height \(height)")
        }
    }

    func testReadableAreaGrowsWithHeight() {
        let small = 1 - 2 * EdgeFade.stops(forHeight: 450).opaque
        let large = 1 - 2 * EdgeFade.stops(forHeight: 1440).opaque
        XCTAssertGreaterThan(large, small)
        // The old proportional mask pinned this at 40% forever.
        XCTAssertEqual(small, 0.40, accuracy: 0.02, "450pt keeps the tuned proportions")
        XCTAssertGreaterThan(large, 0.75, "fullscreen should be mostly readable text")
    }

    /// Below ~300pt the fixed bands would exceed the window; the clamp has to
    /// keep the stops ordered rather than inverting the gradient.
    func testStopsStayOrderedAtExtremeHeights() {
        for height in [1.0, 10.0, 100.0, 200.0, 300.0, 400.0, 4000.0] as [CGFloat] {
            let stops = EdgeFade.stops(forHeight: height)
            XCTAssertGreaterThanOrEqual(stops.clear, 0, "height \(height)")
            XCTAssertLessThan(stops.clear, stops.opaque, "clear must precede opaque at height \(height)")
            XCTAssertLessThan(stops.opaque, 1 - stops.opaque,
                              "top and bottom ramps must not cross at height \(height)")
        }
    }

    func testZeroAndNegativeHeightsDoNotProduceInvalidStops() {
        for height in [0.0, -100.0] as [CGFloat] {
            let stops = EdgeFade.stops(forHeight: height)
            XCTAssertTrue(stops.clear.isFinite && stops.opaque.isFinite, "height \(height)")
            XCTAssertLessThan(stops.clear, stops.opaque, "height \(height)")
        }
    }
}
