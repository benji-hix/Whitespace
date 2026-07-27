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
    static let clearLines: CGFloat = 1.0
    /// Lines over which text ramps from invisible to fully readable. This is
    /// the number you actually see dissolving at each edge.
    static let fadeLines: CGFloat = 7.5

    /// Ceiling on how much of a *short* window the effect may eat. Without it
    /// the line-based bands would consume a small window entirely — 7.5 lines
    /// at each edge is 480pt, more than a 450pt window has. At and above about
    /// 900pt the line bands apply in full; below that the fade degrades to
    /// these proportions, which are the ones the original small window was
    /// tuned to.
    private static let maxClearFraction: CGFloat = 0.10
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
    /// Clamped so a short window degrades to a thinner fade rather than
    /// inverting the gradient stops.
    static func stops(forHeight height: CGFloat, lineHeight: CGFloat) -> (clear: CGFloat, opaque: CGFloat) {
        let h = max(height, 1)
        let line = max(lineHeight, 1)
        let clear  = min(clearLines * line / h, maxClearFraction)
        let opaque = min((clearLines + fadeLines) * line / h, maxOpaqueFraction)
        return (clear, opaque)
    }
}
