// Sources/Folio/Files/FileBuffer.swift
import Foundation

struct FileBuffer: Identifiable {
    let id: UUID
    var url: URL?
    var text: String
    var isDirty: Bool

    init(url: URL? = nil, text: String = "", isDirty: Bool = false) {
        self.id = UUID()
        self.url = url
        self.text = text
        self.isDirty = isDirty
    }

    var displayName: String {
        url?.lastPathComponent ?? "Untitled"
    }
}
