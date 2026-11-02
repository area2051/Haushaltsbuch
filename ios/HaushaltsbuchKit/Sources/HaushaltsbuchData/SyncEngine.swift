import Combine
import Foundation
import os
import SwiftData
import HaushaltsbuchAPI

private let logger = Logger(subsystem: "de.haushaltsbuch.app", category: "sync")

// MARK: Transport

/// Ein `POST /sync`. Fehler kommen als `APIError`.
public protocol SyncTransport: Sendable {
    func sync(_ request: Components.Schemas.SyncRequest) async throws -> Components.Schemas.SyncResponse
}

/// `SyncTransport` über den generierten (authentifizierten) Client.
public struct ClientSyncTransport: SyncTransport {
    private let client: Client

    public init(client: Client) {
        self.client = client
    }

    public func sync(_ request: Components.Schemas.SyncRequest) async throws -> Components.Schemas.SyncResponse {
        let output: Operations.sync.Output
        do {
            output = try await client.sync(body: .json(request))
        } catch {
            throw APIError(error)
        }
        switch output {
        case let .ok(ok):
            do { return try ok.body.json } catch { throw APIError(error) }
        case .unauthorized:
            throw APIError.unauthorized
        case let .badRequest(r):
            throw (try? APIError(r.body.json)) ?? APIError.undocumented(400)
        case let .contentTooLarge(r):
            throw (try? APIError(r.body.json)) ?? APIError.undocumented(413)
        case let .internalServerError(r):
            throw (try? APIError(r.body.json)) ?? APIError.undocumented(500)
        case let .undocumented(statusCode, _):
            throw APIError.undocumented(statusCode)
        }
    }
}

// MARK: Cursor

/// Letzte vom Server übernommene Version (`lastVersion` des nächsten Requests).
public protocol SyncCursorStore {
    var lastVersion: Int { get set }
}

/// Cursor in den UserDefaults; der Schlüssel enthält Server-URL und Benutzer, damit ein Wechsel
/// von Server oder Konto nie einen fremden Cursor weiterverwendet.
public struct UserDefaultsCursorStore: SyncCursorStore {
    public let key: String
    private let defaults: UserDefaults

    public init(key: String, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    public init(serverURL: URL, userId: UUID, defaults: UserDefaults = .standard) {
        self.init(key: Self.key(serverURL: serverURL, userId: userId), defaults: defaults)
    }

    public static func key(serverURL: URL, userId: UUID) -> String {
        "sync.lastVersion.\(serverURL.absoluteString).\(userId.uuidString.lowercased())"
    }

    public var lastVersion: Int {
        get { defaults.integer(forKey: key) }
        nonmutating set { defaults.set(newValue, forKey: key) }
    }
}

/// Flüchtiger Cursor für Tests und Vorschauen.
public final class InMemoryCursorStore: SyncCursorStore {
    public var lastVersion: Int

    public init(lastVersion: Int = 0) {
        self.lastVersion = lastVersion
    }
}

// MARK: Status

public enum SyncStatus: Equatable, Sendable {
    case idle
    case syncing
    case offline(pending: Int)
    case error(String, pending: Int)
    case upToDate(Date)
}

// MARK: Engine

/// Gleicht SwiftData mit dem Server über `POST /sync` ab (Spec §4, Client-Teil).
///
/// Ablauf eines Durchlaufs (`syncNow`):
/// 1. Snapshot der dirty Datensätze (Kategorien → Regeln → Buchungen → gelöschte Budgets → übrige
///    Budgets → gelöschte Kategorien), je Datensatz `id → dirtyGeneration`, höchstens `batchSize`.
/// 2. `POST /sync` mit `lastVersion` und dem Paket.
/// 3. Antwort anwenden: lokal dirty und seit dem Snapshot erneut geändert (oder nicht gesendet) → nicht
///    überschreiben; sonst Server-Stand übernehmen und `isDirty = false`. Unbekannte anlegen,
///    `users` → `MemberEntity`.
/// 4. `rejected` → `rejectionReason`, `isDirty = false` (lokaler Inhalt bleibt zum Bearbeiten).
/// 5. `fullResync` → nicht dirty, nicht abgelehnte und nicht in der Antwort enthaltene Datensätze
///    hart löschen.
/// 6. Speichern, dann `lastVersion = currentVersion`. War das Paket voll, folgt das nächste.
@MainActor
public final class SyncEngine: ObservableObject, SyncRunning {
    public static let defaultBatchSize = 500

    @Published public private(set) var status: SyncStatus = .idle

    private let context: ModelContext
    private let transport: any SyncTransport
    private var cursor: any SyncCursorStore
    private let batchSize: Int
    private let now: @MainActor () -> Date

    private var isRunning = false
    private var rerunRequested = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(context: ModelContext, transport: any SyncTransport, cursor: any SyncCursorStore,
                batchSize: Int = SyncEngine.defaultBatchSize, now: @escaping @MainActor () -> Date = { Date() }) {
        self.context = context
        self.transport = transport
        self.cursor = cursor
        self.batchSize = max(1, batchSize)
        self.now = now
    }

    /// Anzahl noch nicht übertragener Änderungen (abgelehnte zählen nicht).
    public var pendingCount: Int {
        let counts = try? [
            context.fetchCount(CategoryEntity.dirtyFetch),
            context.fetchCount(RecurringRuleEntity.dirtyFetch),
            context.fetchCount(TransactionEntity.dirtyFetch),
            context.fetchCount(BudgetEntity.dirtyFetch),
        ]
        return counts?.reduce(0, +) ?? 0
    }

    /// Synchronisiert jetzt. Läuft bereits ein Sync, wird kein zweiter gestartet: der Aufruf merkt
    /// einen Nachlauf vor und kehrt zurück, wenn der laufende Sync (inkl. Nachlauf) fertig ist.
    public func syncNow() async {
        if isRunning {
            rerunRequested = true
            await withCheckedContinuation { waiters.append($0) }
            return
        }
        isRunning = true
        repeat {
            rerunRequested = false
            await runOnce()
        } while rerunRequested && !Task.isCancelled
        isRunning = false
        let done = waiters
        waiters = []
        done.forEach { $0.resume() }
    }

    // MARK: Ablauf

    private func runOnce() async {
        let previous = status
        status = .syncing
        do {
            try await pushAndPull()
            status = .upToDate(now())
        } catch {
            let apiError = APIError(error)
            if apiError == .cancelled || Task.isCancelled {
                // Abbruch ist kein Fehler: still aufhören.
                status = previous
                return
            }
            switch apiError {
            case .unreachable:
                status = .offline(pending: pendingCount)
            case .unauthorized:
                // AuthService hat die Sitzung verworfen und zeigt die Anmeldung.
                status = .idle
            default:
                logger.error("Sync fehlgeschlagen: \(String(describing: apiError), privacy: .public)")
                status = .error(apiError.germanMessage, pending: pendingCount)
            }
        }
    }

    private func pushAndPull() async throws {
        // In diesem Durchlauf schon gesendete Stände; unbestätigte werden nicht erneut gepusht.
        var sent: [SyncTable: [UUID: Int]] = [:]
        var first = true
        while true {
            try Task.checkCancellation()
            let batch = try makeBatch(excluding: sent)
            if !first && batch.count == 0 { return }
            first = false
            for (table, generations) in batch.generations {
                sent[table, default: [:]].merge(generations) { $1 }
            }

            let request = Components.Schemas.SyncRequest(changes: batch.changes, lastVersion: cursor.lastVersion)
            let response = try await transport.sync(request)
            try apply(response, sent: batch.generations)
            cursor.lastVersion = response.currentVersion

            // Nicht volles Paket: alles gesendet. Während des Requests Geändertes überträgt der
            // nächste Sync (Repository → Scheduler.localChange).
            if batch.count < batchSize { return }
        }
    }

    // MARK: Snapshot

    private struct Batch {
        var changes = Components.Schemas.SyncRequest.changesPayload()
        var generations: [SyncTable: [UUID: Int]] = [:]
        var count = 0
    }

    private enum Pending {
        case category(CategoryEntity)
        case rule(RecurringRuleEntity)
        case transaction(TransactionEntity)
        case budget(BudgetEntity)
    }

    private func makeBatch(excluding sent: [SyncTable: [UUID: Int]]) throws -> Batch {
        let categories = try dirty(CategoryEntity.self, excluding: sent)
        let budgets = try dirty(BudgetEntity.self, excluding: sent)
        // Gelöschte Budgets vor neuen (partieller Unique-Index je Kategorie auf dem Server);
        // gelöschte Kategorien zuletzt, damit sie auch über Paketgrenzen hinweg nach dem Löschen
        // ihrer Buchungen/Regeln ankommen (sonst `category_in_use`).
        let ordered: [Pending] =
            categories.filter { !$0.deleted }.map(Pending.category)
            + (try dirty(RecurringRuleEntity.self, excluding: sent)).map(Pending.rule)
            + (try dirty(TransactionEntity.self, excluding: sent)).map(Pending.transaction)
            + budgets.filter(\.deleted).map(Pending.budget)
            + budgets.filter { !$0.deleted }.map(Pending.budget)
            + categories.filter(\.deleted).map(Pending.category)

        var batch = Batch()
        var cats: [Components.Schemas.CategoryRecord] = []
        var rules: [Components.Schemas.RecurringRuleRecord] = []
        var txs: [Components.Schemas.TransactionRecord] = []
        var buds: [Components.Schemas.BudgetRecord] = []
        for item in ordered.prefix(batchSize) {
            switch item {
            case let .category(e):
                cats.append(e.syncRecord)
                batch.generations[.categories, default: [:]][e.id] = e.dirtyGeneration
            case let .rule(e):
                rules.append(e.syncRecord)
                batch.generations[.recurringRules, default: [:]][e.id] = e.dirtyGeneration
            case let .transaction(e):
                txs.append(e.syncRecord)
                batch.generations[.transactions, default: [:]][e.id] = e.dirtyGeneration
            case let .budget(e):
                buds.append(e.syncRecord)
                batch.generations[.budgets, default: [:]][e.id] = e.dirtyGeneration
            }
            batch.count += 1
        }
        batch.changes = .init(budgets: buds.isEmpty ? nil : buds, categories: cats.isEmpty ? nil : cats,
                              recurringRules: rules.isEmpty ? nil : rules, transactions: txs.isEmpty ? nil : txs)
        return batch
    }

    private func dirty<E: SyncEntity>(_ type: E.Type, excluding sent: [SyncTable: [UUID: Int]]) throws -> [E] {
        let already = sent[E.table] ?? [:]
        return try context.fetch(E.dirtyFetch).filter { already[$0.id] != $0.dirtyGeneration }
    }

    // MARK: Antwort anwenden

    private func apply(_ response: Components.Schemas.SyncResponse, sent: [SyncTable: [UUID: Int]]) throws {
        var rejected: [SyncTable: [UUID: String]] = [:]
        for r in response.rejected {
            // Passt nicht zu einem lokalen Datensatz (unbekannte Tabelle, fehlende/kaputte ID) → ignorieren.
            guard let table = SyncTable(rawValue: r.table), let raw = r.id, let id = UUID(uuidString: raw) else {
                logger.notice("Abgelehnt ohne Zuordnung: \(r.table, privacy: .public) \(r.id ?? "nil", privacy: .public): \(r.reason, privacy: .public)")
                continue
            }
            rejected[table, default: [:]][id] = r.reason
        }
        let full = response.fullResync
        let changes = response.changes
        do {
            try applyRecords(changes.categories, of: CategoryEntity.self, rejected: rejected, sent: sent, fullResync: full)
            try applyRecords(changes.recurringRules, of: RecurringRuleEntity.self, rejected: rejected, sent: sent, fullResync: full)
            try applyRecords(changes.transactions, of: TransactionEntity.self, rejected: rejected, sent: sent, fullResync: full)
            try applyRecords(changes.budgets, of: BudgetEntity.self, rejected: rejected, sent: sent, fullResync: full)
            try applyMembers(changes.users, fullResync: full)
            try context.save()
        } catch {
            // Nichts halb Angewendetes stehen lassen; der Cursor bleibt, der nächste Sync holt alles erneut.
            context.rollback()
            throw error
        }
    }

    private func applyRecords<E: SyncEntity>(_ records: [E.RecordOut], of type: E.Type,
                                             rejected allRejected: [SyncTable: [UUID: String]],
                                             sent allSent: [SyncTable: [UUID: Int]], fullResync: Bool) throws {
        let rejected = allRejected[E.table] ?? [:]
        let sent = allSent[E.table] ?? [:]
        var byId: [UUID: E] = [:]
        for e in try context.fetch(FetchDescriptor<E>()) { byId[e.id] = e }
        var seen = Set<UUID>()

        for record in records {
            let raw = E.id(of: record)
            guard let id = UUID(uuidString: raw) else {
                logger.error("Ungültige ID in \(E.table.rawValue, privacy: .public): \(raw, privacy: .public)")
                continue
            }
            seen.insert(id)
            if let local = byId[id] {
                // Lokale Änderung, die der Server noch nicht (in diesem Stand) hat, nicht überschreiben;
                // abgelehnte behalten ihren lokalen Inhalt.
                if local.isDirty && (sent[id] != local.dirtyGeneration || rejected[id] != nil) { continue }
                if !local.apply(record) {
                    logger.error("Ungültiger Datensatz in \(E.table.rawValue, privacy: .public): \(raw, privacy: .public)")
                }
            } else {
                guard let created = E.make(from: record) else {
                    logger.error("Ungültiger Datensatz in \(E.table.rawValue, privacy: .public): \(raw, privacy: .public)")
                    continue
                }
                context.insert(created)
                byId[id] = created
            }
        }

        for (id, reason) in rejected {
            // Nur den gesendeten Stand als abgelehnt markieren; seither Geändertes wird neu gesendet.
            guard let local = byId[id], local.isDirty, sent[id] == local.dirtyGeneration else { continue }
            local.rejectionReason = reason
            local.isDirty = false
        }

        if fullResync {
            for (id, local) in byId where !seen.contains(id) && !local.isDirty && local.rejectionReason == nil {
                context.delete(local)
            }
        }
    }

    private func applyMembers(_ users: [Components.Schemas.UserRecord], fullResync: Bool) throws {
        var byId: [UUID: MemberEntity] = [:]
        for m in try context.fetch(FetchDescriptor<MemberEntity>()) { byId[m.id] = m }
        var seen = Set<UUID>()
        for u in users {
            guard let id = UUID(uuidString: u.id) else {
                logger.error("Ungültige Benutzer-ID: \(u.id, privacy: .public)")
                continue
            }
            seen.insert(id)
            if let local = byId[id] {
                local.apply(u)
            } else if let created = MemberEntity.make(from: u) {
                context.insert(created)
                byId[id] = created
            }
        }
        if fullResync {
            for (id, local) in byId where !seen.contains(id) {
                context.delete(local)
            }
        }
    }
}
