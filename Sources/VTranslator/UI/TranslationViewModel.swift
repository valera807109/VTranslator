import AppKit
import Combine

/// Общая логика окна перевода (используется и главным, и всплывающим окном).
@MainActor
final class TranslationViewModel: ObservableObject {
    @Published var sourceText = ""
    @Published var result: TranslationResult?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var backTranslation: String?
    @Published var isBackTranslating = false
    @Published var pinned = false
    /// Позиция в истории при листании ◀ ▶ (nil — текущий перевод).
    @Published private(set) var historyIndex: Int?

    let settings = AppSettings.shared
    private var task: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    func setSource(_ text: String) {
        debounceTask?.cancel()
        sourceText = text
        historyIndex = nil
    }

    /// Вызывается при наборе текста в главном окне.
    func sourceEdited() {
        historyIndex = nil
        guard settings.autoTranslate else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self?.translate()
        }
    }

    func translate(addToHistory: Bool = true) {
        task?.cancel()
        debounceTask?.cancel()
        backTranslation = nil
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            result = nil
            errorMessage = nil
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        let from = settings.sourceLang
        let to = settings.targetLang
        let engine = settings.engine
        task = Task { [weak self] in
            do {
                let r = try await Translator.shared.translate(text, from: from, to: to, engine: engine)
                guard let self, !Task.isCancelled else { return }
                self.result = r
                self.isLoading = false
                if addToHistory { HistoryStore.shared.add(r) }
                if self.settings.autoCopy { self.copyTranslation() }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func showMessage(_ message: String) {
        task?.cancel()
        result = nil
        isLoading = false
        errorMessage = message
    }

    /// Поменять языки местами; перевод становится исходным текстом.
    func swapLanguages() {
        let currentSource = settings.sourceLang == Languages.autoCode
            ? (result?.sourceLang ?? settings.secondaryLang)
            : settings.sourceLang
        let currentTarget = result?.targetLang ?? settings.targetLang
        settings.sourceLang = Languages.canonical(currentTarget)
        settings.targetLang = Languages.canonical(currentSource)
        if let r = result { sourceText = r.text }
        translate()
    }

    func toggleBackTranslation() {
        if backTranslation != nil { backTranslation = nil; return }
        guard let r = result else { return }
        isBackTranslating = true
        let engine = settings.engine
        Task { [weak self] in
            let back = try? await Translator.shared.translate(r.text, from: r.targetLang, to: r.sourceLang, engine: engine, smart: false)
            guard let self else { return }
            self.isBackTranslating = false
            self.backTranslation = back?.text ?? "Не удалось выполнить обратный перевод."
        }
    }

    func copyTranslation() {
        guard let text = result?.text, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func speakSource() {
        let text = sourceText
        let lang = result?.sourceLang ?? settings.sourceLang
        if lang == Languages.autoCode {
            Task {
                let detected = await Translator.shared.detect(text) ?? "en"
                SpeechService.shared.toggle(text, lang: detected)
            }
        } else {
            SpeechService.shared.toggle(text, lang: lang)
        }
    }

    func speakTranslation() {
        guard let r = result else { return }
        SpeechService.shared.toggle(r.text, lang: r.targetLang)
    }

    func clear() {
        task?.cancel()
        debounceTask?.cancel()
        sourceText = ""
        result = nil
        errorMessage = nil
        backTranslation = nil
        isLoading = false
        historyIndex = nil
    }

    // MARK: - Листание истории

    var canGoBack: Bool { (historyIndex ?? -1) + 1 < HistoryStore.shared.entries.count }
    var canGoForward: Bool { (historyIndex ?? 0) > 0 }

    func historyBack() {
        let entries = HistoryStore.shared.entries
        var i = (historyIndex ?? -1) + 1
        // Если текущий текст уже первый в истории — пропускаем его.
        if historyIndex == nil, let first = entries.first,
           first.source == sourceText.trimmingCharacters(in: .whitespacesAndNewlines) {
            i = 1
        }
        guard i < entries.count else { return }
        load(entries[i])
        historyIndex = i
    }

    func historyForward() {
        guard let current = historyIndex, current > 0 else { return }
        let entries = HistoryStore.shared.entries
        let i = current - 1
        guard i < entries.count else { return }
        load(entries[i])
        historyIndex = i
    }

    func load(_ entry: HistoryEntry) {
        task?.cancel()
        debounceTask?.cancel()
        sourceText = entry.source
        backTranslation = nil
        errorMessage = nil
        isLoading = false
        result = TranslationResult(
            sourceText: entry.source, text: entry.translation,
            sourceLang: entry.from, targetLang: entry.to, engine: entry.engine)
    }
}
