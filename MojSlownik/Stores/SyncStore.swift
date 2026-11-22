import Foundation
import Observation

/// Owns sync triggers, status and linking for the signed-in account. The engine does the work;
/// this store decides when to run it, keeps one cycle at a time, and refreshes dependent stores.
/// Local SwiftData stays the source of truth: a failed cycle only changes the status line.
@MainActor
@Observable
final class SyncStore {
    enum Status: Equatable {
        /// No transport (previews, unit-test host).
        case unavailable
        case signedOut
        case idle
        case syncing
        case synced(Date)
        case failed
        /// The local data is linked to another account: nothing is uploaded until the user confirms.
        case accountMismatch
    }

    /// Why a cycle started; logged by name.
    enum Trigger: String {
        case link, account, change, foreground, manual, leaving, followUp = "follow_up"
    }

    private(set) var status: Status
    /// True once a cycle finished its workspace pull; reset when the account changes (the phase-4
    /// gate waits for it).
    private(set) var workspacePullFinished = false

    @ObservationIgnored private let engine: SyncEngine?
    @ObservationIgnored private let state: any SyncStateRepository
    @ObservationIgnored private let workspaces: WorkspaceStore
    @ObservationIgnored private let folders: FolderLibraryStore
    @ObservationIgnored private let achievements: AchievementStore?
    @ObservationIgnored private let logger: any AppLogging
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let foregroundInterval: TimeInterval
    @ObservationIgnored private let now: () -> Date

    @ObservationIgnored private var account: AuthAccount?
    @ObservationIgnored private var cycleTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var needsFollowUp = false
    @ObservationIgnored private var lastStart: Date?
    @ObservationIgnored private var lastFailure: String?
    /// Called after each successful cycle. Only UI-test wiring sets it (scripted server changes).
    @ObservationIgnored var onCycleSucceeded: (() -> Void)?

    init(engine: SyncEngine?, state: any SyncStateRepository, workspaces: WorkspaceStore,
         folders: FolderLibraryStore, achievements: AchievementStore?, logger: (any AppLogging)?, debounce: Duration = .seconds(5),
         foregroundInterval: TimeInterval = 30, now: @escaping () -> Date = Date.init) {
        self.engine = engine
        self.state = state
        self.workspaces = workspaces
        self.folders = folders
        self.achievements = achievements
        self.logger = logger ?? NoopAppLogger()
        self.debounce = debounce
        self.foregroundInterval = foregroundInterval
        self.now = now
        status = engine == nil ? .unavailable : .signedOut
        // Before the first pulled page is saved: the tracker's re-sync must not announce it.
        engine?.willApplyPulledRows = { [weak self] in self?.achievements?.beginQuietUnlocks() }
        engine?.onWorkspacesPulled = { [weak self] in
            // Pulled workspaces are saved by now: load them before the gate leaves its waiting state.
            try? self?.workspaces.load()
            self?.workspacePullFinished = true
        }
    }

    var isSyncing: Bool { status == .syncing }

    /// A transport exists (false for previews and the unit-test host).
    var isAvailable: Bool { status != .unavailable }
    /// The signed-in account is linked to this iPhone's data, so a cycle runs (or ran) for it.
    var isLinkedToCurrentAccount: Bool {
        switch status {
        case .idle, .syncing, .synced, .failed: account != nil
        case .unavailable, .signedOut, .accountMismatch: false
        }
    }
    var canSyncNow: Bool { canRun && status != .syncing }
    var statusText: String { Self.text(for: status) }

    // MARK: Entry points

    func accountDidChange(_ account: AuthAccount?) {
        self.account = account
        workspacePullFinished = false
        cancelRunning()
        guard engine != nil else {
            status = .unavailable
            return
        }
        guard let account, let engine else {
            status = .signedOut
            return
        }
        let current = state.load()
        if let linked = current.linkedAccountID, linked != account.userID {
            status = .accountMismatch
            logger.log(.syncAccountMismatch)
            return
        }
        status = current.lastSyncedAt.map(Status.synced) ?? .idle
        if current.linkedAccountID == nil {
            do {
                try engine.link(to: account.userID)
                logger.log(.syncLinked, [.relink: .bool(false)])
            } catch {
                fail(error, trigger: .link)
                return
            }
            startCycle(.link)
        } else {
            startCycle(.account)
        }
    }

    /// From the mismatch block, after the user confirmed: links this iPhone's data to the
    /// current account (clean rows follow the account's version) and syncs.
    func confirmLinkToCurrentAccount() {
        guard status == .accountMismatch, let engine, let account else { return }
        do {
            try engine.link(to: account.userID)
            logger.log(.syncLinked, [.relink: .bool(true)])
        } catch {
            fail(error, trigger: .link)
            return
        }
        status = .idle
        startCycle(.link)
    }

    func localDataChanged() {
        guard canRun else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }
            self.debounceTask = nil
            self.startCycle(.change)
        }
    }

    func sceneDidBecomeActive() {
        guard canRun else { return }
        if let lastStart, now().timeIntervalSince(lastStart) < foregroundInterval { return }
        startCycle(.foreground)
    }

    func syncNow() {
        // The first link failed (a local save error): retry it with the same entry point.
        if status == .failed, let account, engine != nil, state.load().linkedAccountID == nil {
            accountDidChange(account)
            return
        }
        guard canRun else { return }
        startCycle(.manual)
    }

    /// Background and sign-out: waits for a running cycle, then runs one more (pull, then push).
    func syncBeforeLeaving() async {
        guard canRun else { return }
        debounceTask?.cancel()
        debounceTask = nil
        await withTaskCancellationHandler {
            if let running = cycleTask { await running.value }
            // Cancelled while waiting (sign-out timeout, background expiry): do not start a new cycle.
            guard !Task.isCancelled, canRun else { return }
            startCycle(.leaving)
            await cycleTask?.value
        } onCancel: {
            Task { @MainActor [weak self] in self?.cycleTask?.cancel() }
        }
    }

    // MARK: Cycles

    private var canRun: Bool {
        guard engine != nil, let account else { return false }
        switch status {
        case .unavailable, .signedOut, .accountMismatch: return false
        default: break
        }
        return state.load().linkedAccountID == account.userID
    }

    private func cancelRunning() {
        debounceTask?.cancel()
        debounceTask = nil
        cycleTask?.cancel()
        cycleTask = nil
        needsFollowUp = false
        generation += 1
    }

    private func startCycle(_ trigger: Trigger) {
        guard canRun else { return }
        lastStart = now()
        if cycleTask != nil {
            needsFollowUp = true
            return
        }
        let mine = generation
        cycleTask = Task { [weak self] in
            await self?.runLoop(trigger, generation: mine)
        }
    }

    private func runLoop(_ first: Trigger, generation mine: Int) async {
        var trigger = first
        repeat {
            needsFollowUp = false
            await runOnce(trigger, generation: mine)
            trigger = .followUp
        } while needsFollowUp && !Task.isCancelled && mine == generation
        if mine == generation { cycleTask = nil }
    }

    private func runOnce(_ trigger: Trigger, generation mine: Int) async {
        guard let engine, let account, mine == generation else { return }
        status = .syncing
        defer { achievements?.endQuietUnlocks(now: now()) }
        do {
            let report = try await engine.run(ownerID: account.userID)
            guard !Task.isCancelled, mine == generation else { return }
            succeeded(report, trigger: trigger)
        } catch {
            guard !Task.isCancelled, mine == generation, !AppLog.isCancellation(error) else {
                if mine == generation { status = restingStatus() }
                return
            }
            fail(error, trigger: trigger)
        }
    }

    private func restingStatus() -> Status {
        state.load().lastSyncedAt.map(Status.synced) ?? .idle
    }

    private func succeeded(_ report: SyncReport, trigger: Trigger) {
        status = .synced(state.load().lastSyncedAt ?? now())
        lastFailure = nil
        // Workspaces first: loading them re-points the folder store at the active workspace.
        if report.workspacesChanged { try? workspaces.load() }
        if report.foldersChanged || report.membershipsChanged { try? folders.load() }
        if report.pulled > 0 || report.pushed > 0 || trigger == .link || trigger == .manual {
            logger.log(.syncCompleted, [.trigger: .name(trigger.rawValue), .pulled: .int(report.pulled),
                                        .pushed: .int(report.pushed)])
        }
        for (reason, count) in report.skipped.sorted(by: { $0.key < $1.key }) {
            logger.log(.syncRowsSkipped, [.reason: .name(reason), .count: .int(count)])
        }
        onCycleSucceeded?()
    }

    private func fail(_ error: Error, trigger: Trigger) {
        status = .failed
        let nsError = error as NSError
        let signature = "\(nsError.domain)#\(nsError.code)"
        guard signature != lastFailure else { return }
        lastFailure = signature
        logger.log(.syncFailed, error: error, [.trigger: .name(trigger.rawValue)])
    }

    // MARK: Copy

    static func text(for status: Status, now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> String {
        switch status {
        case .unavailable: "Синхронизация недоступна"
        case .signedOut: "Войдите, чтобы синхронизировать словарь"
        case .idle: "Ещё не синхронизировано"
        case .syncing: "Синхронизация…"
        case .synced(let date): "Синхронизировано: " + whenText(date, now: now, calendar: calendar)
        case .failed: "Не удалось синхронизировать. Повторим позже."
        case .accountMismatch: "Словарь на этом iPhone связан с другим аккаунтом. Синхронизация выключена."
        }
    }

    /// «сегодня, 12:14», «вчера, 12:14» or «19 нояб., 12:14» (no year).
    static func whenText(_ date: Date, now: Date, calendar: Calendar) -> String {
        let ru = Locale(identifier: "ru_RU")
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: ru,
                                                   calendar: calendar, timeZone: calendar.timeZone))
        if calendar.isDate(date, inSameDayAs: now) { return "сегодня, \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "вчера, \(time)"
        }
        let day = date.formatted(Date.FormatStyle(date: .omitted, time: .omitted, locale: ru, calendar: calendar,
                                                  timeZone: calendar.timeZone).day().month(.abbreviated))
        return "\(day), \(time)"
    }
}
