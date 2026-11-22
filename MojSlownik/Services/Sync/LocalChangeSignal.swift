import Foundation

/// Tells the sync layer that local vocabulary changed. Stores call `notify()` after every
/// successful write; the app root sets `handler` (to the debounced sync trigger).
@MainActor
final class LocalChangeSignal {
    var handler: (() -> Void)?

    func notify() { handler?() }
}
