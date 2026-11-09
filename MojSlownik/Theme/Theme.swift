import SwiftUI
import UIKit

// Warm pearl, deep ink and lilac actions, with readable dark appearances.
extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let appAccent = Color(
        light: UIColor(red: 0.439, green: 0.275, blue: 0.773, alpha: 1),
        dark: UIColor(red: 0.776, green: 0.659, blue: 0.973, alpha: 1)
    )
    static let appOnAccent = Color(
        light: UIColor(red: 1, green: 1, blue: 1, alpha: 1),
        dark: UIColor(red: 0.133, green: 0.102, blue: 0.200, alpha: 1)
    )
    static let appBackground = Color(
        light: UIColor(red: 0.984, green: 0.980, blue: 0.969, alpha: 1),
        dark: UIColor(red: 0.075, green: 0.063, blue: 0.102, alpha: 1)
    )
    static let cardBackground = Color(
        light: UIColor(red: 1, green: 1, blue: 1, alpha: 1),
        dark: UIColor(red: 0.133, green: 0.114, blue: 0.173, alpha: 1)
    )
    static let appInk = Color(
        light: UIColor(red: 0.141, green: 0.114, blue: 0.208, alpha: 1),
        dark: UIColor(red: 0.953, green: 0.929, blue: 0.980, alpha: 1)
    )
    static let subtleText = Color(
        light: UIColor(red: 0.384, green: 0.357, blue: 0.427, alpha: 1),
        dark: UIColor(red: 0.741, green: 0.706, blue: 0.788, alpha: 1)
    )
    static let appSecondarySurface = Color(
        light: UIColor(red: 0.933, green: 0.906, blue: 0.973, alpha: 1),
        dark: UIColor(red: 0.212, green: 0.165, blue: 0.290, alpha: 1)
    )
    static let appBorder = Color(
        light: UIColor(red: 0.827, green: 0.800, blue: 0.867, alpha: 1),
        dark: UIColor(red: 0.349, green: 0.306, blue: 0.408, alpha: 1)
    )
    static let appSuccess = appAccent
    static let appError = Color(
        light: UIColor(red: 0.608, green: 0.180, blue: 0.275, alpha: 1),
        dark: UIColor(red: 0.984, green: 0.659, blue: 0.710, alpha: 1)
    )
    static let appErrorSurface = Color(
        light: UIColor(red: 0.992, green: 0.918, blue: 0.925, alpha: 1),
        dark: UIColor(red: 0.290, green: 0.122, blue: 0.173, alpha: 1)
    )
    static let appWarning = Color(
        light: UIColor(red: 0.486, green: 0.298, blue: 0.090, alpha: 1),
        dark: UIColor(red: 0.957, green: 0.780, blue: 0.529, alpha: 1)
    )
    static let appWarningSurface = Color(
        light: UIColor(red: 0.984, green: 0.937, blue: 0.859, alpha: 1),
        dark: UIColor(red: 0.263, green: 0.192, blue: 0.114, alpha: 1)
    )
}

extension View {
    func cardStyle(cornerRadius: CGFloat = 18) -> some View {
        self
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
