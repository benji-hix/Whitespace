// Tests/WhitespaceTests/ZenTextViewPasteTests.swift
import XCTest
import AppKit
@testable import Whitespace

/// End-to-end coverage of the real paste/drag hook: writes rich RTF to a
/// pasteboard and drives `ZenTextView.readSelection(from:)`, the same entry
/// point AppKit calls for both ⌘V and drag-and-drop.
@MainActor
final class ZenTextViewPasteTests: XCTestCase {

    private func boldFont(_ size: CGFloat) -> NSFont {
        let d = NSFont.systemFont(ofSize: size).fontDescriptor.withSymbolicTraits(.bold)
        return NSFont(descriptor: d, size: size)!
    }

    /// Builds a view configured the way `ZenTextViewRepresentable` does in
    /// production: colors first, then font (so `typingAttributes` carries the
    /// app's paragraph style and size).
    private func makeView() -> ZenTextView {
        let tv = ZenTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        tv.applyColors(text: .black, cursor: .black, selection: .gray)
        tv.applyFont(size: 18, lineHeightMultiple: 1.2)
        tv.string = ""
        return tv
    }

    private func pasteboard(with attr: NSAttributedString) -> NSPasteboard {
        let pb = NSPasteboard.withUniqueName()
        let rtf = attr.rtf(from: NSRange(location: 0, length: attr.length),
                           documentAttributes: [:])!
        pb.clearContents()
        pb.setData(rtf, forType: .rtf)
        return pb
    }

    func testPasteNormalizesRichText() {
        let src = NSMutableAttributedString()
        src.append(NSAttributedString(string: "\tHello ", attributes: [.foregroundColor: NSColor.red]))
        src.append(NSAttributedString(string: "bold",  attributes: [.font: boldFont(40)]))
        src.append(NSAttributedString(string: " ",     attributes: [:]))
        src.append(NSAttributedString(string: "under", attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue]))

        let tv = makeView()
        let ok = tv.readSelection(from: pasteboard(with: src))
        XCTAssertTrue(ok)

        // Leading tab stripped; bold kept as a mark, not characters.
        XCTAssertEqual(tv.string, "Hello bold under")

        let storage = tv.textStorage!
        let ns = tv.string as NSString

        // Source red color did not survive.
        let head = storage.attributes(at: 0, effectiveRange: nil)
        XCTAssertNotEqual(head[.foregroundColor] as? NSColor, NSColor.red)

        // App paragraph style applied (firstLineHeadIndent = size * 2 = 36).
        XCTAssertEqual((head[.paragraphStyle] as? NSParagraphStyle)?.firstLineHeadIndent, 36)

        // Underline does not survive paste — it has no meaning in the app.
        let underAttrs = storage.attributes(at: ns.range(of: "under").location, effectiveRange: nil)
        XCTAssertNil(underAttrs[.underlineStyle])
        XCTAssertNil(head[.underlineStyle])

        // Source 40pt size did not survive — everything is the app's 18pt.
        XCTAssertEqual((head[.font] as? NSFont)?.pointSize, 18)
        let boldAttrs = storage.attributes(at: ns.range(of: "bold").location, effectiveRange: nil)
        XCTAssertEqual((boldAttrs[.font] as? NSFont)?.pointSize, 18)
    }

    func testPasteStripsAllFormattingInPlainTextMode() {
        let tv = makeView()
        tv.formattingEnabled = false

        let src = NSAttributedString(string: "loud", attributes: [.font: boldFont(20)])
        let ok = tv.readSelection(from: pasteboard(with: src))
        XCTAssertTrue(ok)

        XCTAssertEqual(tv.styledRuns, [StyledRun(text: "loud", bold: false, italic: false)])
    }

    func testPasteReplacesSelectionAndFiresChangeNotification() {
        let tv = makeView()
        tv.string = "XXXX"
        tv.setSelectedRange(NSRange(location: 1, length: 2))  // select the middle "XX"

        var notified = false
        let token = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification, object: tv, queue: nil) { _ in notified = true }
        defer { NotificationCenter.default.removeObserver(token) }

        let src = NSAttributedString(string: "yy")
        _ = tv.readSelection(from: pasteboard(with: src))

        XCTAssertEqual(tv.string, "XyyX")          // selection replaced
        XCTAssertTrue(notified)                     // didChangeText() fired → autosave path
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 3, length: 0))  // caret after insert
    }
}
