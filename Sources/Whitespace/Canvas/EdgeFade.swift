// Sources/Whitespace/Canvas/EdgeFade.swift
import AppKit

/// Stop placement for the writing column's top and bottom fade, as fractions of
/// the column height. Pure geometry so it can be tested without a view.
///
/// The bands are measured in **lines of text**, not points and not fractions of
/// the window. Fractional stops made the vignette grow with the display — only
/// the middle 40% of the height was ever fully opaque, so a 1440pt screen hid
/// 864pt of it. Fixed points fixed that but silently changed depth whenever the
/// font size or line spacing changed. Lines are the unit the effect is actually
/// judged in: "about this many lines dissolve at each edge", at any type size.
enum EdgeFade {
    /// Lines fully hidden at the very edge. Kept to one: this band is invisible
    /// by definition, so it is not what the effect is judged by — the ramp is.
    static let clearLines: CGFloat = 4.5
    /// Lines over which text ramps from invisible to fully readable. This is
    /// the number you actually see dissolving at each edge.
    static let fadeLines: CGFloat = 8.5

    /// Ceiling on how much of a window the effect may eat, so the line-based
    /// bands can never swallow a short window or a large type size. Below the
    /// height where the bands fit, the fade degrades to these proportions —
    /// the ones the original small window was tuned to — and at least 40% of
    /// any window stays fully readable.
    ///
    /// The two `Lines` values above are taste, tuned by eye against a real
    /// screen. `EdgeFadeTests` deliberately asserts no particular depth; it
    /// derives its heights from whatever they are set to, so tuning them does
    /// not break the suite.
    private static let maxOpaqueFraction: CGFloat = 0.30

    /// Height of one laid-out line for the given type settings, matching what
    /// `ZenTextView.applyFont` gives TextKit.
    static func lineHeight(fontSize: CGFloat, lineHeightMultiple: CGFloat) -> CGFloat {
        let font = NSFont(name: WhitespaceFont.regular, size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize)
        let natural = font.ascender + abs(font.descender) + font.leading
        return natural * max(lineHeightMultiple, 0.1)
    }

    /// Fractions measured from the top edge; the bottom mirrors them.
    static func stops(forHeight height: CGFloat, lineHeight: CGFloat) -> (clear: CGFloat, opaque: CGFloat) {
        let h = max(height, 1)
        let line = max(lineHeight, 1)
        let clearPoints  = clearLines * line
        let opaquePoints = (clearLines + fadeLines) * line

        // When the band will not fit, scale it as a unit rather than clamping
        // each stop on its own. Independent clamps kept the clear/ramp split
        // from holding: the outer stop came off its limit at a different height
        // than the inner one, so ramp depth briefly *dipped* as the window grew
        // (8.63 lines down to 8.51 between about 1387pt and 1440pt at the
        // current settings). Scaling keeps the split constant and makes depth
        // rise monotonically to the configured value.
        let scale = min(1, maxOpaqueFraction * h / max(opaquePoints, 1))
        return (clear: clearPoints * scale / h, opaque: opaquePoints * scale / h)
    }
}
