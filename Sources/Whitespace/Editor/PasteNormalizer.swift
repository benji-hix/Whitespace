// Sources/Whitespace/Editor/PasteNormalizer.swift
import AppKit

struct StyledRun: Equatable {
    var text: String
    var bold: Bool
    var italic: Bool
    var underline: Bool
}

enum PasteNormalizer {

    /// Canonical mapping from bold/italic flags to a WhitespaceFont face name.
    static func fontName(bold: Bool, italic: Bool) -> String {
        switch (bold, italic) {
        case (true,  true):  return WhitespaceFont.boldItalic
        case (true,  false): return WhitespaceFont.bold
        case (false, true):  return WhitespaceFont.italic
        case (false, false): return WhitespaceFont.regular
        }
    }

    /// Stage 1: classify the source into flag-only runs. Keeps only
    /// bold/italic/underline, drops every other attribute by construction,
    /// strips leading tabs/spaces at each line start, and normalizes CR/CRLF
    /// to LF.
    static func styledRuns(from source: NSAttributedString) -> [StyledRun] {
        var runs: [StyledRun] = []
        var atLineStart = true

        func append(_ ch: Character, bold: Bool, italic: Bool, underline: Bool) {
            if var last = runs.last,
               last.bold == bold, last.italic == italic, last.underline == underline {
                last.text.append(ch)
                runs[runs.count - 1] = last
            } else {
                runs.append(StyledRun(text: String(ch),
                                      bold: bold, italic: italic, underline: underline))
            }
        }

        let full = NSRange(location: 0, length: source.length)
        let nsString = source.string as NSString

        source.enumerateAttributes(in: full, options: []) { attrs, range, _ in
            let traits = (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            let bold = traits.contains(.bold)
            let italic = traits.contains(.italic)
            let underline = (attrs[.underlineStyle] as? Int ?? 0) != 0

            for ch in nsString.substring(with: range) {
                switch ch {
                case "\n", "\r", "\r\n":
                    append("\n", bold: false, italic: false, underline: false)
                    atLineStart = true
                case "\u{2028}", "\u{2029}":
                    append(ch, bold: false, italic: false, underline: false)
                    atLineStart = true
                default:
                    if atLineStart, ch == " " || ch == "\t" {
                        continue  // drop leading whitespace
                    }
                    append(ch, bold: bold, italic: italic, underline: underline)
                    atLineStart = false
                }
            }
        }
        return runs
    }
}
