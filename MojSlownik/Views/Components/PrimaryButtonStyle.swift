import SwiftUI

/// Full-width primary action. `.accent` is the yellow fill; `.inverse` is only for use inside the yellow hero.
struct PrimaryButtonStyle: ButtonStyle {
    enum Kind { case accent, inverse }

    var kind: Kind = .accent

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(kind: kind, configuration: configuration)
    }
}

private struct PrimaryButtonBody: View {
    let kind: PrimaryButtonStyle.Kind
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var background: Color {
        switch (kind, isEnabled) {
        case (.accent, true): .appAccent
        case (.accent, false): .appSecondarySurface
        case (.inverse, true): .appInverseSurface
        case (.inverse, false): Color.appOnAccent.opacity(0.12)
        }
    }

    private var foreground: Color {
        switch (kind, isEnabled) {
        case (.accent, true): .appOnAccent
        case (.accent, false): .subtleText
        case (.inverse, true): .appAccent
        case (.inverse, false): Color.appOnAccent.opacity(0.5)
        }
    }

    var body: some View {
        configuration.label
            .font(.body.weight(.bold))
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, AppSpacing.m)
            .background(background, in: RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}
