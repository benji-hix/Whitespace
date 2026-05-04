// Sources/Whitespace/Files/WhitespaceDocument.swift
import SwiftUI
import UniformTypeIdentifiers

struct WhitespaceDocument: FileDocument {
    static let markdownType = UTType(importedAs: "net.daringfireball.markdown")

    static var readableContentTypes: [UTType] { [.plainText, .text, markdownType] }
    static var writableContentTypes: [UTType] { [.plainText, markdownType] }

    var text: String
    var contentType: UTType

    init(text: String = "", contentType: UTType = .plainText) {
        self.text = text
        self.contentType = contentType
    }

    init(configuration: ReadConfiguration) throws {
        let type = configuration.contentType
        let data = configuration.file.regularFileContents ?? Data()
        try self.init(data: data, type: type)
    }

    init(data: Data, type: UTType) throws {
        guard !data.isEmpty else {
            self.text = ""
            self.contentType = type
            return
        }
        if let utf8 = String(data: data, encoding: .utf8) {
            self.text = utf8
        } else if let latin1 = String(data: data, encoding: .isoLatin1) {
            self.text = latin1
        } else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.contentType = type
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try encodedData(for: configuration.contentType)
        return FileWrapper(regularFileWithContents: data)
    }

    func encodedData(for type: UTType) throws -> Data {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }
}
