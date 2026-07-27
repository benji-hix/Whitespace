// Sources/Whitespace/Files/PlainTextConversionGate.swift
import AppKit

/// Saving formatted content as plain text flattens bold/italic, so it asks
/// first.
///
/// The write path asks *during* the write and blocks on the answer, rather
/// than aborting and trying to resume. Aborting cannot work: throwing from
/// `fileWrapper` discards the destination the user chose in the save panel,
/// and the only way back in — re-sending `save:` — targets the document's
/// existing URL and type instead, and is a no-op outright when the document
/// is not dirty. That is why "Save Anyway" silently wrote nothing.
///
/// SwiftUI calls `fileWrapper` off the main thread, so the alert runs on main
/// while the serialization thread waits. The main-thread branch exists because
/// hopping to main from main would deadlock.
@MainActor
enum PlainTextConversionGate {
    static let suppressKey = "whitespace.prefs.suppressPlainTextConversionWarning"

    /// Would this write destroy formatting the user has not already agreed to
    /// lose?
    static func needsApproval(runs: [StyledRun], defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: suppressKey) else { return false }
        return runs.contains { $0.bold || $0.italic }
    }

    /// Shows the warning and reports whether the write may proceed. Ticking the
    /// suppression box records the choice for future saves; the current save
    /// still honours the button that was clicked.
    @discardableResult
    static func presentWarning(defaults: UserDefaults = .standard) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Save as plain text?"
        alert.informativeText = "Plain text cannot hold bold or italic — the formatting will be removed."
        alert.addButton(withTitle: "Save Anyway")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't show this again"

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            defaults.set(true, forKey: suppressKey)
        }
        return response == .alertFirstButtonReturn
    }

    /// Returns true when the write may proceed. Called from the serialization
    /// context, which may be any thread.
    ///
    /// `ask` is injectable so the write path can be tested without a modal
    /// alert — tests supply a stub, production gets the real dialog.
    nonisolated static func approveFlattening(
        runs: [StyledRun],
        defaults: UserDefaults = .standard,
        ask: @escaping @MainActor (UserDefaults) -> Bool = { presentWarning(defaults: $0) }
    ) -> Bool {
        // UserDefaults is documented thread-safe, and `sync` means the value
        // cannot outlive this call — neither of which Swift 6 can prove.
        nonisolated(unsafe) let defaults = defaults
        let decide = {
            MainActor.assumeIsolated {
                needsApproval(runs: runs, defaults: defaults) ? ask(defaults) : true
            }
        }
        return Thread.isMainThread ? decide() : DispatchQueue.main.sync(execute: decide)
    }
}
