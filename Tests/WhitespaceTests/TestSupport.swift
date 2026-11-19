// Tests/WhitespaceTests/TestSupport.swift
import AppKit
import UniformTypeIdentifiers
@testable import Whitespace

extension ZenTextView {
    /// The storage as styled runs — what the document would save.
    var styledRuns: [StyledRun] { StyledRun.runs(in: textStorage ?? NSTextStorage()) }
}

/// A document holding `runs` as `type`, the way it would after a read.
@MainActor
func makeDocument(runs: [StyledRun] = [], type: UTType = .plainText) -> WhitespaceDocument {
    let doc = WhitespaceDocument()
    doc.fileType = type.identifier
    doc.replaceContent(with: runs)
    return doc
}

/// Lets queued main-thread work run: NSDocument updates its change count from
/// undo-group notifications, which arrive after the current run-loop pass.
@MainActor
func spinRunLoop(_ seconds: TimeInterval = 0.1) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}
