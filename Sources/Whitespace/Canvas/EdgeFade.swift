// Sources/Whitespace/Canvas/EdgeFade.swift
import CoreGraphics

/// Stop placement for the writing column's top and bottom fade, as fractions of
/// the column height. Pure geometry so it can be tested without a view.
///
/// The bands are absolute point heights, not fractions. Fractional stops
/// (0.1 / 0.3) meant the vignette grew with the window: 90pt of fade at 450pt
/// tall but 288pt of fade plus a 144pt blank band at 1440pt, so only the middle
/// 40% of the height was ever fully opaque no matter how large the display.
/// Fixed bands keep the reading experience identical at every size — a bigger
/// window buys more readable text rather than more vignette.
enum EdgeFade {
    /// Fully transparent band at the very edge.
    static let clearBand: CGFloat = 44
    /// Transparent-to-opaque ramp immediately inside the clear band.
    static let fadeBand: CGFloat = 90

    /// Fractions measured from the top edge; the bottom mirrors them.
    /// Clamped so a short window degrades to a thinner fade rather than
    /// inverting the gradient stops.
    static func stops(forHeight height: CGFloat) -> (clear: CGFloat, opaque: CGFloat) {
        let h = max(height, 1)
        let clear  = min(clearBand / h, 0.40)
        let opaque = min((clearBand + fadeBand) / h, 0.45)
        return (clear, opaque)
    }
}
