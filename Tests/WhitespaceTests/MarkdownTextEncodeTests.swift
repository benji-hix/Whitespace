// Tests/WhitespaceTests/MarkdownTextEncodeTests.swift
import XCTest
@testable import Whitespace

final class MarkdownTextEncodeTests: XCTestCase {

    private func run(_ text: String, bold: Bool = false, italic: Bool = false) -> StyledRun {
        StyledRun(text: text, bold: bold, italic: italic)
    }

    // MARK: - Markers

    func testPlainTextPassesThrough() {
        XCTAssertEqual(MarkdownText.encode(runs: [run("just prose.")]), "just prose.")
    }

    func testBoldUsesDoubleAsterisks() {
        XCTAssertEqual(MarkdownText.encode(runs: [run("bold", bold: true)]), "**bold**")
    }

    func testItalicUsesSingleAsterisk() {
        XCTAssertEqual(MarkdownText.encode(runs: [run("lean", italic: true)]), "*lean*")
    }

    func testBoldItalicUsesTripleAsterisks() {
        XCTAssertEqual(
            MarkdownText.encode(runs: [run("both", bold: true, italic: true)]),
            "***both***"
        )
    }

    func testMixedSequence() {
        let runs = [
            run("The "), run("quick", bold: true), run(" brown "),
            run("fox", italic: true), run("."),
        ]
        XCTAssertEqual(MarkdownText.encode(runs: runs), "The **quick** brown *fox*.")
    }

    func testEmptyRunEmitsNothing() {
        XCTAssertEqual(MarkdownText.encode(runs: [run(""), run("a")]), "a")
        XCTAssertEqual(MarkdownText.encode(runs: [run("", bold: true)]), "")
    }

    // MARK: - Whitespace hoisting (emphasis cannot wrap spaces)

    func testLeadingAndTrailingSpacesHoistedOutsideMarkers() {
        XCTAssertEqual(
            MarkdownText.encode(runs: [run(" padded ", bold: true)]),
            " **padded** "
        )
    }

    func testWhitespaceOnlyStyledRunEmitsPlainWhitespace() {
        XCTAssertEqual(MarkdownText.encode(runs: [run("   ", bold: true)]), "   ")
    }

    func testHoistingAcrossRunBoundary() {
        // "bold " + plain: marker must close before the space
        let runs = [run("bold ", bold: true), run("then")]
        XCTAssertEqual(MarkdownText.encode(runs: runs), "**bold** then")
    }

    // MARK: - Newlines (emphasis is reopened per line)

    func testStyledRunSpanningNewlineClosesAndReopensMarkers() {
        XCTAssertEqual(
            MarkdownText.encode(runs: [run("one\ntwo", bold: true)]),
            "**one**\n**two**"
        )
    }

    func testPlainNewlinesPreserved() {
        XCTAssertEqual(MarkdownText.encode(runs: [run("a\n\nb")]), "a\n\nb")
    }

    // MARK: - Escaping (prose must round-trip verbatim)

    func testEscapesAsterisksInProse() {
        XCTAssertEqual(MarkdownText.encode(runs: [run("2 * 3 = 6")]), "2 \\* 3 = 6")
    }

    func testEscapesUnderscores() {
        XCTAssertEqual(MarkdownText.encode(runs: [run("snake_case")]), "snake\\_case")
    }

    func testEscapesBackticksBracketsAngleAndTilde() {
        XCTAssertEqual(
            MarkdownText.encode(runs: [run("`code` [link] <tag> ~~strike~~")]),
            "\\`code\\` \\[link] \\<tag> \\~\\~strike\\~\\~"
        )
    }

    func testEscapesBackslashItself() {
        XCTAssertEqual(MarkdownText.encode(runs: [run(#"C:\path"#)]), #"C:\\path"#)
    }

    func testEscapesInsideStyledRuns() {
        XCTAssertEqual(
            MarkdownText.encode(runs: [run("a*b", bold: true)]),
            "**a\\*b**"
        )
    }
}
