import UIKit

/// Uploads pending log rows when the app goes to the background, inside a background task that
/// always ends exactly once: when the flush finishes, or when iOS expires the task (the flush is
/// cancelled, rows stay on disk). An assertion left open would get the app killed.
@MainActor
final class BackgroundLogFlush {
    typealias Begin = (_ name: String, _ expiration: @escaping @MainActor () -> Void) -> UIBackgroundTaskIdentifier
    typealias End = (UIBackgroundTaskIdentifier) -> Void

    private var identifier = UIBackgroundTaskIdentifier.invalid
    private var flush: Task<Void, Never>?
    private let end: End

    private init(end: @escaping End) {
        self.end = end
    }

    @discardableResult
    static func start(logger: any AppLogging, begin: Begin? = nil, end: End? = nil) -> Task<Void, Never> {
        run(name: "app-log-flush", begin: begin, end: end) { await logger.flush() }
    }

    /// Runs `work` inside a background task that ends exactly once: on completion, or when iOS
    /// expires it (the work is cancelled).
    @discardableResult
    static func run(name: String, begin: Begin? = nil, end: End? = nil,
                    work: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let begin = begin ?? { name, expiration in
            UIApplication.shared.beginBackgroundTask(withName: name) {
                MainActor.assumeIsolated { expiration() }
            }
        }
        let run = BackgroundLogFlush(end: end ?? { UIApplication.shared.endBackgroundTask($0) })
        run.identifier = begin(name) { [run] in
            run.flush?.cancel()
            run.finish()
        }
        let task = Task { [run] in
            await work()
            run.finish()
        }
        run.flush = task
        return task
    }

    private func finish() {
        guard identifier != .invalid else { return }
        end(identifier)
        identifier = .invalid
    }
}
