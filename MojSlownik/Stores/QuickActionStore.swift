import Foundation
import Observation

/// The quick action the user launched the app with, kept until the screen that handles it consumes it
/// (the tabs may not exist yet while the session is restored or the first-launch wizard is shown).
@MainActor
@Observable
final class QuickActionStore {
    private(set) var pending: QuickAction?

    /// Returns false for a shortcut type this build does not know.
    @discardableResult
    func handle(shortcutType: String) -> Bool {
        guard let action = QuickAction(shortcutType: shortcutType) else { return false }
        pending = action
        return true
    }

    /// Whether the Dictionary tab should open the scanner now. Waits (keeps the action) until that tab is
    /// selected. Drops the action while something is presented there (a sheet with a draft, an alert): the
    /// app comes forward without interrupting it, as a full-screen cover cannot open over it anyway.
    func takeScanRequest(dictionaryIsSelected: Bool, isPresenting: Bool) -> Bool {
        guard pending == .scanText, dictionaryIsSelected else { return false }
        pending = nil
        return !isPresenting
    }
}
