import AppKit

/// Двойное нажатие модификатора (например, ⌃ ⌃) — как «Ctrl+Ctrl» в QTranslate.
/// Требует разрешения «Универсальный доступ».
@MainActor
final class DoubleTapMonitor {
    var modifier: NSEvent.ModifierFlags?
    var onDoubleTap: (() -> Void)?

    private var monitors: [Any] = []
    private var pressedAlone = false
    private var pressTime: TimeInterval = 0
    private var lastTapTime: TimeInterval = 0

    private let maxHold: TimeInterval = 0.35
    private let maxGap: TimeInterval = 0.45

    func start() {
        guard monitors.isEmpty else { return }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] e in
            self?.handleFlags(e)
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] e in
            self?.handleFlags(e)
            return e
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.reset()
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown], handler: { [weak self] e in
            self?.reset()
            return e
        }) { monitors.append(m) }
    }

    func restart() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        start()
    }

    private func reset() {
        pressedAlone = false
        lastTapTime = 0
    }

    private func handleFlags(_ event: NSEvent) {
        guard let target = modifier else { return }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let now = event.timestamp
        if flags == target {
            pressedAlone = true
            pressTime = now
        } else if flags.isEmpty, pressedAlone {
            pressedAlone = false
            if now - pressTime > maxHold {
                lastTapTime = 0
                return
            }
            if lastTapTime > 0, now - lastTapTime < maxGap {
                lastTapTime = 0
                onDoubleTap?()
            } else {
                lastTapTime = now
            }
        } else {
            pressedAlone = false
            lastTapTime = 0
        }
    }
}

/// Кнопка с первого клика (без предварительной активации окна).
final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// «Режим мыши»: после выделения текста мышью рядом с курсором появляется значок перевода.
@MainActor
final class MouseModeMonitor {
    var onTrigger: (() -> Void)?

    var enabled = false {
        didSet {
            guard enabled != oldValue else { return }
            enabled ? start() : stop()
        }
    }

    private var monitors: [Any] = []
    private var downPoint: NSPoint = .zero
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    private func start() {
        guard monitors.isEmpty else { return }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            self?.mouseDown()
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] e in
            self?.mouseUp(clickCount: e.clickCount)
        }) { monitors.append(m) }
    }

    private func stop() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        hideButton()
    }

    private func mouseDown() {
        downPoint = NSEvent.mouseLocation
        if let panel, !panel.frame.contains(downPoint) { hideButton() }
    }

    private func mouseUp(clickCount: Int) {
        let up = NSEvent.mouseLocation
        let dragged = hypot(up.x - downPoint.x, up.y - downPoint.y) > 6
        guard dragged || clickCount >= 2 else { return }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
        showButton(at: up)
    }

    private func showButton(at point: NSPoint) {
        let size: CGFloat = 26
        let p = panel ?? makePanel(size: size)
        panel = p
        p.setFrameOrigin(NSPoint(x: point.x + 8, y: point.y - size - 8))
        p.orderFrontRegardless()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if Task.isCancelled { return }
            self?.hideButton()
        }
    }

    private func hideButton() {
        hideTask?.cancel()
        panel?.orderOut(nil)
    }

    private func makePanel(size: CGFloat) -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let button = FirstMouseButton(frame: NSRect(x: 0, y: 0, width: size, height: size))
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        button.image = NSImage(systemSymbolName: "character.bubble.fill", accessibilityDescription: "Перевести")
        button.contentTintColor = .white
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(clicked)
        button.toolTip = "Перевести выделенное"
        p.contentView = button
        return p
    }

    @objc private func clicked() {
        hideButton()
        onTrigger?()
    }
}
