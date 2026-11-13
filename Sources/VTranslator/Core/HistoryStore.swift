import Foundation

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var source: String
    var translation: String
    var from: String
    var to: String
    var engine: EngineID
}

/// История переводов: ~/Library/Application Support/VTranslator/history.json
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var entries: [HistoryEntry] = []

    private let fileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("VTranslator", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    func add(_ r: TranslationResult) {
        guard AppSettings.shared.historyEnabled else { return }
        let entry = HistoryEntry(
            date: Date(), source: r.sourceText, translation: r.text,
            from: r.sourceLang, to: r.targetLang, engine: r.engine)
        if let i = entries.firstIndex(where: { $0.source == r.sourceText && Languages.same($0.to, r.targetLang) && $0.engine == r.engine }) {
            entries.remove(at: i)
        }
        entries.insert(entry, at: 0)
        let limit = max(10, AppSettings.shared.historyLimit)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        save()
    }

    func remove(_ id: HistoryEntry.ID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
