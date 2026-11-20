// Sources/Whitespace/Files/PlainTextConversionGate.swift
import AppKit
import UniformTypeIdentifiers

/// Saving formatted content as plain text flattens bold/italic, so a save the
/// user asked for asks first.
///
/// The question is put at the save operation, before NSDocument starts
/// writing (`WhitespaceDocument.save(to:ofType:for:completionHandler:)`), not
/// inside the write. The save is held, not aborted: the URL and type the user
/// chose in the save panel are kept and the same save carries on after Save
/// Anyway. Aborting and re-sending `save:` targets the document's existing URL
/// instead, and does nothing at all on a clean document, which is why "Save
/// Anyway" once silently wrote nothing.
@MainActor
enum PlainTextConversionGate {
    static let suppressKey = "whitespace.prefs.suppressPlainTextConversionWarning"

    /// Would this content lose formatting the user has not already agreed to
    /// lose?
    static func needsApproval(runs: [StyledRun], defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: suppressKey) else { return false }
        return runs.contains { $0.bold || $0.italic }
    }

    /// Whether this save should ask before it writes. Only a Save or Save As
    /// the user asked for: an autosave runs unprompted while they write, and
    /// after Save Anyway to plain text the file already holds no formatting
    /// to protect.
    static func shouldAsk(before operation: NSDocument.SaveOperationType, to type: UTType,
                          runs: [StyledRun], defaults: UserDefaults = .standard) -> Bool {
        guard isUserSave(operation), !type.conforms(to: WhitespaceDocument.markdownType) else { return false }
        return needsApproval(runs: runs, defaults: defaults)
    }

    /// Save and Save As, listed rather than "not an autosave", so a save
    /// operation AppKit adds later stays silent until someone decides.
    static func isUserSave(_ operation: NSDocument.SaveOperationType) -> Bool {
        switch operation {
        case .saveOperation, .saveAsOperation: true
        default: false
        }
    }

    /// Shows the warning, as a sheet when there is a window, and reports
    /// whether the save may go ahead. Ticking the suppression box records the
    /// choice for future saves; the current save still honours the button
    /// that was clicked.
    static func presentWarning(on window: NSWindow?, defaults: UserDefaults,
                               completion: @escaping @MainActor (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Save as plain text?"
        alert.informativeText = "Plain text cannot hold bold or italic — the formatting will be removed."
        alert.addButton(withTitle: "Save Anyway")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't show this again"

        let finish: @MainActor (NSApplication.ModalResponse) -> Void = { response in
            if alert.suppressionButton?.state == .on {
                defaults.set(true, forKey: suppressKey)
            }
            completion(response == .alertFirstButtonReturn)
        }
        if let window {
            alert.beginSheetModal(for: window) { response in MainActor.assumeIsolated { finish(response) } }
        } else {
            finish(alert.runModal())
        }
    }
}
