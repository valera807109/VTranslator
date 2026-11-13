import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsTab: ObservableObject {
    @Published var selected = 0
    static let general = 0, languages = 1, hotkeys = 2, appearance = 3, permissions = 4, about = 5
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var tab: SettingsTab

    var body: some View {
        TabView(selection: $tab.selected) {
            GeneralSettingsView(settings: settings)
                .tabItem { Label("Основные", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            LanguageSettingsView(settings: settings)
                .tabItem { Label("Языки", systemImage: "globe") }
                .tag(SettingsTab.languages)
            HotkeySettingsView(settings: settings, manager: HotkeyManager.shared)
                .tabItem { Label("Клавиши", systemImage: "keyboard") }
                .tag(SettingsTab.hotkeys)
            AppearanceSettingsView(settings: settings)
                .tabItem { Label("Вид", systemImage: "textformat.size") }
                .tag(SettingsTab.appearance)
            PermissionsView()
                .tabItem { Label("Доступ", systemImage: "lock.shield") }
                .tag(SettingsTab.permissions)
            AboutView()
                .tabItem { Label("О программе", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .padding(12)
        .frame(minWidth: 620, minHeight: 520)
    }
}

// MARK: - Основные

struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Запуск") {
                Toggle("Запускать при входе в систему", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundColor(.red)
                }
                Toggle("Открывать главное окно при запуске", isOn: $settings.showMainOnLaunch)
                Toggle("Показывать значок в Dock", isOn: $settings.showDockIcon)
            }
            Section("Перевод") {
                Toggle("Переводить автоматически во время набора текста", isOn: $settings.autoTranslate)
                Toggle("Автоматически копировать перевод в буфер обмена", isOn: $settings.autoCopy)
                Toggle("Если ничего не выделено — переводить текст из буфера обмена", isOn: $settings.clipboardFallback)
            }
            Section("Озвучивание") {
                Picker("Голос", selection: $settings.ttsProvider) {
                    ForEach(TTSProvider.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("История") {
                Toggle("Сохранять историю переводов", isOn: $settings.historyEnabled)
                Stepper(value: $settings.historyLimit, in: 50...5000, step: 50) {
                    Text("Хранить записей: \(settings.historyLimit)")
                }
                .disabled(!settings.historyEnabled)
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Не удалось изменить автозапуск: \(error.localizedDescription). Переместите VTranslator в папку «Программы»."
        }
    }
}

// MARK: - Языки

struct LanguageSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Сервис перевода по умолчанию") {
                Picker("Сервис", selection: $settings.engine) {
                    ForEach(EngineID.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Направление перевода") {
                LabeledContent("С языка") {
                    LanguagePicker(selection: $settings.sourceLang, includeAuto: true).frame(width: 220)
                }
                LabeledContent("На язык") {
                    LanguagePicker(selection: $settings.targetLang).frame(width: 220)
                }
            }
            Section("Умное переключение языков") {
                Toggle("Если язык текста совпал с языком перевода — переводить на другой язык", isOn: $settings.smartSwitch)
                LabeledContent("Основной язык") {
                    LanguagePicker(selection: $settings.primaryLang).frame(width: 220)
                }
                LabeledContent("Второй язык") {
                    LanguagePicker(selection: $settings.secondaryLang).frame(width: 220)
                }
                Text("Например: основной — русский, второй — английский. Английский текст переводится на русский, а русский — на английский, без ручного переключения.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Горячие клавиши

struct HotkeySettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var manager: HotkeyManager

    var body: some View {
        Form {
            Section("Горячие клавиши (работают во всех приложениях)") {
                ForEach(HotkeyAction.allCases) { action in
                    LabeledContent {
                        HStack(spacing: 6) {
                            if manager.failed.contains(action) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .help("Сочетание занято системой или другим приложением")
                            }
                            HotkeyRecorder(hotkey: binding(for: action))
                        }
                    } label: {
                        Text(action.title)
                    }
                }
                Button("Сбросить по умолчанию") { settings.resetHotkeys() }
            }
            Section("Двойное нажатие клавиши") {
                Picker("Клавиша", selection: $settings.doubleTapKey) {
                    ForEach(DoubleTapKey.allCases) { Text($0.title).tag($0) }
                }
                Picker("Действие", selection: $settings.doubleTapAction) {
                    ForEach(DoubleTapAction.allCases) { Text($0.title).tag($0) }
                }
                .disabled(settings.doubleTapKey == .off)
                Text("Выделите текст и быстро нажмите клавишу два раза — перевод появится рядом с курсором.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section("Режим мыши") {
                Toggle("Показывать значок перевода после выделения текста мышью", isOn: $settings.mouseMode)
            }
            Section("Исключения") {
                Text("Приложения, в которых горячие клавиши VTranslator не срабатывают (названия через запятую или с новой строки):")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $settings.exceptions)
                    .font(.system(size: 12))
                    .frame(height: 54)
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for action: HotkeyAction) -> Binding<Hotkey?> {
        Binding(
            get: { settings.hotkeys[action] },
            set: { settings.hotkeys[action] = $0 })
    }
}

// MARK: - Внешний вид

struct AppearanceSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Размер шрифта") {
                Stepper(value: $settings.mainFontSize, in: 10...30, step: 1) {
                    Text("Главное окно: \(Int(settings.mainFontSize)) пт")
                }
                Stepper(value: $settings.popupFontSize, in: 10...30, step: 1) {
                    Text("Всплывающее окно: \(Int(settings.popupFontSize)) пт")
                }
            }
            Section("Всплывающее окно") {
                Toggle("Показывать исходный текст", isOn: $settings.popupShowSource)
                Toggle("Закрывать при щелчке вне окна", isOn: $settings.popupCloseOnClickOutside)
            }
            Section("Результат перевода") {
                Toggle("Показывать словарь (варианты перевода)", isOn: $settings.showDictionary)
                Toggle("Показывать транслитерацию", isOn: $settings.showTransliteration)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Доступ

struct PermissionsView: View {
    @State private var accessibility = SelectionService.isTrusted
    @State private var screen = CGPreflightScreenCaptureAccess()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Универсальный доступ — обязательно") {
                status(accessibility, ok: "Разрешено", bad: "Не разрешено")
                Text("Нужен, чтобы получать выделенный текст из других программ, заменять его переводом и отслеживать двойное нажатие клавиши.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    Button("Запросить доступ") { SelectionService.requestTrust() }
                    Button("Открыть Системные настройки") { SelectionService.openAccessibilitySettings() }
                }
            }
            Section("Запись экрана — для распознавания текста") {
                status(screen, ok: "Разрешено", bad: "Не разрешено")
                HStack {
                    Button("Запросить доступ") { _ = CGRequestScreenCaptureAccess() }
                    Button("Открыть Системные настройки") { SelectionService.openScreenRecordingSettings() }
                }
            }
            Section("Если горячие клавиши перестали работать после обновления") {
                Text("Приложение подписано без сертификата Apple, поэтому после установки новой версии macOS может «забыть» разрешение. Откройте «Системные настройки → Конфиденциальность и безопасность → Универсальный доступ», удалите VTranslator кнопкой «–» и добавьте заново (или включите переключатель).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in
            accessibility = SelectionService.isTrusted
            screen = CGPreflightScreenCaptureAccess()
        }
    }

    private func status(_ ok: Bool, ok okText: String, bad: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundColor(ok ? .green : .red)
            Text(ok ? okText : bad)
        }
    }
}

// MARK: - О программе

struct AboutView: View {
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("VTranslator").font(.title.bold())
            Text("Версия \(version)").foregroundColor(.secondary)
            Text("Быстрый переводчик для macOS: перевод выделенного текста по горячим клавишам, всплывающее окно, словарь, озвучка, распознавание текста с экрана.\nСервисы: Google Переводчик и Яндекс Переводчик.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
