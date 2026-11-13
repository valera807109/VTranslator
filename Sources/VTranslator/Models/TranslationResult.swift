import Foundation

enum EngineID: String, CaseIterable, Codable, Identifiable, Sendable {
    case google
    case yandex

    var id: String { rawValue }
    var title: String {
        switch self {
        case .google: return "Google"
        case .yandex: return "Яндекс"
        }
    }
}

struct DictionaryTerm: Identifiable, Hashable, Sendable {
    let id = UUID()
    let word: String
    let reverse: [String]
}

struct DictionaryEntry: Identifiable, Hashable, Sendable {
    let id = UUID()
    let partOfSpeech: String
    let terms: [DictionaryTerm]
}

struct TranslationResult: Sendable {
    var sourceText: String
    var text: String
    /// Язык исходного текста (определённый или заданный).
    var sourceLang: String
    var targetLang: String
    var engine: EngineID
    var transliteration: String? = nil
    var sourceTransliteration: String? = nil
    var dictionary: [DictionaryEntry] = []
}

enum TranslationError: LocalizedError {
    case http(Int)
    case badResponse
    case empty
    case service(String)

    var errorDescription: String? {
        switch self {
        case .http(let code):
            if code == 429 { return "Сервис временно ограничил запросы (HTTP 429). Попробуйте позже или другой движок." }
            return "Ошибка сервиса перевода (HTTP \(code))."
        case .badResponse: return "Не удалось разобрать ответ сервиса."
        case .empty: return "Сервис вернул пустой перевод."
        case .service(let msg): return msg
        }
    }
}
