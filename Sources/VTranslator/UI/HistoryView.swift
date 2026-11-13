import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    var onOpen: @MainActor (HistoryEntry) -> Void

    @State private var query = ""
    @State private var selection: HistoryEntry.ID?
    @State private var confirmClear = false

    private var filtered: [HistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.entries }
        return store.entries.filter {
            $0.source.lowercased().contains(q) || $0.translation.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Поиск по истории", text: $query)
                    .textFieldStyle(.roundedBorder)
                Text("\(filtered.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Очистить…") { confirmClear = true }
                    .disabled(store.entries.isEmpty)
            }
            .padding(8)
            Divider()
            if filtered.isEmpty {
                Spacer()
                Text(store.entries.isEmpty ? "История пуста" : "Ничего не найдено")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List(filtered, selection: $selection) { entry in
                    row(entry)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { onOpen(entry) }
                        .contextMenu {
                            Button("Открыть в главном окне") { onOpen(entry) }
                            Button("Копировать перевод") { copy(entry.translation) }
                            Button("Копировать исходный текст") { copy(entry.source) }
                            Divider()
                            Button("Удалить") { store.remove(entry.id) }
                        }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 300)
        .alert("Очистить всю историю переводов?", isPresented: $confirmClear) {
            Button("Очистить", role: .destructive) { store.clear() }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func row(_ e: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("\(Languages.short(e.from)) → \(Languages.short(e.to))")
                    .font(.caption.weight(.semibold))
                Text(e.engine.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(e.date, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(e.source).lineLimit(2)
            Text(e.translation).foregroundColor(.secondary).lineLimit(2)
        }
        .padding(.vertical, 3)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
