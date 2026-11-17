import SwiftUI
import SwiftData
import VisionKit
import AVFoundation
import UIKit

/// Экран сканера: живая камера, распознанный текст подсвечивается,
/// тап по строке → экран результата с переводом и выбором отдельных слов.
struct ScannerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var unavailableIconSize: CGFloat = 44
    var onPick: (String) -> Void

    @State private var cameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @State private var recognizedLines: [ScannedTextLine] = []
    @State private var frozenLines: [ScannedTextLine] = []
    @State private var frozenBlocks: [ScannedTextBlock] = []
    @State private var capturedPhoto: UIImage?
    @State private var captureRequestID = 0
    @State private var isCapturingPhoto = false
    @State private var captureError: String?
    @State private var selectedBlockIDs = Set<String>()

    private var activeLines: [ScannedTextLine] {
        capturedPhoto == nil ? recognizedLines : frozenLines
    }

    private var selectedBlockText: String {
        ScannedTextBlockBuilder.selectedText(from: frozenBlocks, IDs: selectedBlockIDs)
    }

    private var scannerSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let capturedPhoto {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: capturedPhoto)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .accessibilityHidden(true)
                        FrozenBlockOverlay(blocks: frozenBlocks, selectedIDs: selectedBlockIDs) { blockID in
                            selectedBlockIDs = ScannedTextBlockBuilder.toggled(blockID, in: selectedBlockIDs)
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .ignoresSafeArea()
            } else if cameraAuthorized && scannerSupported {
                DataScannerRepresentable(
                    onPick: onPick,
                    onRecognized: { recognizedLines = $0 },
                    captureRequestID: captureRequestID,
                    onCapturePhoto: { capturedPhoto = $0 },
                    onCapturedLines: {
                        frozenLines = $0
                        frozenBlocks = ScannedTextBlockBuilder.build(from: $0)
                        selectedBlockIDs.removeAll()
                    },
                    onCaptureFinished: { isCapturingPhoto = false },
                    onCaptureFailed: { captureError = $0 }
                )
                    .ignoresSafeArea()
            } else {
                unavailableView
            }

            VStack(spacing: 12) {
                HStack {
                    Text("Сканирование")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(.regularMaterial, in: Capsule())
                    Spacer(minLength: 12)
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.appInk)
                            .frame(width: 44, height: 44)
                            .background(.regularMaterial, in: Circle())
                    }
                    .accessibilityLabel("Закрыть сканер")
                }
                if cameraAuthorized && scannerSupported {
                    Text(instructionText)
                        .font(.caption.weight(.medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .foregroundStyle(.primary)
            .padding(20)
        }
        .overlay(alignment: .bottom) {
            if cameraAuthorized && scannerSupported { scannerControlBar }
        }
        .background((cameraAuthorized && scannerSupported ? Color.black : Color.appBackground).ignoresSafeArea())
        .errorAlert(title: "Не удалось обработать кадр", error: $captureError)
        .task {
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                cameraAuthorized = await AVCaptureDevice.requestAccess(for: .video)
            }
        }
    }

    private var instructionText: String {
        guard capturedPhoto != nil else { return "Коснитесь строки или зафиксируйте кадр" }
        if isCapturingPhoto { return "Распознаём текст на кадре…" }
        if frozenLines.isEmpty { return "Текст не распознан. Снимите кадр заново." }
        return "Нажимайте на блоки, чтобы выбрать текст"
    }

    private var scannerControlBar: some View {
        VStack(spacing: 6) {
            if capturedPhoto != nil {
                if isCapturingPhoto {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Распознаём текст на кадре…")
                            .font(.caption.weight(.medium))
                    }
                    .frame(minHeight: 44)
                } else {
                    HStack(spacing: 10) {
                        Text("Выбрано: \(selectedBlockIDs.count)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.appInk)
                        Button {
                            if !selectedBlockText.isEmpty { onPick(selectedBlockText) }
                        } label: {
                            Label("Перевести выбранное", systemImage: "text.magnifyingglass")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(selectedBlockIDs.isEmpty)
                        .accessibilityHint("Перевести выбранные текстовые блоки по порядку чтения")
                    }
                }
            }

            HStack(spacing: 8) {
                compactControl(
                    title: "Всё",
                    accessibilityTitle: "Перевести весь текст",
                    symbol: "text.viewfinder",
                    enabled: !ScannedTextSelection.text(from: activeLines).isEmpty
                ) {
                    let text = ScannedTextSelection.text(from: activeLines)
                    if !text.isEmpty { onPick(text) }
                }
                compactControl(
                    title: isCapturingPhoto ? "Снимок…" : (capturedPhoto == nil ? "Стоп-кадр" : "Переснять"),
                    accessibilityTitle: capturedPhoto == nil ? "Зафиксировать кадр" : "Снять заново",
                    symbol: capturedPhoto == nil ? "camera" : "camera.rotate",
                    enabled: !isCapturingPhoto && (capturedPhoto != nil || cameraAuthorized && scannerSupported)
                ) {
                    if capturedPhoto != nil {
                        capturedPhoto = nil
                        frozenLines = []
                        frozenBlocks = []
                        selectedBlockIDs.removeAll()
                        recognizedLines = []
                    } else {
                        isCapturingPhoto = true
                        captureRequestID += 1
                    }
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private func compactControl(title: String, accessibilityTitle: String, symbol: String,
                                enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(dynamicTypeSize.isAccessibilitySize ? "" : title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .frame(minWidth: 44, minHeight: 44)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 64 : .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: Capsule())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
        .accessibilityLabel(accessibilityTitle)
    }

    private var unavailableView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "camera")
                .font(.system(size: unavailableIconSize))
                .fontWeight(.medium)
                .foregroundStyle(Color.appAccentText)
                .accessibilityHidden(true)
            Text(cameraAuthorized
                 ? "Сканер недоступен на этом устройстве (в симуляторе нет камеры)."
                 : "Разрешите доступ к камере в Настройках, чтобы сканировать слова.")
                .multilineTextAlignment(.center)
                .font(.body)
                .foregroundStyle(Color.subtleText)
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
    @Environment(VocabularyStore.self) private var vocabulary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var storedSavedWords: [Word]
    private var savedWords: [Word] { storedSavedWords.filter(\.isActive) }
    @State private var draft: ScanResultDraft
    @State private var selectedWord: SelectedWord?
    @State private var saveErrors: [String: String] = [:]
    @State private var categoryOverrides: [String: WordCategory] = [:]
    @State private var selectedFolderID: UUID?
    @State private var savedOverrides: [String: Bool] = [:]

    init(scannedText: String) {
        self.scannedText = scannedText
        _draft = State(initialValue: ScanResultDraft(
            sourceText: ScannedTextTokenizer.joiningLineBreakHyphenation(in: scannedText)
        ))
    }

    private var words: [String] { draft.words }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    VStack(spacing: 0) {
                        sourceCard
                        Divider().overlay(Color.appBorder)
                            .padding(.horizontal, AppSpacing.l)
                        translationCard
                    }
                    .cardStyle(cornerRadius: AppRadius.hero)
                    FolderPicker(selectedFolderID: $selectedFolderID)
                    wordChips
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .foregroundStyle(Color.appInk)
            .tint(Color.appAccentText)
            .navigationTitle("Из текста")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .sheet(item: $selectedWord, onDismiss: {
                savedOverrides.removeAll()
                categoryOverrides.removeAll()
                draft.startTranslationIfNeeded()
            }) { selection in
                AddWordView(initialText: selection.text, initialFolderID: selectedFolderID)
            }
            .onChange(of: selectedFolderID) { savedOverrides.removeAll() }
            .onChange(of: draft.sourceText) {
                savedOverrides.removeAll()
                categoryOverrides.removeAll()
                saveErrors.removeAll()
            }
            .onChange(of: selectedWord) {
                if selectedWord != nil {
                    draft.cancelTranslation()
                }
            }
            .task {
                draft.startTranslationIfNeeded()
            }
            .onDisappear {
                draft.cancelTranslation()
            }
        }
        .achievementBanner()
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Оригинал", systemImage: "text.viewfinder")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.subtleText)
            TextEditor(text: Binding(
                get: { draft.sourceText },
                set: { draft.setSource($0) }
            ))
                .font(.body)
                .foregroundStyle(Color.appInk)
                .frame(minHeight: 120, alignment: .topLeading)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.appSecondarySurface, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .accessibilityIdentifier("scanOriginalText")
                .accessibilityLabel("Оригинал распознавания")
                .accessibilityHint("Исправьте распознанный текст перед переводом")
        }
        .padding(AppSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var wordChips: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Слова в словарь")
                    .font(.headline)
                    .foregroundStyle(Color.appInk)
                Text("Нажмите +, чтобы сохранить. Удерживайте слово, чтобы исправить или выбрать тему.")
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chipColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 150), spacing: 10, alignment: .top)]
    }

    private func wordChip(_ word: String, index: Int) -> some View {
        let translation = draft.translations[word]
        let existing = existingWord(word)
        let isSaved = savedOverrides[word] ?? isIncluded(existing)
        return VStack(alignment: .leading, spacing: 0) {
            if let existing {
                HStack {
                    Spacer(minLength: 0)
                    KnowledgeTierBadge(word: existing, level: KnowledgeProgressService.tier(for: existing))
                }
                .padding(.top, 8)
                .padding(.horizontal, 12)
                .padding(.bottom, 2)
            }
            Button {
                if draft.wordErrors[word] != nil {
                    draft.retryWord(word)
                } else {
                    toggleSaved(word)
                }
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(word.lowercased())
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.appInk)
                        Spacer(minLength: 0)
                        Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle")
                            .foregroundStyle(isSaved ? Color.appMastery : Color.appAccentText)
                            .accessibilityHidden(true)
                    }
                    if let translation {
                        Text(translation.lowercased())
                            .font(.subheadline)
                            .foregroundStyle(Color.subtleText)
                    } else if let error = draft.wordErrors[word] {
                        Text(error).font(.caption).foregroundStyle(Color.subtleText)
                        Label("Повторить", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.appAccentText)
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
                            .foregroundStyle(Color.subtleText)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(translation == nil && draft.wordErrors[word] == nil)
            .accessibilityIdentifier("scanWordChip-\(word)-\(index)")
            .accessibilityLabel("\(word), \(translation ?? draft.wordErrors[word] ?? "Перевод загружается")")
            .accessibilityHint(isSaved ? (selectedFolderID == nil ? "Удалить из словаря" : "Убрать из папки") : draft.wordErrors[word] != nil
                ? "Повторить перевод" : translation == nil
                ? "Дождитесь перевода" : "Добавить в словарь без открытия формы")
            .accessibilityActions {
                Button("Исправить слово") { selectedWord = SelectedWord(text: word) }
                if translation != nil {
                    Button(toggleTitle(isSaved: isSaved)) { toggleSaved(word) }
                    ForEach(WordCategory.allCases) { option in
                        Button("Тема: \(option.rawValue)") { changeCategory(option, for: word, existing: existing) }
                    }
                }
            }
            if let error = saveErrors[word] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.appError)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSaved ? Color.appAccentSoft : Color.cardBackground,
                    in: RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                .strokeBorder(Color.appBorder, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contextMenu {
            Button {
                selectedWord = SelectedWord(text: word)
            } label: {
                Label("Исправить слово…", systemImage: "pencil")
            }
            if let translation {
                Button {
                    toggleSaved(word)
                } label: {
                    Label(toggleTitle(isSaved: isSaved), systemImage: isSaved ? "minus.circle" : "plus")
                }
                categoryContextMenu(word, translation: translation, existing: existing)
            }
        }
    }

    private func toggleTitle(isSaved: Bool) -> String {
        guard isSaved else { return "Добавить в словарь" }
        return selectedFolderID == nil ? "Убрать из словаря" : "Убрать из папки"
    }

    private func categoryContextMenu(_ word: String, translation: String, existing: Word?) -> some View {
        let current = categoryOverrides[word] ?? existing?.category ?? category(word, translation: translation)
        return CategoryMenu(selection: Binding(
            get: { current },
            set: { changeCategory($0, for: word, existing: existing) }
        )) {
            Label("Тема: \(current.rawValue)", systemImage: "tag")
        }
    }

    private func changeCategory(_ category: WordCategory, for word: String, existing: Word?) {
        let isSaved = savedOverrides[word] ?? isIncluded(existing)
        guard isSaved, let translation = draft.translations[word] else {
            categoryOverrides[word] = category
            return
        }
        do {
            try vocabulary.changeCategory(category, source: word, translation: translation)
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.subtleText)
                Spacer()
                if draft.isTranslating { ProgressView().controlSize(.small) }
            }
            if !draft.translatedText.isEmpty {
                Text(draft.translatedText)
                    .font(.body)
                    .foregroundStyle(Color.appInk)
                    .lineSpacing(4)
                    .accessibilityIdentifier("scanTranslationText")
            } else if draft.isTranslating {
                Text("Переводим…").foregroundStyle(Color.subtleText)
            }
            if let translationError = draft.translationError {
                Label("Перевод предложения недоступен", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Color.subtleText)
                    .accessibilityLabel("Перевод предложения недоступен. \(translationError)")
                Button("Повторить перевод предложения") {
                    draft.retryContent()
                }
                .frame(minHeight: 44)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        guard let translation = draft.translations[word] else { return nil }
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
        guard let translation = draft.translations[text] else { return }
        let selectedCategory = categoryOverrides[text] ?? existingWord(text)?.category
            ?? category(text, translation: translation)
        do {
            savedOverrides[text] = try vocabulary.toggleScanned(
                source: text, translation: translation, category: selectedCategory,
                folderID: selectedFolderID
            )
            categoryOverrides[text] = selectedCategory
            saveErrors[text] = nil
        } catch {
            saveErrors[text] = "Не удалось изменить словарь. Нажмите на карточку ещё раз."
        }
    }

}

private struct SelectedWord: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

private struct FrozenBlockOverlay: View {
    let blocks: [ScannedTextBlock]
    let selectedIDs: Set<String>
    let onToggle: (String) -> Void

    var body: some View {
        GeometryReader { _ in
            ZStack {
                ForEach(blocks) { block in
                    let selected = selectedIDs.contains(block.id)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Color.appAccent.opacity(0.3) : Color.white.opacity(0.04))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(selected ? Color.appAccent : Color.white.opacity(0.85), lineWidth: selected ? 3 : 1.5)
                        }
                        .frame(width: block.bounds.width, height: block.bounds.height)
                        .overlay(alignment: .topTrailing) {
                            if selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(Color.appOnAccent, Color.appAccent)
                                    .offset(x: 8, y: -8)
                            }
                        }
                        .position(x: block.bounds.midX, y: block.bounds.midY)
                        .allowsHitTesting(false)

                    Button {
                        onToggle(block.id)
                    } label: {
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: max(44, block.bounds.width), height: max(44, block.bounds.height))
                    }
                    .buttonStyle(.plain)
                    .position(x: block.bounds.midX, y: block.bounds.midY)
                    .accessibilityLabel(block.text)
                    .accessibilityValue(selected ? "Выбрано" : "Не выбрано")
                    .accessibilityHint("Нажмите, чтобы изменить выбор блока")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    var onPick: (String) -> Void
    var onRecognized: ([ScannedTextLine]) -> Void
    var captureRequestID: Int
    var onCapturePhoto: (UIImage) -> Void
    var onCapturedLines: ([ScannedTextLine]) -> Void
    var onCaptureFinished: () -> Void
    var onCaptureFailed: (String) -> Void

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
        if captureRequestID > context.coordinator.lastCaptureRequestID {
            context.coordinator.lastCaptureRequestID = captureRequestID
            context.coordinator.capturePhoto(from: controller)
        } else if !context.coordinator.isCapturingPhoto {
            context.coordinator.isFrozen = false
            if !controller.isScanning {
                try? controller.startScanning()
            }
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onRecognized: onRecognized, captureRequestID: captureRequestID,
                    onCapturePhoto: onCapturePhoto, onCapturedLines: onCapturedLines,
                    onCaptureFinished: onCaptureFinished, onCaptureFailed: onCaptureFailed)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onPick: (String) -> Void
        let onRecognized: ([ScannedTextLine]) -> Void
        let onCapturePhoto: (UIImage) -> Void
        let onCapturedLines: ([ScannedTextLine]) -> Void
        let onCaptureFinished: () -> Void
        let onCaptureFailed: (String) -> Void
        private var recognizedLines: [ScannedTextLine] = []
        fileprivate var lastCaptureRequestID: Int
        fileprivate var isCapturingPhoto = false
        fileprivate var isFrozen = false

        init(onPick: @escaping (String) -> Void, onRecognized: @escaping ([ScannedTextLine]) -> Void,
             captureRequestID: Int, onCapturePhoto: @escaping (UIImage) -> Void,
             onCapturedLines: @escaping ([ScannedTextLine]) -> Void,
             onCaptureFinished: @escaping () -> Void, onCaptureFailed: @escaping (String) -> Void) {
            self.onPick = onPick
            self.onRecognized = onRecognized
            self.lastCaptureRequestID = captureRequestID
            self.onCapturePhoto = onCapturePhoto
            self.onCapturedLines = onCapturedLines
            self.onCaptureFinished = onCaptureFinished
            self.onCaptureFailed = onCaptureFailed
        }

        func capturePhoto(from scanner: DataScannerViewController) {
            guard !isCapturingPhoto else { return }
            isCapturingPhoto = true
            let viewportSize = scanner.view.bounds.size
            Task { @MainActor in
                defer {
                    isCapturingPhoto = false
                    onCaptureFinished()
                }
                do {
                    let photo = try await scanner.capturePhoto()
                    isFrozen = true
                    scanner.stopScanning()
                    onCapturePhoto(photo)
                    let lines = try await ScannedImageTextRecognizer.recognize(image: photo, viewportSize: viewportSize)
                    onCapturedLines(lines)
                } catch {
                    onCaptureFailed(error.localizedDescription)
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            publishTextItems(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            publishTextItems(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            publishTextItems(allItems)
        }

        private func publishTextItems(_ items: [RecognizedItem]) {
            guard !isFrozen else { return }
            recognizedLines = items.compactMap { item in
                guard case .text(let text) = item else { return nil }
                let corners = [text.bounds.topLeft, text.bounds.topRight, text.bounds.bottomLeft, text.bounds.bottomRight]
                let xs = corners.map(\.x)
                let ys = corners.map(\.y)
                let bounds = CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0,
                                    width: (xs.max() ?? 0) - (xs.min() ?? 0),
                                    height: (ys.max() ?? 0) - (ys.min() ?? 0))
                return ScannedTextLine(id: item.id, text: text.transcript, bounds: bounds)
            }
            onRecognized(recognizedLines)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case .text(let text) = item, recognizedLines.contains(where: { $0.id == item.id }) {
                onPick(text.transcript)
            }
        }
    }
}
