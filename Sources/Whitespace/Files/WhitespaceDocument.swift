// Sources/Whitespace/Files/WhitespaceDocument.swift
import SwiftUI
import UniformTypeIdentifiers

struct WhitespaceDocument: FileDocument {
    static let markdownType = UTType(importedAs: "net.daringfireball.markdown")

    static var readableContentTypes: [UTType] { [.plainText, .text, markdownType] }
    static var writableContentTypes: [UTType] { [.plainText, markdownType] }

    /// The document's content, styled. Plain-text documents always hold
    /// plain runs; only markdown documents round-trip bold/italic.
    var runs: [StyledRun]
    var contentType: UTType

    var text: String { runs.map(\.text).joined() }

    init(text: String = "", contentType: UTType = .plainText) {
        self.runs = text.isEmpty
            ? []
            : [StyledRun(text: text, bold: false, italic: false)]
        self.contentType = contentType
    }

    init(runs: [StyledRun], contentType: UTType) {
        self.runs = runs
        self.contentType = contentType
    }

    init(data: Data, type: UTType) throws {
        guard !data.isEmpty else {
            self.init(text: "", contentType: type)
            return
        }
        let string: String
        if let utf8 = String(data: data, encoding: .utf8) {
            string = utf8
        } else if let latin1 = String(data: data, encoding: .isoLatin1) {
            string = latin1
        } else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        if type.conforms(to: Self.markdownType) {
            self.init(runs: MarkdownText.decode(string), contentType: type)
        } else {
            self.init(text: string, contentType: type)
        }
    }

    init(configuration: ReadConfiguration) throws {
        let type = configuration.contentType
        let data = configuration.file.regularFileContents ?? Data()
        try self.init(data: data, type: type)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if !configuration.contentType.conforms(to: Self.markdownType),
           PlainTextConversionGate.shouldWarnSync(runs: runs) {
            Task { @MainActor in PlainTextConversionGate.presentWarning() }
            throw CocoaError(.userCancelled)
        }
        let data = try encodedData(for: configuration.contentType)
        return FileWrapper(regularFileWithContents: data)
    }

    func encodedData(for type: UTType) throws -> Data {
        let string = type.conforms(to: Self.markdownType)
            ? MarkdownText.encode(runs: runs)
            : text
        guard let data = string.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }
}
