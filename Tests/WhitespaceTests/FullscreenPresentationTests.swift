// Tests/WhitespaceTests/FullscreenPresentationTests.swift
import XCTest
import AppKit
@testable import Whitespace

/// AppKit raises an exception for an invalid presentation set, and an uncaught
/// one would take the window down on entering fullscreen. The rules are checked
/// here instead of by assigning a set to `NSApp.presentationOptions`, which in
/// the test host would also change the owner's real screen.
final class FullscreenPresentationTests: XCTestCase {
    func testFullscreenOptionsAreAValidCombination() {
        let options = FullscreenPresentation.options
        XCTAssertTrue(options.contains(.fullScreen))
        XCTAssertTrue(options.contains(.autoHideMenuBar), "menus must stay reachable by mouse")
        XCTAssertTrue(FullscreenPresentation.isValid(options))
    }

    func testValidatorAcceptsTheHiddenMenuBarAlternative() {
        XCTAssertTrue(FullscreenPresentation.isValid([.fullScreen, .hideMenuBar, .hideDock]))
    }

    func testValidatorRejectsTheDocumentedInvalidSets() {
        let invalid: [NSApplication.PresentationOptions] = [
            [.fullScreen, .autoHideMenuBar],
            [.fullScreen, .hideMenuBar],
            [.fullScreen, .hideMenuBar, .autoHideDock],
            [.fullScreen, .hideDock, .autoHideDock],
            [.fullScreen, .hideMenuBar, .autoHideMenuBar, .hideDock],
            [.fullScreen, .disableProcessSwitching],
            [.autoHideToolbar, .autoHideMenuBar, .autoHideDock],
        ]
        for options in invalid {
            XCTAssertFalse(FullscreenPresentation.isValid(options), "accepted \(options.rawValue)")
        }
    }
}
