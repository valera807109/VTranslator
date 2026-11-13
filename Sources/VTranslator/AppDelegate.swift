import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let settings = AppSettings.shared
    private let popup = PopupController()
    private let mainVM = TranslationViewModel()
    private let settingsTab = SettingsTab()
    private let doubleTap = DoubleTapMonitor()
    private let mouseMode = MouseModeMonitor()

    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var trustTimer: Timer?
    private var wasTrusted = false
    private var busy = false

    // MARK: - Запуск

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusItem()

        let hotkeys = HotkeyManager.shared
        hotkeys.installHandler()
        hotkeys.onAction = { [weak self] action in self?.perform(action) }
        settings.$hotkeys
            .sink { map in HotkeyManager.shared.register(map) }
            .store(in: &cancellables)

        doubleTap.onDoubleTap = { [weak self] in
            guard let self else { return }
            self.perform(self.settings.doubleTapAction == .popup ? .popupTranslate : .mainWindow)
        }
        settings.$doubleTapKey
            .sink { [weak self] key in self?.doubleTap.modifier = key.flags }
            .store(in: &cancellables)
        doubleTap.start()

        mouseMode.onTrigger = { [weak self] in self?.perform(.popupTranslate) }
        settings.$mouseMode
            .sink { [weak self] on in self?.mouseMode.enabled = on }
            .store(in: &cancellables)

        settings.$showDockIcon
            .removeDuplicates()
            .sink { show in NSApp.setActivationPolicy(show ? .regular : .accessory) }
            .store(in: &cancellables)

        mainVM.$pinned
            .sink { [weak self] pinned in self?.mainWindow?.level = pinned ? .floating : .normal }
            .store(in: &cancellables)

        popup.onOpenMain = { [weak self] popupVM in
            guard let self else { return }
            self.mainVM.setSource(popupVM.sourceText)
            self.mainVM.result = popupVM.result
            self.mainVM.errorMessage = popupVM.errorMessage
            self.showMainWindow(text: nil)
        }

        wasTrusted = SelectionService.isTrusted
        if !wasTrusted {
            showSettings(tab: SettingsTab.permissions)
            SelectionService.requestTrust()
        } else if settings.showMainOnLaunch {
            showMainWindow(text: nil)
        }
        startTrustWatcher()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow(text: nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Глобальные мониторы клавиатуры начинают работать только после выдачи доступа —
    /// поэтому перезапускаем их, как только доступ появился.
    private func startTrustWatcher() {
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let trusted = SelectionService.isTrusted
                if trusted, !self.wasTrusted {
                    self.doubleTap.restart()
                    if self.settings.mouseMode {
                        self.mouseMode.enabled = false
                        self.mouseMode.enabled = true
                    }
                }
                self.wasTrusted = trusted
            }
        }
    }

    // MARK: - Действия горячих клавиш

    func perform(_ action: HotkeyAction) {
        if isExceptionAppFrontmost() { return }
        switch action {
        case .popupTranslate: translateSelectionInPopup()
        case .mainWindow: translateSelectionInMainWindow()
        case .speakSelection: speakSelection()
        case .replaceSelection: replaceSelection()
        case .ocrTranslate: recognizeScreenText()
        case .translateClipboard: translateClipboard()
        }
    }

    private func isExceptionAppFrontmost() -> Bool {
        guard let name = NSWorkspace.shared.frontmostApplication?.localizedName?.lowercased() else { return false }
        return settings.exceptionList.contains(name)
    }

    /// Выделенный текст или (по настройке) содержимое буфера обмена.
    private func grabText(allowClipboard: Bool) async -> String? {
        if let text = await SelectionService.selectedText(), !text.isBlank { return text }
        if allowClipboard, settings.clipboardFallback, let clip = SelectionService.clipboardText(), !clip.isBlank {
            return clip
        }
        return nil
    }

    private var noSelectionMessage: String {
        SelectionService.isTrusted
            ? "Не удалось получить выделенный текст. Выделите текст и нажмите сочетание ещё раз."
            : "Нет доступа к выделенному тексту. Разрешите VTranslator в «Системные настройки → Конфиденциальность и безопасность → Универсальный доступ»."
    }

    private func translateSelectionInPopup() {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            if let text = await grabText(allowClipboard: true) {
                popup.show(text: text)
            } else {
                popup.showMessage(noSelectionMessage)
                if !SelectionService.isTrusted { SelectionService.requestTrust() }
            }
        }
    }

    private func translateSelectionInMainWindow() {
        Task {
            let text = await grabText(allowClipboard: false)
            showMainWindow(text: text)
        }
    }

    private func translateClipboard() {
        guard let text = SelectionService.clipboardText(), !text.isBlank else {
            popup.showMessage("Буфер обмена не содержит текста.")
            return
        }
        popup.show(text: text)
    }

    private func speakSelection() {
        if SpeechService.shared.isSpeaking {
            SpeechService.shared.stop()
            return
        }
        Task {
            guard let text = await grabText(allowClipboard: false) else {
                NSSound.beep()
                return
            }
            let lang = await Translator.shared.detect(text) ?? "en"
            SpeechService.shared.speak(text, lang: lang)
        }
    }

    private func replaceSelection() {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            guard let text = await SelectionService.selectedText(), !text.isBlank else {
                NSSound.beep()
                return
            }
            do {
                let r = try await Translator.shared.translate(
                    text, from: settings.sourceLang, to: settings.targetLang, engine: settings.engine)
                HistoryStore.shared.add(r)
                await SelectionService.replaceSelection(with: r.text)
            } catch {
                popup.showMessage(error.localizedDescription)
            }
        }
    }

    private func recognizeScreenText() {
        Task {
            do {
                guard let text = try await OCRService.captureAndRecognize() else { return }
                if text.isBlank {
                    popup.showMessage("Текст в выбранной области не найден. Если окно выбора не появилось — разрешите «Запись экрана» в настройках.")
                } else {
                    popup.show(text: text)
                }
            } catch {
                popup.showMessage("Ошибка распознавания: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Окна

    func showMainWindow(text: String?) {
        if mainWindow == nil {
            let view = MainView(
                vm: mainVM,
                settings: settings,
                speech: SpeechService.shared,
                history: HistoryStore.shared,
                onOpenHistory: { [weak self] in self?.showHistory() },
                onOpenSettings: { [weak self] in self?.showSettings(tab: SettingsTab.general) })
            mainWindow = makeWindow(title: "VTranslator", size: NSSize(width: 600, height: 560), autosave: "MainWindow", view: view)
            mainWindow?.level = mainVM.pinned ? .floating : .normal
        }
        if let text, !text.isBlank {
            mainVM.setSource(text)
            mainVM.translate()
        }
        bringToFront(mainWindow)
    }

    @objc func showMainWindowAction() { showMainWindow(text: nil) }

    func showSettings(tab: Int) {
        settingsTab.selected = tab
        if settingsWindow == nil {
            let view = SettingsView(settings: settings, tab: settingsTab)
            settingsWindow = makeWindow(title: "Настройки VTranslator", size: NSSize(width: 640, height: 560), autosave: "SettingsWindow", view: view)
        }
        bringToFront(settingsWindow)
    }

    @objc func showSettingsAction() { showSettings(tab: SettingsTab.general) }

    func showHistory() {
        if historyWindow == nil {
            let view = HistoryView(store: HistoryStore.shared) { [weak self] entry in
                guard let self else { return }
                self.mainVM.load(entry)
                self.showMainWindow(text: nil)
            }
            historyWindow = makeWindow(title: "История переводов", size: NSSize(width: 520, height: 560), autosave: "HistoryWindow", view: view)
        }
        bringToFront(historyWindow)
    }

    @objc func showHistoryAction() { showHistory() }

    private func makeWindow<V: View>(title: String, size: NSSize, autosave: String, view: V) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        let host = NSHostingController(rootView: view)
        host.sizingOptions = [.minSize]
        window.contentViewController = host
        window.setContentSize(size)
        if !window.setFrameUsingName(autosave) { window.center() }
        window.setFrameAutosaveName(autosave)
        return window
    }

    private func bringToFront(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Главное меню (нужно для ⌘C/⌘V/⌘A в полях ввода)

    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "О VTranslator", action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Настройки…", action: #selector(showSettingsAction), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Скрыть VTranslator", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Завершить VTranslator", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Правка")
        edit.addItem(withTitle: "Отменить", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Повторить", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Выбрать всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "Окно")
        windowMenu.addItem(withTitle: "Закрыть", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Свернуть", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "История переводов", action: #selector(showHistoryAction), keyEquivalent: "y").target = self
        windowItem.submenu = windowMenu

        NSApp.mainMenu = main
    }

    @objc func showAbout() {
        showSettings(tab: SettingsTab.about)
    }

    // MARK: - Значок в строке меню

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "VTranslator")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "VTranslator — щелчок: главное окно, правый щелчок: меню"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        let isRight = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isRight {
            guard let statusItem else { return }
            statusItem.menu = buildStatusMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            if mainWindow?.isVisible == true, NSApp.isActive, mainWindow?.isKeyWindow == true {
                mainWindow?.orderOut(nil)
            } else {
                showMainWindow(text: nil)
            }
        }
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(menuItem("Перевести выделенное", #selector(menuPopupTranslate), hotkey: .popupTranslate))
        menu.addItem(menuItem("Главное окно", #selector(showMainWindowAction), hotkey: .mainWindow))
        menu.addItem(menuItem("Перевести буфер обмена", #selector(menuTranslateClipboard), hotkey: .translateClipboard))
        menu.addItem(menuItem("Распознать текст с экрана…", #selector(menuOCR), hotkey: .ocrTranslate))
        menu.addItem(.separator())

        let engineItem = NSMenuItem(title: "Сервис перевода", action: nil, keyEquivalent: "")
        let engineMenu = NSMenu()
        for engine in EngineID.allCases {
            let mi = NSMenuItem(title: engine.title, action: #selector(menuSelectEngine(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = engine.rawValue
            mi.state = settings.engine == engine ? .on : .off
            engineMenu.addItem(mi)
        }
        engineItem.submenu = engineMenu
        menu.addItem(engineItem)

        let langItem = NSMenuItem(title: "Переводить на: \(Languages.name(settings.targetLang))", action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        var codes = [settings.primaryLang, settings.secondaryLang]
        if !codes.contains(where: { Languages.same($0, settings.targetLang) }) { codes.append(settings.targetLang) }
        for code in codes {
            let mi = NSMenuItem(title: Languages.name(code), action: #selector(menuSelectTarget(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = code
            mi.state = Languages.same(code, settings.targetLang) ? .on : .off
            langMenu.addItem(mi)
        }
        langMenu.addItem(.separator())
        let more = NSMenuItem(title: "Другие языки…", action: #selector(menuLanguages), keyEquivalent: "")
        more.target = self
        langMenu.addItem(more)
        langItem.submenu = langMenu
        menu.addItem(langItem)

        let mouse = NSMenuItem(title: "Режим мыши", action: #selector(menuToggleMouseMode), keyEquivalent: "")
        mouse.target = self
        mouse.state = settings.mouseMode ? .on : .off
        menu.addItem(mouse)

        menu.addItem(.separator())
        menu.addItem(menuItem("История переводов…", #selector(showHistoryAction)))
        let prefs = menuItem("Настройки…", #selector(showSettingsAction))
        prefs.keyEquivalent = ","
        menu.addItem(prefs)
        if !SelectionService.isTrusted {
            menu.addItem(menuItem("⚠️ Выдать доступ (Универсальный доступ)…", #selector(menuPermissions)))
        }
        menu.addItem(.separator())
        menu.addItem(menuItem("О VTranslator", #selector(showAbout)))
        let quit = NSMenuItem(title: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    private func menuItem(_ title: String, _ action: Selector, hotkey: HotkeyAction? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let hotkey, let hk = settings.hotkeys[hotkey] {
            let name = KeyNames.name(for: hk.keyCode)
            if name.count == 1 {
                item.keyEquivalent = name.lowercased()
                item.keyEquivalentModifierMask = hk.flags
            }
        }
        return item
    }

    @objc private func menuPopupTranslate() {
        // Даём меню закрыться, чтобы ⌘C попал в приложение с выделенным текстом.
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            perform(.popupTranslate)
        }
    }

    @objc private func menuTranslateClipboard() { translateClipboard() }

    @objc private func menuOCR() {
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            recognizeScreenText()
        }
    }

    @objc private func menuSelectEngine(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let engine = EngineID(rawValue: raw) {
            settings.engine = engine
        }
    }

    @objc private func menuSelectTarget(_ sender: NSMenuItem) {
        if let code = sender.representedObject as? String { settings.targetLang = code }
    }

    @objc private func menuLanguages() { showSettings(tab: SettingsTab.languages) }

    @objc private func menuToggleMouseMode() { settings.mouseMode.toggle() }

    @objc private func menuPermissions() {
        showSettings(tab: SettingsTab.permissions)
        SelectionService.requestTrust()
    }
}
