// Sources/Folio/Files/FileStore.swift
import AppKit

@Observable
@MainActor
final class FileStore {
    private(set) var buffers: [FileBuffer] = []
    var activeIndex: Int = 0
    private var autoSaveTask: Task<Void, Never>?

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

    func saveActive() async throws {
        guard var buffer = activeBuffer else { return }
        guard let url = buffer.url else { return }
        try buffer.text.write(to: url, atomically: true, encoding: .utf8)
        buffer.isDirty = false
        activeBuffer = buffer
    }

    func closeActive() {
        guard buffers.indices.contains(activeIndex) else { return }
        buffers.remove(at: activeIndex)
        activeIndex = max(0, min(activeIndex, buffers.count - 1))
    }

    func updateActiveText(_ text: String) {
        guard var buffer = activeBuffer else { return }
        buffer.text = text
        buffer.isDirty = true
        activeBuffer = buffer
    }

    func scheduleAutoSave(delay: Int) {
        autoSaveTask?.cancel()
        autoSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            try? await self.saveActive()
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
        Task { try? await self.saveActive() }
        return url
    }
}
