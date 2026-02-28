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
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 50: return "`"
        case 49: return "Space"
        case 36: return "Return"
        case 51: return "Delete"
        default:
            return "Key\(keyCode)"
        }
    }
}
