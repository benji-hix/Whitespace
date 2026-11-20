// Sources/Whitespace/Files/DocumentCodec.swift
import Foundation
import UniformTypeIdentifiers

/// How a file's bytes are laid out around its text: kept from the read so the
/// save writes them back the same way.
struct TextFileFormat: Equatable {
    enum LineEnding: Equatable { case lf, crlf }

    var hasBOM = false
    var lineEnding = LineEnding.lf
}

/// Bytes ↔ styled runs for both document types. UTF-8 only.
///
/// `decode` also reports whether the file survives the trip back: a file is
/// lossless when encoding what was decoded, with the format read from it,
/// gives back the same bytes. Markdown outside the dialect (links, code spans,
/// `_x_`), mixed line endings and some emphasis the encoder cannot express all
/// fail that check, and the document protects such files from being
/// overwritten.
enum DocumentCodec {
    struct Decoded {
        var runs: [StyledRun]
        var format: TextFileFormat
        var isLossless: Bool
    }

    private static let bom: [UInt8] = [0xEF, 0xBB, 0xBF]

    static func decode(_ data: Data, as type: UTType) throws -> Decoded {
        let hasBOM = data.starts(with: bom)
        guard let raw = String(validating: data.dropFirst(hasBOM ? bom.count : 0), as: UTF8.self) else {
            throw notUTF8Error
        }
        let format = TextFileFormat(hasBOM: hasBOM, lineEnding: dominantLineEnding(in: raw))
        let text = normalizingLineEndings(raw)
        let runs: [StyledRun]
        if text.isEmpty {
            runs = []
        } else if isMarkdown(type) {
            runs = MarkdownText.decode(text)
        } else {
            runs = [StyledRun(text: text, bold: false, italic: false)]
        }
        return Decoded(runs: runs, format: format,
                       isLossless: encode(runs, as: type, format: format) == data)
    }

    static func encode(_ runs: [StyledRun], as type: UTType, format: TextFileFormat) -> Data {
        var text = isMarkdown(type) ? MarkdownText.encode(runs: runs) : runs.map(\.text).joined()
        // Pasted text can carry its own CRs; the file gets one line-ending style.
        text = normalizingLineEndings(text)
        if format.lineEnding == .crlf {
            text = text.replacingOccurrences(of: "\n", with: "\r\n")
        }
        return (format.hasBOM ? Data(bom) : Data()) + Data(text.utf8)
    }

    /// NSDocument shows the failure reason and suggestion under its own
    /// "could not be opened" line.
    static let notUTF8Error = CocoaError(.fileReadInapplicableStringEncoding, userInfo: [
        NSLocalizedFailureReasonErrorKey: "Whitespace opens only text saved as UTF-8.",
        NSLocalizedRecoverySuggestionErrorKey:
            "Save the file as UTF-8 in another editor, then open it again.",
    ])

    private static func isMarkdown(_ type: UTType) -> Bool {
        type.conforms(to: WhitespaceDocument.markdownType)
    }

    private static func normalizingLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    /// CRLF only when it is the majority, so a mixed file saves in the style
    /// most of it already uses. Mixed files are never lossless whichever wins.
    private static func dominantLineEnding(in text: String) -> TextFileFormat.LineEnding {
        var crlf = 0, other = 0
        // Swift treats "\r\n" as one Character, which is what is wanted here.
        for ch in text {
            if ch == "\r\n" { crlf += 1 } else if ch == "\n" || ch == "\r" { other += 1 }
        }
        return crlf > other ? .crlf : .lf
    }
}
