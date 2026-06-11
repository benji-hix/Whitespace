// Sources/Whitespace/Editor/TypewriterScroll.swift
import Foundation

/// The typewriter-mode scroll decision, separated from TextKit so it can be
/// tested as plain geometry. All Y values share the text view's coordinate
/// space (container coordinates plus inset).
enum TypewriterScroll {
    struct Input {
        var caretMinY: CGFloat
        var caretMaxY: CGFloat
        var paragraphMidY: CGFloat
        var paragraphOffset: Int
        var anchoredParagraphOffset: Int?
        var viewportY: CGFloat
        var viewportHeight: CGFloat
    }

    /// Desired clip-view bounds origin Y, or nil for "don't scroll".
    ///
    /// Two regimes:
    /// 1. **Paragraph change** (offset differs from the anchor, or no anchor):
    ///    place the paragraph's midpoint at 45% of the viewport, clamped so
    ///    the caret stays inside the middle 70% when the paragraph is taller
    ///    than the safe zone.
    /// 2. **Same paragraph**: hold position while the caret stays inside the
    ///    central deadzone (middle 40%); otherwise scroll just enough to
    ///    return it to the opposite deadzone edge — the typewriter
    ///    "page flip" without per-keystroke drift.
    static func target(for input: Input) -> CGFloat? {
        let h = input.viewportHeight

        if input.anchoredParagraphOffset != input.paragraphOffset {
            var target = input.paragraphMidY - h * 0.45
            let safeMin = h * 0.15
            let safeMax = h * 0.85
            if input.caretMinY - target < safeMin {
                target = input.caretMinY - safeMin
            } else if input.caretMaxY - target > safeMax {
                target = input.caretMaxY - safeMax
            }
            return max(0, target.rounded())
        }

        let deadzoneTop    = input.viewportY + h * 0.30
        let deadzoneBottom = input.viewportY + h * 0.70
        if input.caretMinY >= deadzoneTop && input.caretMaxY <= deadzoneBottom {
            return nil
        }
        let target: CGFloat
        if input.caretMaxY > deadzoneBottom {
            target = input.caretMinY - h * 0.30
        } else {
            target = input.caretMaxY - h * 0.70
        }
        return max(0, target.rounded())
    }
}
