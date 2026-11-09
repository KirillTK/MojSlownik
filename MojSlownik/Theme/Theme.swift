import SwiftUI
import UIKit

// Warm paper, terracotta actions and olive success, with matching dark surfaces.
extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let appAccent = Color(
        light: UIColor(red: 0.635, green: 0.263, blue: 0.165, alpha: 1),
        dark: UIColor(red: 0.953, green: 0.631, blue: 0.518, alpha: 1)
    )

    static let appOnAccent = Color(
        light: UIColor(red: 1, green: 0.992, blue: 0.980, alpha: 1),
        dark: UIColor(red: 0.161, green: 0.129, blue: 0.118, alpha: 1)
    )

    static let appBackground = Color(
        light: UIColor(red: 0.976, green: 0.953, blue: 0.918, alpha: 1),
        dark: UIColor(red: 0.102, green: 0.082, blue: 0.071, alpha: 1)
    )

    static let cardBackground = Color(
        light: UIColor(red: 1, green: 0.992, blue: 0.980, alpha: 1),
        dark: UIColor(red: 0.161, green: 0.129, blue: 0.118, alpha: 1)
    )

    static let appInk = Color(
        light: UIColor(red: 0.200, green: 0.157, blue: 0.133, alpha: 1),
        dark: UIColor(red: 0.961, green: 0.922, blue: 0.863, alpha: 1)
    )

    static let subtleText = Color(
        light: UIColor(red: 0.427, green: 0.361, blue: 0.314, alpha: 1),
        dark: UIColor(red: 0.753, green: 0.686, blue: 0.624, alpha: 1)
    )

    static let appSecondarySurface = Color(
        light: UIColor(red: 0.937, green: 0.898, blue: 0.859, alpha: 1),
        dark: UIColor(red: 0.224, green: 0.180, blue: 0.153, alpha: 1)
    )

    static let appBorder = Color(
        light: UIColor(red: 0.824, green: 0.753, blue: 0.686, alpha: 1),
        dark: UIColor(red: 0.376, green: 0.310, blue: 0.267, alpha: 1)
    )

    static let appSuccess = Color(
        light: UIColor(red: 0.282, green: 0.365, blue: 0.204, alpha: 1),
        dark: UIColor(red: 0.694, green: 0.780, blue: 0.553, alpha: 1)
    )
}

extension View {
    func cardStyle(cornerRadius: CGFloat = 18) -> some View {
        self
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.appBorder.opacity(0.4), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.025), radius: 6, y: 2)
    }
}
