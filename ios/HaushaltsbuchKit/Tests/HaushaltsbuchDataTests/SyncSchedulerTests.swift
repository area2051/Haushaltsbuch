import Foundation
import Testing
@testable import HaushaltsbuchData

/// Engine-Attrappe: zählt Syncs und setzt danach den vorgegebenen Status.
@MainActor
final class FakeEngine: SyncRunning {
    private(set) var status: SyncStatus = .idle
    private(set) var syncCount = 0
    var nextStatus: SyncStatus = .upToDate(Date(timeIntervalSince1970: 0))

    func syncNow() async {
        syncCount += 1
        status = nextStatus
    }
}

/// Steuerbarer Sleeper: jeder Aufruf wartet, bis der Test ihn freigibt; Abbruch wirft.
@MainActor
final class FakeSleeper: Sleeper {
    private(set) var requested: [Double] = []
    private var pending: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var nextID = 0

    var pendingCount: Int { pending.count }

    func sleep(seconds: Double) async throws {
        requested.append(seconds)
        let id = nextID
        nextID += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending[id] = $0 }
        } onCancel: {
            Task { @MainActor in self.finish(id, throwing: CancellationError()) }
        }
    }

    func resumeAll() {
        for id in pending.keys { finish(id, throwing: nil) }
    }

    private func finish(_ id: Int, throwing error: (any Error)?) {
        guard let c = pending.removeValue(forKey: id) else { return }
        if let error { c.resume(throwing: error) } else { c.resume() }
    }
}

@MainActor
final class FakeNetwork: NetworkStatusProviding {
    private var handler: (@MainActor @Sendable (Bool) -> Void)?
    private(set) var started = false

    func start(_ onChange: @escaping @MainActor @Sendable (Bool) -> Void) {
        started = true
        handler = onChange
    }

    func stop() { handler = nil }

    func emit(_ satisfied: Bool) { handler?(satisfied) }
}

@MainActor
private struct SchedulerFixture {
    let engine = FakeEngine()
    let sleeper = FakeSleeper()
    let network = FakeNetwork()
    let scheduler: SyncScheduler

    init() {
        scheduler = SyncScheduler(engine: engine, sleeper: sleeper, pathMonitor: network)
    }
}

@MainActor @Test func schedulerDebouncesLocalChanges() async throws {
    let f = SchedulerFixture()

    f.scheduler.localChange()
    f.scheduler.localChange()
    f.scheduler.localChange()
    await waitUntil { f.sleeper.requested.count == 3 && f.sleeper.pendingCount == 1 }
    #expect(f.sleeper.requested == [2, 2, 2])
    #expect(f.sleeper.pendingCount == 1)  // die ersten beiden wurden abgebrochen
    #expect(f.engine.syncCount == 0)

    f.sleeper.resumeAll()
    await waitUntil { f.engine.syncCount == 1 }
    for _ in 0..<20 { await Task.yield() }
    #expect(f.engine.syncCount == 1)
}

@MainActor @Test func schedulerBacksOffUpTo300Seconds() async throws {
    let f = SchedulerFixture()
    f.engine.nextStatus = .offline(pending: 1)

    await f.scheduler.pullToRefresh()
    for attempt in 1...8 {
        await waitUntil { f.sleeper.pendingCount == 1 }
        #expect(f.engine.syncCount == attempt)
        f.sleeper.resumeAll()
        await waitUntil { f.engine.syncCount == attempt + 1 }
    }
    await waitUntil { f.sleeper.pendingCount == 1 }
    #expect(f.sleeper.requested == [5, 10, 20, 40, 80, 160, 300, 300, 300])

    // Erfolg setzt den Backoff zurück.
    f.engine.nextStatus = .upToDate(Date())
    f.sleeper.resumeAll()
    await waitUntil { f.engine.syncCount == 10 }
    for _ in 0..<20 { await Task.yield() }
    #expect(f.sleeper.pendingCount == 0)

    f.engine.nextStatus = .error("x", pending: 1)
    await f.scheduler.pullToRefresh()
    await waitUntil { f.sleeper.pendingCount == 1 }
    #expect(f.sleeper.requested.last == 5)
}

@MainActor @Test func schedulerSyncsWhenNetworkReturns() async throws {
    let f = SchedulerFixture()
    f.engine.nextStatus = .offline(pending: 1)
    f.scheduler.start()
    #expect(f.network.started)
    await waitUntil { f.engine.syncCount == 1 && f.sleeper.pendingCount == 1 }
    #expect(f.engine.syncCount == 1)
    f.network.emit(false)
    for _ in 0..<20 { await Task.yield() }
    #expect(f.engine.syncCount == 1)

    f.engine.nextStatus = .upToDate(Date())
    f.network.emit(true)
    await waitUntil { f.engine.syncCount == 2 }
    #expect(f.engine.syncCount == 2)
    // Der wartende Backoff-Versuch wurde verworfen.
    await waitUntil { f.sleeper.pendingCount == 0 }
    #expect(f.sleeper.pendingCount == 0)

    // Wiederholtes „verbunden“ ohne Unterbrechung löst nichts aus.
    f.network.emit(true)
    for _ in 0..<20 { await Task.yield() }
    #expect(f.engine.syncCount == 2)
}

@MainActor @Test func schedulerSyncsOnStartAndForeground() async throws {
    let f = SchedulerFixture()
    f.scheduler.start()
    f.network.emit(true)  // erste Meldung „verbunden“ ist kein „wieder da“
    await waitUntil { f.engine.syncCount == 1 }
    for _ in 0..<20 { await Task.yield() }
    #expect(f.engine.syncCount == 1)
    f.scheduler.appDidBecomeActive()
    await waitUntil { f.engine.syncCount == 2 }
    #expect(f.engine.syncCount == 2)
}
