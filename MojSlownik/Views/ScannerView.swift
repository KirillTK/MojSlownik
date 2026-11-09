import SwiftUI
import SwiftData
import VisionKit
import AVFoundation

/// Экран сканера: живая камера, распознанный текст подсвечивается,
/// тап по строке → экран результата с переводом и выбором отдельных слов.
struct ScannerScreen: View {
    @Environment(\.dismiss) private var dismiss
    var onPick: (String) -> Void

    @State private var cameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized

    private var scannerSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        ZStack(alignment: .top) {
            if cameraAuthorized && scannerSupported {
                DataScannerRepresentable(onPick: onPick)
                    .ignoresSafeArea()

                Text("Наведите камеру на текст и коснитесь строки")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 12)
            } else {
                unavailableView
            }

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding()
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                cameraAuthorized = await AVCaptureDevice.requestAccess(for: .video)
            }
        }
    }

    private var unavailableView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "camera.on.rectangle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(cameraAuthorized
                 ? "Сканер недоступен на этом устройстве (в симуляторе нет камеры)."
                 : "Разрешите доступ к камере в Настройках, чтобы сканировать слова.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Scan results keep context visible while translated words can be saved in one tap.
struct ScanResultView: View {
    let scannedText: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var savedWords: [Word]
    @State private var translatedText = ""
    @State private var isTranslating = false
    @State private var translationError: String?
    @State private var selectedWord: SelectedWord?
    @State private var translations: [String: String] = [:]
    @State private var wordErrors: [String: String] = [:]
    @State private var saveErrors: [String: String] = [:]
    @State private var retryVersion = 0
    @State private var categoryOverrides: [String: WordCategory] = [:]
    @State private var selectedFolderID: UUID?
    @State private var savedOverrides: [String: Bool] = [:]

    private var words: [String] {
        var seen = Set<String>()
        return ScannedTextTokenizer.words(in: scannedText).filter {
            seen.insert(normalize($0)).inserted
        }
    }

    private var translationRequestID: String {
        "\(scannedText)-\(retryVersion)-\(selectedWord?.id.uuidString ?? "")"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FolderPicker(selectedFolderID: $selectedFolderID)
                    sourceCard
                    translationCard
                    wordChips
                }
                .padding()
            }
            .background(Color.appBackground)
            .navigationTitle("Результат сканирования")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .sheet(item: $selectedWord, onDismiss: {
                savedOverrides.removeAll()
                categoryOverrides.removeAll()
            }) { selection in
                AddWordView(initialText: selection.text, initialFolderID: selectedFolderID)
            }
            .onChange(of: selectedFolderID) { savedOverrides.removeAll() }
            .task(id: translationRequestID) {
                guard selectedWord == nil else { return }
                await translateContent()
            }
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Оригинал", systemImage: "text.viewfinder")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.subtleText)
            Text(scannedText)
                .font(.body)
                .foregroundStyle(Color.appInk)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .accessibilityIdentifier("scanOriginalText")
            if !words.isEmpty {
                Menu {
                    ForEach(words, id: \.self) { word in
                        Button(word) { selectedWord = SelectedWord(text: word) }
                    }
                } label: {
                    Label("Исправить слово", systemImage: "pencil")
                        .font(.subheadline.weight(.medium))
                        .frame(minHeight: 44)
                }
                .accessibilityHint("Выберите слово, чтобы исправить его перед добавлением")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var wordChips: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Слова в словарь")
                    .font(.headline)
                    .foregroundStyle(Color.appInk)
                Text("Коснитесь слова, чтобы добавить или удалить. Категорию можно изменить.")
                    .font(.caption)
                    .foregroundStyle(Color.subtleText)
            }
            if words.isEmpty {
                Text("Не удалось выделить слова. Попробуйте отсканировать другую строку.")
                    .font(.subheadline)
                    .foregroundStyle(Color.subtleText)
            }
            LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 10) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    wordChip(word, index: index)
                }
            }
            Text("Темы определяются автоматически; незнакомые слова — «Другое».")
                .font(.caption)
                .foregroundStyle(Color.subtleText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chipColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 150), spacing: 10, alignment: .top)]
    }

    private func wordChip(_ word: String, index: Int) -> some View {
        let translation = translations[word]
        let existing = existingWord(word)
        let isSaved = savedOverrides[word] ?? isIncluded(existing)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if wordErrors[word] != nil {
                    wordErrors[word] = nil
                    retryVersion += 1
                } else {
                    toggleSaved(word)
                }
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(word.lowercased())
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.appInk)
                        Spacer(minLength: 0)
                        Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle")
                            .foregroundStyle(isSaved ? Color.appSuccess : Color.appAccent)
                            .accessibilityHidden(true)
                    }
                    if let translation {
                        Text(translation.lowercased())
                            .font(.subheadline)
                            .foregroundStyle(Color.subtleText)
                    } else if let error = wordErrors[word] {
                        Text(error).font(.caption).foregroundStyle(Color.subtleText)
                        Label("Повторить", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.appAccent)
                    } else {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Переводим…").font(.caption)
                        }
                        .foregroundStyle(Color.subtleText)
                    }
                    if isSaved {
                        Text(selectedFolderID == nil ? "В словаре · нажмите, чтобы удалить" : "В папке · нажмите, чтобы убрать")
                            .font(.caption)
                            .foregroundStyle(Color.appSuccess)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(translation == nil && wordErrors[word] == nil)
            .accessibilityIdentifier("scanWordChip-\(word)-\(index)")
            .accessibilityLabel("\(word), \(translation ?? wordErrors[word] ?? "Перевод загружается")")
            .accessibilityHint(isSaved ? (selectedFolderID == nil ? "Удалить из словаря" : "Убрать из папки") : wordErrors[word] != nil
                ? "Повторить перевод" : translation == nil
                ? "Дождитесь перевода" : "Добавить в словарь без открытия формы")
            if let translation {
                categoryMenu(word, translation: translation, existing: existing)
            }
            if let error = saveErrors[word] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isSaved ? Color.appSuccess.opacity(0.4) : Color.appBorder, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private func categoryMenu(_ word: String, translation: String, existing: Word?) -> some View {
        let current = categoryOverrides[word] ?? existing?.category ?? category(word, translation: translation)
        return CategoryMenu(selection: Binding(
            get: { current },
            set: { changeCategory($0, for: word, existing: existing) }
        )) {
            HStack(spacing: 5) {
                Text(current.rawValue)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.appAccent)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.appSecondarySurface, in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .accessibilityLabel("Категория слова \(word): \(current.rawValue)")
        .accessibilityHint("Открыть выбор категории")
    }

    private func changeCategory(_ category: WordCategory, for word: String, existing: Word?) {
        let isSaved = savedOverrides[word] ?? isIncluded(existing)
        guard isSaved, let translation = translations[word] else {
            categoryOverrides[word] = category
            return
        }
        do {
            try ScanWordStore.changeCategory(category, source: word, translation: translation,
                                             container: modelContext.container)
            categoryOverrides[word] = category
            saveErrors[word] = nil
        } catch {
            saveErrors[word] = "Не удалось изменить категорию. Попробуйте ещё раз."
        }
    }

    private var translationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Перевод")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.subtleText)
                Spacer()
                if isTranslating { ProgressView().controlSize(.small) }
            }
            if !translatedText.isEmpty {
                Text(translatedText)
                    .font(.body)
                    .foregroundStyle(Color.appInk)
                    .lineSpacing(4)
                    .accessibilityIdentifier("scanTranslationText")
            } else if isTranslating {
                Text("Переводим…").foregroundStyle(Color.subtleText)
            }
            if let translationError {
                Label(translationError, systemImage: "wifi.exclamationmark")
                    .font(.caption).foregroundStyle(.orange)
                Button("Повторить перевод предложения") {
                    self.translationError = nil
                    retryVersion += 1
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping.lowercased()
    }

    private func category(_ word: String, translation: String) -> WordCategory {
        if let selected = categoryOverrides[word] { return selected }
        let language = LanguageDetector.detect(word)
        return WordCategory.detect(
            russian: language == .russian ? word : translation,
            polish: language == .polish ? word : translation
        )
    }

    private func existingWord(_ word: String) -> Word? {
        guard let translation = translations[word] else { return nil }
        let language = LanguageDetector.detect(word)
        let matches = savedWords.filter {
            $0.matches(source: word, translation: translation, language: language)
        }
        if let selectedFolderID,
           let member = matches.first(where: { $0.folderIDs.contains(selectedFolderID) }) { return member }
        return matches.first
    }

    private func isIncluded(_ word: Word?) -> Bool {
        guard let word else { return false }
        return selectedFolderID.map { word.folderIDs.contains($0) } ?? true
    }

    private func toggleSaved(_ text: String) {
        guard let translation = translations[text] else { return }
        let selectedCategory = categoryOverrides[text] ?? existingWord(text)?.category
            ?? category(text, translation: translation)
        do {
            savedOverrides[text] = try ScanWordStore.toggle(
                source: text, translation: translation, category: selectedCategory,
                folderID: selectedFolderID, container: modelContext.container
            )
            categoryOverrides[text] = selectedCategory
            saveErrors[text] = nil
        } catch {
            saveErrors[text] = "Не удалось изменить словарь. Нажмите на карточку ещё раз."
        }
    }

    @MainActor
    private func translateContent() async {
        // AppleTranslationModel supports one pending request, so translate sequentially.
        let text = scannedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty && translatedText.isEmpty && translationError == nil {
            isTranslating = true
            do {
                let language = LanguageDetector.detect(text)
                let result = try await Translator.translate(text, from: language, to: language.other)
                try Task.checkCancellation()
                translatedText = result
            } catch is CancellationError {
                isTranslating = false
                return
            } catch {
                guard !Task.isCancelled else { return }
                translationError = error.localizedDescription
            }
            isTranslating = false
        }
        for word in words where translations[word] == nil && wordErrors[word] == nil {
            guard !Task.isCancelled else { return }
            do {
                let language = LanguageDetector.detect(word)
                let result = try await Translator.translate(word, from: language, to: language.other)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                try Task.checkCancellation()
                guard !result.isEmpty else { throw TranslationError.emptyResult }
                translations[word] = result
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                wordErrors[word] = error.localizedDescription
            }
        }
    }
}

private struct SelectedWord: Identifiable {
    let id = UUID()
    let text: String
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    var onPick: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        // Польский и русский; если системе языки неизвестны, Vision использует базовый набор.
        let supported = DataScannerViewController.supportedTextRecognitionLanguages
        var languages = ["pl-PL", "ru-RU"].filter { code in
            supported.contains { $0.hasPrefix(String(code.prefix(2))) }
        }
        if languages.isEmpty { languages = [] } // пустой список = автоматический выбор

        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text(languages: languages)],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        if !controller.isScanning {
            try? controller.startScanning()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onPick: (String) -> Void

        init(onPick: @escaping (String) -> Void) {
            self.onPick = onPick
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case .text(let text) = item {
                onPick(text.transcript)
            }
        }
    }
}
