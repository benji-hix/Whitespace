import XCTest
import UniformTypeIdentifiers
@testable import Whitespace

final class DocumentCodecTests: XCTestCase {
    private var markdown: UTType { WhitespaceDocument.markdownType }

    private func decode(_ string: String, as type: UTType? = nil) throws -> DocumentCodec.Decoded {
        try DocumentCodec.decode(Data(string.utf8), as: type ?? markdown)
    }

    /// Decode, then encode with the format read: the bytes a save would write.
    private func roundTrip(_ data: Data, as type: UTType) throws -> Data {
        let decoded = try DocumentCodec.decode(data, as: type)
        return DocumentCodec.encode(decoded.runs, as: type, format: decoded.format)
    }

    // MARK: - Encoding refusal

    func testRefusesLatin1WithAReadableError() {
        let latin1 = Data([0x68, 0xE9, 0x6C, 0x6C, 0x6F]) // "héllo" in Latin-1
        XCTAssertThrowsError(try DocumentCodec.decode(latin1, as: .plainText)) { error in
            let cocoa = error as? CocoaError
            XCTAssertEqual(cocoa?.code, .fileReadInapplicableStringEncoding)
            XCTAssertEqual(cocoa?.userInfo[NSLocalizedFailureReasonErrorKey] as? String,
                           "Whitespace opens only text saved as UTF-8.")
        }
    }

    func testRefusesUTF16EvenWithItsBOM() {
        let utf16 = "hi".data(using: .utf16)! // starts FF FE
        XCTAssertThrowsError(try DocumentCodec.decode(utf16, as: markdown))
    }

    // MARK: - Byte-exact round trips

    func testBOMIsReportedAndKept() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("hi".utf8)
        let decoded = try DocumentCodec.decode(data, as: markdown)
        XCTAssertEqual(decoded.runs.map(\.text).joined(), "hi", "the BOM is not content")
        XCTAssertTrue(decoded.format.hasBOM)
        XCTAssertTrue(decoded.isLossless)
        XCTAssertEqual(try roundTrip(data, as: markdown), data)
    }

    func testBOMOnlyFileIsEmptyAndLossless() throws {
        let data = Data([0xEF, 0xBB, 0xBF])
        let decoded = try DocumentCodec.decode(data, as: .plainText)
        XCTAssertEqual(decoded.runs, [])
        XCTAssertTrue(decoded.isLossless)
    }

    func testEmptyFileIsLossless() throws {
        let decoded = try DocumentCodec.decode(Data(), as: markdown)
        XCTAssertEqual(decoded.runs, [])
        XCTAssertEqual(decoded.format, TextFileFormat())
        XCTAssertTrue(decoded.isLossless)
    }

    func testUniformCRLFIsReportedAndKept() throws {
        for type in [markdown, .plainText] {
            let decoded = try decode("one\r\n**two**\r\n", as: type)
            XCTAssertEqual(decoded.format.lineEnding, .crlf)
            XCTAssertFalse(decoded.runs.map(\.text).joined().contains("\r"), "the storage holds LF only")
            XCTAssertTrue(decoded.isLossless, "\(type)")
        }
    }

    func testTrailingNewlinesSurvive() throws {
        for type in [markdown, .plainText] {
            for text in ["abc\n", "abc\n\n", "\n", "abc"] {
                let data = Data(text.utf8)
                XCTAssertEqual(try roundTrip(data, as: type), data, "\(text.debugDescription) as \(type)")
            }
        }
    }

    func testBOMCRLFAndTrailingNewlineTogether() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("*a*\r\nb\r\n".utf8)
        XCTAssertTrue(try DocumentCodec.decode(data, as: markdown).isLossless)
        XCTAssertEqual(try roundTrip(data, as: markdown), data)
    }

    func testMixedLineEndingsAreLossyAndSaveInTheMajorityStyle() throws {
        let decoded = try decode("a\r\nb\r\nc\nd", as: .plainText)
        XCTAssertFalse(decoded.isLossless)
        XCTAssertEqual(decoded.format.lineEnding, .crlf)
        XCTAssertFalse(try decode("a\rb", as: .plainText).isLossless, "a lone CR becomes LF")
    }

    /// Pasted text can carry CRs into the storage; the file still gets one style.
    func testEncodeNormalisesStrayCarriageReturns() {
        let runs = [StyledRun(text: "a\r\nb\nc", bold: false, italic: false)]
        let crlf = DocumentCodec.encode(runs, as: .plainText, format: TextFileFormat(lineEnding: .crlf))
        XCTAssertEqual(String(data: crlf, encoding: .utf8), "a\r\nb\r\nc")
        let lf = DocumentCodec.encode(runs, as: .plainText, format: TextFileFormat())
        XCTAssertEqual(String(data: lf, encoding: .utf8), "a\nb\nc")
    }

    // MARK: - What the dialect cannot keep

    func testForeignMarkdownIsLossy() throws {
        for foreign in ["[a](https://b)", "`code`", "_x_", "__x__", "~~x~~", "\\.", "\\#", "a\\\nb", "&amp;"] {
            XCTAssertFalse(try decode(foreign).isLossless, foreign)
        }
    }

    /// The plan listed `\[` as lossy, but the encoder escapes `[` itself, so
    /// it comes back as written.
    func testEscapesTheEncoderWritesAreLossless() throws {
        for own in ["\\[", "\\*", "\\_", "\\\\", "\\<", "\\~", "\\`", "\\&amp;"] {
            XCTAssertTrue(try decode(own).isLossless, own)
        }
    }

    func testPlainTextIsLosslessWhateverItContains() throws {
        XCTAssertTrue(try decode("[a](b) `c` _d_ &amp;", as: .plainText).isLossless)
    }

    // MARK: - The encoder's own output

    /// Measured before relying on it: own output is lossless for prose whose
    /// styled runs are separated by plain text. Seeded, so a failure repeats.
    func testOwnOutputIsLosslessForSeparatedEmphasis() throws {
        var rng = SplitMix64(seed: 0x5EED)
        let prose = Array("ab é😀\n.,;:!?'\"()-#&1*_\\`[]<>~")
        let letters = Array("abé😀")
        func text(from chars: [Character], _ count: ClosedRange<Int>) -> String {
            String((0..<Int.random(in: count, using: &rng)).map { _ in chars.randomElement(using: &rng)! })
        }
        for _ in 0..<3000 {
            // Any prose in plain runs; emphasis on letters, with plain spaces
            // either side. The shapes that can't be expressed are pinned below.
            var runs: [StyledRun] = []
            for index in 0..<Int.random(in: 1...5, using: &rng) {
                if index.isMultiple(of: 2), Bool.random(using: &rng) {
                    let bold = Bool.random(using: &rng)
                    runs.append(StyledRun(text: text(from: letters, 1...4), bold: bold,
                                          italic: !bold || Bool.random(using: &rng)))
                } else {
                    runs.append(StyledRun(text: " " + text(from: prose, 1...8) + " ", bold: false, italic: false))
                }
            }
            let bytes = Data(MarkdownText.encode(runs: runs).utf8)
            let decoded = try DocumentCodec.decode(bytes, as: markdown)
            XCTAssertTrue(decoded.isLossless, String(decoding: bytes, as: UTF8.self))
            XCTAssertEqual(decoded.runs.map(\.text).joined(), runs.map(\.text).joined(),
                           "the visible text must come back unchanged")
        }
    }

    /// Typed text that looks like an entity is escaped, so it reloads as typed.
    func testTypedEntitiesComeBackAsTyped() throws {
        let typed = "&amp; &#169; &#xA9; salt & pepper"
        let bytes = Data(MarkdownText.encode(runs: [StyledRun(text: typed, bold: false, italic: false)]).utf8)
        let decoded = try DocumentCodec.decode(bytes, as: markdown)
        XCTAssertEqual(decoded.runs.map(\.text).joined(), typed)
        XCTAssertTrue(decoded.isLossless)
    }

    /// Shapes CommonMark `*` emphasis cannot express. The encoder writes them,
    /// they read back differently, and the guard catches them on the next
    /// open. Pinned so the day the encoder handles them, these fail and move up.
    func testEmphasisTheEncoderCannotExpressIsCaughtByTheGuard() throws {
        let unexpressible: [[StyledRun]] = [
            // bold, then bold-italic, then italic: the delimiter runs merge
            [StyledRun(text: "a", bold: true, italic: false),
             StyledRun(text: "b", bold: true, italic: true),
             StyledRun(text: "c", bold: false, italic: true)],
            // emphasis whose edge is punctuation touching a letter
            [StyledRun(text: "a", bold: false, italic: false),
             StyledRun(text: "(b)", bold: true, italic: false)],
        ]
        for runs in unexpressible {
            let bytes = Data(MarkdownText.encode(runs: runs).utf8)
            XCTAssertFalse(try DocumentCodec.decode(bytes, as: markdown).isLossless,
                           String(decoding: bytes, as: UTF8.self))
        }
    }
}

/// A small seeded generator, so property tests repeat exactly.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE5_E4B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
