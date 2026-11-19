// Sources/Whitespace/Editor/PasteNormalizer.swift
import AppKit

struct StyledRun: Equatable {
    var text: String
    var bold: Bool
    var italic: Bool
}

extension StyledRun {
    /// Faithful snapshot of an attributed string as styled runs — text
    /// verbatim (whitespace and newlines included), the app's font faces
    /// mapped back to flags. The document calls this at save time on its text
    /// storage; `PasteNormalizer.attributedString(runs:baseAttributes:)` is
    /// the reverse.
    ///
    /// Faces are recognised by font name, not traits: only the app's own
    /// faces count, which is what the storage holds.
    static func runs(in attributed: NSAttributedString) -> [StyledRun] {
        guard attributed.length > 0 else { return [] }
        let nsString = attributed.string as NSString
        var runs: [StyledRun] = []
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            let font = value as? NSFont
            let bold = isBold(font)
            let italic = isItalic(font)
            let text = nsString.substring(with: range)
            if var last = runs.last, last.bold == bold, last.italic == italic {
                last.text += text
                runs[runs.count - 1] = last
            } else {
                runs.append(StyledRun(text: text, bold: bold, italic: italic))
            }
        }
        return runs
    }

    static func isBold(_ font: NSFont?) -> Bool {
        guard let name = font?.fontName else { return false }
        return name == WhitespaceFont.bold || name == WhitespaceFont.boldItalic
    }

    static func isItalic(_ font: NSFont?) -> Bool {
        guard let name = font?.fontName else { return false }
        return name == WhitespaceFont.italic || name == WhitespaceFont.boldItalic
    }
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
    /// bold/italic, drops every other attribute by construction, strips
    /// leading tabs/spaces at each line start, and normalizes CR/CRLF to LF.
    static func styledRuns(from source: NSAttributedString) -> [StyledRun] {
        var runs: [StyledRun] = []
        var atLineStart = true

        func append(_ ch: Character, bold: Bool, italic: Bool) {
            if var last = runs.last, last.bold == bold, last.italic == italic {
                last.text.append(ch)
                runs[runs.count - 1] = last
            } else {
                runs.append(StyledRun(text: String(ch), bold: bold, italic: italic))
            }
        }

        let full = NSRange(location: 0, length: source.length)
        let nsString = source.string as NSString

        source.enumerateAttributes(in: full, options: []) { attrs, range, _ in
            let traits = (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            let bold = traits.contains(.bold)
            let italic = traits.contains(.italic)

            for ch in nsString.substring(with: range) {
                switch ch {
                case "\n", "\r", "\r\n":
                    append("\n", bold: false, italic: false)
                    atLineStart = true
                case "\u{2028}", "\u{2029}":
                    append(ch, bold: false, italic: false)
                    atLineStart = true
                default:
                    if atLineStart, ch == " " || ch == "\t" {
                        continue  // drop leading whitespace
                    }
                    append(ch, bold: bold, italic: italic)
                    atLineStart = false
                }
            }
        }
        return runs
    }

    /// Stage 2: rebuild an attributed string from flag-only runs, using the
    /// editor's current typing attributes as the base. Overrides only `.font`
    /// (the matching WhitespaceFont face at the base size).
    static func attributedString(runs: [StyledRun],
                                 baseAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let size = (baseAttributes[.font] as? NSFont)?.pointSize ?? 18
        let result = NSMutableAttributedString()

        for run in runs {
            let name = fontName(bold: run.bold, italic: run.italic)
            let font = NSFont(name: name, size: size)
                ?? NSFont(name: WhitespaceFont.regular, size: size)
                ?? NSFont.systemFont(ofSize: size)

            var attrs = baseAttributes
            attrs[.font] = font
            result.append(NSAttributedString(string: run.text, attributes: attrs))
        }
        return result
    }
}
