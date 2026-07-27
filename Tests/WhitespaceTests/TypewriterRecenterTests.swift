// Tests/WhitespaceTests/TypewriterRecenterTests.swift
import XCTest
import AppKit
@testable import Whitespace

/// End-to-end typewriter behaviour. `TypewriterScrollTests` covers the decision
/// math in isolation; this covers whether the view ever *asks* it.
///
/// Scope note, measured rather than assumed: the open "recentering doesn't
/// follow sustained typing" bug does **not** reproduce here at any realistic
/// typing rate. Lines every 1.4s, lines every 0.35s, and continuous prose at 20
/// insertions/sec all hold the caret near 50% of the viewport. It only breaks at
/// ~50 lines/sec, where the 0.68s animation floor cannot keep up — a synthetic
/// rate, so that is a finding, not a reproduction. What this file does pin is
/// the one defect that was proved: no scroll target on an empty final line.
@MainActor
final class TypewriterRecenterTests: XCTestCase {
    private var window: NSWindow!
    private var scrollView: NSScrollView!
    private var textView: ZenTextView!

    private let viewportHeight: CGFloat = 600

    override func setUp() {
        super.setUp()
        let frame = NSRect(x: 0, y: 0, width: 500, height: viewportHeight)
        textView = ZenTextView(frame: frame)
        // Mirror ZenTextViewRepresentable.makeNSView. Without the unbounded
        // maxSize the view cannot grow past its initial frame, the scroll view
        // has nothing to scroll into, and the harness measures its own
        // inertness rather than the recenter decision.
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        scrollView = NSScrollView(frame: frame)
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scrollView
        window.makeFirstResponder(textView)
        textView.applyFont(size: 18, lineHeightMultiple: 1.6)
        // kineticDuration divides by scrollSpeed, so this collapses the ~0.7s
        // scroll animation to a few milliseconds and keeps the suite quick.
        // Correctness does not depend on it — the assertions read the recenter
        // target, not the animated position.
        textView.scrollSpeed = 100
        pump()
    }

    override func tearDown() {
        window = nil; scrollView = nil; textView = nil
        super.tearDown()
    }

    /// `handleSelectionChange` defers the recenter by one runloop turn, so the
    /// main queue has to drain before the viewport reflects the edit.
    private func pump(_ seconds: TimeInterval = 0.35) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func typeLine(_ s: String, cadence: TimeInterval = 0.35) {
        textView.insertText(s, replacementRange: NSRange(location: textView.string.utf16.count, length: 0))
        // An offscreen window never draws, so TK2's viewport layout controller
        // never runs and the text view never resizes itself. Drive it by hand.
        if let tlm = textView.textLayoutManager {
            tlm.ensureLayout(for: tlm.documentRange)
        }
        textView.sizeToFit()
        pump(cadence)
    }

    /// Where the caret sits relative to the viewport the recenter **decided
    /// on**, as a percentage of viewport height.
    ///
    /// Deliberately measured against `currentScrollTarget` rather than the clip
    /// view's actual origin. `recenter` applies the target through
    /// `animator().setBoundsOrigin`, and Core Animation does not step while the
    /// display is asleep — so the real origin stays at 0 overnight and these
    /// tests reported a phantom regression with numbers identical to the real
    /// one. The decision is ours and is what the fix restored; committing the
    /// animation is AppKit's.
    private func caretPercentOfTargetViewport(
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> CGFloat {
        let caret = try XCTUnwrap(textView.currentCursorBarRect(), file: file, line: line)
        let target = textView.currentScrollTarget
        // Once anything has been typed a target must exist. NaN means recenter
        // never produced one, which is the defect itself — fail, never skip.
        try XCTUnwrap(target.isNaN ? nil : target,
                      "recenter produced no scroll target at all", file: file, line: line)
        return (caret.midY - target) / viewportHeight * 100
    }

    /// TK2 returns no layout fragment for a location at end-of-text, which is
    /// where the caret sits on the empty line Return just created.
    /// `caretCenterTargetY` used to bail there — no fragment, no target, no
    /// scroll — so the viewport froze for exactly that keystroke and only caught
    /// up once the next character was typed.
    ///
    /// This discriminates: without the `layoutFragment(atOrBefore:)` fallback no
    /// target is produced at all and `currentScrollTarget` stays NaN.
    func testViewportFollowsReturnAtEndOfDocument() throws {
        for i in 1...12 {
            typeLine("line \(i)\n", cadence: 0.2)
        }
        XCTAssertFalse(textView.currentScrollTarget.isNaN,
                       "Return at end-of-document produced no scroll target at all")
        let afterReturns = try caretPercentOfTargetViewport()
        XCTAssertLessThanOrEqual(afterReturns, 70, "caret sank to \(afterReturns)% of the viewport")
        XCTAssertGreaterThanOrEqual(afterReturns, 30, "caret rose above the deadzone")
    }

    /// The typewriter promise at a realistic writing pace.
    func testCaretHoldsCentreDuringSustainedTyping() throws {
        var worst: CGFloat = 0
        for i in 1...16 {
            typeLine("line \(i)\n", cadence: 0.2)
            worst = max(worst, abs(try caretPercentOfTargetViewport() - 50))
        }
        XCTAssertLessThanOrEqual(worst, 20, "caret drifted \(worst)% from centre at a realistic typing rate")
    }

    /// Continuous prose inside one paragraph, which takes TypewriterScroll's
    /// same-paragraph deadzone branch rather than the paragraph-change branch.
    func testCaretHoldsCentreDuringContinuousProse() throws {
        for _ in 1...120 {
            textView.insertText("writing ", replacementRange: NSRange(location: textView.string.utf16.count, length: 0))
            if let tlm = textView.textLayoutManager { tlm.ensureLayout(for: tlm.documentRange) }
            textView.sizeToFit()
            pump(0.05)
        }
        let pct = try caretPercentOfTargetViewport()
        XCTAssertLessThanOrEqual(abs(pct - 50), 25, "caret sat at \(pct)% of the viewport after continuous prose")
    }

    /// The typewriter inset is half the viewport, so it has to follow the
    /// scroll view's size. It used to be driven by NSWindow.didResizeNotification
    /// alone, which arrives before AppKit re-lays-out the scroll view: entering
    /// fullscreen, the window reported 1440 while contentSize was still 486, so
    /// the inset stayed at 243 and the first line of an empty document sat at
    /// 17% of the screen — inside the top fade — instead of centred.
    ///
    /// This resizes only the scroll view, so it fails outright without the
    /// frame-change observer: nothing would notice the viewport had changed.
    func testTypewriterInsetFollowsTheViewportNotTheWindow() throws {
        XCTAssertEqual(textView.textContainerInset.height, viewportHeight / 2, accuracy: 1,
                       "inset should start at half the viewport")

        let taller: CGFloat = 1440
        scrollView.setFrameSize(NSSize(width: 500, height: taller))
        pump(0.3)

        XCTAssertEqual(textView.textContainerInset.height, scrollView.contentSize.height / 2, accuracy: 1,
                       "inset must track the viewport it is centring within")
        XCTAssertEqual(textView.textContainerInset.height, taller / 2, accuracy: 1)
    }

    /// The point of the inset: one line of text on an otherwise empty page sits
    /// in the middle of the viewport, not up in the fade.
    func testFirstLineOfAnEmptyPageIsCentred() throws {
        scrollView.setFrameSize(NSSize(width: 500, height: 1440))
        pump(0.3)
        textView.insertText("Testing 123", replacementRange: NSRange(location: 0, length: 0))
        textView.textLayoutManager.map { $0.ensureLayout(for: $0.documentRange) }
        textView.sizeToFit()
        pump(0.3)

        let caret = try XCTUnwrap(textView.currentCursorBarRect())
        let viewportTop = textView.currentScrollTarget.isNaN ? 0 : textView.currentScrollTarget
        let pct = (caret.midY - viewportTop) / 1440 * 100
        XCTAssertEqual(pct, 50, accuracy: 10,
                       "first line sat at \(pct)% of the viewport instead of centred")
    }
}
