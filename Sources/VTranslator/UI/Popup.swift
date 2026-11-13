import AppKit
import SwiftUI

/// Содержимое всплывающего окна перевода.
struct PopupView: View {
    @ObservedObject var vm: TranslationViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var speech: SpeechService
    var onClose: @MainActor () -> Void
    var onOpenMain: @MainActor () -> Void

    private var fontSize: CGFloat { CGFloat(settings.popupFontSize) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .controlSize(.small)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            Divider()
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        }
        .frame(minWidth: 300, minHeight: 110)
        .onChange(of: settings.sourceLang) { _ in retranslate() }
        .onChange(of: settings.targetLang) { _ in retranslate() }
        .onChange(of: settings.engine) { _ in retranslate() }
    }

    private func retranslate() {
        if !vm.sourceText.isBlank { vm.translate() }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            LanguagePicker(selection: $settings.sourceLang, includeAuto: true, compact: true)
                .frame(width: 118)
            Button {
                vm.swapLanguages()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .buttonStyle(.borderless)
            .help("Поменять языки местами")
            LanguagePicker(selection: $settings.targetLang, compact: true)
                .frame(width: 118)
            Picker("", selection: $settings.engine) {
                ForEach(EngineID.allCases) { engine in
                    Text(engine == .google ? "G" : "Я").tag(engine)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 64)
            .help("Сервис перевода: Google / Яндекс")
            Spacer(minLength: 4)
            IconButton(
                systemName: speech.isSpeaking ? "stop.fill" : "speaker.wave.2",
                help: "Прослушать перевод") { vm.speakTranslation() }
            IconButton(systemName: "doc.on.doc", help: "Копировать перевод") { vm.copyTranslation() }
            IconButton(systemName: "macwindow", help: "Открыть в главном окне") { onOpenMain() }
            IconButton(
                systemName: vm.pinned ? "pin.fill" : "pin",
                help: "Не закрывать при щелчке вне окна",
                active: vm.pinned) { vm.pinned.toggle() }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if settings.popupShowSource, !vm.sourceText.isBlank {
                Text(vm.sourceText)
                    .font(.system(size: fontSize - 2))
                    .foregroundColor(.secondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
            if vm.isLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Перевод…").foregroundColor(.secondary)
                }
            } else if let error = vm.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                if !vm.sourceText.isBlank {
                    Button("Повторить") { vm.translate() }
                }
            } else if let r = vm.result {
                Text(r.text)
                    .font(.system(size: fontSize))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if settings.showTransliteration, let t = r.transliteration, t != r.text {
                    Text(t)
                        .font(.system(size: fontSize - 2))
                        .italic()
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                if settings.showDictionary, !r.dictionary.isEmpty {
                    Divider()
                    DictionaryView(entries: r.dictionary, fontSize: fontSize - 2)
                }
                Text("\(Languages.name(r.sourceLang)) → \(Languages.name(r.targetLang)) · \(r.engine.title)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
        }
    }
}

final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc закрывает окно.
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

/// Всплывающее окно рядом с курсором (аналог popup-окна QTranslate).
@MainActor
final class PopupController: NSObject, NSWindowDelegate {
    let vm = TranslationViewModel()
    var onOpenMain: ((TranslationViewModel) -> Void)?

    private var panel: PopupPanel?
    private var clickMonitor: Any?

    var isVisible: Bool { panel?.isVisible == true }

    func show(text: String) {
        present()
        vm.setSource(text)
        vm.translate()
    }

    func showMessage(_ message: String) {
        present()
        vm.setSource("")
        vm.showMessage(message)
    }

    func close() {
        panel?.close()
    }

    private func present() {
        let p = panel ?? makePanel()
        panel = p
        if !p.isVisible || !vm.pinned { position(p) }
        p.orderFrontRegardless()
        p.makeKey()
        installClickMonitor()
    }

    private func makePanel() -> PopupPanel {
        let s = AppSettings.shared
        let p = PopupPanel(
            contentRect: NSRect(x: 0, y: 0, width: s.popupWidth, height: s.popupHeight),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        p.title = "VTranslator"
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isMovableByWindowBackground = true
        p.becomesKeyOnlyIfNeeded = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.minSize = NSSize(width: 300, height: 120)
        p.delegate = self

        let root = PopupView(
            vm: vm,
            settings: s,
            speech: SpeechService.shared,
            onClose: { [weak self] in self?.close() },
            onOpenMain: { [weak self] in self?.openMain() })
        let host = NSHostingController(rootView: root)
        host.sizingOptions = []
        p.contentViewController = host
        p.setContentSize(NSSize(width: s.popupWidth, height: s.popupHeight))
        return p
    }

    private func position(_ p: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = p.frame.size
        var x = mouse.x + 12
        var y = mouse.y - 18 - size.height
        if x + size.width > visible.maxX { x = visible.maxX - size.width - 4 }
        if x < visible.minX { x = visible.minX + 4 }
        if y < visible.minY { y = min(mouse.y + 18, visible.maxY - size.height - 4) }
        if y + size.height > visible.maxY { y = visible.maxY - size.height - 4 }
        p.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.handleOutsideClick()
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    private func handleOutsideClick() {
        guard let panel, panel.isVisible else { return }
        guard AppSettings.shared.popupCloseOnClickOutside, !vm.pinned else { return }
        if !panel.frame.contains(NSEvent.mouseLocation) { close() }
    }

    private func openMain() {
        onOpenMain?(vm)
        if !vm.pinned { close() }
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        guard let panel else { return }
        let size = panel.contentRect(forFrameRect: panel.frame).size
        AppSettings.shared.popupWidth = Double(size.width)
        AppSettings.shared.popupHeight = Double(size.height)
    }

    func windowWillClose(_ notification: Notification) {
        removeClickMonitor()
        SpeechService.shared.stop()
    }
}
