// Tests/WhitespaceTests/PasteNormalizerTests.swift
import XCTest
import AppKit
@testable import Whitespace

final class PasteNormalizerTests: XCTestCase {

    // Fonts that reliably carry the symbolic traits, independent of which
    // concrete family the test machine resolves them to.
    private func font(traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let base = NSFont.systemFont(ofSize: 12).fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: base, size: 12)!
    }
    private var boldFont: NSFont   { font(traits: .bold) }
    private var italicFont: NSFont { font(traits: .italic) }

    func testDetectsBoldAndItalicStripsUnderline() {
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "b", attributes: [.font: boldFont]))
        s.append(NSAttributedString(string: "i", attributes: [.font: italicFont]))
        s.append(NSAttributedString(string: "u",
            attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue]))

        // Underline carries no meaning in the app (markdown cannot express
        // it); underlined sources classify as plain.
        XCTAssertEqual(PasteNormalizer.styledRuns(from: s), [
            StyledRun(text: "b", bold: true,  italic: false),
            StyledRun(text: "i", bold: false, italic: true),
            StyledRun(text: "u", bold: false, italic: false),
        ])
    }

    func testStripsColorStrikethroughLinkAndSize() {
        let s = NSAttributedString(string: "x", attributes: [
            .foregroundColor:    NSColor.red,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .link:               URL(string: "https://example.com")!,
            .font:               NSFont.systemFont(ofSize: 99),
        ])
        XCTAssertEqual(PasteNormalizer.styledRuns(from: s),
                       [StyledRun(text: "x", bold: false, italic: false)])
    }

    func testStripsLeadingTabsAndSpacesPerLine() {
        let s = NSAttributedString(string: "\t  Alpha\n   Beta")
        XCTAssertEqual(PasteNormalizer.styledRuns(from: s).map(\.text).joined(),
                       "Alpha\nBeta")
    }

    func testPreservesInteriorWhitespace() {
        let s = NSAttributedString(string: "a   b")
        XCTAssertEqual(PasteNormalizer.styledRuns(from: s).map(\.text).joined(), "a   b")
    }

    func testNormalizesCRLFAndCR() {
        let s = NSAttributedString(string: "a\r\nb\rc")
        XCTAssertEqual(PasteNormalizer.styledRuns(from: s).map(\.text).joined(), "a\nb\nc")
    }

    func testWordStyleParagraphRoundTrips() {
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "\tThe ", attributes: [.foregroundColor: NSColor.blue]))
        s.append(NSAttributedString(string: "quick",  attributes: [.font: boldFont]))
        s.append(NSAttributedString(string: " brown ", attributes: [:]))
        s.append(NSAttributedString(string: "fox",    attributes: [.font: italicFont]))

        XCTAssertEqual(PasteNormalizer.styledRuns(from: s), [
            StyledRun(text: "The ",    bold: false, italic: false),
            StyledRun(text: "quick",   bold: true,  italic: false),
            StyledRun(text: " brown ", bold: false, italic: false),
            StyledRun(text: "fox",     bold: false, italic: true),
        ])
    }

    func testAttributedStringAppliesBaseStyle() {
        let pStyle = NSMutableParagraphStyle()
        pStyle.firstLineHeadIndent = 36
        let base: [NSAttributedString.Key: Any] = [
            .font:            NSFont.systemFont(ofSize: 20),
            .paragraphStyle:  pStyle,
            .foregroundColor: NSColor.green,
        ]
        let runs = [
            StyledRun(text: "a", bold: false, italic: false),
            StyledRun(text: "b", bold: true, italic: false),
        ]

        let out = PasteNormalizer.attributedString(runs: runs, baseAttributes: base)
        XCTAssertEqual(out.string, "ab")

        let a0 = out.attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual(a0[.paragraphStyle] as? NSParagraphStyle, pStyle)
        XCTAssertEqual(a0[.foregroundColor] as? NSColor, NSColor.green)
        XCTAssertEqual((a0[.font] as? NSFont)?.pointSize, 20)   // size from base

        let a1 = out.attributes(at: 1, effectiveRange: nil)
        XCTAssertEqual((a1[.font] as? NSFont)?.fontName, WhitespaceFont.bold)
    }
}
