import Foundation
import SwiftData
import Testing
import HaushaltsbuchCore
@testable import HaushaltsbuchData

@MainActor
private final class Counter { var n = 0 }

@MainActor
private struct Fixture {
    let container: ModelContainer
    let repo: Repository
    let changes: Counter
    let user = UUID()
    let cat = UUID()
    let day = CalendarDay(year: 2026, month: 11, day: 1)!

    init() throws {
        container = try ModelContainer.makeAppContainer(inMemory: true)
        let counter = Counter()
        changes = counter
        repo = Repository(context: container.mainContext, onChange: { counter.n += 1 })
    }

    @discardableResult
    func addTx(day: CalendarDay? = nil, category: UUID? = nil) throws -> TransactionEntity {
        try repo.addTransaction(amountCents: 1250, kind: .expense, categoryId: category ?? cat,
                                day: day ?? self.day, paidBy: user, note: "Brot")
    }

    func makeCategory(_ name: String = "Essen", kind: Kind = .expense) throws -> CategoryEntity {
        try repo.saveCategory(CategoryDraft(name: name, icon: "cart", color: "#112233", kind: kind))
    }

    func ruleDraft() -> RuleDraft {
        RuleDraft(amountCents: 5000, kind: .expense, categoryId: cat, note: nil, paidBy: user,
                  frequency: .monthly, startDate: day, endDate: nil)
    }
}

@MainActor @Test func addTransactionIsDirtyWithNilVersion() throws {
    let f = try Fixture()
    let tx = try f.addTx()
    #expect(tx.isDirty)
    #expect(tx.version == nil)
    #expect(tx.dirtyGeneration == 1)
    #expect(tx.recurringRuleId == nil)
    #expect(tx.day == "2026-11-01")
    #expect(tx.value == TxValue(id: tx.id, amountCents: 1250, kind: .expense, categoryId: f.cat,
                                day: f.day, paidBy: f.user, note: "Brot"))
}

@MainActor @Test func updateBumpsDirtyGenerationAndClearsRejection() throws {
    let f = try Fixture()
    let tx = try f.addTx()
    tx.rejectionReason = "amount_cents must be > 0"
    tx.isDirty = false
    try f.repo.update(tx, amountCents: 999, kind: .income, categoryId: f.cat, day: f.day, paidBy: f.user, note: nil)
    #expect(tx.dirtyGeneration == 2)
    #expect(tx.isDirty)
    #expect(tx.rejectionReason == nil)
    #expect(tx.amountCents == 999)
    #expect(tx.kind == "income")
    #expect(tx.note == nil)
}

@MainActor @Test func deleteIsSoftAndDirty() throws {
    let f = try Fixture()
    let tx = try f.addTx()
    try f.repo.delete(tx)
    #expect(tx.deleted)
    #expect(tx.isDirty)
    #expect(try f.container.mainContext.fetchCount(FetchDescriptor<TransactionEntity>()) == 1)
}

@MainActor @Test func removeCategoryWithTransactionsArchives() throws {
    let f = try Fixture()
    let c = try f.makeCategory()
    try f.addTx(category: c.id)
    try f.repo.removeCategory(c)
    #expect(c.archived)
    #expect(!c.deleted)
}

@MainActor @Test func removeCategoryWithoutUsageDeletes() throws {
    let f = try Fixture()
    let c = try f.makeCategory()
    try f.repo.setBudget(categoryId: c.id, monthlyLimitCents: 5000)
    // gelöschte Buchung zählt nicht als Nutzung
    let tx = try f.addTx(category: c.id)
    try f.repo.delete(tx)
    try f.repo.removeCategory(c)
    #expect(c.deleted)
    #expect(!c.archived)
    #expect(f.repo.activeBudgets().isEmpty)
}

@MainActor @Test func removeCategoryWithRuleArchives() throws {
    let f = try Fixture()
    let c = try f.makeCategory()
    var d = f.ruleDraft()
    d.categoryId = c.id
    try f.repo.saveRule(d)
    try f.repo.removeCategory(c)
    #expect(c.archived)
}

@MainActor @Test func setBudgetNilSoftDeletesActiveBudget() throws {
    let f = try Fixture()
    try f.repo.setBudget(categoryId: f.cat, monthlyLimitCents: 10_000)
    #expect(f.repo.activeBudgets().count == 1)
    try f.repo.setBudget(categoryId: f.cat, monthlyLimitCents: 20_000)
    #expect(f.repo.activeBudgets().map(\.monthlyLimitCents) == [20_000])
    try f.repo.setBudget(categoryId: f.cat, monthlyLimitCents: nil)
    #expect(f.repo.activeBudgets().isEmpty)
    let all = try f.container.mainContext.fetch(FetchDescriptor<BudgetEntity>())
    #expect(all.count == 1)
    #expect(all[0].deleted && all[0].isDirty)
    try f.repo.setBudget(categoryId: f.cat, monthlyLimitCents: 5_000)
    #expect(f.repo.activeBudgets().count == 1)
}

@MainActor @Test func discardRejectedNeverSyncedHardDeletes() throws {
    let f = try Fixture()
    let tx = try f.addTx()
    tx.rejectionReason = "kaputt"
    try f.repo.discardRejected(tx)
    #expect(try f.container.mainContext.fetchCount(FetchDescriptor<TransactionEntity>()) == 0)
}

@MainActor @Test func discardRejectedSyncedClearsDirty() throws {
    let f = try Fixture()
    let tx = try f.addTx()
    tx.version = 7
    tx.rejectionReason = "kaputt"
    try f.repo.discardRejected(tx)
    #expect(!tx.isDirty)
    #expect(tx.rejectionReason == nil)
    #expect(try f.container.mainContext.fetchCount(FetchDescriptor<TransactionEntity>()) == 1)
}

@MainActor @Test func pendingChangesCountCountsAllTypes() throws {
    let f = try Fixture()
    #expect(try f.repo.pendingChanges().unsent == 0)
    try f.addTx()
    _ = try f.makeCategory()
    try f.repo.setBudget(categoryId: f.cat, monthlyLimitCents: 100)
    try f.repo.saveRule(f.ruleDraft())
    #expect(try f.repo.pendingChanges().unsent == 4)
}

@MainActor @Test func writesCallOnChange() throws {
    let f = try Fixture()
    let tx = try f.addTx()
    #expect(f.changes.n == 1)
    try f.repo.delete(tx)
    _ = try f.makeCategory()
    try f.repo.setBudget(categoryId: f.cat, monthlyLimitCents: 100)
    try f.repo.saveRule(f.ruleDraft())
    #expect(f.changes.n == 5)
}

@MainActor @Test func newCategoriesGetNextSortOrderPerKind() throws {
    let f = try Fixture()
    let a = try f.makeCategory("A")
    let b = try f.makeCategory("B")
    let income = try f.makeCategory("Gehalt", kind: .income)
    #expect(a.sortOrder == 0)
    #expect(b.sortOrder == 1)
    #expect(income.sortOrder == 0)
    try f.repo.moveCategories([b, a])
    #expect(f.repo.activeCategories(kind: .expense).map(\.name) == ["B", "A"])
}

@MainActor @Test func saveCategoryUpdatesExisting() throws {
    let f = try Fixture()
    let c = try f.makeCategory("Alt")
    let again = try f.repo.saveCategory(CategoryDraft(id: c.id, name: "Neu", icon: "x", color: "#000000", kind: .expense))
    #expect(again === c)
    #expect(c.name == "Neu")
    #expect(c.dirtyGeneration == 2)
    #expect(f.repo.activeCategories().count == 1)
}

@MainActor @Test func activeFetchesExcludeDeleted() throws {
    let f = try Fixture()
    let old = try f.addTx(day: CalendarDay(year: 2026, month: 1, day: 5)!)
    let new = try f.addTx(day: CalendarDay(year: 2026, month: 10, day: 5)!)
    let gone = try f.addTx()
    try f.repo.delete(gone)
    #expect(f.repo.activeTransactions().map(\.id) == [new.id, old.id])

    let c1 = try f.makeCategory("Weg")
    _ = try f.makeCategory("Bleibt")
    try f.repo.removeCategory(c1)
    #expect(f.repo.activeCategories().map(\.name) == ["Bleibt"])

    let rule = try f.repo.saveRule(f.ruleDraft())
    try f.repo.deleteRule(rule)
    #expect(f.repo.activeRules().isEmpty)

    try f.repo.setBudget(categoryId: f.cat, monthlyLimitCents: 1)
    try f.repo.setBudget(categoryId: f.cat, monthlyLimitCents: nil)
    #expect(f.repo.activeBudgets().isEmpty)

    let ctx = f.container.mainContext
    ctx.insert(MemberEntity(id: UUID(), username: "a", displayName: "A", isAdmin: true))
    ctx.insert(MemberEntity(id: UUID(), username: "b", displayName: "B", isAdmin: false, deleted: true))
    #expect(f.repo.activeMembers().map(\.username) == ["a"])
}

@MainActor @Test func activeCategoriesIncludeArchivedAndFilterByKind() throws {
    let f = try Fixture()
    let c = try f.makeCategory("Essen")
    _ = try f.makeCategory("Gehalt", kind: .income)
    try f.addTx(category: c.id)
    try f.repo.removeCategory(c)
    #expect(f.repo.activeCategories(kind: .expense).map(\.name) == ["Essen"])
    #expect(f.repo.activeCategories(kind: .income).map(\.name) == ["Gehalt"])
    #expect(f.repo.activeCategories().count == 2)
}

@Test func ruleDraftValidation() {
    let base = RuleDraft(amountCents: 100, kind: .expense, categoryId: UUID(), note: nil, paidBy: UUID(),
                         frequency: .monthly, startDate: CalendarDay(year: 2026, month: 1, day: 1)!, endDate: nil)
    #expect(base.validationError() == nil)

    var early = base
    early.startDate = CalendarDay(year: 1999, month: 12, day: 31)!
    #expect(early.validationError() == "Der Start darf nicht vor dem 01.01.2000 liegen.")
    var edge = base
    edge.startDate = CalendarDay(year: 2000, month: 1, day: 1)!
    #expect(edge.validationError() == nil)

    var badEnd = base
    badEnd.endDate = CalendarDay(year: 2025, month: 12, day: 31)!
    #expect(badEnd.validationError() == "Das Ende darf nicht vor dem Start liegen.")
    var sameDay = base
    sameDay.endDate = base.startDate
    #expect(sameDay.validationError() == nil)

    var zero = base
    zero.amountCents = 0
    #expect(zero.validationError() == "Bitte einen Betrag eingeben.")
}

@MainActor @Test func saveRuleThrowsOnInvalidDraftAndSavesValid() throws {
    let f = try Fixture()
    var bad = f.ruleDraft()
    bad.amountCents = 0
    #expect(throws: RepositoryError.invalid("Bitte einen Betrag eingeben.")) { try f.repo.saveRule(bad) }
    #expect(f.repo.activeRules().isEmpty)
    let rule = try f.repo.saveRule(f.ruleDraft())
    #expect(rule.isDirty && rule.version == nil && rule.nextDueDate == nil)
    var edit = f.ruleDraft()
    edit.id = rule.id
    edit.amountCents = 7000
    edit.frequency = .weekly
    edit.endDate = CalendarDay(year: 2027, month: 1, day: 1)
    let again = try f.repo.saveRule(edit)
    #expect(again === rule)
    #expect(rule.amountCents == 7000 && rule.frequency == "weekly" && rule.endDate == "2027-01-01")
    #expect(rule.value.frequency == .weekly)
}

// MARK: Final-Review: abgelehnte zählen mit, Budgets je Kategorie eindeutig

@MainActor @Test func pendingChangesCountsRejectedSeparately() throws {
    let f = try Fixture()
    let tx = try f.addTx()
    try f.addTx()
    tx.rejectionReason = "unknown_user"
    tx.isDirty = false
    try f.container.mainContext.save()
    #expect(try f.repo.pendingChanges() == PendingChanges(unsent: 1, rejected: 1))
    #expect(try f.repo.pendingChanges().total == 2)
}

@MainActor @Test func activeBudgetsPreferSyncedRowPerCategory() throws {
    let f = try Fixture()
    let ctx = f.container.mainContext
    let synced = BudgetEntity(categoryId: f.cat, monthlyLimitCents: 30000, version: 5)
    let rejected = BudgetEntity(categoryId: f.cat, monthlyLimitCents: 20000)
    rejected.rejectionReason = "unique_violation"
    let other = BudgetEntity(categoryId: UUID(), monthlyLimitCents: 100)
    for b in [rejected, synced, other] { ctx.insert(b) }
    try ctx.save()

    let active = f.repo.activeBudgets()
    #expect(active.count == 2)
    #expect(active.first { $0.categoryId == f.cat } === synced)
    #expect(BudgetEntity.onePerCategory([rejected, synced, other]).count == 2)
    #expect(BudgetEntity.onePerCategory([synced, rejected]).first === synced)

    // Bearbeiten schreibt ins synchronisierte Budget und räumt die nie synchronisierte Dublette weg.
    try f.repo.setBudget(categoryId: f.cat, monthlyLimitCents: 25000)
    #expect(synced.monthlyLimitCents == 25000)
    #expect(synced.isDirty)
    let left = try ctx.fetch(FetchDescriptor<BudgetEntity>()).filter { $0.categoryId == f.cat }
    #expect(left.count == 1)
}
