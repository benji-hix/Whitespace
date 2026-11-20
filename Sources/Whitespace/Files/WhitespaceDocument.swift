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

    /// Tests save documents in the temporary folder, which has no version
    /// store, so NSDocument would preserve each old version in
    /// ~/Library/Autosave Information — the owner's real folder, shared with
    /// the test host — and leave it there.
    override class var preservesVersions: Bool { !AppDelegate.isRunningTests }

    /// Save As can change the type; the editor's formatting mode follows it.
    ///
    /// NSDocument declares `fileType` nonisolated. Here it is set on the main
    /// thread, because reads (`canConcurrentlyReadDocuments`) and writes
    /// (`canAsynchronouslyWrite`) both stay on main; the hop is a guard, not a
    /// path that runs today.
    override var fileType: String? {
        didSet {
            if Thread.isMainThread {
                MainActor.assumeIsolated { matchEditorToFileType() }
            } else {
                Task { @MainActor [weak self] in self?.matchEditorToFileType() }
            }
        }
    }

    private func matchEditorToFileType() {
        editor?.formattingEnabled = isMarkdown
        editor?.isRichText = isMarkdown
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

    /// BOM and line endings as read, written back on save.
    private(set) var format = TextFileFormat()

    /// The file holds something a save would not write back byte for byte
    /// (see `DocumentCodec`). Until the owner chooses Edit Anyway, edits ask
    /// first and nothing is written over the original file.
    var isProtected = false

    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        let decoded = try DocumentCodec.decode(data, as: UTType(typeName) ?? .plainText)
        // canConcurrentlyReadDocuments is false, so AppKit reads documents on
        // the main thread; the storage is main-actor state.
        MainActor.assumeIsolated {
            format = decoded.format
            isProtected = !decoded.isLossless
            replaceContent(with: decoded.runs)
        }
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

    /// Every save, autosaves included, is a point where typing must stop
    /// coalescing. NSTextView folds consecutive keystrokes into one undo
    /// action, and NSDocument counts edits by undo group; typing that carried
    /// on after a save joined the action from before it, so the document
    /// stayed clean and was never autosaved again.
    override func save(to url: URL, ofType typeName: String,
                       for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        editor?.breakUndoCoalescing()
        super.save(to: url, ofType: typeName, for: saveOperation) { error in
            // A Save As that got this far wrote somewhere other than the
            // original (`writeSafely` refuses that), and the document now
            // refers to a file it wrote itself.
            if error == nil, saveOperation == .saveAsOperation {
                MainActor.assumeIsolated { self.isProtected = false }
            }
            completionHandler(error)
        }
    }

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
        return DocumentCodec.encode(runs, as: type, format: format)
    }

    func encodedData(for type: UTType) throws -> Data {
        DocumentCodec.encode(runs, as: type, format: format)
    }

    // MARK: - Protection

    /// The guarantee behind the edit gate: whatever path an edit took, a
    /// protected document never writes over its original file. Every write
    /// NSDocument makes (save, autosave in place, Save As, duplicate) comes
    /// through here.
    override func writeSafely(to url: URL, ofType typeName: String,
                              for saveOperation: NSDocument.SaveOperationType) throws {
        if isProtected, isOriginalFile(url) { throw protectedWriteError }
        try super.writeSafely(to: url, ofType: typeName, for: saveOperation)
    }

    /// By file identity when both exist, so a symlink or a differently cased
    /// path to the same file still counts as the original.
    private func isOriginalFile(_ url: URL) -> Bool {
        guard let original = fileURL else { return false }
        if url.standardizedFileURL == original.standardizedFileURL { return true }
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let target = try? url.resourceValues(forKeys: key).fileResourceIdentifier,
              let source = try? original.resourceValues(forKeys: key).fileResourceIdentifier
        else { return false }
        return target.isEqual(source)
    }

    /// NSDocument shows its own "could not be saved" line, then the reason.
    /// A permission code would make it add "You don't have permission".
    private var protectedWriteError: CocoaError {
        CocoaError(.fileWriteUnknown, userInfo: [
            NSLocalizedFailureReasonErrorKey:
                "Whitespace can’t save it back exactly as it is, so the original file stays untouched.",
            NSLocalizedRecoverySuggestionErrorKey:
                "Choose File ▸ Duplicate to keep your changes in a new document.",
        ])
    }

    /// A duplicate holds what this window shows, unprotected. NSDocument
    /// builds it from a file (a copy of the original, or our own encoding),
    /// and re-reading either can come back different or protected again.
    override func duplicate() throws -> NSDocument {
        let copy = try super.duplicate()
        if let copy = copy as? WhitespaceDocument {
            copy.replaceContent(with: runs)
            copy.isProtected = false
        }
        return copy
    }

    enum ProtectedEditChoice { case duplicate, cancel, editAnyway }

    /// Shows the sheet; tests replace it.
    var askBeforeEditingProtected: @MainActor (NSWindow?, @escaping @MainActor (ProtectedEditChoice) -> Void) -> Void
        = WhitespaceDocument.presentProtectedEditSheet

    private var isAskingToEdit = false

    private func askToEditProtected(in window: NSWindow?) {
        guard !isAskingToEdit else { return }
        isAskingToEdit = true
        askBeforeEditingProtected(window) { [weak self] choice in
            guard let self else { return }
            isAskingToEdit = false
            switch choice {
            case .duplicate: duplicate(nil)
            case .cancel: break
            case .editAnyway: isProtected = false
            }
        }
    }

    private static func presentProtectedEditSheet(
        on window: NSWindow?, completion: @escaping @MainActor (ProtectedEditChoice) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Whitespace can’t save this file back exactly as it is."
        alert.informativeText = """
            Editing it here rewrites the file in Whitespace’s own format, which \
            can change what Whitespace doesn’t support, such as links, code or \
            line endings. Duplicate leaves the original untouched.
            """
        alert.addButton(withTitle: "Duplicate")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        alert.addButton(withTitle: "Edit Anyway")
        let choose: @MainActor (NSApplication.ModalResponse) -> Void = { response in
            switch response {
            case .alertFirstButtonReturn: completion(.duplicate)
            case .alertThirdButtonReturn: completion(.editAnyway)
            default: completion(.cancel)
            }
        }
        if let window {
            alert.beginSheetModal(for: window) { response in MainActor.assumeIsolated { choose(response) } }
        } else {
            choose(alert.runModal())
        }
    }

    // MARK: - NSTextViewDelegate

    /// Through the delegate rather than the window, so the editor and the
    /// document share one undo stack wherever the view is hosted.
    func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                  replacementString: String?) -> Bool {
        // Typing, paste and ⌘B on a selection all arrive here first. The
        // edit is dropped while the owner decides; Edit Anyway lets the next
        // one through.
        if isProtected {
            askToEditProtected(in: textView.window)
            return false
        }
        // A nil replacement is an attribute-only edit (⌘B/⌘I on a selection).
        // TextKit 2 registers no undo action for it, so NSDocument, which
        // counts edits through the undo manager, would never mark the document
        // edited. Text edits are already counted; counting them here too would
        // leave the document dirty after undoing back to the saved state.
        if replacementString == nil { updateChangeCount(.changeDone) }
        return true
    }
}
