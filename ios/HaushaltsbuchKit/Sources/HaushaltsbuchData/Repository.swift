import Foundation
import SwiftData
import HaushaltsbuchCore

public enum RepositoryError: Error, Equatable {
    case notFound
    case invalid(String)
}

/// Einziger Schreibzugang der UI auf SwiftData. Jede Schreibmethode markiert dirty, speichert und ruft `onChange`.
@MainActor
public final class Repository {
    private let context: ModelContext
    private let onChange: @MainActor () -> Void
    private let onRefetchNeeded: @MainActor () -> Void

    /// - Parameter onRefetchNeeded: nach dem Verwerfen einer abgelehnten Änderung an einem schon
    ///   synchronisierten Datensatz – der Sync muss alles ab Version 0 neu holen (Cursor auf 0, Sync
    ///   anstoßen), sonst käme der unveränderte Server-Stand nie zurück.
    public init(context: ModelContext, onChange: @escaping @MainActor () -> Void = {},
                onRefetchNeeded: @escaping @MainActor () -> Void = {}) {
        self.context = context
        self.onChange = onChange
        self.onRefetchNeeded = onRefetchNeeded
    }

    // MARK: Lesen (aktive = nicht gelöscht)

    public func activeTransactions() -> [TransactionEntity] {
        fetchOrEmpty(FetchDescriptor<TransactionEntity>(
            predicate: #Predicate { !$0.softDeleted },
            sortBy: [SortDescriptor(\.day, order: .reverse)]))
    }

    /// Archivierte sind enthalten; Aufrufer filtern.
    public func activeCategories(kind: Kind? = nil) -> [CategoryEntity] {
        let all = fetchOrEmpty(FetchDescriptor<CategoryEntity>(
            predicate: #Predicate { !$0.softDeleted },
            sortBy: [SortDescriptor(\.sortOrder)]))
        guard let kind else { return all }
        return all.filter { $0.kind == kind.rawValue }
    }

    public func activeBudgets() -> [BudgetEntity] {
        fetchOrEmpty(FetchDescriptor<BudgetEntity>(predicate: #Predicate { !$0.softDeleted }))
    }

    public func activeRules() -> [RecurringRuleEntity] {
        fetchOrEmpty(FetchDescriptor<RecurringRuleEntity>(
            predicate: #Predicate { !$0.softDeleted },
            sortBy: [SortDescriptor(\.startDate)]))
    }

    public func activeMembers() -> [MemberEntity] {
        fetchOrEmpty(FetchDescriptor<MemberEntity>(
            predicate: #Predicate { !$0.softDeleted },
            sortBy: [SortDescriptor(\.displayName)]))
    }

    /// Anzeigewert; bei Lesefehler 0.
    public var pendingChangesCount: Int {
        let counts = try? [
            count(FetchDescriptor<CategoryEntity>(predicate: #Predicate { $0.isDirty })),
            count(FetchDescriptor<TransactionEntity>(predicate: #Predicate { $0.isDirty })),
            count(FetchDescriptor<BudgetEntity>(predicate: #Predicate { $0.isDirty })),
            count(FetchDescriptor<RecurringRuleEntity>(predicate: #Predicate { $0.isDirty })),
        ]
        return counts?.reduce(0, +) ?? 0
    }

    // MARK: Buchungen

    @discardableResult
    public func addTransaction(amountCents: Int, kind: Kind, categoryId: UUID, day: CalendarDay,
                               paidBy: UUID, note: String?) throws -> TransactionEntity {
        let tx = TransactionEntity(amountCents: amountCents, kind: kind, categoryId: categoryId,
                                   day: day, paidBy: paidBy, note: note)
        tx.markDirty()
        context.insert(tx)
        try commit()
        return tx
    }

    public func update(_ tx: TransactionEntity, amountCents: Int, kind: Kind, categoryId: UUID,
                       day: CalendarDay, paidBy: UUID, note: String?) throws {
        tx.amountCents = amountCents
        tx.kind = kind.rawValue
        tx.categoryId = categoryId
        tx.day = day.string
        tx.paidBy = paidBy
        tx.note = note
        tx.markDirty()
        try commit()
    }

    public func delete(_ tx: TransactionEntity) throws {
        tx.deleted = true
        tx.markDirty()
        try commit()
    }

    // MARK: Kategorien

    @discardableResult
    public func saveCategory(_ draft: CategoryDraft) throws -> CategoryEntity {
        let entity: CategoryEntity
        if let id = draft.id {
            guard let existing = try fetch(FetchDescriptor<CategoryEntity>(predicate: #Predicate { $0.id == id })).first
            else { throw RepositoryError.notFound }
            existing.name = draft.name
            existing.icon = draft.icon
            existing.color = draft.color
            existing.kind = draft.kind.rawValue
            entity = existing
        } else {
            let sameKind = try fetch(FetchDescriptor<CategoryEntity>(predicate: #Predicate { !$0.softDeleted }))
                .filter { $0.kind == draft.kind.rawValue }
            let next = (sameKind.map(\.sortOrder).max() ?? -1) + 1
            entity = CategoryEntity(name: draft.name, icon: draft.icon, color: draft.color,
                                    kind: draft.kind, sortOrder: next)
            context.insert(entity)
        }
        entity.markDirty()
        try commit()
        return entity
    }

    /// Mit nicht gelöschten Buchungen/Regeln: archivieren, sonst Soft-Delete (inkl. Budget der Kategorie).
    public func removeCategory(_ c: CategoryEntity) throws {
        let id = c.id
        // Zählfehler werfen (statt als „unbenutzt“ zu gelten und die Kategorie zu löschen).
        let txCount = try count(FetchDescriptor<TransactionEntity>(predicate: #Predicate { $0.categoryId == id && !$0.softDeleted }))
        let ruleCount = try count(FetchDescriptor<RecurringRuleEntity>(predicate: #Predicate { $0.categoryId == id && !$0.softDeleted }))
        let used = txCount > 0 || ruleCount > 0
        // Alle Lesezugriffe vor der ersten Änderung: wirft einer, bleibt der Kontext unverändert.
        let budgets = used ? [] : try fetch(FetchDescriptor<BudgetEntity>(
            predicate: #Predicate { $0.categoryId == id && !$0.softDeleted }))
        if used {
            c.archived = true
        } else {
            c.deleted = true
            for b in budgets {
                b.deleted = true
                b.markDirty()
            }
        }
        c.markDirty()
        try commit()
    }

    /// Vergibt `sortOrder` 0…n-1 in der übergebenen Reihenfolge (nur geänderte werden dirty).
    public func moveCategories(_ ordered: [CategoryEntity]) throws {
        for (index, c) in ordered.enumerated() where c.sortOrder != index {
            c.sortOrder = index
            c.markDirty()
        }
        try commit()
    }

    // MARK: Budgets

    public func setBudget(categoryId: UUID, monthlyLimitCents: Int?) throws {
        let existing = try fetch(FetchDescriptor<BudgetEntity>(
            predicate: #Predicate { $0.categoryId == categoryId && !$0.softDeleted })).first
        switch (existing, monthlyLimitCents) {
        case let (b?, limit?):
            b.monthlyLimitCents = limit
            b.markDirty()
        case let (b?, nil):
            b.deleted = true
            b.markDirty()
        case let (nil, limit?):
            let b = BudgetEntity(categoryId: categoryId, monthlyLimitCents: limit)
            b.markDirty()
            context.insert(b)
        case (nil, nil):
            return
        }
        try commit()
    }

    // MARK: Regeln

    @discardableResult
    public func saveRule(_ draft: RuleDraft) throws -> RecurringRuleEntity {
        if let message = draft.validationError() { throw RepositoryError.invalid(message) }
        let rule: RecurringRuleEntity
        if let id = draft.id {
            guard let existing = try fetch(FetchDescriptor<RecurringRuleEntity>(predicate: #Predicate { $0.id == id })).first
            else { throw RepositoryError.notFound }
            existing.amountCents = draft.amountCents
            existing.kind = draft.kind.rawValue
            existing.categoryId = draft.categoryId
            existing.note = draft.note
            existing.paidBy = draft.paidBy
            existing.frequency = draft.frequency.rawValue
            existing.startDate = draft.startDate.string
            existing.endDate = draft.endDate?.string
            rule = existing
        } else {
            rule = RecurringRuleEntity(amountCents: draft.amountCents, kind: draft.kind,
                                       categoryId: draft.categoryId, note: draft.note, paidBy: draft.paidBy,
                                       frequency: draft.frequency, startDate: draft.startDate,
                                       endDate: draft.endDate)
            context.insert(rule)
        }
        rule.markDirty()
        try commit()
        return rule
    }

    public func deleteRule(_ r: RecurringRuleEntity) throws {
        r.deleted = true
        r.markDirty()
        try commit()
    }

    // MARK: Abgelehnte Änderungen

    /// Nie synchronisiert → hart löschen. Sonst Ablehnung und Dirty-Markierung entfernen und einen
    /// Neuabruf ab Version 0 anfordern (`onRefetchNeeded`): der Server-Stand hat sich nicht geändert,
    /// ein normaler Pull (`version > lastVersion`) brächte ihn nie zurück. Bis dahin bleibt der
    /// lokale (abgelehnte) Inhalt stehen; der Neuabruf überschreibt ihn, weil er nicht mehr dirty ist.
    public func discardRejected(_ e: any SyncTracked) throws {
        let synced = e.version != nil
        if !synced, let model = e as? any PersistentModel {
            context.delete(model)
        } else {
            e.rejectionReason = nil
            e.isDirty = false
        }
        try commit()
        if synced { onRefetchNeeded() }
    }

    // MARK: Intern

    /// Bei Speicherfehler werden die ungespeicherten Änderungen verworfen, damit der Kontext
    /// nicht in einem halb geänderten Zustand bleibt, den ein späteres `save()` mitschreiben würde.
    private func commit() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        onChange()
    }

    private func fetch<T: PersistentModel>(_ d: FetchDescriptor<T>) throws -> [T] {
        try context.fetch(d)
    }

    /// Nur für Lese-Methoden der UI: Fehler → leere Liste.
    private func fetchOrEmpty<T: PersistentModel>(_ d: FetchDescriptor<T>) -> [T] {
        (try? fetch(d)) ?? []
    }

    private func count<T: PersistentModel>(_ d: FetchDescriptor<T>) throws -> Int {
        try context.fetchCount(d)
    }
}
