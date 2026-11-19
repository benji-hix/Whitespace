import Foundation

enum ColumnWidth: String, CaseIterable, Codable {
    case narrow, medium, wide

    var maxPoints: CGFloat {
        switch self {
        case .narrow: return 560
        case .medium: return 680
        case .wide:   return 820
        }
    }
}

enum NewDocumentType: String, CaseIterable, Codable {
    case markdown, plainText

    /// Shared with WhitespaceDocumentController, which types new untitled
    /// documents from it outside any store instance.
    static let defaultsKey = "whitespace.prefs.newDocumentType"
}

@Observable
@MainActor
final class PreferencesStore {
    private let defaults: UserDefaults
    private var _fontSize: Int
    private var _shortcutsAutoDismissDelay: Int

    var newDocumentType: NewDocumentType {
        didSet { defaults.set(newDocumentType.rawValue, forKey: Keys.newDocumentType) }
    }

    /// Stored inverted: the gate reads a *suppress* flag, because that is what
    /// NSAlert's suppression button writes. Settings shows the positive sense.
    var warnBeforeFlatteningFormatting: Bool {
        didSet { defaults.set(!warnBeforeFlatteningFormatting, forKey: PlainTextConversionGate.suppressKey) }
    }

    /// The alert's suppression checkbox writes the same key straight to
    /// UserDefaults, with no route back into this store — so after a user ticks
    /// it, this cached value is stale for the rest of the session and Settings
    /// would show the warning as enabled while it is actually off. Settings
    /// calls this when it appears.
    func reloadFlattenWarning() {
        let live = !defaults.bool(forKey: PlainTextConversionGate.suppressKey)
        if live != warnBeforeFlatteningFormatting {
            warnBeforeFlatteningFormatting = live
        }
    }

    var fontSize: Int {
        get { _fontSize }
        set {
            let clamped = min(28, max(12, newValue))
            _fontSize = clamped
            defaults.set(clamped, forKey: Keys.fontSize)
        }
    }

    var lineHeightMultiple: Double {
        didSet { defaults.set(lineHeightMultiple, forKey: Keys.lineHeight) }
    }
    var columnWidth: ColumnWidth {
        didSet { defaults.set(columnWidth.rawValue, forKey: Keys.columnWidth) }
    }
    var scrollSpeed: Double {
        didSet { defaults.set(scrollSpeed, forKey: Keys.scrollSpeed) }
    }

    var shortcutsAutoDismissEnabled: Bool {
        didSet { defaults.set(shortcutsAutoDismissEnabled, forKey: Keys.shortcutsAutoDismissEnabled) }
    }

    var shortcutsAutoDismissDelay: Int {
        get { _shortcutsAutoDismissDelay }
        set {
            let clamped = max(1, newValue)
            _shortcutsAutoDismissDelay = clamped
            defaults.set(clamped, forKey: Keys.shortcutsAutoDismissDelay)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let rawFontSize = defaults.object(forKey: Keys.fontSize) != nil
            ? defaults.integer(forKey: Keys.fontSize) : 18
        self._fontSize = min(28, max(12, rawFontSize))
        let rawLineHeight = defaults.object(forKey: Keys.lineHeight) != nil
            ? defaults.double(forKey: Keys.lineHeight) : 1.6
        self.lineHeightMultiple = rawLineHeight
        if let raw = defaults.string(forKey: Keys.columnWidth),
           let cw = ColumnWidth(rawValue: raw) {
            self.columnWidth = cw
        } else {
            self.columnWidth = .medium
        }
        let rawSpeed = defaults.object(forKey: Keys.scrollSpeed) != nil
            ? defaults.double(forKey: Keys.scrollSpeed) : 1.0
        self.scrollSpeed = min(2.0, max(0.4, rawSpeed))
        if let raw = defaults.string(forKey: Keys.newDocumentType),
           let type = NewDocumentType(rawValue: raw) {
            self.newDocumentType = type
        } else {
            self.newDocumentType = .markdown
        }
        self.warnBeforeFlatteningFormatting = !defaults.bool(forKey: PlainTextConversionGate.suppressKey)
        self.shortcutsAutoDismissEnabled = defaults.bool(forKey: Keys.shortcutsAutoDismissEnabled)
        let rawShortcutDelay = defaults.object(forKey: Keys.shortcutsAutoDismissDelay) != nil
            ? defaults.integer(forKey: Keys.shortcutsAutoDismissDelay) : 4
        self._shortcutsAutoDismissDelay = max(1, rawShortcutDelay)
    }

    private enum Keys {
        static let fontSize        = "whitespace.prefs.fontSize"
        static let lineHeight      = "whitespace.prefs.lineHeight"
        static let columnWidth     = "whitespace.prefs.columnWidth"
        static let scrollSpeed     = "whitespace.prefs.scrollSpeed"
        static let newDocumentType = NewDocumentType.defaultsKey
        static let shortcutsAutoDismissEnabled = "whitespace.prefs.shortcutsAutoDismissEnabled"
        static let shortcutsAutoDismissDelay   = "whitespace.prefs.shortcutsAutoDismissDelay"
    }
}

extension PreferencesStore {
    func setFontSize(_ size: Int) {
        fontSize = size  // clamping happens in the setter
    }
}
