import SwiftUI
import VisionKit
import AVFoundation

/// Экран сканера: живая камера, распознанный текст подсвечивается,
/// тап по строке → выбор слова и добавление в словарь.
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

                Text("Наведите камеру на текст и коснитесь слова")
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
