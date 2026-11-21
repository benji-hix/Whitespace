// Tests/WhitespaceTests/TestSupport.swift
import AppKit
import XCTest
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

/// A keybinding store on its own defaults suite, holding the default chords.
/// The app's store reads the owner's real keybindings; tests never use it.
@MainActor
func makeTestKeybindingStore(for test: XCTestCase) -> KeybindingStore {
    let suite = "test-keybindings-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    test.addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
    return KeybindingStore(defaults: defaults)
}

/// Presses an editor keybinding's default chord through `keyDown`. The store
/// is set immediately before the event because the window's hosted editor is
/// given the app's store on every SwiftUI update.
@MainActor
func press(_ action: KeybindingAction, on tv: ZenTextView, store: KeybindingStore) {
    tv.keybindingStore = store
    let binding = action.defaultBinding
    tv.keyDown(with: NSEvent.keyEvent(
        with: .keyDown, location: .zero,
        modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(binding.modifiers)), timestamp: 0,
        windowNumber: tv.window?.windowNumber ?? 0, context: nil, characters: " ",
        charactersIgnoringModifiers: " ", isARepeat: false, keyCode: binding.keyCode)!)
}
