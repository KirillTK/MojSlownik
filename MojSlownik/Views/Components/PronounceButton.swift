import SwiftUI

struct PronounceButton: View {
    let text: String
    let language: AppLanguage

    var body: some View {
        Button {
            SpeechService.shared.speak(text, language: language)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.body)
                .foregroundStyle(Color.appAccent)
                .padding(10)
                .background(Color.appAccent.opacity(0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
