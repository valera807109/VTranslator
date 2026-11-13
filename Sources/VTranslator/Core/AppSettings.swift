import AppKit
import Combine

enum DoubleTapKey: String, CaseIterable, Identifiable {
    case off, control, option, command, shift

    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Выключено"
        case .control: return "⌃ Control"
        case .option: return "⌥ Option"
        case .command: return "⌘ Command"
        case .shift: return "⇧ Shift"
        }
    }
    var flags: NSEvent.ModifierFlags? {
        switch self {
        case .off: return nil
        case .control: return .control
        case .option: return .option
        case .command: return .command
        case .shift: return .shift
        }
    }
}

enum DoubleTapAction: String, CaseIterable, Identifiable {
    case popup, mainWindow
    var id: String { rawValue }
    var title: String { self == .popup ? "Всплывающее окно" : "Главное окно" }
}

enum TTSProvider: String, CaseIterable, Identifiable {
    case google, system
    var id: String { rawValue }
    var title: String { self == .google ? "Google (онлайн)" : "Системный голос macOS" }
}

/// Все настройки приложения. Хранятся в UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let d = UserDefaults.standard

    // Языки и движок
    @Published var sourceLang: String { didSet { d.set(sourceLang, forKey: "sourceLang") } }
    @Published var targetLang: String { didSet { d.set(targetLang, forKey: "targetLang") } }
    @Published var primaryLang: String { didSet { d.set(primaryLang, forKey: "primaryLang") } }
    @Published var secondaryLang: String { didSet { d.set(secondaryLang, forKey: "secondaryLang") } }
    @Published var smartSwitch: Bool { didSet { d.set(smartSwitch, forKey: "smartSwitch") } }
    @Published var engine: EngineID { didSet { d.set(engine.rawValue, forKey: "engine") } }

    // Поведение
    @Published var autoTranslate: Bool { didSet { d.set(autoTranslate, forKey: "autoTranslate") } }
    @Published var autoCopy: Bool { didSet { d.set(autoCopy, forKey: "autoCopy") } }
    @Published var showMainOnLaunch: Bool { didSet { d.set(showMainOnLaunch, forKey: "showMainOnLaunch") } }
    @Published var showDockIcon: Bool { didSet { d.set(showDockIcon, forKey: "showDockIcon") } }
    @Published var historyEnabled: Bool { didSet { d.set(historyEnabled, forKey: "historyEnabled") } }
    @Published var historyLimit: Int { didSet { d.set(historyLimit, forKey: "historyLimit") } }
    @Published var ttsProvider: TTSProvider { didSet { d.set(ttsProvider.rawValue, forKey: "ttsProvider") } }
    @Published var clipboardFallback: Bool { didSet { d.set(clipboardFallback, forKey: "clipboardFallback") } }

    // Горячие клавиши и мышь
    @Published var hotkeys: [HotkeyAction: Hotkey] { didSet { saveHotkeys() } }
    @Published var doubleTapKey: DoubleTapKey { didSet { d.set(doubleTapKey.rawValue, forKey: "doubleTapKey") } }
    @Published var doubleTapAction: DoubleTapAction { didSet { d.set(doubleTapAction.rawValue, forKey: "doubleTapAction") } }
    @Published var mouseMode: Bool { didSet { d.set(mouseMode, forKey: "mouseMode") } }
    /// Названия приложений (через запятую или с новой строки), в которых горячие клавиши не работают.
    @Published var exceptions: String { didSet { d.set(exceptions, forKey: "exceptions") } }

    // Внешний вид
    @Published var mainFontSize: Double { didSet { d.set(mainFontSize, forKey: "mainFontSize") } }
    @Published var popupFontSize: Double { didSet { d.set(popupFontSize, forKey: "popupFontSize") } }
    @Published var popupShowSource: Bool { didSet { d.set(popupShowSource, forKey: "popupShowSource") } }
    @Published var popupCloseOnClickOutside: Bool { didSet { d.set(popupCloseOnClickOutside, forKey: "popupCloseOnClickOutside") } }
    @Published var showDictionary: Bool { didSet { d.set(showDictionary, forKey: "showDictionary") } }
    @Published var showTransliteration: Bool { didSet { d.set(showTransliteration, forKey: "showTransliteration") } }
    @Published var popupWidth: Double { didSet { d.set(popupWidth, forKey: "popupWidth") } }
    @Published var popupHeight: Double { didSet { d.set(popupHeight, forKey: "popupHeight") } }

    private init() {
        let d = UserDefaults.standard
        let systemLang = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "ru"
        let primary = d.string(forKey: "primaryLang") ?? (Languages.language(systemLang) != nil ? systemLang : "ru")

        sourceLang = d.string(forKey: "sourceLang") ?? Languages.autoCode
        targetLang = d.string(forKey: "targetLang") ?? primary
        primaryLang = primary
        secondaryLang = d.string(forKey: "secondaryLang") ?? (primary == "en" ? "ru" : "en")
        smartSwitch = d.object(forKey: "smartSwitch") as? Bool ?? true
        engine = EngineID(rawValue: d.string(forKey: "engine") ?? "") ?? .google

        autoTranslate = d.object(forKey: "autoTranslate") as? Bool ?? true
        autoCopy = d.object(forKey: "autoCopy") as? Bool ?? false
        showMainOnLaunch = d.object(forKey: "showMainOnLaunch") as? Bool ?? true
        showDockIcon = d.object(forKey: "showDockIcon") as? Bool ?? false
        historyEnabled = d.object(forKey: "historyEnabled") as? Bool ?? true
        historyLimit = d.object(forKey: "historyLimit") as? Int ?? 500
        ttsProvider = TTSProvider(rawValue: d.string(forKey: "ttsProvider") ?? "") ?? .google
        clipboardFallback = d.object(forKey: "clipboardFallback") as? Bool ?? false

        hotkeys = Self.loadHotkeys(d)
        doubleTapKey = DoubleTapKey(rawValue: d.string(forKey: "doubleTapKey") ?? "") ?? .control
        doubleTapAction = DoubleTapAction(rawValue: d.string(forKey: "doubleTapAction") ?? "") ?? .popup
        mouseMode = d.object(forKey: "mouseMode") as? Bool ?? false
        exceptions = d.string(forKey: "exceptions") ?? ""

        mainFontSize = d.object(forKey: "mainFontSize") as? Double ?? 14
        popupFontSize = d.object(forKey: "popupFontSize") as? Double ?? 14
        popupShowSource = d.object(forKey: "popupShowSource") as? Bool ?? false
        popupCloseOnClickOutside = d.object(forKey: "popupCloseOnClickOutside") as? Bool ?? true
        showDictionary = d.object(forKey: "showDictionary") as? Bool ?? true
        showTransliteration = d.object(forKey: "showTransliteration") as? Bool ?? true
        popupWidth = d.object(forKey: "popupWidth") as? Double ?? 420
        popupHeight = d.object(forKey: "popupHeight") as? Double ?? 240
    }

    /// Куда переводить, если язык исходного текста совпал с целевым.
    func alternateTarget(for target: String) -> String {
        Languages.same(target, primaryLang) ? secondaryLang : primaryLang
    }

    var exceptionList: [String] {
        exceptions
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    func resetHotkeys() {
        var map: [HotkeyAction: Hotkey] = [:]
        for a in HotkeyAction.allCases { map[a] = a.defaultHotkey }
        hotkeys = map
    }

    // MARK: - Хранение горячих клавиш

    private struct StoredHotkeys: Codable {
        var map: [String: Hotkey]
        var known: [String]
    }

    private static func loadHotkeys(_ d: UserDefaults) -> [HotkeyAction: Hotkey] {
        var result: [HotkeyAction: Hotkey] = [:]
        let stored = d.data(forKey: "hotkeys").flatMap { try? JSONDecoder().decode(StoredHotkeys.self, from: $0) }
        for action in HotkeyAction.allCases {
            if let stored, stored.known.contains(action.rawValue) {
                result[action] = stored.map[action.rawValue]
            } else {
                result[action] = action.defaultHotkey
            }
        }
        return result
    }

    private func saveHotkeys() {
        var map: [String: Hotkey] = [:]
        for (k, v) in hotkeys { map[k.rawValue] = v }
        let stored = StoredHotkeys(map: map, known: HotkeyAction.allCases.map(\.rawValue))
        if let data = try? JSONEncoder().encode(stored) { d.set(data, forKey: "hotkeys") }
    }
}
