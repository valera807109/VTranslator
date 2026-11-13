import SwiftUI

/// Главное окно: исходный текст сверху, перевод снизу, языки и движки — как в QTranslate.
struct MainView: View {
    @ObservedObject var vm: TranslationViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var speech: SpeechService
    @ObservedObject var history: HistoryStore
    var onOpenHistory: @MainActor () -> Void
    var onOpenSettings: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            languageBar
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            Divider()
            VSplitView {
                sourcePane.frame(minHeight: 90)
                resultPane.frame(minHeight: 130)
            }
            Divider()
            bottomBar
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .frame(minWidth: 500, minHeight: 420)
        .onChange(of: settings.sourceLang) { _ in retranslate() }
        .onChange(of: settings.targetLang) { _ in retranslate() }
        .onChange(of: settings.engine) { _ in retranslate() }
    }

    private func retranslate() {
        if !vm.sourceText.isBlank { vm.translate() }
    }

    // MARK: - Языки

    private var languageBar: some View {
        HStack(spacing: 8) {
            LanguagePicker(selection: $settings.sourceLang, includeAuto: true)
                .frame(width: 190)
            Button {
                vm.swapLanguages()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .help("Поменять языки местами")
            LanguagePicker(selection: $settings.targetLang)
                .frame(width: 190)
            Spacer()
            Button {
                vm.translate()
            } label: {
                Text("Перевести")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .help("Перевести (⌘↩)")
        }
    }

    // MARK: - Исходный текст

    private var sourcePane: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                TextArea(
                    text: $vm.sourceText,
                    fontSize: CGFloat(settings.mainFontSize),
                    onEdit: { vm.sourceEdited() })
                if vm.sourceText.isEmpty {
                    Text("Введите или вставьте текст…")
                        .font(.system(size: CGFloat(settings.mainFontSize)))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            HStack(spacing: 10) {
                IconButton(systemName: "speaker.wave.2", help: "Прослушать исходный текст") { vm.speakSource() }
                IconButton(systemName: "doc.on.clipboard", help: "Вставить из буфера обмена") {
                    if let text = SelectionService.clipboardText() {
                        vm.setSource(text)
                        vm.translate()
                    }
                }
                IconButton(systemName: "xmark.circle", help: "Очистить") { vm.clear() }
                Spacer()
                if let r = vm.result {
                    if settings.showTransliteration, let st = r.sourceTransliteration {
                        Text(st)
                            .font(.caption)
                            .italic()
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if settings.sourceLang == Languages.autoCode {
                        Text("Язык: \(Languages.name(r.sourceLang))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
    }

    // MARK: - Перевод

    private var hasExtras: Bool {
        guard let r = vm.result else { return vm.backTranslation != nil }
        return (settings.showTransliteration && r.transliteration != nil)
            || (settings.showDictionary && !r.dictionary.isEmpty)
            || vm.backTranslation != nil
    }

    private var resultPane: some View {
        VStack(spacing: 0) {
            ZStack {
                TextArea(
                    text: .constant(vm.result?.text ?? ""),
                    editable: false,
                    fontSize: CGFloat(settings.mainFontSize))
                if vm.isLoading {
                    ProgressView().controlSize(.small)
                }
                if let error = vm.errorMessage {
                    VStack(spacing: 8) {
                        Text(error)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                        Button("Повторить") { vm.translate() }
                    }
                    .padding()
                }
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))

            if hasExtras {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if settings.showTransliteration, let t = vm.result?.transliteration {
                            Text(t)
                                .italic()
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                        if let back = vm.backTranslation {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Обратный перевод").font(.caption).foregroundColor(.secondary)
                                Text(back).textSelection(.enabled)
                            }
                        }
                        if settings.showDictionary, let dict = vm.result?.dictionary, !dict.isEmpty {
                            DictionaryView(entries: dict, fontSize: CGFloat(settings.mainFontSize) - 1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .frame(maxHeight: 200)
            }

            HStack(spacing: 10) {
                IconButton(
                    systemName: speech.isSpeaking ? "stop.fill" : "speaker.wave.2",
                    help: "Прослушать перевод") { vm.speakTranslation() }
                    .disabled(vm.result == nil)
                IconButton(systemName: "doc.on.doc", help: "Копировать перевод") { vm.copyTranslation() }
                    .disabled(vm.result == nil)
                IconButton(
                    systemName: "arrow.uturn.backward",
                    help: "Обратный перевод",
                    active: vm.backTranslation != nil) { vm.toggleBackTranslation() }
                    .disabled(vm.result == nil)
                if vm.isBackTranslating { ProgressView().controlSize(.mini) }
                Spacer()
                if let r = vm.result {
                    Text("\(Languages.short(r.sourceLang)) → \(Languages.short(r.targetLang)) · \(r.engine.title)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
    }

    // MARK: - Нижняя панель

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $settings.engine) {
                ForEach(EngineID.allCases) { engine in
                    Text(engine.title).tag(engine)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)
            .help("Сервис перевода")

            Spacer()

            IconButton(systemName: "chevron.left", help: "Предыдущий перевод из истории") { vm.historyBack() }
                .disabled(!vm.canGoBack)
            IconButton(systemName: "chevron.right", help: "Следующий перевод из истории") { vm.historyForward() }
                .disabled(!vm.canGoForward)
            IconButton(systemName: "clock.arrow.circlepath", help: "История переводов") { onOpenHistory() }
            IconButton(
                systemName: vm.pinned ? "pin.fill" : "pin",
                help: "Поверх всех окон",
                active: vm.pinned) { vm.pinned.toggle() }
            IconButton(systemName: "gearshape", help: "Настройки") { onOpenSettings() }
        }
    }
}
