import AVFoundation

final class SpeechService {
    static let shared = SpeechService()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    func speak(_ text: String, language: AppLanguage) {
        stop()
        // Capture changes the shared category; restore silent-mode playback each time.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language.speechCode)
        utterance.rate = 0.45
        synthesizer.speak(utterance)
    }
}
