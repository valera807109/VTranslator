import Foundation

/// Яндекс.Переводчик через неофициальный адрес мобильного приложения (translate.yandex.net, srv=android).
final class YandexEngine: TranslationEngine, @unchecked Sendable {
    let id = EngineID.yandex
    let maxChunk = 9000

    private let userAgent = "ru.yandex.translate/21.15.4.21402814 (Xiaomi Redmi K20 Pro; Android 11)"

    /// Идентификатор «устройства» — генерируется один раз и хранится в настройках.
    private let ucid: String = {
        let key = "yandexUCID"
        if let saved = UserDefaults.standard.string(forKey: key), saved.count == 32 { return saved }
        let fresh = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }()

    func translateChunk(_ text: String, from: String, to: String, withDictionary: Bool) async throws -> TranslationResult {
        let target = Languages.yandexCode(to)
        let lang = from == Languages.autoCode ? target : "\(Languages.yandexCode(from))-\(target)"

        guard let url = URL(string: "https://translate.yandex.net/api/v1/tr.json/translate?ucid=\(ucid)&srv=android&format=text") else {
            throw TranslationError.badResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded;charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(HTTP.query([("text", text), ("lang", lang)]).utf8)

        let data: Data
        do {
            data = try await HTTP.data(for: request)
        } catch TranslationError.http(let code) {
            switch code {
            case 413: throw TranslationError.service("Яндекс: слишком длинный текст.")
            case 422: throw TranslationError.service("Яндекс не смог перевести этот текст.")
            case 501: throw TranslationError.service("Яндекс не поддерживает это направление перевода.")
            default: throw TranslationError.http(code)
            }
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationError.badResponse
        }
        if let code = json["code"] as? Int, code != 200 {
            throw TranslationError.service((json["message"] as? String) ?? "Ошибка Яндекса (код \(code)).")
        }
        let parts = json["text"] as? [String] ?? []
        let translation = parts.joined(separator: "\n")
        if translation.isEmpty { throw TranslationError.empty }

        var detected = from
        if let pair = json["lang"] as? String, let src = pair.split(separator: "-").first {
            detected = Languages.fromYandex(String(src))
        }

        var translit: String?
        if withDictionary, translation.count < 500 {
            translit = try? await transliterate(translation, lang: target)
        }

        return TranslationResult(
            sourceText: text,
            text: translation,
            sourceLang: detected,
            targetLang: to,
            engine: id,
            transliteration: translit)
    }

    /// Транслитерация латиницей (работает для нелатинских языков).
    private func transliterate(_ text: String, lang: String) async throws -> String? {
        let latin = ["en", "de", "fr", "es", "it", "pt", "pl", "nl", "cs", "sk", "sv", "da", "no", "fi", "tr", "ro", "hu", "lv", "lt", "et", "id", "ms", "vi", "hr", "sl", "sq", "az", "uz", "tk", "la", "eo", "ca", "gl", "eu", "ga", "cy", "is", "mt", "af", "sw", "tl"]
        if latin.contains(lang) { return nil }
        let q = HTTP.query([("text", text), ("lang", lang)])
        guard let url = URL(string: "https://translate.yandex.net/translit/translit?" + q) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let data = try await HTTP.data(for: request)
        let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String
        guard let v = value, !v.isEmpty, v != text else { return nil }
        return v
    }
}
