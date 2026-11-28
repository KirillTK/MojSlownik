import UIKit

/// Whether any window of a foreground scene presents a view controller (SwiftUI sheet, full-screen cover,
/// alert or confirmation dialog), including one still animating in or out.
@MainActor
enum PresentationProbe {
    static var isPresenting: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState != .background }
            .flatMap(\.windows)
            .contains { $0.rootViewController?.presentedViewController != nil }
    }
}
