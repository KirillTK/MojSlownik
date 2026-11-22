import Foundation

/// One row of public.app_logs (snake_case columns). `user_id` is filled by the database.
struct AppLogRow: Codable, Equatable, Sendable {
    let occurredAt: Date
    let sessionID: UUID
    let level: LogLevel
    let event: LogEvent
    let properties: [String: LogValue]
    let appVersion: String
    let osVersion: String

    enum CodingKeys: String, CodingKey {
        case level, event, properties
        case occurredAt = "occurred_at"
        case sessionID = "session_id"
        case appVersion = "app_version"
        case osVersion = "os_version"
    }
}

/// The server refused the rows for good (constraint, RLS, bad request); retrying cannot help.
struct AppLogRejectedError: Error, Equatable {}

/// Sends rows to the server. Implemented by Backend/SupabaseLogUploader.swift.
/// Throws `AppLogRejectedError` for permanent rejections; anything else is retried later.
@MainActor
protocol AppLogUploading: AnyObject {
    func upload(_ rows: [AppLogRow]) async throws
}

/// Buffers log rows on disk and uploads them in batches while the user is signed in
/// (RLS lets only signed-in users insert their own rows). Without a session rows wait,
/// capped at `maxStoredRows` (oldest dropped first). Logging never throws or blocks the UI.
///
/// Attribution: each row remembers the account that was signed in when it was logged.
/// Rows of another account are never uploaded under the current one; rows logged while
/// signed out are device diagnostics and go out with the next signed-in account.
@MainActor
final class AppLogQueue: AppLogging {
    struct Entry: Codable, Equatable, Sendable {
        let id: UUID
        let row: AppLogRow
        /// Signed-in account at logging time; nil while signed out.
        var accountID: UUID?
    }

    static let maxStoredRows = 500
    static let batchSize = 50
    static let flushThreshold = 20
    /// After a transient failure, automatic (threshold) flushes pause this long.
    static let retryBackoff: TimeInterval = 60

    private(set) var pending: [Entry]
    var uploader: (any AppLogUploading)?
    /// The signed-in account, if any; set by the app root once auth is wired.
    var currentAccountID: () -> UUID? = { nil }

    private let fileURL: URL?
    private let sessionID: UUID
    private let appVersion: String
    private let osVersion: String
    private let now: () -> Date
    private let persistDelay: Duration
    private let write: (Data, URL) throws -> Void
    /// The running upload loop; later `flush()` calls wait for it, then drain what is left.
    private var flushTask: Task<Void, Never>?
    /// An automatic flush is spawned but has not started yet (`flushTask` is still nil).
    private var isAutoFlushScheduled = false
    /// Callers waiting for `flushTask` to end; resumed when it ends or when the caller is cancelled.
    private var flushWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    /// Set when `pending` changed since the last successful write.
    private var isDirty = false
    private var autoFlushAllowedAfter: Date = .distantPast
    private var persistTask: Task<Void, Never>?

    init(fileURL: URL?, sessionID: UUID = UUID(),
         appVersion: String = AppLogQueue.currentAppVersion,
         osVersion: String = AppLogQueue.currentOSVersion,
         now: @escaping () -> Date = Date.init,
         persistDelay: Duration = .seconds(1),
         write: @escaping (Data, URL) throws -> Void = AppLogQueue.writeProtected) {
        self.fileURL = fileURL
        self.sessionID = sessionID
        self.appVersion = Self.sanitizedVersion(appVersion)
        self.osVersion = Self.sanitizedVersion(osVersion)
        self.now = now
        self.persistDelay = persistDelay
        self.write = write
        pending = Self.load(from: fileURL)
    }

    func log(_ event: LogEvent, level: LogLevel, properties: [LogKey: LogValue]) {
        let row = AppLogRow(occurredAt: now(), sessionID: sessionID, level: level, event: event,
                            properties: Dictionary(uniqueKeysWithValues: properties.map { ($0.key.rawValue, $0.value) }),
                            appVersion: appVersion, osVersion: osVersion)
        let account = currentAccountID()
        pending.append(Entry(id: UUID(), row: row, accountID: account))
        if pending.count > Self.maxStoredRows {
            pending.removeFirst(pending.count - Self.maxStoredRows)
        }
        isDirty = true
        schedulePersist()
        if shouldAutoFlush(for: account) {
            isAutoFlushScheduled = true
            Task {
                isAutoFlushScheduled = false
                await flush()
            }
        }
    }

    /// One automatic flush at a time, only with enough rows this account may upload, and not
    /// right after a failure (offline): logging never turns into a request per event.
    /// Cheap checks first; the scan runs only when a flush is otherwise due.
    private func shouldAutoFlush(for account: UUID?) -> Bool {
        guard let account, uploader != nil, flushTask == nil, !isAutoFlushScheduled,
              pending.count >= Self.flushThreshold,
              now() >= autoFlushAllowedAfter else { return false }
        let uploadable = pending.lazy.filter { $0.accountID == nil || $0.accountID == account }.count
        return uploadable >= Self.flushThreshold
    }

    /// Persists, then uploads everything this account may send. A call made while another flush
    /// runs waits for it and then drains rows logged since (backgrounding and sign-out must not
    /// return early while their rows are still unsent). Cancelling the caller cancels the upload.
    func flush() async {
        // Write first, even if another flush is running: the app may be suspended or killed
        // during the network round trip.
        persistNow()
        while flushTask != nil {
            await waitForRunningFlush()
            if Task.isCancelled { return }
        }
        guard let uploader else { return }
        let task = Task { [weak self] in
            await self?.drain(with: uploader)
            self?.finishFlush()
        }
        flushTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    /// Unlike `await task.value`, returns as soon as the caller is cancelled (sign-out's timeout
    /// must not be held up by another, uncancelled flush still uploading).
    private func waitForRunningFlush() async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if flushTask == nil || Task.isCancelled {
                    continuation.resume()
                } else {
                    flushWaiters[id] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor in self.flushWaiters.removeValue(forKey: id)?.resume() }
        }
    }

    private func finishFlush() {
        flushTask = nil
        persistNow()
        let waiters = flushWaiters.values
        flushWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func drain(with uploader: any AppLogUploading) async {
        while !Task.isCancelled, let account = currentAccountID() {
            let batch = Array(pending.lazy.filter { $0.accountID == nil || $0.accountID == account }
                .prefix(Self.batchSize))
            guard !batch.isEmpty else { return }
            do {
                try await uploader.upload(batch.map(\.row))
                remove(batch)
            } catch is AppLogRejectedError {
                // Isolate the bad rows instead of blocking the queue behind them.
                guard await uploadIndividually(batch, with: uploader) else {
                    backOffUnlessCancelled()
                    return
                }
            } catch {
                // Transient (network, expired token): keep the rows for the next flush.
                backOffUnlessCancelled()
                return
            }
        }
    }

    /// A cancelled flush (sign-out timeout, background expiry) is not a network failure.
    private func backOffUnlessCancelled() {
        guard !Task.isCancelled else { return }
        autoFlushAllowedAfter = now().addingTimeInterval(Self.retryBackoff)
    }

    /// Uploads rows one by one, dropping only those the server rejects. False on a transient error.
    private func uploadIndividually(_ batch: [Entry], with uploader: any AppLogUploading) async -> Bool {
        for entry in batch {
            do {
                try await uploader.upload([entry.row])
                remove([entry])
            } catch is AppLogRejectedError {
                remove([entry])
            } catch {
                return false
            }
        }
        return true
    }

    private func remove(_ entries: [Entry]) {
        let ids = Set(entries.map(\.id))
        pending.removeAll { ids.contains($0.id) }
        isDirty = true
    }

    // MARK: Storage

    /// Coalesces bursts of logging into one write per `persistDelay`.
    private func schedulePersist() {
        guard fileURL != nil, persistTask == nil else { return }
        persistTask = Task { [weak self, persistDelay] in
            // Cancelled means persistNow already ran; writing here would also cancel a newer task.
            guard (try? await Task.sleep(for: persistDelay)) != nil else { return }
            self?.persistNow()
        }
    }

    /// Writes the queue immediately if it changed (flush, app backgrounding, tests).
    /// A failed write stays dirty and is retried by the next persist.
    func persistNow() {
        persistTask?.cancel()
        persistTask = nil
        guard isDirty, let fileURL, let data = try? JSONEncoder().encode(pending) else { return }
        do {
            try write(data, fileURL)
            isDirty = false
        } catch {}
    }

    nonisolated static func writeProtected(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Application Support/Logs/app-log-queue.json, excluded from backups.
    static func defaultFileURL(fileManager: FileManager = .default) -> URL? {
        guard let support = try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true) else { return nil }
        var directory = support.appendingPathComponent("Logs", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        return directory.appendingPathComponent("app-log-queue.json")
    }

    /// Decodes entry by entry: one unreadable row (say, an event removed in a later version)
    /// drops only itself, not the whole queue.
    private static func load(from url: URL?) -> [Entry] {
        guard let url, let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([LossyEntry].self, from: data) else { return [] }
        return Array(entries.compactMap(\.entry).suffix(maxStoredRows))
    }

    private struct LossyEntry: Decodable {
        let entry: Entry?

        init(from decoder: any Decoder) throws {
            entry = try? Entry(from: decoder)
        }
    }

    // MARK: Versions

    nonisolated static var currentAppVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    nonisolated static var currentOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// Mirrors the server CHECK on app_version/os_version.
    nonisolated static func sanitizedVersion(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz.()_ -")
        guard (1...32).contains(value.count), value.unicodeScalars.allSatisfy(allowed.contains) else {
            return "unknown"
        }
        return value
    }
}
