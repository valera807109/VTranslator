import AppKit
import Carbon.HIToolbox

/// Глобальные горячие клавиши через Carbon RegisterEventHotKey.
/// Не требует разрешения «Универсальный доступ» — работает в любом приложении.
@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    var onAction: ((HotkeyAction) -> Void)?
    /// Действия, которые не удалось зарегистрировать (сочетание занято системой).
    @Published private(set) var failed: Set<HotkeyAction> = []

    private var refs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private var paused = false
    private var current: [HotkeyAction: Hotkey] = [:]

    private static let signature: OSType = 0x5654_524E  // 'VTRN'

    func installHandler() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID)
            guard err == noErr else { return err }
            let id = hotKeyID.id
            Task { @MainActor in HotkeyManager.shared.fire(id: id) }
            return noErr
        }, 1, &spec, nil, &handlerRef)
        if status != noErr { NSLog("VTranslator: InstallEventHandler failed \(status)") }
    }

    func register(_ map: [HotkeyAction: Hotkey]) {
        current = map
        unregisterAll()
        guard !paused else { return }
        var failedNow: Set<HotkeyAction> = []
        for (index, action) in HotkeyAction.allCases.enumerated() {
            guard let hk = map[action] else { continue }
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            let status = RegisterEventHotKey(hk.keyCode, hk.carbonModifiers, hkID, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
            } else {
                failedNow.insert(action)
            }
        }
        failed = failedNow
    }

    /// Временно отключить (например, пока пользователь записывает новое сочетание).
    func pause() {
        paused = true
        unregisterAll()
    }

    func resume() {
        paused = false
        register(current)
    }

    private func unregisterAll() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }

    private func fire(id: UInt32) {
        let index = Int(id) - 1
        let all = HotkeyAction.allCases
        guard index >= 0, index < all.count else { return }
        onAction?(all[index])
    }
}
