// Sources/Whitespace/App/WhitespaceDocumentController.swift
import AppKit
import UniformTypeIdentifiers

/// Types new untitled documents from Settings ▸ Documents ▸ New Files. Without
/// this, AppKit takes the first Editor type in Info.plist, which is Plain Text.
final class WhitespaceDocumentController: NSDocumentController {
    override var defaultType: String? {
        Self.defaultTypeIdentifier(defaults: .standard)
    }

    /// Pure, because NSDocumentController is effectively a singleton: a second
    /// instance hands back the shared one, so tests cannot inject defaults
    /// through an initialiser.
    static func defaultTypeIdentifier(defaults: UserDefaults) -> String {
        let prefersPlainText = defaults.string(forKey: NewDocumentType.defaultsKey)
            == NewDocumentType.plainText.rawValue
        return prefersPlainText ? UTType.plainText.identifier : WhitespaceDocument.markdownType.identifier
    }
}
