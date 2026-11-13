import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Получение выделенного текста из любого приложения и замена выделения.
@MainActor
enum SelectionService {
    nonisolated static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Показывает системный запрос на доступ к «Универсальному доступу».
    @discardableResult
    static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Выделенный текст: сначала через Accessibility API, затем через ⌘C (с восстановлением буфера обмена).
    static func selectedText() async -> String? {
        if let text = accessibilitySelectedText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        guard isTrusted else { return nil }
        return await copySelectionViaClipboard()
    }

    static func accessibilitySelectedText() -> String? {
        guard isTrusted else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let element = focused as! AXUIElement
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    static func clipboardText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    static func copySelectionViaClipboard() async -> String? {
        let pb = NSPasteboard.general
        let saved = snapshot(pb)
        let before = pb.changeCount
        await waitForModifiersRelease()
        postKey(CGKeyCode(kVK_ANSI_C), flags: .maskCommand)

        var changed = false
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if pb.changeCount != before { changed = true; break }
        }
        guard changed else { return nil }
        // Небольшая пауза: некоторые приложения пишут в буфер в несколько приёмов.
        try? await Task.sleep(nanoseconds: 30_000_000)
        let text = pb.string(forType: .string)
        restore(pb, saved)
        return text
    }

    /// Вставляет `text` вместо выделения (через буфер обмена и ⌘V), затем восстанавливает буфер.
    static func replaceSelection(with text: String) async {
        let pb = NSPasteboard.general
        let saved = snapshot(pb)
        pb.clearContents()
        pb.setString(text, forType: .string)
        await waitForModifiersRelease()
        postKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        try? await Task.sleep(nanoseconds: 500_000_000)
        restore(pb, saved)
    }

    // MARK: - Низкоуровневое

    private static func waitForModifiersRelease() async {
        for _ in 0..<30 {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty { return }
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
    }

    private static func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        down?.flags = flags
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private typealias Snapshot = [[(NSPasteboard.PasteboardType, Data)]]

    private static func snapshot(_ pb: NSPasteboard) -> Snapshot {
        (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    private static func restore(_ pb: NSPasteboard, _ snapshot: Snapshot) {
        pb.clearContents()
        let items: [NSPasteboardItem] = snapshot.compactMap { pairs in
            guard !pairs.isEmpty else { return nil }
            let item = NSPasteboardItem()
            for (type, data) in pairs { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pb.writeObjects(items) }
    }
}
