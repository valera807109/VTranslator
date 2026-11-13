import AppKit
import SwiftUI

/// Многострочное текстовое поле на основе NSTextView (нормальные ⌘C/⌘V/⌘A, отмена, прокрутка).
struct TextArea: NSViewRepresentable {
    @Binding var text: String
    var editable: Bool = true
    var fontSize: CGFloat = 14
    var onEdit: (@MainActor () -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.isEditable = editable
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.font = .systemFont(ofSize: fontSize)
        tv.textContainerInset = NSSize(width: 6, height: 8)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text {
            tv.string = text
            tv.scrollToBeginningOfDocument(nil)
        }
        if tv.font?.pointSize != fontSize { tv.font = .systemFont(ofSize: fontSize) }
        if tv.isEditable != editable { tv.isEditable = editable }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextArea
        init(_ parent: TextArea) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.onEdit?()
        }
    }
}

/// Маленькая кнопка-иконка для панелей инструментов.
struct IconButton: View {
    let systemName: String
    let help: String
    var active: Bool = false
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: systemName)
                .frame(width: 18, height: 18)
                .foregroundColor(active ? .accentColor : .primary)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

/// Словарная статья: часть речи → варианты перевода с обратными переводами.
struct DictionaryView: View {
    let entries: [DictionaryEntry]
    var fontSize: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.partOfSpeech)
                        .font(.system(size: fontSize - 1, weight: .semibold))
                        .foregroundColor(.accentColor)
                    ForEach(entry.terms) { term in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(term.word)
                                .font(.system(size: fontSize, weight: .medium))
                            if !term.reverse.isEmpty {
                                Text(term.reverse.joined(separator: ", "))
                                    .font(.system(size: fontSize - 1))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .textSelection(.enabled)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Выпадающий список языков.
struct LanguagePicker: View {
    @Binding var selection: String
    var includeAuto: Bool = false
    var compact: Bool = false

    var body: some View {
        Picker("", selection: $selection) {
            if includeAuto {
                Text(compact ? "АВТО" : "Автоопределение").tag(Languages.autoCode)
                Divider()
            }
            ForEach(Languages.all) { lang in
                Text(compact ? "\(lang.name)" : lang.name).tag(lang.code)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }
}

/// Запись сочетания клавиш: нажмите кнопку, затем нужное сочетание. Esc — отмена.
struct HotkeyRecorder: View {
    @Binding var hotkey: Hotkey?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggle) {
                Text(recording ? "Нажмите сочетание…" : (hotkey?.display ?? "Не задано"))
                    .frame(minWidth: 130)
                    .foregroundColor(recording ? .accentColor : (hotkey == nil ? .secondary : .primary))
            }
            if hotkey != nil, !recording {
                Button {
                    hotkey = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Убрать сочетание")
            }
        }
        .onDisappear(perform: stop)
    }

    private func toggle() {
        recording ? stop() : start()
    }

    private func start() {
        recording = true
        HotkeyManager.shared.pause()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {  // Esc
                stop()
                return nil
            }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let code = UInt32(event.keyCode)
            if mods.isEmpty, !KeyNames.functionKeys.contains(code) {
                NSSound.beep()
                return nil
            }
            hotkey = Hotkey(keyCode: code, modifiers: mods.rawValue)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            HotkeyManager.shared.resume()
        }
    }
}

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
