import Foundation

enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"

    private static let unreserved = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
    }

    /// `a=1&b=2` с корректным кодированием (включая `+`, `&`, кириллицу).
    static func query(_ params: [(String, String)]) -> String {
        params.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&")
    }

    static func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TranslationError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw TranslationError.http(http.statusCode) }
        return data
    }
}

/// Делит длинный текст на куски не длиннее `max` символов, стараясь резать по строкам и словам.
enum TextChunker {
    static func split(_ text: String, max: Int) -> [String] {
        if text.count <= max { return [text] }
        var chunks: [String] = []
        var current = ""
        for line in text.components(separatedBy: "\n") {
            let pieces = line.count > max ? splitLong(line, max: max) : [line]
            for piece in pieces {
                let candidate = current.isEmpty ? piece : current + "\n" + piece
                if candidate.count > max, !current.isEmpty {
                    chunks.append(current)
                    current = piece
                } else {
                    current = candidate
                }
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static func splitLong(_ line: String, max: Int) -> [String] {
        var result: [String] = []
        var current = ""
        for word in line.split(separator: " ", omittingEmptySubsequences: false) {
            var w = String(word)
            while w.count > max {
                if !current.isEmpty { result.append(current); current = "" }
                result.append(String(w.prefix(max)))
                w = String(w.dropFirst(max))
            }
            let candidate = current.isEmpty ? w : current + " " + w
            if candidate.count > max {
                result.append(current)
                current = w
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
