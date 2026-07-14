import SwiftUI
import UIKit

// Палитра: индиго-акцент, тёплые нейтральные фоны, полная поддержка тёмной темы.
extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let appAccent = Color(
        light: UIColor(red: 0.36, green: 0.37, blue: 0.94, alpha: 1), // #5B5FEF
        dark: UIColor(red: 0.55, green: 0.56, blue: 1.00, alpha: 1)   // #8B8FFF
    )

    static let appBackground = Color(
        light: UIColor(red: 0.97, green: 0.96, blue: 0.95, alpha: 1), // тёплый off-white
        dark: UIColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
    )

    static let cardBackground = Color(
        light: .white,
        dark: UIColor(red: 0.13, green: 0.14, blue: 0.17, alpha: 1)
    )

    static let subtleText = Color(
        light: UIColor(red: 0.45, green: 0.45, blue: 0.50, alpha: 1),
        dark: UIColor(red: 0.62, green: 0.62, blue: 0.68, alpha: 1)
    )
}

extension View {
    /// Стандартная «карточка» приложения.
    func cardStyle(cornerRadius: CGFloat = 20) -> some View {
        self
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}
