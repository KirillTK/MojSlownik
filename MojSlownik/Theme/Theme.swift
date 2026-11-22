import SwiftUI
import UIKit

// "Marker": warm paper, ink, highlighter-yellow fills. DESIGN.md is the source of truth;
// change this file, DESIGN.md and ThemeTests together.

extension UIColor {
    /// 0xRRGGBB.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    convenience init(light: UIColor, dark: UIColor) {
        self.init { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }
}

enum Palette {
    private static func pair(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor(light: UIColor(hex: light), dark: UIColor(hex: dark))
    }

    static let background = pair(0xFAF8F2, 0x141310)
    static let card = pair(0xFFFFFF, 0x1F1E1A)
    static let ink = pair(0x1C1B17, 0xF4F1E8)
    static let subtle = pair(0x6B675C, 0xA8A293)
    static let border = pair(0xE7E2D5, 0x2E2C26)
    static let secondarySurface = pair(0xF0ECE1, 0x2A2823)
    static let accent = pair(0xFFD43B, 0xFFD43B)
    static let onAccent = pair(0x1C1B17, 0x1C1B17)
    static let accentText = pair(0x8A6A00, 0xFFD43B)
    static let accentStrong = pair(0x1C1B17, 0xFFD43B)
    static let accentSoft = pair(0xFFF3BF, 0x3A3318)
    static let inverseSurface = pair(0x1C1B17, 0x1C1B17)
    static let onInverse = pair(0xF4F1E8, 0xF4F1E8)
    static let cardEdge = pair(0xE7E2D5, 0x2E2C26)
    static let ringTrack = pair(0xCDC5B0, 0x46423A)
    static let inverseEdge = pair(0x1C1B17, 0x3A372F)
    static let mastery = pair(0x25704C, 0x8BD3A8)
    static let masterySurface = pair(0xE3F1E8, 0x1C3125)
    static let error = pair(0xB3261E, 0xFF8A80)
    static let errorSurface = pair(0xFCE8E6, 0x3B1D1A)
    static let warning = pair(0x7C4C17, 0xF4C787)
    static let warningSurface = pair(0xFBEFDB, 0x43311D)
    static let caution = pair(0xC77700, 0xFFA94D)
}

extension Color {
    static let appBackground = Color(uiColor: Palette.background)
    static let cardBackground = Color(uiColor: Palette.card)
    static let appInk = Color(uiColor: Palette.ink)
    static let subtleText = Color(uiColor: Palette.subtle)
    static let appBorder = Color(uiColor: Palette.border)
    static let appSecondarySurface = Color(uiColor: Palette.secondarySurface)
    static let appAccent = Color(uiColor: Palette.accent)
    static let appOnAccent = Color(uiColor: Palette.onAccent)
    static let appAccentText = Color(uiColor: Palette.accentText)
    static let appAccentStrong = Color(uiColor: Palette.accentStrong)
    static let appAccentSoft = Color(uiColor: Palette.accentSoft)
    static let appInverseSurface = Color(uiColor: Palette.inverseSurface)
    static let appOnInverse = Color(uiColor: Palette.onInverse)
    static let appCardEdge = Color(uiColor: Palette.cardEdge)
    static let appRingTrack = Color(uiColor: Palette.ringTrack)
    static let appInverseEdge = Color(uiColor: Palette.inverseEdge)
    static let appMastery = Color(uiColor: Palette.mastery)
    static let appMasterySurface = Color(uiColor: Palette.masterySurface)
    static let appError = Color(uiColor: Palette.error)
    static let appErrorSurface = Color(uiColor: Palette.errorSurface)
    static let appWarning = Color(uiColor: Palette.warning)
    static let appWarningSurface = Color(uiColor: Palette.warningSurface)
    static let appCaution = Color(uiColor: Palette.caution)
    /// Success feedback uses the mastery green, never the brand yellow.
    static let appSuccess = appMastery
}

enum AppSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum AppRadius {
    static let control: CGFloat = 12
    static let button: CGFloat = 16
    static let card: CGFloat = 18
    static let hero: CGFloat = 24
    static let flashcard: CGFloat = 28
}

extension View {
    /// Card surface with a 1 pt hairline edge and no shadow.
    func cardStyle(cornerRadius: CGFloat = AppRadius.card) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(Color.cardBackground)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.appCardEdge, lineWidth: 1) }
    }
}
