import Foundation
import SwiftData
import Testing
import HaushaltsbuchCore
import HaushaltsbuchData
@testable import HaushaltsbuchUI

@MainActor
private struct QuickEntryFixture {
    static let me = UUID(uuidString: "0F8FAD5B-D9CB-469F-A165-70867728950E")!
    static let today = CalendarDay(year: 2026, month: 11, day: 2)!

    let container: ModelContainer
    let repository: Repository
    let food: CategoryEntity
    let rent: CategoryEntity
    let salary: CategoryEntity

    init() throws {
        container = try ModelContainer.makeAppContainer(inMemory: true)
        repository = Repository(context: container.mainContext)
        food = try repository.saveCategory(CategoryDraft(name: "Lebensmittel", icon: "cart", color: "#4CAF50", kind: .expense))
        rent = try repository.saveCategory(CategoryDraft(name: "Wohnen", icon: "house", color: "#795548", kind: .expense))
        salary = try repository.saveCategory(CategoryDraft(name: "Gehalt", icon: "banknote", color: "#009688", kind: .income))
    }

    func model() -> QuickEntryModel {
        QuickEntryModel(repository: repository, currentUserId: Self.me, today: { Self.today })
    }
}

@MainActor @Test func cannotSaveWithoutAmount() throws {
    let f = try QuickEntryFixture()
    let m = f.model()
    #expect(!m.canSave)
    m.amount.append(digit: 0)
    #expect(!m.canSave)
    m.amount.append(digit: 5)
    #expect(m.canSave)
    #expect(throws: (any Error).self) {
        let empty = f.model()
        try empty.save(category: f.food.id)
    }
    #expect(f.repository.activeTransactions().isEmpty)
}

@MainActor @Test func saveCreatesExpenseTodayPaidByMe() throws {
    let f = try QuickEntryFixture()
    let m = f.model()
    for d in [1, 2, 5, 0] { m.amount.append(digit: d) }
    try m.save(category: f.food.id)
    let tx = try #require(f.repository.activeTransactions().only)
    #expect(tx.amountCents == 1250)
    #expect(tx.kindValue == .expense)
    #expect(tx.categoryId == f.food.id)
    #expect(tx.day == QuickEntryFixture.today.string)
    #expect(tx.paidBy == QuickEntryFixture.me)
    #expect(tx.isDirty)
}

@MainActor @Test func switchingToIncomeShowsIncomeCategories() throws {
    let f = try QuickEntryFixture()
    let m = f.model()
    #expect(Set(m.categories.map(\.name)) == ["Lebensmittel", "Wohnen"])
    m.kind = .income
    #expect(m.categories.map(\.name) == ["Gehalt"])
}

@MainActor @Test func emptyNoteSavedAsNil() throws {
    let f = try QuickEntryFixture()
    let m = f.model()
    m.amount.append(digit: 7)
    m.note = "  \n "
    try m.save(category: f.food.id)
    let m2 = f.model()
    m2.amount.append(digit: 8)
    m2.note = " Wocheneinkauf "
    try m2.save(category: f.food.id)
    let notes = f.repository.activeTransactions().map(\.note)
    #expect(notes.contains(nil))
    #expect(notes.contains("Wocheneinkauf"))
}

@MainActor @Test func categoriesRankedByRecentUse() throws {
    let f = try QuickEntryFixture()
    #expect(f.model().categories.map(\.name) == ["Lebensmittel", "Wohnen"])
    try f.repository.addTransaction(amountCents: 500, kind: .expense, categoryId: f.rent.id,
                                    day: QuickEntryFixture.today, paidBy: QuickEntryFixture.me, note: nil)
    #expect(f.model().categories.map(\.name) == ["Wohnen", "Lebensmittel"])
}

@MainActor @Test func secondSaveIsNoOp() throws {
    let f = try QuickEntryFixture()
    let m = f.model()
    m.amount.append(digit: 9)
    try m.save(category: f.food.id)
    try m.save(category: f.rent.id)
    #expect(f.repository.activeTransactions().count == 1)
    #expect(!m.canSave)
}

@MainActor @Test func payerOptionsAlwaysContainCurrentUser() throws {
    let f = try QuickEntryFixture()
    let m = f.model()
    #expect(m.members.isEmpty)
    #expect(m.payerOptions.map(\.id) == [QuickEntryFixture.me])
    #expect(m.payerOptions.first?.name == "Ich")
    let other = UUID()
    f.container.mainContext.insert(MemberEntity(id: QuickEntryFixture.me, username: "a", displayName: "Anna", isAdmin: true))
    f.container.mainContext.insert(MemberEntity(id: other, username: "b", displayName: "Bert", isAdmin: false))
    try f.container.mainContext.save()
    let m2 = f.model()
    #expect(m2.payerOptions.map(\.name) == ["Anna", "Bert"])
}

@MainActor @Test func switchingKindKeepsAmount() throws {
    let f = try QuickEntryFixture()
    let m = f.model()
    m.amount.append(digit: 4)
    m.kind = .income
    #expect(m.amount.cents == 4)
}

@MainActor @Test func quickEntryNoteIsLimitedTo200Characters() throws {
    let f = try QuickEntryFixture()
    let m = f.model()
    m.amount.append(digit: 7)
    m.note = String(repeating: "x", count: 201)
    try m.save(category: f.food.id)
    #expect(f.repository.activeTransactions().first?.note?.count == 200)
}
