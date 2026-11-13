import AppKit
import Carbon.HIToolbox

/// Действия, на которые можно назначить глобальную горячую клавишу.
enum HotkeyAction: String, CaseIterable, Codable, Identifiable {
    case popupTranslate
    case mainWindow
    case speakSelection
    case replaceSelection
    case ocrTranslate
    case translateClipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .popupTranslate: return "Перевести выделенное во всплывающем окне"
        case .mainWindow: return "Перевести выделенное в главном окне"
        case .speakSelection: return "Прослушать выделенный текст"
        case .replaceSelection: return "Заменить выделенный текст переводом"
        case .ocrTranslate: return "Распознать текст с экрана и перевести"
        case .translateClipboard: return "Перевести текст из буфера обмена"
        }
    }

    var defaultHotkey: Hotkey? {
        let ctrl = NSEvent.ModifierFlags.control.rawValue
        let shift = NSEvent.ModifierFlags.shift.rawValue
        switch self {
        case .popupTranslate: return Hotkey(keyCode: UInt32(kVK_ANSI_Q), modifiers: ctrl)
        case .mainWindow: return Hotkey(keyCode: UInt32(kVK_ANSI_W), modifiers: ctrl)
        case .speakSelection: return Hotkey(keyCode: UInt32(kVK_ANSI_E), modifiers: ctrl)
        case .replaceSelection: return Hotkey(keyCode: UInt32(kVK_ANSI_I), modifiers: ctrl)
        case .ocrTranslate: return Hotkey(keyCode: UInt32(kVK_ANSI_Q), modifiers: ctrl | shift)
        case .translateClipboard: return nil
        }
    }
}

struct Hotkey: Codable, Equatable, Hashable {
    var keyCode: UInt32
    /// Сырые значения NSEvent.ModifierFlags (command/option/control/shift).
    var modifiers: UInt

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    var display: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + KeyNames.name(for: keyCode)
    }
}

enum KeyNames {
    private static let table: [UInt32: String] = {
        let t: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
            kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
            kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
            kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
            kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
            kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
            kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
            kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`",
            kVK_Space: "Пробел", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "PgUp", kVK_PageDown: "PgDn",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
            kVK_F18: "F18", kVK_F19: "F19",
        ]
        var result: [UInt32: String] = [:]
        for (k, v) in t { result[UInt32(k)] = v }
        return result
    }()

    static let functionKeys: Set<UInt32> = Set([
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19,
    ].map { UInt32($0) })

    static func name(for keyCode: UInt32) -> String {
        table[keyCode] ?? "#\(keyCode)"
    }
}
