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

enum LineHeight: Double, CaseIterable, Codable {
    case compact = 1.4
    case normal  = 1.6
    case relaxed = 1.8
}

@Observable
@MainActor
final class PreferencesStore {
    private let defaults: UserDefaults
    private var _fontSize: Int
    private var _autoSaveDelay: Int

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
    var autoSaveEnabled: Bool {
        didSet { defaults.set(autoSaveEnabled, forKey: Keys.autoSaveEnabled) }
    }
    var autoSaveDelay: Int {
        get { _autoSaveDelay }
        set {
            let clamped = max(1, newValue)
            _autoSaveDelay = clamped
            defaults.set(clamped, forKey: Keys.autoSaveDelay)
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
        self.autoSaveEnabled = defaults.bool(forKey: Keys.autoSaveEnabled)
        let rawDelay = defaults.object(forKey: Keys.autoSaveDelay) != nil
            ? defaults.integer(forKey: Keys.autoSaveDelay) : 2
        self._autoSaveDelay = max(1, rawDelay)
    }

    private enum Keys {
        static let fontSize        = "folio.prefs.fontSize"
        static let lineHeight      = "folio.prefs.lineHeight"
        static let columnWidth     = "folio.prefs.columnWidth"
        static let autoSaveEnabled = "folio.prefs.autoSaveEnabled"
        static let autoSaveDelay   = "folio.prefs.autoSaveDelay"
    }
}

extension PreferencesStore {
    func setFontSize(_ size: Int) {
        fontSize = size  // clamping happens in the setter
    }
}
