// Tests/WhitespaceTests/ZenTextViewStyledRunsTests.swift
import XCTest
import AppKit
@testable import Whitespace

/// The faithful storage extractor: unlike PasteNormalizer's classifier it
/// must preserve text verbatim (leading whitespace, newlines) and map the
/// app's own font faces back to flags.
@MainActor
final class ZenTextViewStyledRunsTests: XCTestCase {

    private func makeView() -> ZenTextView {
        let tv = ZenTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        tv.applyColors(text: .black, cursor: .black, selection: .gray)
        tv.applyFont(size: 18, lineHeightMultiple: 1.6)
        return tv
    }

    private func run(_ text: String, bold: Bool = false, italic: Bool = false) -> StyledRun {
        StyledRun(text: text, bold: bold, italic: italic)
    }

    func testEmptyStorageExtractsNoRuns() {
        XCTAssertEqual(makeView().styledRuns, [])
    }

    func testRoundTripThroughStorage() {
        let tv = makeView()
        let original = [
            run("  leading spaces kept "),
            run("bold", bold: true),
            run("\nnew line "),
            run("both", bold: true, italic: true),
        ]
        tv.textStorage?.setAttributedString(
            PasteNormalizer.attributedString(runs: original, baseAttributes: tv.typingAttributes)
        )
        XCTAssertEqual(tv.styledRuns, original)
    }

    func testPlainTypingExtractsSinglePlainRun() {
        let tv = makeView()
        tv.insertText("hello world", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(tv.styledRuns, [run("hello world")])
    }

    func testBoldToggleProducesBoldRun() {
        let tv = makeView()
        tv.insertText("a", replacementRange: NSRange(location: 0, length: 0))
        tv.keyDown(with: NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
            windowNumber: 0, context: nil, characters: "b", charactersIgnoringModifiers: "b",
            isARepeat: false, keyCode: 11
        )!)
        tv.insertText("b", replacementRange: NSRange(location: 1, length: 0))
        XCTAssertEqual(tv.styledRuns, [run("a"), run("b", bold: true)])
    }
}
