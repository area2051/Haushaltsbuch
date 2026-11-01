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

    public init(context: ModelContext, onChange: @escaping @MainActor () -> Void = {}) {
        self.context = context
        self.onChange = onChange
    }

    // MARK: Lesen (aktive = nicht gelöscht)

    public func activeTransactions() -> [TransactionEntity] {
        fetch(FetchDescriptor<TransactionEntity>(
            predicate: #Predicate { !$0.softDeleted },
            sortBy: [SortDescriptor(\.day, order: .reverse)]))
    }

    /// Archivierte sind enthalten; Aufrufer filtern.
    public func activeCategories(kind: Kind? = nil) -> [CategoryEntity] {
        let all = fetch(FetchDescriptor<CategoryEntity>(
            predicate: #Predicate { !$0.softDeleted },
            sortBy: [SortDescriptor(\.sortOrder)]))
        guard let kind else { return all }
        return all.filter { $0.kind == kind.rawValue }
    }

    public func activeBudgets() -> [BudgetEntity] {
        fetch(FetchDescriptor<BudgetEntity>(predicate: #Predicate { !$0.softDeleted }))
    }

    public func activeRules() -> [RecurringRuleEntity] {
        fetch(FetchDescriptor<RecurringRuleEntity>(
            predicate: #Predicate { !$0.softDeleted },
            sortBy: [SortDescriptor(\.startDate)]))
    }

    public func activeMembers() -> [MemberEntity] {
        fetch(FetchDescriptor<MemberEntity>(
            predicate: #Predicate { !$0.softDeleted },
            sortBy: [SortDescriptor(\.displayName)]))
    }

    public var pendingChangesCount: Int {
        count(FetchDescriptor<CategoryEntity>(predicate: #Predicate { $0.isDirty }))
        + count(FetchDescriptor<TransactionEntity>(predicate: #Predicate { $0.isDirty }))
        + count(FetchDescriptor<BudgetEntity>(predicate: #Predicate { $0.isDirty }))
        + count(FetchDescriptor<RecurringRuleEntity>(predicate: #Predicate { $0.isDirty }))
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
            guard let existing = fetch(FetchDescriptor<CategoryEntity>(predicate: #Predicate { $0.id == id })).first
            else { throw RepositoryError.notFound }
            existing.name = draft.name
            existing.icon = draft.icon
            existing.color = draft.color
            existing.kind = draft.kind.rawValue
            entity = existing
        } else {
            let next = (activeCategories(kind: draft.kind).map(\.sortOrder).max() ?? -1) + 1
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
        let used = count(FetchDescriptor<TransactionEntity>(predicate: #Predicate { $0.categoryId == id && !$0.softDeleted })) > 0
            || count(FetchDescriptor<RecurringRuleEntity>(predicate: #Predicate { $0.categoryId == id && !$0.softDeleted })) > 0
        if used {
            c.archived = true
        } else {
            c.deleted = true
            for b in fetch(FetchDescriptor<BudgetEntity>(predicate: #Predicate { $0.categoryId == id && !$0.softDeleted })) {
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
        let existing = fetch(FetchDescriptor<BudgetEntity>(
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
            guard let existing = fetch(FetchDescriptor<RecurringRuleEntity>(predicate: #Predicate { $0.id == id })).first
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

    /// Nie synchronisiert → hart löschen; sonst Änderung verwerfen (nächster Pull bringt den Server-Stand).
    public func discardRejected(_ e: any SyncTracked) throws {
        if e.version == nil, let model = e as? any PersistentModel {
            context.delete(model)
        } else {
            e.rejectionReason = nil
            e.isDirty = false
        }
        try commit()
    }

    // MARK: Intern

    private func commit() throws {
        try context.save()
        onChange()
    }

    private func fetch<T: PersistentModel>(_ d: FetchDescriptor<T>) -> [T] {
        (try? context.fetch(d)) ?? []
    }

    private func count<T: PersistentModel>(_ d: FetchDescriptor<T>) -> Int {
        (try? context.fetchCount(d)) ?? 0
    }
}
