import SwiftUI
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

/// Результат сканирования: контекстный перевод строки и выбор слова для добавления.
struct ScanResultView: View {
    let scannedText: String

    @Environment(\.dismiss) private var dismiss
    @State private var translatedText = ""
    @State private var isTranslating = false
    @State private var translationError: String?
    @State private var selectedWord: SelectedWord?

    private var tokens: [ScannedTextTokenizer.Token] {
        ScannedTextTokenizer.tokens(in: scannedText)
    }

    private var words: [String] {
        ScannedTextTokenizer.words(in: scannedText)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sourceCard
                    wordChips
                    translationCard
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
            .sheet(item: $selectedWord) { selection in
                AddWordView(initialText: selection.text)
            }
            .task(id: scannedText) {
                await translateSentence()
            }
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Распознанный текст")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.subtleText)

            FlowLayout(spacing: 4) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                    switch token {
                    case let .word(word) where word.count > 1:
                        Button { select(word) } label: {
                            Text(word)
                                .font(.title3.weight(.medium))
                                .foregroundStyle(Color.appAccent)
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("scanInlineWord-\(index)")
                        .accessibilityLabel("Добавить слово \(word)")
                    case let .word(word):
                        Text(word)
                            .font(.title3.weight(.medium))
                    case let .text(word):
                        Text(word)
                            .font(.title3.weight(.medium))
                    }
            }
            .accessibilityIdentifier("scanOriginalText")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var wordChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Выберите слово для добавления")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.subtleText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        Button { select(word) } label: {
                            Text(word)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.appAccent.opacity(0.12))
                                .foregroundStyle(Color.appAccent)
                                .clipShape(Capsule())
                        }
                        .accessibilityIdentifier("scanWordChip-\(word)-\(index)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var translationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Перевод предложения")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.subtleText)
                Spacer()
                if isTranslating { ProgressView().controlSize(.small) }
            }
            if !translatedText.isEmpty {
                Text(translatedText)
                    .font(.title3.weight(.medium))
                    .accessibilityIdentifier("scanTranslationText")
            } else if isTranslating {
                Text("Переводим…")
                    .foregroundStyle(Color.subtleText)
            }
            if let translationError {
                Label(translationError, systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func select(_ word: String) {
        selectedWord = SelectedWord(text: word)
    }

    private func translateSentence() async {
        let text = scannedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isTranslating = true
        translationError = nil
        translatedText = ""
        do {
            let language = LanguageDetector.detect(text)
            translatedText = try await Translator.translate(text, from: language, to: language.other)
        } catch is CancellationError {
            // Экран закрыли до завершения запроса.
        } catch {
            translationError = error.localizedDescription
        }
        isTranslating = false
    }
}

private struct SelectedWord: Identifiable {
    let id = UUID()
    let text: String
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for placement in layout(proposal: proposal, subviews: subviews).placements {
            placement.subview.place(at: CGPoint(x: bounds.minX + placement.origin.x, y: bounds.minY + placement.origin.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, placements: [(subview: LayoutSubview, origin: CGPoint)]) {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var placements: [(subview: LayoutSubview, origin: CGPoint)] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            placements.append((subview, CGPoint(x: x, y: y)))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return (CGSize(width: proposal.width ?? x, height: y + lineHeight), placements)
    }
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
