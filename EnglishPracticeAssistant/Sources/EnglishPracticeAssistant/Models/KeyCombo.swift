import Cocoa

struct KeyCombo: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt
    var isModifierOnly: Bool

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isModifierOnly: Bool = false) {
        self.keyCode = keyCode
        self.modifiers = modifiers.rawValue
        self.isModifierOnly = isModifierOnly
    }

    static func modifierOnly(_ modifier: NSEvent.ModifierFlags) -> KeyCombo {
        let keyCode: UInt16
        switch modifier {
        case .control: keyCode = 59
        case .shift: keyCode = 56
        case .option: keyCode = 58
        case .command: keyCode = 55
        default: keyCode = 59
        }
        return KeyCombo(keyCode: keyCode, modifiers: modifier, isModifierOnly: true)
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    var displayString: String {
        if isModifierOnly {
            return modifierFlags.humanReadable
        }
        let key = KeyCodeMap.name(for: keyCode)
        let prefix = modifierFlags.humanReadable
        if prefix.isEmpty { return key }
        return "\(prefix)+\(key)"
    }
}

extension NSEvent.ModifierFlags {
    static let relevant: NSEvent.ModifierFlags = [.command, .option, .shift, .control]

    var humanReadable: String {
        var parts: [String] = []
        if contains(.control) { parts.append("Ctrl") }
        if contains(.option) { parts.append("Opt") }
        if contains(.shift) { parts.append("Shift") }
        if contains(.command) { parts.append("Cmd") }
        if parts.isEmpty { return "" }
        return parts.joined(separator: "+")
    }
}

enum KeyCodeMap {
    static func name(for keyCode: UInt16) -> String {
        switch keyCode {
        case 15: return "R"
        case 5: return "G"
        case 49: return "Space"
        case 36: return "Return"
        case 51: return "Delete"
        default:
            return "Key\(keyCode)"
        }
    }
}
