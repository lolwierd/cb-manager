import AppKit
import Carbon
import Foundation

struct HotKeyShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let fallback = HotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    var title: String {
        let symbols = modifierSymbols(modifiers)
        let key = keyName(keyCode)
        return symbols + key
    }

    var isValid: Bool {
        let command = UInt32(cmdKey)
        let option = UInt32(optionKey)
        let control = UInt32(controlKey)
        return (modifiers & command) != 0 || (modifiers & option) != 0 || (modifiers & control) != 0
    }

    private func modifierSymbols(_ flags: UInt32) -> String {
        var result = ""
        if (flags & UInt32(controlKey)) != 0 { result += "⌃" }
        if (flags & UInt32(optionKey)) != 0 { result += "⌥" }
        if (flags & UInt32(shiftKey)) != 0 { result += "⇧" }
        if (flags & UInt32(cmdKey)) != 0 { result += "⌘" }
        return result
    }

    private func keyName(_ code: UInt32) -> String {
        switch Int(code) {
        case Int(kVK_ANSI_A): "A"
        case Int(kVK_ANSI_B): "B"
        case Int(kVK_ANSI_C): "C"
        case Int(kVK_ANSI_D): "D"
        case Int(kVK_ANSI_E): "E"
        case Int(kVK_ANSI_F): "F"
        case Int(kVK_ANSI_G): "G"
        case Int(kVK_ANSI_H): "H"
        case Int(kVK_ANSI_I): "I"
        case Int(kVK_ANSI_J): "J"
        case Int(kVK_ANSI_K): "K"
        case Int(kVK_ANSI_L): "L"
        case Int(kVK_ANSI_M): "M"
        case Int(kVK_ANSI_N): "N"
        case Int(kVK_ANSI_O): "O"
        case Int(kVK_ANSI_P): "P"
        case Int(kVK_ANSI_Q): "Q"
        case Int(kVK_ANSI_R): "R"
        case Int(kVK_ANSI_S): "S"
        case Int(kVK_ANSI_T): "T"
        case Int(kVK_ANSI_U): "U"
        case Int(kVK_ANSI_V): "V"
        case Int(kVK_ANSI_W): "W"
        case Int(kVK_ANSI_X): "X"
        case Int(kVK_ANSI_Y): "Y"
        case Int(kVK_ANSI_Z): "Z"
        case Int(kVK_ANSI_0): "0"
        case Int(kVK_ANSI_1): "1"
        case Int(kVK_ANSI_2): "2"
        case Int(kVK_ANSI_3): "3"
        case Int(kVK_ANSI_4): "4"
        case Int(kVK_ANSI_5): "5"
        case Int(kVK_ANSI_6): "6"
        case Int(kVK_ANSI_7): "7"
        case Int(kVK_ANSI_8): "8"
        case Int(kVK_ANSI_9): "9"
        case Int(kVK_Space): "Space"
        case Int(kVK_Return): "↩"
        case Int(kVK_Escape): "⎋"
        case Int(kVK_Tab): "⇥"
        case Int(kVK_Delete): "⌫"
        default: "Key\(code)"
        }
    }
}

extension NSEvent.ModifierFlags {
    var carbonHotKeyModifiers: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.control) { flags |= UInt32(controlKey) }
        return flags
    }
}
