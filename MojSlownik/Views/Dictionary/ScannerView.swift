import SwiftUI
import SwiftData
import VisionKit
import AVFoundation
import UIKit

/// Scanner screen: live camera with recognized text highlighted;
/// tapping a line opens the result screen with the translation and per-word selection.
struct ScannerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var unavailableIconSize: CGFloat = 44
    let pair: LanguagePair
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
                    languages: ScannedImageTextRecognizer.ocrLanguages(for: pair),
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
                    Text("Scanning")
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
                    .accessibilityLabel("Close scanner")
                    .accessibilityIdentifier("closeScannerButton")
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
        .errorAlert(title: "Couldn’t process the frame", error: $captureError)
        .task {
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                cameraAuthorized = await AVCaptureDevice.requestAccess(for: .video)
            }
        }
    }

    private var instructionText: String {
        guard capturedPhoto != nil else { return String(localized: "Tap a line or freeze the frame") }
        if isCapturingPhoto { return String(localized: "Recognizing text in the frame…") }
        if frozenLines.isEmpty { return String(localized: "No text recognized. Retake the frame.") }
        return String(localized: "Tap blocks to select text")
    }

    private var scannerControlBar: some View {
        VStack(spacing: 6) {
            if capturedPhoto != nil {
                if isCapturingPhoto {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Recognizing text in the frame…")
                            .font(.caption.weight(.medium))
                    }
                    .frame(minHeight: 44)
                } else {
                    HStack(spacing: 10) {
                        Text("Selected: \(selectedBlockIDs.count)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.appInk)
                        Button {
                            if !selectedBlockText.isEmpty { onPick(selectedBlockText) }
                        } label: {
                            Label("Translate selected", systemImage: "text.magnifyingglass")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(selectedBlockIDs.isEmpty)
                        .accessibilityHint("Translate the selected text blocks in reading order")
                    }
                }
            }

            HStack(spacing: 8) {
                compactControl(
                    title: "All",
                    accessibilityTitle: "Translate all text",
                    symbol: "text.viewfinder",
                    enabled: !ScannedTextSelection.text(from: activeLines).isEmpty
                ) {
                    let text = ScannedTextSelection.text(from: activeLines)
                    if !text.isEmpty { onPick(text) }
                }
                compactControl(
                    title: isCapturingPhoto ? "Capturing…" : (capturedPhoto == nil ? "Freeze" : "Retake"),
                    accessibilityTitle: capturedPhoto == nil ? "Freeze the frame" : "Retake the frame",
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

    private func compactControl(title: LocalizedStringKey, accessibilityTitle: LocalizedStringKey, symbol: String,
                                enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                if dynamicTypeSize.isAccessibilitySize { Text(verbatim: "") } else { Text(title) }
            } icon: {
                Image(systemName: symbol)
            }
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
                 ? "The scanner isn’t available on this device (the simulator has no camera)."
                 : "Allow camera access in Settings to scan words.")
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
    @Environment(WorkspaceStore.self) private var workspaces
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var storedSavedWords: [Word]
    @Query private var storedMemberships: [FolderMembership]
    private var memberships: MembershipIndex { MembershipIndex(storedMemberships) }
    private var savedWords: [Word] { WorkspaceScope.words(storedSavedWords, workspaceID: workspaces.activeID) }
    @State private var draft: ScanResultDraft
    @State private var selectedWord: SelectedWord?
    @State private var saveErrors: [String: String] = [:]
    @State private var categoryOverrides: [String: WordCategory] = [:]
    @State private var selectedFolderID: UUID?
    @State private var savedOverrides: [String: Bool] = [:]

    init(scannedText: String, pair: LanguagePair) {
        self.scannedText = scannedText
        _draft = State(initialValue: ScanResultDraft(
            sourceText: ScannedTextTokenizer.joiningLineBreakHyphenation(in: scannedText), pair: pair
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
            .navigationTitle("From text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("scanDoneButton")
                }
            }
            .sheet(item: $selectedWord, onDismiss: {
                savedOverrides.removeAll()
                categoryOverrides.removeAll()
                draft.startTranslationIfNeeded()
            }) { selection in
                AddWordView(initialText: selection.text, initialFolderID: selectedFolderID, pair: workspaces.pair,
                            inputSide: workspaces.activeInputSide)
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
            Label("Original", systemImage: "text.viewfinder")
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
                .accessibilityLabel("Recognized original")
                .accessibilityHint("Fix the recognized text before translating")
        }
        .padding(AppSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var wordChips: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Words for the dictionary")
                    .font(.headline)
                    .foregroundStyle(Color.appInk)
                Text("Tap + to save. Hold a word to fix it or choose a topic.")
                    .font(.caption)
                    .foregroundStyle(Color.subtleText)
            }
            if words.isEmpty {
                Text("Couldn’t pick out words. Try scanning another line.")
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
        let status = translation ?? draft.wordErrors[word] ?? String(localized: "Loading translation")
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
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.appAccentText)
                    } else {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Translating…").font(.caption)
                        }
                        .foregroundStyle(Color.subtleText)
                    }
                    if isSaved {
                        Text(selectedFolderID == nil ? "In the dictionary · tap to delete" : "In the folder · tap to remove")
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
            .accessibilityLabel(Text(verbatim: "\(word), \(status)"))
            .accessibilityHint(isSaved ? (selectedFolderID == nil ? "Delete from the dictionary" : "Remove from the folder") : draft.wordErrors[word] != nil
                ? "Retry translation" : translation == nil
                ? "Wait for the translation" : "Add to the dictionary without opening the form")
            .accessibilityActions {
                Button("Fix word") { selectedWord = SelectedWord(text: word) }
                if translation != nil {
                    Button(toggleTitle(isSaved: isSaved)) { toggleSaved(word) }
                    ForEach(WordCategory.allCases) { option in
                        Button("Topic: \(option.title)") { changeCategory(option, for: word, existing: existing) }
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
                Label("Fix word…", systemImage: "pencil")
            }
            .accessibilityIdentifier("scanEditWordButton")
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
        guard isSaved else { return String(localized: "Add to the dictionary") }
        return selectedFolderID == nil ? String(localized: "Remove from the dictionary") : String(localized: "Remove from the folder")
    }

    private func categoryContextMenu(_ word: String, translation: String, existing: Word?) -> some View {
        let current = categoryOverrides[word] ?? existing?.category ?? category(word, translation: translation)
        return CategoryMenu(selection: Binding(
            get: { current },
            set: { changeCategory($0, for: word, existing: existing) }
        )) {
            Label("Topic: \(current.title)", systemImage: "tag")
        }
    }

    private func changeCategory(_ category: WordCategory, for word: String, existing: Word?) {
        let isSaved = savedOverrides[word] ?? isIncluded(existing)
        guard isSaved, let translation = draft.translations[word] else {
            categoryOverrides[word] = category
            return
        }
        do {
            try vocabulary.changeCategory(category, entry: entry(for: word, translation: translation))
            categoryOverrides[word] = category
            saveErrors[word] = nil
        } catch {
            saveErrors[word] = String(localized: "Couldn’t change the category. Try again.")
        }
    }

    private var translationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Translation")
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
                Text("Translating…").foregroundStyle(Color.subtleText)
            }
            if let translationError = draft.translationError {
                Label("Sentence translation is unavailable", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Color.subtleText)
                    .accessibilityLabel("Sentence translation is unavailable. \(translationError)")
                Button("Retry sentence translation") {
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
        let isTerm = draft.side(of: word) == .term
        return WordCategory.detect(term: isTerm ? word : translation, translation: isTerm ? translation : word)
    }

    private func entry(for word: String, translation: String) -> WordEntry {
        WordEntry.make(input: word, translation: translation, side: draft.side(of: word))
    }

    private func existingWord(_ word: String) -> Word? {
        guard let translation = draft.translations[word] else { return nil }
        let entry = entry(for: word, translation: translation)
        let matches = savedWords.filter { $0.matches(entry) }
        if let selectedFolderID,
           let member = matches.first(where: { memberships.contains(wordID: $0.uuid, folderID: selectedFolderID) }) { return member }
        return matches.first
    }

    private func isIncluded(_ word: Word?) -> Bool {
        guard let word else { return false }
        return selectedFolderID.map { memberships.contains(wordID: word.uuid, folderID: $0) } ?? true
    }

    private func toggleSaved(_ text: String) {
        guard let translation = draft.translations[text] else { return }
        let selectedCategory = categoryOverrides[text] ?? existingWord(text)?.category
            ?? category(text, translation: translation)
        do {
            savedOverrides[text] = try vocabulary.toggleScanned(
                entry(for: text, translation: translation), category: selectedCategory,
                folderID: selectedFolderID
            )
            categoryOverrides[text] = selectedCategory
            saveErrors[text] = nil
        } catch {
            saveErrors[text] = String(localized: "Couldn’t update the dictionary. Tap the card again.")
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
                    .accessibilityValue(selected ? "Selected" : "Not selected")
                    .accessibilityHint("Tap to change the block selection")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    var languages: [String]
    var onPick: (String) -> Void
    var onRecognized: ([ScannedTextLine]) -> Void
    var captureRequestID: Int
    var onCapturePhoto: (UIImage) -> Void
    var onCapturedLines: ([ScannedTextLine]) -> Void
    var onCaptureFinished: () -> Void
    var onCaptureFailed: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        // The dictionary languages; if the system does not know them, the list is empty = automatic selection.
        let supported = DataScannerViewController.supportedTextRecognitionLanguages
        let languages = ScannedImageTextRecognizer.dataScannerLanguages(wanted: self.languages, supported: supported)

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
        Coordinator(languages: languages, onPick: onPick, onRecognized: onRecognized, captureRequestID: captureRequestID,
                    onCapturePhoto: onCapturePhoto, onCapturedLines: onCapturedLines,
                    onCaptureFinished: onCaptureFinished, onCaptureFailed: onCaptureFailed)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let languages: [String]
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

        init(languages: [String], onPick: @escaping (String) -> Void, onRecognized: @escaping ([ScannedTextLine]) -> Void,
             captureRequestID: Int, onCapturePhoto: @escaping (UIImage) -> Void,
             onCapturedLines: @escaping ([ScannedTextLine]) -> Void,
             onCaptureFinished: @escaping () -> Void, onCaptureFailed: @escaping (String) -> Void) {
            self.languages = languages
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
                    let lines = try await ScannedImageTextRecognizer.recognize(image: photo, viewportSize: viewportSize,
                                                                              languages: languages)
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
