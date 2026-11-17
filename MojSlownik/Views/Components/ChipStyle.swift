import SwiftUI

extension View {
    /// Capsule chip: selected = yellow fill with on-accent content, otherwise neutral fill with ink.
    /// Callers must not set their own foreground colours on the label.
    func chipStyle(isSelected: Bool) -> some View {
        self
            .font(.subheadline.weight(isSelected ? .bold : .semibold))
            .foregroundStyle(isSelected ? Color.appOnAccent : Color.appInk)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(isSelected ? Color.appAccent : Color.appSecondarySurface, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}
