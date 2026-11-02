import Foundation
import Network

/// Was der Scheduler von der Engine braucht (Tests ersetzen sie).
@MainActor
public protocol SyncRunning: AnyObject {
    var status: SyncStatus { get }
    func syncNow() async
}

/// Warten, austauschbar für Tests. Muss bei Task-Abbruch werfen.
@MainActor
public protocol Sleeper {
    func sleep(seconds: Double) async throws
}

public struct TaskSleeper: Sleeper {
    public init() {}

    public func sleep(seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}

/// Meldet, ob ein Netzweg verfügbar ist (`true` = verbunden).
@MainActor
public protocol NetworkStatusProviding: AnyObject {
    func start(_ onChange: @escaping @MainActor @Sendable (Bool) -> Void)
    func stop()
}

/// `NWPathMonitor` auf der Main-Queue (Meldungen kommen in Reihenfolge auf dem MainActor an).
public final class NWPathNetworkStatus: NetworkStatusProviding {
    private var monitor: NWPathMonitor?

    public init() {}

    public func start(_ onChange: @escaping @MainActor @Sendable (Bool) -> Void) {
        stop()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let satisfied = path.status == .satisfied
            MainActor.assumeIsolated { onChange(satisfied) }
        }
        monitor.start(queue: .main)
        self.monitor = monitor
    }

    public func stop() {
        monitor?.cancel()
        monitor = nil
    }
}

/// Löst Syncs aus (Spec §4 „Auslöser“): App-Start, Vordergrund, 2 s nach der letzten lokalen
/// Änderung, Netz wieder da, Pull-to-Refresh. Nach Fehlschlägen (offline/Fehler) erneuter Versuch
/// nach 5 s · 2ⁿ, höchstens 300 s; ein Erfolg setzt den Backoff zurück.
@MainActor
public final class SyncScheduler {
    public static let debounceSeconds = 2.0
    public static let initialBackoffSeconds = 5.0
    public static let maxBackoffSeconds = 300.0

    private let engine: any SyncRunning
    private let sleeper: any Sleeper
    private let pathMonitor: any NetworkStatusProviding

    private var debounceTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var failures = 0
    private var networkSatisfied: Bool?
    private var started = false

    public init(engine: any SyncRunning, sleeper: any Sleeper = TaskSleeper(),
                pathMonitor: any NetworkStatusProviding = NWPathNetworkStatus()) {
        self.engine = engine
        self.sleeper = sleeper
        self.pathMonitor = pathMonitor
    }

    /// App-Start: Netz beobachten und sofort synchronisieren.
    public func start() {
        guard !started else { return }
        started = true
        pathMonitor.start { [weak self] satisfied in
            self?.networkChanged(satisfied)
        }
        trigger()
    }

    /// Beendet Beobachtung und wartende Versuche (z. B. beim Abmelden).
    public func stop() {
        started = false
        pathMonitor.stop()
        networkSatisfied = nil
        debounceTask?.cancel()
        debounceTask = nil
        retryTask?.cancel()
        retryTask = nil
    }

    public func appDidBecomeActive() {
        trigger()
    }

    /// Nach jeder lokalen Änderung; synchronisiert 2 s nach der letzten.
    public func localChange() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            do { try await self.sleeper.sleep(seconds: Self.debounceSeconds) } catch { return }
            guard !Task.isCancelled else { return }
            self.debounceTask = nil
            await self.runSync()
        }
    }

    public func pullToRefresh() async {
        await runSync()
    }

    // MARK: Intern

    private func trigger() {
        Task { await self.runSync() }
    }

    private func networkChanged(_ satisfied: Bool) {
        let wasOffline = networkSatisfied == false
        networkSatisfied = satisfied
        guard satisfied, wasOffline else { return }
        // Wartenden Backoff-Versuch verwerfen und sofort synchronisieren.
        retryTask?.cancel()
        retryTask = nil
        trigger()
    }

    private func runSync() async {
        await engine.syncNow()
        switch engine.status {
        case .upToDate:
            failures = 0
            retryTask?.cancel()
            retryTask = nil
        case .offline, .error:
            failures += 1
            scheduleRetry()
        case .idle, .syncing:
            // Abgemeldet oder abgebrochen: kein automatischer Wiederholversuch.
            break
        }
    }

    private func scheduleRetry() {
        let delay = min(Self.initialBackoffSeconds * pow(2, Double(min(failures, 32) - 1)), Self.maxBackoffSeconds)
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            guard let self else { return }
            do { try await self.sleeper.sleep(seconds: delay) } catch { return }
            guard !Task.isCancelled else { return }
            self.retryTask = nil
            await self.runSync()
        }
    }
}
