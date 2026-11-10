import AVFoundation
import Observation
import Speech

@MainActor
protocol SpeechRecognitionBackend: AnyObject {
    func requestPermission() async -> Bool
    func start(locale: String, onResult: @escaping @MainActor (String, Bool) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) throws
    func finishAudio()
    func cancel()
}

@MainActor
@Observable
final class SpeechRecognitionService {
    enum State { case idle, requestingPermission, listening, finishing }

    private(set) var state: State = .idle
    private(set) var draft = ""
    private(set) var errorMessage: String?
    var isBusy: Bool { state != .idle }

    private let backend: any SpeechRecognitionBackend
    private let finishTimeout: Duration
    private var token = UUID()
    private var completion: (@MainActor (String) -> Void)?
    private var permissionTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(backend: (any SpeechRecognitionBackend)? = nil,
         finishTimeout: Duration = .seconds(3)) {
        self.backend = backend ?? NativeSpeechRecognitionBackend()
        self.finishTimeout = finishTimeout
    }

    func start(onRecognized: @escaping @MainActor (String) -> Void) {
        guard !isBusy else { return }
        token = UUID()
        let session = token
        completion = onRecognized
        draft = ""
        errorMessage = nil
        state = .requestingPermission
        SpeechService.shared.stop()
        permissionTask = Task { [weak self] in
            guard let self else { return }
            let allowed = await self.backend.requestPermission()
            guard self.token == session, self.state == .requestingPermission else { return }
            guard allowed else {
                self.fail("Разрешите доступ к микрофону и распознаванию речи в Настройках.", session: session)
                return
            }
            do {
                try self.backend.start(locale: AppLanguage.polish.speechCode, onResult: { [weak self] text, final in
                    guard let self, self.token == session, self.isBusy else { return }
                    self.draft = text
                    if final { self.commit(session: session) }
                }, onFailure: { [weak self] message in
                    self?.fail(message, session: session)
                })
                if self.token == session { self.state = .listening }
            } catch {
                self.fail((error as? LocalizedError)?.errorDescription ?? "Не удалось включить микрофон. Попробуйте ещё раз.", session: session)
            }
        }
    }

    func finish() {
        guard state == .listening else { return }
        state = .finishing
        let session = token
        backend.finishAudio()
        guard token == session else { return }
        timeoutTask = Task { [weak self, finishTimeout] in
            do { try await Task.sleep(for: finishTimeout) } catch { return }
            self?.commit(session: session)
        }
    }

    func cancel() { teardown() }

    private func commit(session: UUID) {
        guard token == session, isBusy else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            fail("Речь не распознана. Попробуйте ещё раз.", session: session)
            return
        }
        let callback = completion
        teardown()
        callback?(text)
    }

    private func fail(_ message: String, session: UUID) {
        guard token == session, isBusy else { return }
        teardown()
        errorMessage = message
    }

    private func teardown() {
        guard isBusy else { return }
        token = UUID()
        permissionTask?.cancel()
        permissionTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        completion = nil
        backend.cancel()
        state = .idle
        draft = ""
    }
}

private enum CaptureError: LocalizedError {
    case unavailable, invalidFormat
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Распознавание польской речи сейчас недоступно. Попробуйте позже."
        case .invalidFormat: return "Микрофон недоступен. Проверьте подключение и попробуйте ещё раз."
        }
    }
}

@MainActor
final class NativeSpeechRecognitionBackend: SpeechRecognitionBackend {
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var interruptionObserver: NSObjectProtocol?
    private var hasTap = false
    private var audioActive = false
    private var audioEnded = false

    func requestPermission() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard !Task.isCancelled, speech else { return false }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    func start(locale: String, onResult: @escaping @MainActor (String, Bool) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) throws {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable else {
            throw CaptureError.unavailable
        }
        self.recognizer = recognizer
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.record, mode: .measurement)
        try audio.setActive(true)
        audioActive = true
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request
        audioEnded = false
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureError.invalidFormat }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        hasTap = true
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
            object: audio, queue: .main) { notification in
                guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      value == AVAudioSession.InterruptionType.began.rawValue else { return }
                Task { @MainActor in onFailure("Запись прервана. Попробуйте ещё раз.") }
            }
        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            Task { @MainActor in
                if let text { onResult(text, final) }
                if error != nil { onFailure("Не удалось распознать речь. Проверьте подключение и попробуйте ещё раз.") }
            }
        }
        engine.prepare()
        try engine.start()
    }

    func finishAudio() {
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        if !audioEnded { request?.endAudio(); audioEnded = true }
    }

    func cancel() {
        finishAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
        recognizer = nil
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        if audioActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            audioActive = false
        }
    }
}
