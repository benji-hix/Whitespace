// Tests/WhitespaceTests/MarkdownTextDecodeTests.swift
import XCTest
@testable import Whitespace

final class MarkdownTextDecodeTests: XCTestCase {

    private func run(_ text: String, bold: Bool = false, italic: Bool = false) -> StyledRun {
        StyledRun(text: text, bold: bold, italic: italic, underline: false)
    }

    // MARK: - Decoding

    func testPlainProse() {
        XCTAssertEqual(MarkdownText.decode("just prose."), [run("just prose.")])
    }

    func testBoldItalicAndBoth() {
        XCTAssertEqual(MarkdownText.decode("**bold**"), [run("bold", bold: true)])
        XCTAssertEqual(MarkdownText.decode("*lean*"), [run("lean", italic: true)])
        XCTAssertEqual(
            MarkdownText.decode("***both***"),
            [run("both", bold: true, italic: true)]
        )
    }

    func testMixedSequence() {
        XCTAssertEqual(
            MarkdownText.decode("The **quick** brown *fox*."),
            [run("The "), run("quick", bold: true), run(" brown "),
             run("fox", italic: true), run(".")]
        )
    }

    func testEscapedCharactersBecomeLiterals() {
        XCTAssertEqual(MarkdownText.decode("2 \\* 3 = 6"), [run("2 * 3 = 6")])
        XCTAssertEqual(MarkdownText.decode("snake\\_case"), [run("snake_case")])
        XCTAssertEqual(MarkdownText.decode(#"C:\\path"#), [run(#"C:\path"#)])
    }

    func testEmptyStringDecodesToNoRuns() {
        XCTAssertEqual(MarkdownText.decode(""), [])
    }

    func testNewlinesPreserved() {
        XCTAssertEqual(MarkdownText.decode("a\n\nb"), [run("a\n\nb")])
    }

    func testCRLFNormalizedToLF() {
        XCTAssertEqual(MarkdownText.decode("a\r\nb\rc"), [run("a\nb\nc")])
    }

    func testBlockSyntaxIsNotInterpreted() {
        // Inline-only parsing: headings/lists stay literal text.
        XCTAssertEqual(MarkdownText.decode("# not a heading"), [run("# not a heading")])
        XCTAssertEqual(MarkdownText.decode("- not a list"), [run("- not a list")])
    }

    func testForeignLinkSyntaxFlattensToItsText() {
        // Known dialect limitation (documented): constructs beyond
        // bold/italic in files written elsewhere are normalized away.
        XCTAssertEqual(MarkdownText.decode("see [docs](https://x.y)"), [run("see docs")])
    }

    // MARK: - Round trips (encode then decode)

    private func roundTrip(_ runs: [StyledRun]) -> [StyledRun] {
        MarkdownText.decode(MarkdownText.encode(runs: runs))
    }

    func testRoundTripMixedProse() {
        let original = [
            run("The "), run("quick", bold: true), run(" brown "),
            run("fox", italic: true), run(" jumps "), run("high", bold: true, italic: true),
        ]
        XCTAssertEqual(roundTrip(original), original)
    }

    func testRoundTripAdjacentBoldThenItalic() {
        // Encodes to "**a***b*" — the delimiter-stack stress case.
        let original = [run("a", bold: true), run("b", italic: true)]
        XCTAssertEqual(roundTrip(original), original)
    }

    func testRoundTripEscapedProse() {
        let original = [run("2 * 3 = 6, snake_case, `tick` [x] <y> ~z~ C:\\path")]
        XCTAssertEqual(roundTrip(original), original)
    }

    func testRoundTripMultiline() {
        // Styled spaces cannot survive markdown (whitespace is hoisted
        // outside markers), so the round trip restyles the spaces as plain;
        // characters and visible styling are identical.
        let original = [run("one\ntwo", bold: true)]
        XCTAssertEqual(
            roundTrip(original),
            [run("one", bold: true), run("\n"), run("two", bold: true)]
        )
    }

    func testRoundTripHoistedWhitespaceRestylesSpacesOnly() {
        let original = [run(" padded ", bold: true)]
        XCTAssertEqual(
            roundTrip(original),
            [run(" "), run("padded", bold: true), run(" ")]
        )
    }

    func testRoundTripDropsUnderlineByDesign() {
        let original = [StyledRun(text: "u", bold: true, italic: false, underline: true)]
        XCTAssertEqual(roundTrip(original), [run("u", bold: true)])
    }
}
