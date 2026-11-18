import Foundation
@testable import MojSlownik

/// Records log calls; asserts that no property ever carries user text.
@MainActor
final class AppLogSpy: AppLogging {
    struct Entry: Equatable {
        let event: LogEvent
        let level: LogLevel
        let properties: [LogKey: LogValue]
    }

    private(set) var entries: [Entry] = []
    private(set) var flushCount = 0

    func log(_ event: LogEvent, level: LogLevel, properties: [LogKey: LogValue]) {
        entries.append(Entry(event: event, level: level, properties: properties))
    }

    func flush() async {
        flushCount += 1
    }

    var events: [LogEvent] { entries.map(\.event) }

    /// Every name value as logged (ints/bools excluded).
    var loggedNames: [String] {
        entries.flatMap { $0.properties.values }.compactMap {
            if case .name(let value) = $0.storage { return value }
            return nil
        }
    }
}

/// An upload stuck on the network: ignores cancellation, hangs until `release()`, then fails
/// transiently.
@MainActor
final class HangingUploader: AppLogUploading {
    private(set) var uploads = 0
    private var gates: [CheckedContinuation<Void, Never>] = []

    var started: Bool { uploads > 0 }

    func upload(_ rows: [AppLogRow]) async throws {
        uploads += 1
        await withCheckedContinuation { gates.append($0) }
        throw URLError(.timedOut)
    }

    func release() {
        gates.forEach { $0.resume() }
        gates.removeAll()
    }
}

/// An error whose message contains user text, to prove only domain/code are logged.
struct UserTextError: LocalizedError {
    let text: String
    var errorDescription: String? { "Failed to save \(text)" }
}
