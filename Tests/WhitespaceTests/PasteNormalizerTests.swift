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

    func testDetectsBoldItalicUnderline() {
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "b", attributes: [.font: boldFont]))
        s.append(NSAttributedString(string: "i", attributes: [.font: italicFont]))
        s.append(NSAttributedString(string: "u",
            attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue]))

        XCTAssertEqual(PasteNormalizer.styledRuns(from: s), [
            StyledRun(text: "b", bold: true,  italic: false, underline: false),
            StyledRun(text: "i", bold: false, italic: true,  underline: false),
            StyledRun(text: "u", bold: false, italic: false, underline: true),
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
                       [StyledRun(text: "x", bold: false, italic: false, underline: false)])
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
            StyledRun(text: "The ",    bold: false, italic: false, underline: false),
            StyledRun(text: "quick",   bold: true,  italic: false, underline: false),
            StyledRun(text: " brown ", bold: false, italic: false, underline: false),
            StyledRun(text: "fox",     bold: false, italic: true,  underline: false),
        ])
    }
}
