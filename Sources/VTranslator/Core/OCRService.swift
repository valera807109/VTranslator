import Foundation
import ImageIO
import Vision

/// Распознавание текста с выбранной области экрана (встроенный в macOS Vision, работает офлайн).
/// При первом использовании macOS попросит разрешение «Запись экрана».
enum OCRService {
    static func captureAndRecognize() async throws -> String? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vtranslator-ocr-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        guard await runScreencapture(to: url),
              FileManager.default.fileExists(atPath: url.path),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        return try recognize(image)
    }

    private static func runScreencapture(to url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            // -i: интерактивный выбор области, -x: без звука
            process.arguments = ["-i", "-x", url.path]
            process.terminationHandler = { _ in continuation.resume(returning: true) }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }

    static func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let preferred = ["ru-RU", "en-US", "uk-UA", "de-DE", "fr-FR", "es-ES", "it-IT", "pt-BR",
                         "zh-Hans", "zh-Hant", "ja-JP", "ko-KR"].filter { supported.contains($0) }
        if !preferred.isEmpty { request.recognitionLanguages = preferred }

        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}
