// Tests/WhitespaceTests/FileStoreTests.swift
import XCTest
@testable import Whitespace

@MainActor
final class FileStoreTests: XCTestCase {
    var store: FileStore!
    var tmpURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        store = FileStore()
        tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".txt")
        try "hello world".write(to: tmpURL, atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpURL)
        try await super.tearDown()
    }

    func testOpenFileCreatesBuffer() async throws {
        try await store.open(url: tmpURL)
        XCTAssertEqual(store.buffers.count, 1)
        XCTAssertEqual(store.activeBuffer?.text, "hello world")
    }

    func testNewBufferAppendsUntitled() {
        store.newBuffer()
        XCTAssertEqual(store.buffers.count, 1)
        XCTAssertNil(store.activeBuffer?.url)
    }

    func testSaveWritesToDisk() async throws {
        try await store.open(url: tmpURL)
        store.updateActiveText("updated")
        try await store.saveActive()
        let content = try String(contentsOf: tmpURL, encoding: .utf8)
        XCTAssertEqual(content, "updated")
    }

    func testCloseActiveRemovesBuffer() async throws {
        try await store.open(url: tmpURL)
        store.closeActive()
        XCTAssertTrue(store.buffers.isEmpty)
    }
}
