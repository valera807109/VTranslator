import Foundation

/// Google Translate через неофициальный адрес translate.googleapis.com (client=gtx), как в QTranslate.
final class GoogleEngine: TranslationEngine, @unchecked Sendable {
    let id = EngineID.google
    let maxChunk = 4500

    func translateChunk(_ text: String, from: String, to: String, withDictionary: Bool) async throws -> TranslationResult {
        var params: [(String, String)] = [
            ("client", "gtx"), ("sl", from), ("tl", to), ("hl", "ru"),
            ("ie", "UTF-8"), ("oe", "UTF-8"), ("dj", "1"),
            ("dt", "t"), ("dt", "rm"),
        ]
        if withDictionary { params.append(("dt", "bd")) }

        let base = "https://translate.googleapis.com/translate_a/single?" + HTTP.query(params)
        let body = HTTP.query([("q", text)])

        var request: URLRequest
        if body.count < 6000, let url = URL(string: base + "&" + body) {
            request = URLRequest(url: url)
        } else {
            guard let url = URL(string: base) else { throw TranslationError.badResponse }
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = Data(body.utf8)
            request.setValue("application/x-www-form-urlencoded;charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        request.setValue(HTTP.browserUserAgent, forHTTPHeaderField: "User-Agent")

        let data = try await HTTP.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationError.badResponse
        }

        var translation = ""
        var translit: String?
        var srcTranslit: String?
        for sentence in json["sentences"] as? [[String: Any]] ?? [] {
            if let t = sentence["trans"] as? String { translation += t }
            if let tr = sentence["translit"] as? String, !tr.isEmpty { translit = tr }
            if let st = sentence["src_translit"] as? String, !st.isEmpty { srcTranslit = st }
        }
        if translation.isEmpty { throw TranslationError.empty }

        var dictionary: [DictionaryEntry] = []
        for item in json["dict"] as? [[String: Any]] ?? [] {
            let pos = item["pos"] as? String ?? ""
            var terms: [DictionaryTerm] = []
            if let entries = item["entry"] as? [[String: Any]] {
                for e in entries {
                    guard let word = e["word"] as? String else { continue }
                    terms.append(DictionaryTerm(word: word, reverse: e["reverse_translation"] as? [String] ?? []))
                }
            } else if let plain = item["terms"] as? [String] {
                terms = plain.map { DictionaryTerm(word: $0, reverse: []) }
            }
            if !terms.isEmpty { dictionary.append(DictionaryEntry(partOfSpeech: pos, terms: terms)) }
        }

        let detected = (json["src"] as? String).map(Languages.canonical) ?? from
        return TranslationResult(
            sourceText: text,
            text: translation,
            sourceLang: detected,
            targetLang: to,
            engine: id,
            transliteration: translit,
            sourceTransliteration: srcTranslit,
            dictionary: dictionary)
    }
}
