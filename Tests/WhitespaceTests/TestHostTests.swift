// Tests/WhitespaceTests/TestHostTests.swift
import XCTest
import AppKit
@testable import Whitespace

/// The hosted test bundle launches the real app, under the owner's bundle id,
/// so it can see the owner's saved window state and autosaved drafts.
@MainActor
final class TestHostTests: XCTestCase {
    func testHostKnowsItIsUnderTest() {
        XCTAssertTrue(AppDelegate.isRunningTests)
    }

    /// If restoration ran, the owner's last session would reopen inside the
    /// test host. Tests create their documents directly and never add them to
    /// the controller, so the controller should hold none.
    func testHostRestoredNoDocuments() {
        XCTAssertEqual(NSDocumentController.shared.documents.map(\.displayName), [])
    }
}

