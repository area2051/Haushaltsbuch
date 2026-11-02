import Foundation
import SwiftData
import Synchronization
import HaushaltsbuchAPI
import HaushaltsbuchCore
@testable import HaushaltsbuchData

typealias SyncRequest = Components.Schemas.SyncRequest
typealias SyncResponse = Components.Schemas.SyncResponse
typealias SyncChanges = Components.Schemas.SyncChanges

/// Fake-`SyncTransport`: schneidet Requests mit, zählt gleichzeitige Requests und delegiert die
/// Antwort an einen (auf dem MainActor laufenden) Handler.
final class FakeSyncTransport: SyncTransport {
    typealias Handler = @MainActor @Sendable (SyncRequest) async throws -> SyncResponse

    private struct State {
        var requests: [SyncRequest] = []
        var inFlight = 0
        var maxInFlight = 0
        var handler: Handler?
    }

    private let state = Mutex(State())

    var requests: [SyncRequest] { state.withLock { $0.requests } }
    var maxInFlight: Int { state.withLock { $0.maxInFlight } }

    func handle(_ handler: @escaping Handler) {
        state.withLock { $0.handler = handler }
    }

    func sync(_ request: SyncRequest) async throws -> SyncResponse {
        let handler = state.withLock { s -> Handler? in
            s.requests.append(request)
            s.inFlight += 1
            s.maxInFlight = max(s.maxInFlight, s.inFlight)
            return s.handler
        }
        defer { state.withLock { $0.inFlight -= 1 } }
        guard let handler else { fatalError("FakeSyncTransport: kein Handler") }
        return try await handler(request)
    }
}

/// Simulierter Server: bestätigt jeden gepushten Datensatz mit neuer Version (wie der echte Server
/// „auch die gerade geschriebenen“ zurückgibt) und hängt konfigurierbare Fremdänderungen an.
@MainActor
final class ServerSim {
    var currentVersion = 0
    var extra = SyncChanges(budgets: [], categories: [], recurringRules: [], transactions: [], users: [])
    var rejected: [Components.Schemas.RejectedRecord] = []
    var fullResync = false
    /// IDs (lowercase), die der Server nicht zurückmeldet.
    var drop: Set<String> = []

    func handle(_ req: SyncRequest) -> SyncResponse {
        var out = extra
        let rejectedKeys = Set(rejected.compactMap { r in r.id.map { "\(r.table)/\($0)" } })
        let keep: (String, String) -> Bool = { table, id in
            !rejectedKeys.contains("\(table)/\(id)") && !self.drop.contains(id)
        }
        for r in req.changes.categories ?? [] where keep("categories", r.id) {
            currentVersion += 1
            out.categories.append(.init(archived: r.archived, color: r.color, deleted: r.deleted, icon: r.icon,
                                        id: r.id, kind: .init(rawValue: r.kind.rawValue)!, name: r.name,
                                        sortOrder: r.sortOrder, version: currentVersion))
        }
        for r in req.changes.recurringRules ?? [] where keep("recurringRules", r.id) {
            currentVersion += 1
            out.recurringRules.append(.init(amountCents: r.amountCents, categoryId: r.categoryId, deleted: r.deleted,
                                            endDate: r.endDate, frequency: .init(rawValue: r.frequency.rawValue)!,
                                            id: r.id, kind: .init(rawValue: r.kind.rawValue)!,
                                            nextDueDate: r.startDate, note: r.note, paidBy: r.paidBy,
                                            startDate: r.startDate, version: currentVersion))
        }
        for r in req.changes.transactions ?? [] where keep("transactions", r.id) {
            currentVersion += 1
            out.transactions.append(.init(amountCents: r.amountCents, categoryId: r.categoryId, date: r.date,
                                          deleted: r.deleted, id: r.id, kind: .init(rawValue: r.kind.rawValue)!,
                                          note: r.note, paidBy: r.paidBy, recurringRuleId: r.recurringRuleId,
                                          version: currentVersion))
        }
        for r in req.changes.budgets ?? [] where keep("budgets", r.id) {
            currentVersion += 1
            out.budgets.append(.init(categoryId: r.categoryId, deleted: r.deleted, id: r.id,
                                     monthlyLimitCents: r.monthlyLimitCents, version: currentVersion))
        }
        currentVersion = max(currentVersion, extraMaxVersion)
        return SyncResponse(changes: out, currentVersion: currentVersion, fullResync: fullResync, rejected: rejected)
    }

    private var extraMaxVersion: Int {
        (extra.categories.map(\.version) + extra.transactions.map(\.version) + extra.budgets.map(\.version)
            + extra.recurringRules.map(\.version) + extra.users.map(\.version)).max() ?? 0
    }
}

@MainActor
final class SyncFixture {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    let container: ModelContainer
    let context: ModelContext
    private(set) lazy var repo = Repository(context: context, onRefetchNeeded: { [unowned self] in
        self.refetchRequests += 1
        self.engine.requestRefetch()
    })
    /// Aufrufe von `onRefetchNeeded` (Verwerfen einer abgelehnten synchronisierten Änderung).
    private(set) var refetchRequests = 0
    let transport = FakeSyncTransport()
    let server = ServerSim()
    let cursor: InMemoryCursorStore
    let engine: SyncEngine
    let user = UUID()
    let day = CalendarDay(year: 2026, month: 11, day: 1)!

    init(lastVersion: Int = 0, batchSize: Int = 500) throws {
        container = try ModelContainer.makeAppContainer(inMemory: true)
        context = container.mainContext
        cursor = InMemoryCursorStore(lastVersion: lastVersion)
        engine = SyncEngine(context: context, transport: transport, cursor: cursor,
                            batchSize: batchSize, now: { SyncFixture.now })
        let server = self.server
        transport.handle { req in server.handle(req) }
    }

    func makeCategory(_ name: String = "Essen") throws -> CategoryEntity {
        try repo.saveCategory(CategoryDraft(name: name, icon: "cart", color: "#112233", kind: .expense))
    }

    @discardableResult
    func addTx(category: UUID, amount: Int = 1250) throws -> TransactionEntity {
        try repo.addTransaction(amountCents: amount, kind: .expense, categoryId: category, day: day,
                                paidBy: user, note: "Brot")
    }

    func all<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }
}

/// Wartet (kooperativ) bis `condition` gilt; bricht nach ~2 s ab.
@MainActor
func waitUntil(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<2000 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
}

/// Lässt einen Fake-Request hängen, bis `open()` gerufen wird (oder die Task abgebrochen wird).
@MainActor
final class Latch {
    private var continuations: [CheckedContinuation<Void, any Error>] = []
    private(set) var isOpen = false
    private(set) var arrivals = 0

    func wait() async throws {
        arrivals += 1
        if isOpen { return }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuations.append($0) }
        } onCancel: {
            Task { @MainActor in self.cancelAll() }
        }
    }

    func open() {
        isOpen = true
        let all = continuations
        continuations = []
        all.forEach { $0.resume() }
    }

    private func cancelAll() {
        let all = continuations
        continuations = []
        all.forEach { $0.resume(throwing: CancellationError()) }
    }
}
