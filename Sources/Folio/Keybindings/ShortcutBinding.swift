// Sources/Folio/Keybindings/ShortcutBinding.swift
import Carbon

struct ShortcutBinding: Equatable, Codable, Hashable {
    let keyCode: UInt16
    let modifiers: UInt64

    static let modifierMask: UInt64 = 0x001E0000

    var displayString: String {
        var s = ""
        if modifiers & CGEventFlags.maskControl.rawValue   != 0 { s += "⌃" }
        if modifiers & CGEventFlags.maskAlternate.rawValue != 0 { s += "⌥" }
        if modifiers & CGEventFlags.maskShift.rawValue     != 0 { s += "⇧" }
        if modifiers & CGEventFlags.maskCommand.rawValue   != 0 { s += "⌘" }
        s += glyph(for: keyCode)
        return s
    }

    private func glyph(for code: UInt16) -> String {
        switch code {
        case 36:  return "↩"
        case 49:  return "Space"
        case 51:  return "⌫"
        case 53:  return "⎋"
        case 117: return "⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            guard let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "[\(code)]" }
            let data = Unmanaged<CFData>.fromOpaque(ptr).takeRetainedValue() as Data
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            var deadKey: UInt32 = 0
            data.withUnsafeBytes { raw in
                let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!
                UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKey, 4, &length, &chars)
            }
            return length > 0 ? String(chars[0]).uppercased() : "[\(code)]"
        }
    }
}
