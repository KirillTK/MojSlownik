import Foundation

// Diagnostics and product events. Privacy by construction: there is no free-form string in
// this API. Events and keys are enums; values are Int, Bool or a short ASCII identifier.
// User content (words, translations, OCR/speech text, folder names), emails, tokens and
// error messages can therefore never be logged. Errors contribute only domain and code.

enum LogLevel: String, Codable, Sendable {
    case info, warning, error
}

enum LogEvent: String, CaseIterable, Codable, Sendable {
    case appLaunched = "app.launched"
    case wordAdded = "word.added"
    case wordRemoved = "word.removed"
    case wordDeleted = "word.deleted"
    case wordCategoryChanged = "word.category_changed"
    case wordFoldersChanged = "word.folders_changed"
    case folderCreated = "folder.created"
    case folderDeleted = "folder.deleted"
    case folderRenamed = "folder.renamed"
    case foldersReordered = "folder.reordered"
    case practiceAnswered = "practice.answered"
    case achievementUnlocked = "achievement.unlocked"
    case authSignedIn = "auth.signed_in"
    case authSignedOut = "auth.signed_out"
    case authSignInCancelled = "auth.sign_in_cancelled"
    case authFailed = "auth.failed"
    case storageFailed = "storage.failed"
    case translationFailed = "translation.failed"
    case syncCompleted = "sync.completed"
    case syncFailed = "sync.failed"
    case syncRowsSkipped = "sync.rows_skipped"
    case syncLinked = "sync.linked"
    case syncAccountMismatch = "sync.account_mismatch"

    /// Same pattern as the CHECK constraint on public.app_logs.event.
    static let serverPattern = #"^[a-z][a-z0-9_]{0,31}(\.[a-z][a-z0-9_]{0,31}){1,2}$"#
}

enum LogKey: String, CaseIterable, Sendable {
    case source, language, category, mode, correct, grade, provider, achievement, operation, count
    case trigger, pulled, pushed, skipped, reason, relink
    case inFolder = "in_folder"
    case included
    case targetLanguage = "target_language"
    case errorDomain = "error_domain"
    case errorCode = "error_code"
}

/// A log property value: an integer, a boolean or a short identifier (never free text).
struct LogValue: Equatable, Codable, Sendable {
    enum Storage: Equatable, Sendable {
        case int(Int)
        case bool(Bool)
        case name(String)
    }

    let storage: Storage

    static let maxNameLength = 64
    static let invalidName = "invalid"

    static func int(_ value: Int) -> LogValue { LogValue(storage: .int(value)) }
    static func bool(_ value: Bool) -> LogValue { LogValue(storage: .bool(value)) }

    /// Identifier made of `[A-Za-z0-9_.-]`, at most 64 characters. Anything else (spaces,
    /// Cyrillic, URLs, emails, …) is replaced with "invalid", so free text cannot slip through.
    static func name(_ value: String) -> LogValue {
        let bytes = value.utf8
        let allowed = (1...maxNameLength).contains(bytes.count) && bytes.allSatisfy(isNameByte)
        return LogValue(storage: .name(allowed ? value : invalidName))
    }

    /// ASCII `[A-Za-z0-9_.-]`; a byte check (no CharacterSet per character on every log call).
    private static func isNameByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "_"), UInt8(ascii: "."), UInt8(ascii: "-"):
            true
        default:
            false
        }
    }

    static func name<T: RawRepresentable>(_ value: T) -> LogValue where T.RawValue == String {
        name(value.rawValue)
    }

    /// Private: values are built only through the checked factories above.
    private init(storage: Storage) {
        self.storage = storage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            storage = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            storage = .int(value)
        } else {
            storage = LogValue.name(try container.decode(String.self)).storage
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch storage {
        case .int(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .name(let value): try container.encode(value)
        }
    }
}

/// Destination for app events. Callers pass only enums and typed values.
@MainActor
protocol AppLogging: AnyObject {
    func log(_ event: LogEvent, level: LogLevel, properties: [LogKey: LogValue])
    /// Sends what is pending, if the destination can; never throws.
    func flush() async
}

extension AppLogging {
    func flush() async {}

    func log(_ event: LogEvent, _ properties: [LogKey: LogValue] = [:]) {
        log(event, level: .info, properties: properties)
    }

    /// Logs only the error's domain and code: messages can contain user text.
    func log(_ event: LogEvent, error: Error, _ properties: [LogKey: LogValue] = [:]) {
        guard !AppLog.isCancellation(error) else { return }
        let nsError = error as NSError
        var merged = properties
        merged[.errorDomain] = .name(nsError.domain)
        merged[.errorCode] = .int(nsError.code)
        log(event, level: .error, properties: merged)
    }

    /// Runs a storage write; on failure logs `storage.failed` with the operation id and rethrows.
    func logged<T>(_ operation: String, _ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch {
            log(.storageFailed, error: error, [.operation: .name(operation)])
            throw error
        }
    }
}

final class NoopAppLogger: AppLogging {
    nonisolated init() {}
    func log(_ event: LogEvent, level: LogLevel, properties: [LogKey: LogValue]) {}
}

/// Logger for code that is not wired through AppResources (static services such as
/// Translator). The app root sets it once; it is a no-op in tests, previews and UI tests.
@MainActor
enum AppLog {
    static var shared: any AppLogging = NoopAppLogger()

    /// Cancellation is not a failure: Swift task cancellation, or URLSession's -999 when a
    /// cancelled task's request is torn down.
    nonisolated static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    nonisolated static func record(_ event: LogEvent, error: Error, _ properties: [LogKey: LogValue] = [:]) async {
        await MainActor.run { shared.log(event, error: error, properties) }
    }
}
