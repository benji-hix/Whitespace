// Sources/Whitespace/Files/FileStore.swift
import AppKit

@Observable
@MainActor
final class FileStore {
    private(set) var buffers: [FileBuffer] = []
    var activeIndex: Int = 0
    var autoSaveTasks: [UUID: Task<Void, Never>] = [:]

    var hasUnsavedChanges: Bool {
        buffers.contains { $0.isDirty }
    }

    var activeBuffer: FileBuffer? {
        get { buffers.indices.contains(activeIndex) ? buffers[activeIndex] : nil }
        set { if let v = newValue, buffers.indices.contains(activeIndex) { buffers[activeIndex] = v } }
    }

    func newBuffer() {
        buffers.append(FileBuffer())
        activeIndex = buffers.count - 1
    }

    func open(url: URL) async throws {
        // If already open, just switch to it
        if let idx = buffers.firstIndex(where: { $0.url == url }) {
            activeIndex = idx
            return
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        buffers.append(FileBuffer(url: url, text: text))
        activeIndex = buffers.count - 1
    }

    func saveActive() throws {
        guard let buffer = activeBuffer else { return }
        try save(bufferID: buffer.id)
    }

    /// Entry point for the user-initiated Save command: an untitled buffer
    /// gets the Save As panel instead of silently doing nothing.
    func saveActiveOrPrompt() {
        if activeBuffer?.url == nil {
            saveAsPanel()
        } else {
            try? saveActive()
        }
    }

    private func save(bufferID: UUID) throws {
        guard let idx = buffers.firstIndex(where: { $0.id == bufferID }),
              let url = buffers[idx].url else { return }
        try buffers[idx].text.write(to: url, atomically: true, encoding: .utf8)
        buffers[idx].isDirty = false
    }

    /// Reads the user's auto-save preference at edit time. Wired once at
    /// startup; defaults to off so headless tests opt in explicitly.
    var autoSavePolicy: () -> (enabled: Bool, delaySeconds: Int) = { (false, 0) }

    func updateActiveText(_ text: String) {
        guard var buffer = activeBuffer else { return }
        buffer.text = text
        buffer.isDirty = true
        activeBuffer = buffer
        let policy = autoSavePolicy()
        if policy.enabled { scheduleAutoSave(delay: policy.delaySeconds) }
    }

    /// Debounced per buffer: a new edit in the same buffer resets its timer,
    /// but a save pending for one buffer survives edits and switches in
    /// others — the buffer captured here is the one written, not whichever
    /// is active when the timer fires.
    func scheduleAutoSave(delay: Int) {
        guard let id = activeBuffer?.id else { return }
        autoSaveTasks[id]?.cancel()
        autoSaveTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.autoSaveTasks[id] = nil
            try? self.save(bufferID: id)
        }
    }

    // Called from NSOpenPanel result
    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { try? await self.open(url: url) }
    }

    // Returns save URL (nil if cancelled)
    @discardableResult
    func saveAsPanel() -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = activeBuffer?.displayName ?? "Untitled.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        if var buffer = activeBuffer {
            buffer.url = url
            activeBuffer = buffer
        }
        try? saveActive()
        return url
    }
}
