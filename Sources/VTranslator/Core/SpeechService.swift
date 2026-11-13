import AVFoundation
import Foundation

/// Озвучка текста: Google TTS (онлайн) с запасным вариантом — системный голос.
@MainActor
final class SpeechService: NSObject, ObservableObject {
    static let shared = SpeechService()

    @Published private(set) var isSpeaking = false

    private var player: AVAudioPlayer?
    private var queue: [Data] = []
    private let synth = AVSpeechSynthesizer()
    private var task: Task<Void, Never>?

    override init() {
        super.init()
        synth.delegate = self
    }

    /// Повторное нажатие останавливает воспроизведение.
    func toggle(_ text: String, lang: String) {
        if isSpeaking { stop() } else { speak(text, lang: lang) }
    }

    func speak(_ text: String, lang: String) {
        stop()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSpeaking = true

        if AppSettings.shared.ttsProvider == .system || lang == Languages.autoCode {
            speakSystem(trimmed, lang: lang)
            return
        }

        task = Task { [weak self] in
            do {
                let chunks = Array(TextChunker.split(trimmed, max: 180).prefix(40))
                var audio: [Data] = []
                for chunk in chunks {
                    try Task.checkCancellation()
                    audio.append(try await Self.fetchGoogleTTS(chunk, lang: lang))
                }
                guard let self, !Task.isCancelled else { return }
                self.queue = audio
                self.playNext()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.speakSystem(trimmed, lang: lang)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        queue.removeAll()
        player?.stop()
        player = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        isSpeaking = false
    }

    private func playNext() {
        guard !queue.isEmpty else {
            player = nil
            isSpeaking = false
            return
        }
        let data = queue.removeFirst()
        do {
            let p = try AVAudioPlayer(data: data)
            p.delegate = self
            player = p
            p.play()
        } catch {
            playNext()
        }
    }

    private func speakSystem(_ text: String, lang: String) {
        let utterance = AVSpeechUtterance(string: text)
        if lang != Languages.autoCode {
            utterance.voice = AVSpeechSynthesisVoice(language: Languages.speechLocale(lang))
        }
        isSpeaking = true
        synth.speak(utterance)
    }

    private nonisolated static func fetchGoogleTTS(_ text: String, lang: String) async throws -> Data {
        let q = HTTP.query([("ie", "UTF-8"), ("client", "tw-ob"), ("tl", lang), ("q", text)])
        guard let url = URL(string: "https://translate.google.com/translate_tts?" + q) else {
            throw TranslationError.badResponse
        }
        var request = URLRequest(url: url)
        request.setValue(HTTP.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://translate.google.com/", forHTTPHeaderField: "Referer")
        let data = try await HTTP.data(for: request)
        if data.count < 200 { throw TranslationError.empty }
        return data
    }
}

extension SpeechService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playNext() }
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
