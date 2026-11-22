import SwiftUI

struct PronounceButton: View {
    let text: String
    let language: Language

    var body: some View {
        Button {
            SpeechService.shared.speak(text, language: language)
        } label: {
            Image(systemName: "speaker.wave.2")
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(Color.appInk)
                .frame(width: 44, height: 44)
                .background(Color.appSecondarySurface, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pronounce: \(text)")
    }
}
