import Foundation
import SwiftData
import Testing
import HaushaltsbuchCore
import HaushaltsbuchData
@testable import HaushaltsbuchUI

/// `RuleEditModel` nutzt `RuleDraft.validationError()` (Regeln selbst sind in den Data-Tests geprüft).
@MainActor
private struct RuleFixture {
    let container: ModelContainer
    let repo: Repository
    let category: CategoryEntity
    let user = UUID()

    init() throws {
        container = try ModelContainer.makeAppContainer(inMemory: true)
        repo = Repository(context: container.mainContext)
        category = try repo.saveCategory(CategoryDraft(name: "Wohnen", icon: "house", color: "#3F51B5", kind: .expense))
    }

    func model(rule: RecurringRuleEntity? = nil) -> RuleEditModel {
        RuleEditModel(rule: rule, repository: repo, currentUserId: user,
                      today: CalendarDay(year: 2026, month: 11, day: 2)!)
    }

    func rules() throws -> [RecurringRuleEntity] {
        try container.mainContext.fetch(FetchDescriptor<RecurringRuleEntity>())
    }
}

@MainActor @Test func ruleDraftRejectsStartBefore2000() throws {
    let f = try RuleFixture()
    let m = f.model()
    m.amount = AmountInput(cents: 85000)
    m.categoryId = f.category.id
    m.startDate = CalendarDay(year: 1999, month: 12, day: 31)!
    #expect(m.validationMessage == "Der Start darf nicht vor dem 01.01.2000 liegen.")
    #expect(!m.canSave)
    #expect(throws: RepositoryError.self) { try m.save() }
    #expect(try f.rules().isEmpty)
}

@MainActor @Test func ruleDraftRejectsEndBeforeStart() throws {
    let f = try RuleFixture()
    let m = f.model()
    m.amount = AmountInput(cents: 85000)
    m.categoryId = f.category.id
    m.hasEndDate = true
    m.endDate = CalendarDay(year: 2026, month: 11, day: 1)!
    #expect(m.validationMessage == "Das Ende darf nicht vor dem Start liegen.")
    m.hasEndDate = false                   // ohne Ende gilt das Datum nicht
    #expect(m.validationMessage == nil)
}

@MainActor @Test func ruleEditModelDefaultsAndSave() throws {
    let f = try RuleFixture()
    let m = f.model()
    #expect(m.startDate == CalendarDay(year: 2026, month: 11, day: 2)!)
    #expect(m.frequency == .monthly)
    #expect(m.paidBy == f.user)
    #expect(m.categoryId == f.category.id)   // erste aktive Kategorie der Art
    #expect(!m.canSave)                       // Betrag fehlt
    #expect(m.validationMessage == "Bitte einen Betrag eingeben.")

    m.amount = AmountInput(cents: 85000)
    m.note = "  Miete "
    try m.save()
    let rule = try #require(try f.rules().only)
    #expect(rule.amountCents == 85000)
    #expect(rule.note == "Miete")
    #expect(rule.endDate == nil)
    #expect(rule.isDirty)

    // Bearbeiten übernimmt die Werte und ändert dieselbe Regel.
    let edit = f.model(rule: rule)
    #expect(edit.amount.cents == 85000)
    #expect(edit.note == "Miete")
    edit.frequency = .yearly
    edit.note = ""
    try edit.save()
    #expect(try f.rules().count == 1)
    #expect(rule.frequency == "yearly")
    #expect(rule.note == nil)
}

@MainActor @Test func ruleEditModelSwitchingKindPicksMatchingCategory() throws {
    let f = try RuleFixture()
    let income = try f.repo.saveCategory(CategoryDraft(name: "Gehalt", icon: "banknote", color: "#4CAF50", kind: .income))
    let m = f.model()
    m.kind = .income
    #expect(m.categoryId == income.id)
    #expect(m.categories.map(\.id) == [income.id])
}
