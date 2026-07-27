// Sources/Whitespace/Files/WhitespaceDocument.swift
import SwiftUI
import UniformTypeIdentifiers

struct WhitespaceDocument: FileDocument {
    static let markdownType = UTType(importedAs: "net.daringfireball.markdown")

    /// SwiftUI's document controller types untitled documents (and defaults
    /// the save panel's format popup) from the FIRST readable/writable
    /// entry, ignoring the instance's contentType — so the order of both
    /// lists must follow the new-files preference.
    private static var prefersPlainText: Bool {
        UserDefaults.standard.string(forKey: NewDocumentType.defaultsKey)
            == NewDocumentType.plainText.rawValue
    }

    static var readableContentTypes: [UTType] {
        prefersPlainText
            ? [.plainText, .text, markdownType]
            : [markdownType, .plainText, .text]
    }

    static var writableContentTypes: [UTType] {
        prefersPlainText
            ? [.plainText, markdownType]
            : [markdownType, .plainText]
    }

    /// A new untitled document of the type Settings ▸ Documents ▸ New Files
    /// asks for.
    ///
    /// Reads UserDefaults rather than `PreferencesStore` because
    /// `DocumentGroup`'s autoclosure is Sendable and cannot reference
    /// main-actor state — and because the content-type lists above already
    /// derive from the same key, so this keeps one source of truth rather than
    /// two that can disagree.
    static func newUntitled() -> WhitespaceDocument {
        WhitespaceDocument(contentType: prefersPlainText ? .plainText : markdownType)
    }

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
        let data = try approvedData(for: configuration.contentType)
        return FileWrapper(regularFileWithContents: data)
    }

    /// The write, minus SwiftUI's `WriteConfiguration` — which has no public
    /// initializer, so this is the deepest point a test can drive.
    ///
    /// Throws `userCancelled` when the user declines to flatten, which is the
    /// code NSDocument treats as "abandon quietly, show no error".
    func approvedData(
        for type: UTType,
        defaults: UserDefaults = .standard,
        ask: @escaping @MainActor (UserDefaults) -> Bool = { PlainTextConversionGate.presentWarning(defaults: $0) }
    ) throws -> Data {
        if !type.conforms(to: Self.markdownType),
           !PlainTextConversionGate.approveFlattening(runs: runs, defaults: defaults, ask: ask) {
            throw CocoaError(.userCancelled)
        }
        return try encodedData(for: type)
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
