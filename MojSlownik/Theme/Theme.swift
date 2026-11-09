import SwiftUI
import UIKit

// Linen surfaces and sage actions, with matching dark appearances.
extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let appAccent = Color(
        light: UIColor(red: 0.302, green: 0.400, blue: 0.294, alpha: 1),
        dark: UIColor(red: 0.682, green: 0.780, blue: 0.643, alpha: 1)
    )

    static let appOnAccent = Color(
        light: UIColor(red: 0.996, green: 0.996, blue: 0.980, alpha: 1),
        dark: UIColor(red: 0.129, green: 0.157, blue: 0.125, alpha: 1)
    )

    static let appBackground = Color(
        light: UIColor(red: 0.973, green: 0.969, blue: 0.937, alpha: 1),
        dark: UIColor(red: 0.075, green: 0.090, blue: 0.075, alpha: 1)
    )

    static let cardBackground = Color(
        light: UIColor(red: 0.996, green: 0.996, blue: 0.980, alpha: 1),
        dark: UIColor(red: 0.129, green: 0.157, blue: 0.125, alpha: 1)
    )

    static let appInk = Color(
        light: UIColor(red: 0.137, green: 0.165, blue: 0.133, alpha: 1),
        dark: UIColor(red: 0.941, green: 0.953, blue: 0.910, alpha: 1)
    )

    static let subtleText = Color(
        light: UIColor(red: 0.365, green: 0.400, blue: 0.345, alpha: 1),
        dark: UIColor(red: 0.694, green: 0.741, blue: 0.659, alpha: 1)
    )

    static let appSecondarySurface = Color(
        light: UIColor(red: 0.886, green: 0.910, blue: 0.855, alpha: 1),
        dark: UIColor(red: 0.192, green: 0.235, blue: 0.180, alpha: 1)
    )

    static let appBorder = Color(
        light: UIColor(red: 0.765, green: 0.800, blue: 0.729, alpha: 1),
        dark: UIColor(red: 0.337, green: 0.392, blue: 0.310, alpha: 1)
    )

    static let appSuccess = Color(
        light: UIColor(red: 0.302, green: 0.400, blue: 0.294, alpha: 1),
        dark: UIColor(red: 0.682, green: 0.780, blue: 0.643, alpha: 1)
    )
}

extension View {
    func cardStyle(cornerRadius: CGFloat = 18) -> some View {
        self
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
