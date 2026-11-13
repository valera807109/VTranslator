import Foundation

/// Точка входа для перевода: выбирает движок и делает «умное» переключение языка (как в QTranslate):
/// если язык текста совпал с целевым — переводит на второй язык (например, RU → EN вместо RU → RU).
@MainActor
final class Translator {
    static let shared = Translator()

    private let google = GoogleEngine()
    private let yandex = YandexEngine()

    func engine(_ id: EngineID) -> TranslationEngine {
        switch id {
        case .google: return google
        case .yandex: return yandex
        }
    }

    func translate(_ text: String, from: String, to: String, engine id: EngineID, smart: Bool = true) async throws -> TranslationResult {
        let selected = self.engine(id)
        var result = try await selected.translate(text, from: from, to: to)
        let settings = AppSettings.shared
        if smart, settings.smartSwitch, Languages.same(result.sourceLang, to) {
            let alt = settings.alternateTarget(for: to)
            if !Languages.same(alt, to) {
                result = try await selected.translate(text, from: result.sourceLang, to: alt)
            }
        }
        return result
    }

    /// Определение языка текста (через Google, т.к. он отдаёт язык в том же запросе).
    func detect(_ text: String) async -> String? {
        let sample = String(text.prefix(300))
        if let r = try? await google.translateChunk(sample, from: Languages.autoCode, to: "en", withDictionary: false) {
            return r.sourceLang
        }
        if let r = try? await yandex.translateChunk(sample, from: Languages.autoCode, to: "en", withDictionary: false) {
            return r.sourceLang
        }
        return nil
    }
}
