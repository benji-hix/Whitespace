// Tests/WhitespaceTests/FileStoreAutoSaveTests.swift
import XCTest
@testable import Whitespace

@MainActor
final class FileStoreAutoSaveTests: XCTestCase {
    var store: FileStore!
    var urlA: URL!
    var urlB: URL!

    override func setUp() async throws {
        try await super.setUp()
        store = FileStore()
        urlA = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-a.txt")
        urlB = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-b.txt")
        try "original A".write(to: urlA, atomically: true, encoding: .utf8)
        try "original B".write(to: urlB, atomically: true, encoding: .utf8)
        try await store.open(url: urlA)
        try await store.open(url: urlB)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: urlA)
        try? FileManager.default.removeItem(at: urlB)
        try await super.tearDown()
    }

    private func drainAutoSaves() async {
        for task in store.autoSaveTasks.values { await task.value }
    }

    func testAutoSaveSavesTheEditedBufferNotTheActiveOne() async throws {
        // Edit A, schedule, then switch to B before the delay elapses.
        store.activeIndex = 0
        store.updateActiveText("edited A")
        store.scheduleAutoSave(delay: 1)
        store.activeIndex = 1
        await drainAutoSaves()

        XCTAssertEqual(try String(contentsOf: urlA, encoding: .utf8), "edited A")
        XCTAssertEqual(try String(contentsOf: urlB, encoding: .utf8), "original B")
    }

    func testSwitchTriggeredRescheduleDoesNotCancelPendingSave() async throws {
        // The CanvasView onChange fires again on buffer switch and schedules
        // an auto-save for the newly active buffer. That must not cancel A's
        // pending save.
        store.activeIndex = 0
        store.updateActiveText("edited A")
        store.scheduleAutoSave(delay: 1)
        store.activeIndex = 1
        store.scheduleAutoSave(delay: 1)
        await drainAutoSaves()

        XCTAssertEqual(try String(contentsOf: urlA, encoding: .utf8), "edited A")
    }

    func testNewEditDebouncesPendingSaveForSameBuffer() async throws {
        store.activeIndex = 0
        store.updateActiveText("first")
        store.scheduleAutoSave(delay: 1)
        store.updateActiveText("second")
        store.scheduleAutoSave(delay: 1)
        await drainAutoSaves()

        XCTAssertEqual(try String(contentsOf: urlA, encoding: .utf8), "second")
    }

    func testAutoSaveClearsDirtyFlag() async throws {
        store.activeIndex = 0
        store.updateActiveText("edited A")
        store.scheduleAutoSave(delay: 1)
        await drainAutoSaves()

        XCTAssertEqual(store.buffers[0].isDirty, false)
    }

    func testEditSchedulesAutoSaveWhenPolicyEnabled() async throws {
        store.autoSavePolicy = { (true, 1) }
        store.activeIndex = 0
        store.updateActiveText("policy save")
        await drainAutoSaves()

        XCTAssertEqual(try String(contentsOf: urlA, encoding: .utf8), "policy save")
    }

    func testEditDoesNotScheduleAutoSaveWhenPolicyDisabled() {
        store.activeIndex = 0
        store.updateActiveText("no autosave")

        XCTAssertTrue(store.autoSaveTasks.isEmpty)
    }

    func testHasUnsavedChangesReflectsDirtyBuffers() {
        XCTAssertFalse(store.hasUnsavedChanges)
        store.activeIndex = 0
        store.updateActiveText("edited A")
        XCTAssertTrue(store.hasUnsavedChanges)
    }
}
