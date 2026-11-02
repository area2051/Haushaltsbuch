import Foundation
import SwiftData
import HaushaltsbuchAPI
import HaushaltsbuchCore

/// Tabellen des Sync-Protokolls (Namen wie im Server-Feld `rejected[].table`).
public enum SyncTable: String, Sendable, CaseIterable {
    case categories, recurringRules, transactions, budgets
}

/// Abbildung Entity ↔ generierte Sync-Records.
///
/// - Senden: IDs als `uuidString.lowercased()`; `nil`-Optionals lässt der Encoder weg, der Server
///   wertet fehlende `note`/`recurringRuleId`/`endDate` als `null`.
/// - Empfangen: IDs über `UUID(uuidString:)` (Groß-/Kleinschreibung egal). Ist eine Pflicht-ID nicht
///   parsebar, wird der Datensatz übersprungen (`make` → `nil`, `apply` → `false`, Entity unverändert).
@MainActor
protocol SyncEntity: PersistentModel, SyncTracked {
    associatedtype Record
    associatedtype RecordOut
    static var table: SyncTable { get }
    /// Alle lokal geänderten (`isDirty`) Datensätze dieses Typs.
    static var dirtyFetch: FetchDescriptor<Self> { get }
    static func id(of record: RecordOut) -> String
    /// Neue Entity aus einem Server-Datensatz; `nil`, wenn IDs nicht parsebar sind.
    static func make(from record: RecordOut) -> Self?
    /// Übernimmt den Server-Stand (Felder, `version`, `deleted`) und setzt `isDirty = false`.
    func apply(_ record: RecordOut) -> Bool
    var syncRecord: Record { get }
}

extension UUID {
    /// Form für den Server.
    var wire: String { uuidString.lowercased() }
}

extension SyncTracked {
    /// Gemeinsamer Teil von `apply`: Server-Stand übernommen, nichts mehr zu senden.
    fileprivate func markSynced(version: Int, deleted: Bool) {
        self.version = version
        self.deleted = deleted
        self.isDirty = false
        self.rejectionReason = nil
    }
}

// MARK: Kategorien

extension CategoryEntity: SyncEntity {
    typealias Record = Components.Schemas.CategoryRecord
    typealias RecordOut = Components.Schemas.CategoryRecordOut

    static var table: SyncTable { .categories }
    static var dirtyFetch: FetchDescriptor<CategoryEntity> { FetchDescriptor(predicate: #Predicate { $0.isDirty }) }
    static func id(of record: RecordOut) -> String { record.id }

    static func make(from record: RecordOut) -> CategoryEntity? {
        guard let id = UUID(uuidString: record.id) else { return nil }
        let e = CategoryEntity(id: id, name: record.name, icon: record.icon, color: record.color,
                               kind: .expense, sortOrder: record.sortOrder)
        return e.apply(record) ? e : nil
    }

    func apply(_ r: RecordOut) -> Bool {
        name = r.name
        icon = r.icon
        color = r.color
        kind = r.kind.rawValue
        sortOrder = r.sortOrder
        archived = r.archived
        markSynced(version: r.version, deleted: r.deleted)
        return true
    }

    var syncRecord: Record {
        Record(archived: archived, color: color, deleted: deleted, icon: icon, id: id.wire,
               kind: Record.kindPayload(rawValue: kind) ?? .expense, name: name, sortOrder: sortOrder)
    }
}

// MARK: Buchungen

extension TransactionEntity: SyncEntity {
    typealias Record = Components.Schemas.TransactionRecord
    typealias RecordOut = Components.Schemas.TransactionRecordOut

    static var table: SyncTable { .transactions }
    static var dirtyFetch: FetchDescriptor<TransactionEntity> { FetchDescriptor(predicate: #Predicate { $0.isDirty }) }
    static func id(of record: RecordOut) -> String { record.id }

    static func make(from record: RecordOut) -> TransactionEntity? {
        guard let id = UUID(uuidString: record.id), let categoryId = UUID(uuidString: record.categoryId),
              let paidBy = UUID(uuidString: record.paidBy) else { return nil }
        let e = TransactionEntity(id: id, amountCents: record.amountCents, kind: .expense, categoryId: categoryId,
                                  day: CalendarDayPlaceholder.value, paidBy: paidBy, note: nil)
        return e.apply(record) ? e : nil
    }

    func apply(_ r: RecordOut) -> Bool {
        guard let categoryId = UUID(uuidString: r.categoryId), let paidBy = UUID(uuidString: r.paidBy) else {
            return false
        }
        var ruleId: UUID?
        if let raw = r.recurringRuleId {
            guard let parsed = UUID(uuidString: raw) else { return false }
            ruleId = parsed
        }
        amountCents = r.amountCents
        kind = r.kind.rawValue
        self.categoryId = categoryId
        day = r.date
        self.paidBy = paidBy
        note = r.note
        recurringRuleId = ruleId
        markSynced(version: r.version, deleted: r.deleted)
        return true
    }

    var syncRecord: Record {
        Record(amountCents: amountCents, categoryId: categoryId.wire, date: day, deleted: deleted, id: id.wire,
               kind: Record.kindPayload(rawValue: kind) ?? .expense, note: note, paidBy: paidBy.wire,
               recurringRuleId: recurringRuleId?.wire)
    }
}

// MARK: Budgets

extension BudgetEntity: SyncEntity {
    typealias Record = Components.Schemas.BudgetRecord
    typealias RecordOut = Components.Schemas.BudgetRecordOut

    static var table: SyncTable { .budgets }
    static var dirtyFetch: FetchDescriptor<BudgetEntity> { FetchDescriptor(predicate: #Predicate { $0.isDirty }) }
    static func id(of record: RecordOut) -> String { record.id }

    static func make(from record: RecordOut) -> BudgetEntity? {
        guard let id = UUID(uuidString: record.id), let categoryId = UUID(uuidString: record.categoryId)
        else { return nil }
        let e = BudgetEntity(id: id, categoryId: categoryId, monthlyLimitCents: record.monthlyLimitCents)
        return e.apply(record) ? e : nil
    }

    func apply(_ r: RecordOut) -> Bool {
        guard let categoryId = UUID(uuidString: r.categoryId) else { return false }
        self.categoryId = categoryId
        monthlyLimitCents = r.monthlyLimitCents
        markSynced(version: r.version, deleted: r.deleted)
        return true
    }

    var syncRecord: Record {
        Record(categoryId: categoryId.wire, deleted: deleted, id: id.wire, monthlyLimitCents: monthlyLimitCents)
    }
}

// MARK: Daueraufträge

extension RecurringRuleEntity: SyncEntity {
    typealias Record = Components.Schemas.RecurringRuleRecord
    typealias RecordOut = Components.Schemas.RecurringRuleRecordOut

    static var table: SyncTable { .recurringRules }
    static var dirtyFetch: FetchDescriptor<RecurringRuleEntity> { FetchDescriptor(predicate: #Predicate { $0.isDirty }) }
    static func id(of record: RecordOut) -> String { record.id }

    static func make(from record: RecordOut) -> RecurringRuleEntity? {
        guard let id = UUID(uuidString: record.id), let categoryId = UUID(uuidString: record.categoryId),
              let paidBy = UUID(uuidString: record.paidBy) else { return nil }
        let e = RecurringRuleEntity(id: id, amountCents: record.amountCents, kind: .expense, categoryId: categoryId,
                                    note: nil, paidBy: paidBy, frequency: .monthly,
                                    startDate: CalendarDayPlaceholder.value, endDate: nil)
        return e.apply(record) ? e : nil
    }

    func apply(_ r: RecordOut) -> Bool {
        guard let categoryId = UUID(uuidString: r.categoryId), let paidBy = UUID(uuidString: r.paidBy) else {
            return false
        }
        amountCents = r.amountCents
        kind = r.kind.rawValue
        self.categoryId = categoryId
        note = r.note
        self.paidBy = paidBy
        frequency = r.frequency.rawValue
        startDate = r.startDate
        endDate = r.endDate
        nextDueDate = r.nextDueDate
        markSynced(version: r.version, deleted: r.deleted)
        return true
    }

    /// `nextDueDate` setzt nur der Server und wird nicht gesendet.
    var syncRecord: Record {
        Record(amountCents: amountCents, categoryId: categoryId.wire, deleted: deleted, endDate: endDate,
               frequency: Record.frequencyPayload(rawValue: frequency) ?? .monthly, id: id.wire,
               kind: Record.kindPayload(rawValue: kind) ?? .expense, note: note, paidBy: paidBy.wire,
               startDate: startDate)
    }
}

// MARK: Mitglieder

extension MemberEntity {
    /// `nil`, wenn die ID nicht parsebar ist.
    static func make(from r: Components.Schemas.UserRecord) -> MemberEntity? {
        guard let id = UUID(uuidString: r.id) else { return nil }
        return MemberEntity(id: id, username: r.username, displayName: r.displayName, isAdmin: r.isAdmin,
                            deleted: r.deleted, version: r.version)
    }

    func apply(_ r: Components.Schemas.UserRecord) {
        username = r.username
        displayName = r.displayName
        isAdmin = r.isAdmin
        deleted = r.deleted
        version = r.version
    }
}

/// Platzhalter für Initialisierer; `apply` überschreibt das Datum sofort mit dem Server-Wert.
private enum CalendarDayPlaceholder {
    static let value = CalendarDay(year: 2000, month: 1, day: 1)!
}
