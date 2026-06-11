// Tests/WhitespaceTests/ZenTextViewKeyDownTests.swift
import XCTest
import AppKit
@testable import Whitespace

/// Characterization of the keyDown dispatch that ZenTextView itself owns —
/// the chords with no menu equivalent. Menu-equivalent chords (⌘S, ⌘N, …)
/// are dispatched by AppKit's menu system before keyDown and are covered by
/// the menu wiring, not here.
@MainActor
final class ZenTextViewKeyDownTests: XCTestCase {

    private func makeView() -> ZenTextView {
        let tv = ZenTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        tv.applyColors(text: .black, cursor: .black, selection: .gray)
        tv.applyFont(size: 18, lineHeightMultiple: 1.6)
        return tv
    }

    private func chord(_ characters: String, keyCode: UInt16,
                       _ flags: NSEvent.ModifierFlags = [.command]) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: keyCode
        )!
    }

    func testCmdPlusAndMinusFireFontSizeCallbacks() {
        let tv = makeView()
        var increased = false
        var decreased = false
        tv.onIncreaseFontSize = { increased = true }
        tv.onDecreaseFontSize = { decreased = true }
        tv.keyDown(with: chord("=", keyCode: 24))
        tv.keyDown(with: chord("-", keyCode: 27))
        XCTAssertTrue(increased)
        XCTAssertTrue(decreased)
    }

    func testCmdBTogglesBoldTypingAttribute() {
        let tv = makeView()
        tv.keyDown(with: chord("b", keyCode: 11))
        let font = tv.typingAttributes[.font] as? NSFont
        XCTAssertEqual(font?.fontName, WhitespaceFont.bold)

        tv.keyDown(with: chord("b", keyCode: 11))
        let font2 = tv.typingAttributes[.font] as? NSFont
        XCTAssertEqual(font2?.fontName, WhitespaceFont.regular)
    }

    func testCmdITogglesItalicTypingAttribute() {
        let tv = makeView()
        tv.keyDown(with: chord("i", keyCode: 34))
        let font = tv.typingAttributes[.font] as? NSFont
        XCTAssertEqual(font?.fontName, WhitespaceFont.italic)
    }

    func testFormattingChordsAreSilentlyInertInPlainTextMode() {
        let tv = makeView()
        tv.formattingEnabled = false
        let before = (tv.typingAttributes[.font] as? NSFont)?.fontName

        tv.keyDown(with: chord("b", keyCode: 11))
        tv.keyDown(with: chord("i", keyCode: 34))

        let after = (tv.typingAttributes[.font] as? NSFont)?.fontName
        XCTAssertEqual(after, before)
        XCTAssertEqual(after, WhitespaceFont.regular)
    }

    func testCustomKeybindingActionDispatches() {
        let suite = UserDefaults(suiteName: "test-keydown")!
        suite.removePersistentDomain(forName: "test-keydown")
        let tv = makeView()
        tv.keybindingStore = KeybindingStore(defaults: suite)

        tv.string = "hello world"
        tv.setSelectedRange(NSRange(location: 5, length: 0))
        // killLine default: ⌃K (keyCode 40)
        tv.keyDown(with: chord("k", keyCode: 40, [.control]))
        XCTAssertEqual(tv.string, "hello")
    }
}
