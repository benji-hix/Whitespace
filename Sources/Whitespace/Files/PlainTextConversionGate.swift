// Sources/Whitespace/Files/PlainTextConversionGate.swift
import AppKit

/// Saving formatted content as plain text flattens bold/italic. The write
/// path (FileDocument.fileWrapper) must not present UI, so it consults this
/// gate and throws userCancelled; the gate then shows the warning and, on
/// "Save Anyway", arms a one-shot approval and re-sends the save action.
@MainActor
enum PlainTextConversionGate {
    static let suppressKey = "whitespace.prefs.suppressPlainTextConversionWarning"
    static var approvedNextWrite = false

    static func shouldWarn(runs: [StyledRun], defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: suppressKey) else { return false }
        if approvedNextWrite {
            approvedNextWrite = false
            return false
        }
        return runs.contains { $0.bold || $0.italic }
    }

    /// Bridges from the (possibly non-main) serialization context.
    nonisolated static func shouldWarnSync(runs: [StyledRun]) -> Bool {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { shouldWarn(runs: runs) }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { shouldWarn(runs: runs) }
        }
    }

    static func presentWarning(defaults: UserDefaults = .standard) {
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
        if response == .alertFirstButtonReturn {
            approvedNextWrite = true
            NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil)
        }
    }
}
