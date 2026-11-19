// Sources/Whitespace/Files/WhitespaceDocument.swift
import AppKit
import UniformTypeIdentifiers

/// One open file. The document owns its text: `textStorage` is the single
/// source of truth, laid out and edited directly by the window's `ZenTextView`.
/// Styled runs and markdown exist only at read and save time.
///
/// The storage holds faces only (regular, bold, italic, bold-italic). Size,
/// paragraph style and colour belong to the editor, which restyles the storage
/// when it attaches and after any wholesale replacement.
final class WhitespaceDocument: NSDocument, NSTextViewDelegate {
    nonisolated static let markdownType = UTType(importedAs: "net.daringfireball.markdown")

    let textStorage = NSTextStorage()

    /// The editor showing this document, once its window exists. Wholesale
    /// replacement needs it to reset scrolling and restyle.
    weak var editor: ZenTextView?

    override class var autosavesInPlace: Bool { true }

    /// Save As can change the type; the editor's formatting mode follows it.
    ///
    /// NSDocument declares `fileType` nonisolated. It is set on the main thread
    /// here because reads (`canConcurrentlyReadDocuments`) and writes
    /// (`canAsynchronouslyWrite`) both stay on main.
    override var fileType: String? {
        didSet {
            MainActor.assumeIsolated {
                editor?.formattingEnabled = isMarkdown
                editor?.isRichText = isMarkdown
            }
        }
    }

    var contentType: UTType { fileType.flatMap { UTType($0) } ?? .plainText }
    var isMarkdown: Bool { contentType.conforms(to: Self.markdownType) }
    var runs: [StyledRun] { StyledRun.runs(in: textStorage) }

    /// The save panel's format picker. The Plain Text document type lists
    /// three text UTIs so the app can open them all, but it saves only one.
    override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        [Self.markdownType.identifier, UTType.plainText.identifier]
    }

    override func makeWindowControllers() {
        guard let app = NSApp.delegate as? AppDelegate else { return }
        addWindowController(DocumentWindowController(
            document: self,
            themeStore: app.themeStore,
            preferences: app.preferencesStore,
            keybindingStore: app.keybindingStore
        ))
    }

    // MARK: - Reading

    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        let runs = try Self.decode(data, type: UTType(typeName) ?? .plainText)
        // canConcurrentlyReadDocuments is false, so AppKit reads documents on
        // the main thread; the storage is main-actor state.
        MainActor.assumeIsolated { replaceContent(with: runs) }
    }

    nonisolated static func decode(_ data: Data, type: UTType) throws -> [StyledRun] {
        guard !data.isEmpty else { return [] }
        let string: String
        if let utf8 = String(data: data, encoding: .utf8) {
            string = utf8
        } else if let latin1 = String(data: data, encoding: .isoLatin1) {
            string = latin1
        } else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        if type.conforms(to: markdownType) {
            return MarkdownText.decode(string)
        }
        return [StyledRun(text: string, bold: false, italic: false)]
    }

    /// The only way content is replaced wholesale (open, revert, restoration).
    /// The steps stay together: the scroll anchor and the undo stack both refer
    /// to the old content, and the new content arrives as bare faces.
    func replaceContent(with runs: [StyledRun]) {
        editor?.invalidateScrollAnchor()
        undoManager?.removeAllActions()
        textStorage.setAttributedString(
            PasteNormalizer.attributedString(runs: runs, baseAttributes: [:])
        )
        editor?.restyleContent()
    }

    // MARK: - Writing

    override func data(ofType typeName: String) throws -> Data {
        try approvedData(for: UTType(typeName) ?? .plainText)
    }

    /// The write, minus NSDocument. Throws `userCancelled` when the user
    /// declines to flatten, which NSDocument treats as "abandon quietly".
    func approvedData(
        for type: UTType,
        defaults: UserDefaults = .standard,
        ask: @escaping @MainActor (UserDefaults) -> Bool = { PlainTextConversionGate.presentWarning(defaults: $0) }
    ) throws -> Data {
        let runs = runs
        if !type.conforms(to: Self.markdownType),
           !PlainTextConversionGate.approveFlattening(runs: runs, defaults: defaults, ask: ask) {
            throw CocoaError(.userCancelled)
        }
        return try Self.encode(runs, for: type)
    }

    func encodedData(for type: UTType) throws -> Data {
        try Self.encode(runs, for: type)
    }

    private static func encode(_ runs: [StyledRun], for type: UTType) throws -> Data {
        let string = type.conforms(to: markdownType)
            ? MarkdownText.encode(runs: runs)
            : runs.map(\.text).joined()
        guard let data = string.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }

    // MARK: - NSTextViewDelegate

    /// Through the delegate rather than the window, so the editor and the
    /// document share one undo stack wherever the view is hosted.
    func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                  replacementString: String?) -> Bool {
        // A nil replacement is an attribute-only edit (⌘B/⌘I on a selection).
        // TextKit 2 registers no undo action for it, so NSDocument, which
        // counts edits through the undo manager, would never mark the document
        // edited. Text edits are already counted; counting them here too would
        // leave the document dirty after undoing back to the saved state.
        if replacementString == nil { updateChangeCount(.changeDone) }
        return true
    }
}
