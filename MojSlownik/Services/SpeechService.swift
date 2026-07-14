import AVFoundation

final class SpeechService {
    static let shared = SpeechService()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {
        // Чтобы озвучка работала даже с включённым беззвучным режимом.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: .duckOthers)
    }

    func speak(_ text: String, language: AppLanguage) {
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language.speechCode)
        utterance.rate = 0.45
        synthesizer.speak(utterance)
    }
}
