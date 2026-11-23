import XCTest
import UIKit
import SwiftUI
@testable import MojSlownik

final class ThemeTests: XCTestCase {
    private enum Mode { case light, dark }

    private func rgba(_ color: UIColor, _ mode: Mode) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        let style: UIUserInterfaceStyle = mode == .light ? .light : .dark
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    private func luminance(_ c: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)) -> Double {
        func lin(_ v: CGFloat) -> Double {
            let x = Double(v)
            return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    /// WCAG contrast of `fg` (optionally with extra alpha, composited over `bg`) against `bg`.
    private func contrast(_ fg: UIColor, _ bg: UIColor, _ mode: Mode, fgAlpha: CGFloat = 1) -> Double {
        let b = rgba(bg, mode)
        let f = rgba(fg, mode)
        let a = f.a * fgAlpha
        let composited = (r: f.r * a + b.r * (1 - a), g: f.g * a + b.g * (1 - a),
                          b: f.b * a + b.b * (1 - a), a: CGFloat(1))
        let l1 = luminance(composited), l2 = luminance(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    private func hexString(_ color: UIColor, _ mode: Mode) -> String {
        let c = rgba(color, mode)
        func byte(_ v: CGFloat) -> Int { Int((v * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.r), byte(c.g), byte(c.b))
    }

    private let modes: [Mode] = [.light, .dark]

    func testHexInitResolvesChannels() {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(hex: 0xFFD43B).getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 1, accuracy: 0.001)
        XCTAssertEqual(g, 212.0 / 255, accuracy: 0.001)
        XCTAssertEqual(b, 59.0 / 255, accuracy: 0.001)
        XCTAssertEqual(a, 1, accuracy: 0.001)
    }

    func testTextPairsMeetAAInBothAppearances() {
        let pairs: [(String, UIColor, UIColor)] = [
            ("ink/background", Palette.ink, Palette.background),
            ("ink/card", Palette.ink, Palette.card),
            ("subtle/background", Palette.subtle, Palette.background),
            ("subtle/card", Palette.subtle, Palette.card),
            ("subtle/secondarySurface", Palette.subtle, Palette.secondarySurface),
            ("accentText/background", Palette.accentText, Palette.background),
            ("accentText/card", Palette.accentText, Palette.card),
            ("accentText/accentSoft", Palette.accentText, Palette.accentSoft),
            ("onAccent/accent", Palette.onAccent, Palette.accent),
            ("onInverse/inverse", Palette.onInverse, Palette.inverseSurface),
            ("accent/inverse", Palette.accent, Palette.inverseSurface),
            ("error/errorSurface", Palette.error, Palette.errorSurface),
            ("warning/warningSurface", Palette.warning, Palette.warningSurface),
            ("mastery/background", Palette.mastery, Palette.background),
            ("mastery/masterySurface", Palette.mastery, Palette.masterySurface),
            ("mastery/secondarySurface", Palette.mastery, Palette.secondarySurface),
        ]
        for mode in modes {
            for (name, fg, bg) in pairs {
                XCTAssertGreaterThanOrEqual(contrast(fg, bg, mode), 4.5, "\(name) \(mode)")
            }
            XCTAssertGreaterThanOrEqual(contrast(Palette.onAccent, Palette.accent, mode, fgAlpha: 0.75), 4.5,
                                        "onAccent@0.75/accent \(mode)")
        }
    }

    func testGraphicsMeetNonTextContrast() {
        let pairs: [(String, UIColor, UIColor)] = [
            ("caution/card", Palette.caution, Palette.card),
            ("caution/background", Palette.caution, Palette.background),
            ("error/card", Palette.error, Palette.card),
            ("accentText/card", Palette.accentText, Palette.card),
            ("mastery/card", Palette.mastery, Palette.card),
            ("learning/card", Palette.learning, Palette.card),
            ("learning/background", Palette.learning, Palette.background),
        ]
        for mode in modes {
            for (name, fg, bg) in pairs {
                XCTAssertGreaterThanOrEqual(contrast(fg, bg, mode), 3.0, "\(name) \(mode)")
            }
            XCTAssertGreaterThanOrEqual(contrast(Palette.ringTrack, Palette.card, mode), 1.5, "ringTrack/card \(mode)")
            XCTAssertGreaterThanOrEqual(contrast(Palette.ringTrack, Palette.background, mode), 1.5,
                                        "ringTrack/background \(mode)")
        }
        XCTAssertGreaterThanOrEqual(contrast(Palette.inverseEdge, Palette.background, .dark), 1.5)
    }

    func testYellowIsFillOnlyAndOchreStaysOffSecondarySurfaceText() {
        let ochre = contrast(Palette.accentText, Palette.secondarySurface, .light)
        XCTAssertGreaterThanOrEqual(ochre, 3.0)
        XCTAssertLessThan(ochre, 4.5)
        XCTAssertLessThan(contrast(Palette.ink, Palette.accent, .dark), 3.0,
                          "dark appInk on yellow is unreadable; appOnAccent is mandatory")
        XCTAssertLessThan(contrast(Palette.accent, Palette.background, .light), 3.0)
        let amber = contrast(Palette.caution, Palette.background, .light)
        XCTAssertGreaterThanOrEqual(amber, 3.0)
        XCTAssertLessThan(amber, 4.5, "amber stays graphics-only")
    }

    func testCoordinatorVerifiedRatios() {
        let white = UIColor(hex: 0xFFFFFF)
        let ochreOnSoft = contrast(Palette.accentText, Palette.accentSoft, .light)
        let expected: [(String, Double, Double)] = [
            ("ink/yellow", contrast(Palette.ink, Palette.accent, .light), 12.1),
            ("yellow/paper", contrast(Palette.accent, Palette.background, .light), 1.34),
            ("ochre/paper", contrast(Palette.accentText, Palette.background, .light), 4.77),
            ("ochre/white", contrast(Palette.accentText, white, .light), 5.07),
            ("ochre/soft", ochreOnSoft, 4.54),
            ("subtle/paper", contrast(Palette.subtle, Palette.background, .light), 5.32),
            ("dark yellow/bg", contrast(Palette.accentText, Palette.background, .dark), 13.0),
            ("dark yellow/card", contrast(Palette.accentText, Palette.card, .dark), 11.7),
            ("dark subtle/card", contrast(Palette.subtle, Palette.card, .dark), 6.56),
            ("error/white", contrast(Palette.error, white, .light), 6.54),
            ("mastery/paper", contrast(Palette.mastery, Palette.background, .light), 5.65),
            ("mastery/masterySurface", contrast(Palette.mastery, Palette.masterySurface, .light), 5.15),
            ("mastery/secondarySurface", contrast(Palette.mastery, Palette.secondarySurface, .light), 5.08),
            ("amber/paper", contrast(Palette.caution, Palette.background, .light), 3.26),
            ("honey/card", contrast(Palette.learning, Palette.card, .light), 3.25),
            ("honey/paper", contrast(Palette.learning, Palette.background, .light), 3.06),
            ("dark honey/card", contrast(Palette.learning, Palette.card, .dark), 11.7),
        ]
        for (name, actual, wanted) in expected {
            XCTAssertEqual(actual, wanted, accuracy: 0.05, name)
        }
    }

    func testSuccessIsMasteryAlias() {
        XCTAssertEqual(Color.appSuccess, Color.appMastery)
    }

    func testDesignDocTokenTableMatchesPalette() throws {
        let palette: [String: UIColor] = [
            "appBackground": Palette.background, "cardBackground": Palette.card,
            "appInk": Palette.ink, "subtleText": Palette.subtle, "appBorder": Palette.border,
            "appSecondarySurface": Palette.secondarySurface, "appAccent": Palette.accent,
            "appOnAccent": Palette.onAccent, "appAccentText": Palette.accentText,
            "appAccentStrong": Palette.accentStrong, "appAccentSoft": Palette.accentSoft,
            "appInverseSurface": Palette.inverseSurface, "appOnInverse": Palette.onInverse,
            "appCardEdge": Palette.cardEdge, "appRingTrack": Palette.ringTrack,
            "appInverseEdge": Palette.inverseEdge, "appMastery": Palette.mastery,
            "appMasterySurface": Palette.masterySurface, "appError": Palette.error,
            "appErrorSurface": Palette.errorSurface, "appWarning": Palette.warning,
            "appWarningSurface": Palette.warningSurface, "appCaution": Palette.caution, "appLearning": Palette.learning,
        ]
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let doc = root.appendingPathComponent("DESIGN.md")
        let text = try String(contentsOf: doc, encoding: .utf8)

        var seen = Set<String>()
        for line in text.split(separator: "\n") {
            let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 6, cells[1].hasPrefix("`app") || cells[1].hasPrefix("`card") || cells[1].hasPrefix("`subtle"),
                  cells[3].hasPrefix("#"), cells[4].hasPrefix("#") else { continue }
            let token = cells[1].trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            let color = try XCTUnwrap(palette[token], "DESIGN.md lists unknown token \(token)")
            XCTAssertEqual(cells[3].uppercased(), hexString(color, .light), "\(token) light")
            XCTAssertEqual(cells[4].uppercased(), hexString(color, .dark), "\(token) dark")
            seen.insert(token)
        }
        XCTAssertEqual(seen, Set(palette.keys), "DESIGN.md table must list every palette token")
    }
}
