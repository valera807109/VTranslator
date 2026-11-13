import Foundation

protocol TranslationEngine: Sendable {
    var id: EngineID { get }
    /// Максимальная длина одного запроса (символов).
    var maxChunk: Int { get }
    func translateChunk(_ text: String, from: String, to: String, withDictionary: Bool) async throws -> TranslationResult
}

extension TranslationEngine {
    /// Перевод произвольной длины: длинный текст режется на части.
    func translate(_ text: String, from: String, to: String) async throws -> TranslationResult {
        if text.count <= maxChunk {
            return try await translateChunk(text, from: from, to: to, withDictionary: true)
        }
        let parts = TextChunker.split(text, max: maxChunk)
        var translated: [String] = []
        var detected = from
        for part in parts {
            try Task.checkCancellation()
            let r = try await translateChunk(part, from: detected, to: to, withDictionary: false)
            translated.append(r.text)
            if detected == Languages.autoCode { detected = r.sourceLang }
        }
        return TranslationResult(
            sourceText: text,
            text: translated.joined(separator: "\n"),
            sourceLang: detected,
            targetLang: to,
            engine: id)
    }
}
