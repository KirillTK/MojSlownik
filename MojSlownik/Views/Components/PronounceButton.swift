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
                .frame(minWidth: 44, minHeight: 44)
                .background(Color.appSecondarySurface)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Произнести: \(text)")
    }
}
