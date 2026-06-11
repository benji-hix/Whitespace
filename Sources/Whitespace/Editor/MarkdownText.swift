// Sources/Whitespace/Editor/MarkdownText.swift
import Foundation

/// Markdown (de)serialization for the document layer. Storage format only —
/// the user always sees rendered styles, never syntax. Only bold and italic
/// exist in this dialect; underline is dropped by design (markdown cannot
/// express it).
enum MarkdownText {

    /// Characters that can open an inline construct under AttributedString's
    /// inline-only markdown parsing (emphasis, code spans, links, raw HTML,
    /// strikethrough, or an escape). Escaping them guarantees prose
    /// round-trips verbatim.
    private static let escapables: Set<Character> = ["\\", "*", "_", "`", "[", "<", "~"]

    static func encode(runs: [StyledRun]) -> String {
        var out = ""
        for styledRun in runs {
            // CommonMark emphasis does not survive a line break; close the
            // markers before each newline and reopen after.
            let lines = styledRun.text.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() {
                if index > 0 { out += "\n" }
                out += encodeLine(String(line), bold: styledRun.bold, italic: styledRun.italic)
            }
        }
        return out
    }

    private static func encodeLine(_ text: String, bold: Bool, italic: Bool) -> String {
        guard !text.isEmpty else { return "" }

        let marker: String
        switch (bold, italic) {
        case (true, true):   marker = "***"
        case (true, false):  marker = "**"
        case (false, true):  marker = "*"
        case (false, false): marker = ""
        }
        guard !marker.isEmpty else { return escaped(text) }

        // Emphasis cannot wrap whitespace ("** bold **" does not parse);
        // hoist leading/trailing spaces outside the markers.
        let isSpace: (Character) -> Bool = { $0 == " " || $0 == "\t" }
        let leading = String(text.prefix(while: isSpace))
        let trailing = String(text.reversed().prefix(while: isSpace).reversed())
        let core = String(text.dropFirst(leading.count).dropLast(trailing.count))
        guard !core.isEmpty else { return text }

        return leading + marker + escaped(core) + marker + trailing
    }

    private static func escaped(_ text: String) -> String {
        var out = ""
        for ch in text {
            if escapables.contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }
}
