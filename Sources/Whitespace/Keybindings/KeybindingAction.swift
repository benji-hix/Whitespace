// Sources/Whitespace/Keybindings/KeybindingAction.swift
import Carbon

enum KeybindingAction: String, CaseIterable, Codable {
    case deleteWordLeft     // ⌥⌫
    case deleteWordRight    // ⌥⌦
    case deleteToLineStart  // ⌘⌫
    case deleteToLineEnd    // ⌘⌦
    case killLine           // ⌃K  (delete rest of line)
    case deleteCharForward  // ⌃D

    var displayName: String {
        switch self {
        case .deleteWordLeft:    return "Delete Word Left"
        case .deleteWordRight:   return "Delete Word Right"
        case .deleteToLineStart: return "Delete to Line Start"
        case .deleteToLineEnd:   return "Delete to Line End"
        case .killLine:          return "Kill Line"
        case .deleteCharForward: return "Delete Char Forward"
        }
    }

    var defaultBinding: ShortcutBinding {
        let opt  = CGEventFlags.maskAlternate.rawValue
        let cmd  = CGEventFlags.maskCommand.rawValue
        let ctrl = CGEventFlags.maskControl.rawValue
        switch self {
        case .deleteWordLeft:    return ShortcutBinding(keyCode: 51,  modifiers: opt)
        case .deleteWordRight:   return ShortcutBinding(keyCode: 117, modifiers: opt)
        case .deleteToLineStart: return ShortcutBinding(keyCode: 51,  modifiers: cmd)
        case .deleteToLineEnd:   return ShortcutBinding(keyCode: 117, modifiers: cmd)
        case .killLine:          return ShortcutBinding(keyCode: 40,  modifiers: ctrl)
        case .deleteCharForward: return ShortcutBinding(keyCode: 2,   modifiers: ctrl)
        }
    }
}
