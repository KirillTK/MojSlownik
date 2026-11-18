import SwiftUI

/// Full-width primary action. `.accent` is the yellow fill; `.inverse` is only for use inside the yellow hero.
/// `.ink` and `.card` are the non-accent sign-in buttons of the account sheet (Apple / Google).
struct PrimaryButtonStyle: ButtonStyle {
    enum Kind { case accent, inverse, ink, card }

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
        case (.ink, _): .appInverseSurface
        case (.card, _): .cardBackground
        }
    }

    private var edge: Color? {
        switch kind {
        case .ink: .appInverseEdge
        case .card: .appCardEdge
        case .accent, .inverse: nil
        }
    }

    private var foreground: Color {
        switch (kind, isEnabled) {
        case (.accent, true): .appOnAccent
        case (.accent, false): .subtleText
        case (.inverse, true): .appAccent
        case (.inverse, false): Color.appOnAccent.opacity(0.5)
        case (.ink, _): .appOnInverse
        case (.card, _): .appInk
        }
    }

    /// Kinds without a dedicated disabled colour dim instead.
    private var disabledOpacity: Double {
        switch kind {
        case .ink, .card: isEnabled ? 1 : 0.5
        case .accent, .inverse: 1
        }
    }

    var body: some View {
        configuration.label
            .font(.body.weight(.bold))
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .tint(foreground)  // spinners inside the label match the text colour
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, AppSpacing.m)
            .background(background, in: RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
            .overlay {
                if let edge {
                    RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous).strokeBorder(edge, lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity((configuration.isPressed ? 0.9 : 1) * disabledOpacity)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}
