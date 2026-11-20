import Foundation
import SwiftData
import Testing
import HaushaltsbuchCore
import HaushaltsbuchData
@testable import HaushaltsbuchUI

private let anna = UUID(uuidString: "0F8FAD5B-D9CB-469F-A165-70867728950E")!
private let bert = UUID(uuidString: "7C9E6679-7425-40DE-944B-E07FC1F90AE7")!
private let foodId = UUID()
private let rentId = UUID()
private let salaryId = UUID()

private let powerId = UUID()
private let waterId = UUID()

private let categories = CategoryTree([
    CategoryValue(id: foodId, name: "Lebensmittel", icon: "cart", color: "#4CAF50", kind: .expense, sortOrder: 0, archived: false),
    CategoryValue(id: rentId, name: "Wohnen", icon: "house", color: "#795548", kind: .expense, sortOrder: 1, archived: false),
    CategoryValue(id: salaryId, name: "Gehalt", icon: "banknote", color: "#009688", kind: .income, sortOrder: 0, archived: false),
    CategoryValue(id: powerId, name: "Strom", icon: "bolt", color: "#795548", kind: .expense, sortOrder: 0, archived: false,
                  parentId: rentId),
    CategoryValue(id: waterId, name: "Wasser", icon: "drop", color: "#795548", kind: .expense, sortOrder: 1, archived: false,
                  parentId: rentId),
])

private func tx(_ cents: Int, _ day: Int, cat: UUID = foodId, kind: Kind = .expense, by: UUID = anna,
                note: String? = nil) -> TxValue {
    TxValue(id: UUID(), amountCents: cents, kind: kind, categoryId: cat,
            day: CalendarDay(year: 2026, month: 11, day: day)!, paidBy: by, note: note)
}

@Test func groupsByDayDescending() {
    let a = tx(100, 1), b = tx(200, 2), c = tx(300, 2), d = tx(400, 30)
    let sections = TransactionListModel.sections([a, b, d, c], filter: TransactionFilter(), tree: categories)
    #expect(sections.map(\.day.day) == [30, 2, 1])
    #expect(sections[1].items.map(\.amountCents) == [200, 300])
}

@Test func searchMatchesNoteAndCategoryName() {
    let withNote = tx(100, 1, cat: rentId, note: "Wocheneinkauf")
    let byCategory = tx(200, 2, cat: foodId, note: nil)
    let other = tx(300, 3, cat: rentId, note: "Miete")
    let all = [withNote, byCategory, other]
    func ids(_ s: String) -> [Int] {
        TransactionListModel.sections(all, filter: TransactionFilter(search: s), tree: categories)
            .flatMap(\.items).map(\.amountCents).sorted()
    }
    #expect(ids("wochen") == [100])
    #expect(ids("LEBENS") == [200])
    #expect(ids("  wohnen ") == [100, 300])
    #expect(ids("zzz").isEmpty)
    #expect(ids("") == [100, 200, 300])
}

@Test func filtersByPersonCategoryAndKind() {
    let a = tx(100, 1, cat: foodId, by: anna)
    let b = tx(200, 1, cat: rentId, by: bert)
    let c = tx(300, 1, cat: salaryId, kind: .income, by: anna)
    let all = [a, b, c]
    func amounts(_ f: TransactionFilter) -> [Int] {
        TransactionListModel.sections(all, filter: f, tree: categories).flatMap(\.items).map(\.amountCents).sorted()
    }
    #expect(amounts(TransactionFilter(paidBy: anna)) == [100, 300])
    #expect(amounts(TransactionFilter(categoryId: rentId)) == [200])
    #expect(amounts(TransactionFilter(kind: .income)) == [300])
    #expect(amounts(TransactionFilter(paidBy: anna, kind: .expense)) == [100])
}

@MainActor @Test func excludesDeleted() throws {
    let container = try ModelContainer.makeAppContainer(inMemory: true)
    let repo = Repository(context: container.mainContext)
    let cat = try repo.saveCategory(CategoryDraft(name: "Essen", icon: "cart", color: "#112233", kind: .expense))
    let keep = try repo.addTransaction(amountCents: 100, kind: .expense, categoryId: cat.id,
                                       day: CalendarDay(year: 2026, month: 11, day: 1)!, paidBy: anna, note: nil)
    let gone = try repo.addTransaction(amountCents: 200, kind: .expense, categoryId: cat.id,
                                       day: CalendarDay(year: 2026, month: 11, day: 2)!, paidBy: anna, note: nil)
    try repo.delete(gone)
    let values = TransactionListModel.activeValues(of: [keep, gone])
    #expect(values.map(\.amountCents) == [100])
    let sections = TransactionListModel.sections(values, filter: TransactionFilter(),
                                                 tree: CategoryTree([cat.value]))
    #expect(sections.flatMap(\.items).map(\.amountCents) == [100])
}

@Test func categoryFilterParentMatchesItsChildrenAChildOnlyItself() {
    let all = [tx(1, 2, cat: rentId), tx(2, 2, cat: powerId), tx(3, 2, cat: waterId), tx(4, 2, cat: foodId)]
    func only(_ id: UUID) -> [Int] {
        TransactionListModel.sections(all, filter: TransactionFilter(categoryId: id), tree: categories)
            .flatMap(\.items).map(\.amountCents).sorted()
    }
    #expect(only(rentId) == [1, 2, 3])
    #expect(only(powerId) == [2])
}

@Test func searchMatchesTheLabelOfASubcategoryBooking() {
    let all = [tx(2, 2, cat: powerId), tx(4, 2, cat: foodId)]
    func hits(_ q: String) -> [Int] {
        TransactionListModel.sections(all, filter: TransactionFilter(search: q), tree: categories)
            .flatMap(\.items).map(\.amountCents)
    }
    #expect(hits("strom") == [2])
    #expect(hits("Wohnen · Strom") == [2])
}

@Test func filterOptionsAreLabelsSortedByName() {
    #expect(TransactionListModel.filterOptions(categories).map(\.label)
            == ["Gehalt", "Lebensmittel", "Wohnen", "Wohnen · Strom", "Wohnen · Wasser"])
}

@Test func dayHeaderFormat() {
    let now = CalendarDay(year: 2026, month: 11, day: 2)!
    #expect(TransactionListModel.header(for: now, today: now) == "Montag, 2. November")
    #expect(TransactionListModel.header(for: CalendarDay(year: 2025, month: 12, day: 24)!, today: now)
            == "Mittwoch, 24. Dezember 2025")
}

// MARK: Bearbeiten

@MainActor
private struct EditFixture {
    let container: ModelContainer
    let repo: Repository
    let food: CategoryEntity
    let old: CategoryEntity
    let salary: CategoryEntity
    let entity: TransactionEntity

    init() throws {
        container = try ModelContainer.makeAppContainer(inMemory: true)
        repo = Repository(context: container.mainContext)
        food = try repo.saveCategory(CategoryDraft(name: "Lebensmittel", icon: "cart", color: "#4CAF50", kind: .expense))
        old = try repo.saveCategory(CategoryDraft(name: "Alt", icon: "tray", color: "#999999", kind: .expense))
        salary = try repo.saveCategory(CategoryDraft(name: "Gehalt", icon: "banknote", color: "#009688", kind: .income))
        entity = try repo.addTransaction(amountCents: 1250, kind: .expense, categoryId: old.id,
                                         day: CalendarDay(year: 2026, month: 11, day: 1)!, paidBy: bert, note: "Test")
        try repo.removeCategory(old) // in Benutzung -> archiviert
    }

    func model() -> TransactionEditModel {
        TransactionEditModel(transaction: entity, repository: repo, currentUserId: anna)
    }
}

@MainActor @Test func editModelPrefillsAndKeepsArchivedCategory() throws {
    let f = try EditFixture()
    let m = f.model()
    #expect(m.amount.cents == 1250)
    #expect(m.kind == .expense)
    #expect(m.note == "Test")
    #expect(m.categoryId == f.old.id)
    #expect(Set(m.categories.map(\.name)) == ["Lebensmittel", "Alt"])
    #expect(m.canSave)
    m.kind = .income
    #expect(m.categories.map(\.name) == ["Gehalt"])
    #expect(m.categoryId == nil)
    #expect(!m.canSave)
}

@MainActor @Test func editModelPayerOptionsIncludeAssignedPayer() throws {
    let f = try EditFixture()
    let m = f.model()
    #expect(m.payerOptions.map(\.id).contains(bert))
    #expect(m.payerOptions.map(\.id).contains(anna))
}

@MainActor @Test func editModelSaveUpdatesTransaction() throws {
    let f = try EditFixture()
    let m = f.model()
    m.amount.clear()
    for d in [9, 9] { m.amount.append(digit: d) }
    m.categoryId = f.food.id
    m.note = "  "
    try m.save()
    #expect(f.entity.amountCents == 99)
    #expect(f.entity.categoryId == f.food.id)
    #expect(f.entity.note == nil)
    #expect(f.entity.isDirty)
}

@MainActor @Test func editModelDeleteSoftDeletes() throws {
    let f = try EditFixture()
    try f.model().delete()
    #expect(f.entity.deleted)
    #expect(f.repo.activeTransactions().isEmpty)
}

@MainActor @Test func editModelRejectsInvalidAmount() throws {
    let f = try EditFixture()
    let m = f.model()
    m.amount.clear()
    #expect(!m.canSave)
    #expect(throws: (any Error).self) { try m.save() }
    #expect(f.entity.amountCents == 1250)
}

// MARK: Final-Review: gelöscht, während das Formular offen ist

@MainActor @Test func editModelRefusesWhenTransactionWasHardDeleted() throws {
    let f = try EditFixture()
    let m = f.model()
    #expect(!m.isGone)
    // z. B. Verwerfen einer abgelehnten, nie synchronisierten Buchung oder Full-Resync.
    f.container.mainContext.delete(f.entity)
    try f.container.mainContext.save()
    #expect(m.isGone)
    #expect(throws: TransactionEditModel.SaveError.gone) { try m.save() }
    #expect(throws: TransactionEditModel.SaveError.gone) { try m.delete() }
}

@MainActor @Test func editModelRefusesWhenTransactionWasSoftDeletedBySync() throws {
    let f = try EditFixture()
    let m = f.model()
    f.entity.deleted = true
    try f.container.mainContext.save()
    #expect(m.isGone)
    #expect(throws: TransactionEditModel.SaveError.gone) { try m.save() }
}

@Test func noteLimitClampsTo200Utf16Units() {
    #expect(NoteLimit.clamp(String(repeating: "a", count: 250)).count == 200)
    #expect(NoteLimit.clamp("kurz") == "kurz")
    let emoji = String(repeating: "😀", count: 150)  // je 2 UTF-16-Einheiten
    #expect(NoteLimit.clamp(emoji).utf16.count == 200)
    #expect(NoteLimit.normalized("   ") == nil)
    #expect(NoteLimit.normalized("  x ") == "x")
}

@MainActor @Test func editModelSaveClampsNote() throws {
    let f = try EditFixture()
    let m = f.model()
    m.note = String(repeating: "b", count: 300)
    try m.save()
    #expect(f.entity.note?.count == 200)
}

@Test func rejectionReasonsAreGerman() {
    #expect(RejectionText.german("category_in_use") == "Kategorie wird noch verwendet.")
    #expect(RejectionText.german("unknown_user") == "Person existiert nicht mehr.")
    #expect(RejectionText.german("foreign_key_violation") == "Verweis auf nicht vorhandene Daten.")
    #expect(RejectionText.german("unique_violation") == "Eintrag existiert bereits.")
    #expect(RejectionText.german("invalid_value") == "Ungültiger Wert.")
    #expect(RejectionText.german("amount_cents must be > 0") == "Vom Server abgelehnt.")
    #expect(RejectionText.german(nil) == "Vom Server abgelehnt.")
}

// MARK: Bearbeiten mit Unterkategorien

@MainActor
private struct SubEditFixture {
    let container: ModelContainer
    let repo: Repository
    let food: CategoryEntity
    let home: CategoryEntity
    let power: CategoryEntity
    let gas: CategoryEntity

    init() throws {
        container = try ModelContainer.makeAppContainer(inMemory: true)
        repo = Repository(context: container.mainContext)
        food = try repo.saveCategory(CategoryDraft(name: "Lebensmittel", icon: "cart", color: "#4CAF50", kind: .expense))
        home = try repo.saveCategory(CategoryDraft(name: "Wohnen", icon: "house", color: "#795548", kind: .expense))
        power = try repo.saveCategory(CategoryDraft(name: "Strom", icon: "bolt", color: "#000000", kind: .expense, parentId: home.id))
        gas = try repo.saveCategory(CategoryDraft(name: "Gas", icon: "flame", color: "#000000", kind: .expense, parentId: home.id))
    }

    func model(on category: CategoryEntity) throws -> (TransactionEditModel, TransactionEntity) {
        let tx = try repo.addTransaction(amountCents: 6000, kind: .expense, categoryId: category.id,
                                         day: CalendarDay(year: 2026, month: 11, day: 2)!, paidBy: anna, note: nil)
        return (TransactionEditModel(transaction: tx, repository: repo, currentUserId: anna), tx)
    }
}

@MainActor @Test func editingASubcategoryBookingPreselectsParentAndChip() throws {
    let f = try SubEditFixture()
    let (m, tx) = try f.model(on: f.power)
    #expect(m.categories.map(\.name) == ["Lebensmittel", "Wohnen"])
    #expect(m.mainId == f.home.id)
    #expect(m.categoryId == f.power.id)
    #expect(m.chipOptions.map(\.name) == ["Allgemein", "Strom", "Gas"])
    #expect(m.canSave)
    // Chips setzen nur den Wert; gespeichert wird mit „Sichern“.
    m.categoryId = f.home.id
    #expect(tx.categoryId == f.power.id)
    try m.save()
    #expect(tx.categoryId == f.home.id)
}

@MainActor @Test func pickingAnotherMainCategoryStartsAtAllgemein() throws {
    let f = try SubEditFixture()
    let (m, _) = try f.model(on: f.power)
    m.selectMain(f.home.id)          // gleiche Hauptkategorie: Unterkategorie bleibt
    #expect(m.categoryId == f.power.id)
    m.selectMain(f.food.id)
    #expect(m.categoryId == f.food.id)
    #expect(m.chipOptions.isEmpty)
    m.selectMain(f.home.id)
    #expect(m.categoryId == f.home.id)
}

@MainActor @Test func anArchivedSubcategoryStaysVisibleAsChip() throws {
    let f = try SubEditFixture()
    let (_, tx) = try f.model(on: f.gas)
    f.gas.archived = true
    try f.container.mainContext.save()
    let m = TransactionEditModel(transaction: tx, repository: f.repo, currentUserId: anna)
    #expect(m.chipOptions.map(\.name) == ["Allgemein", "Strom", "Gas"])
    #expect(m.canSave)
    m.categoryId = f.home.id          // auch nach dem Wechsel auf „Allgemein“ zurückwählbar
    #expect(m.chipOptions.map(\.name) == ["Allgemein", "Strom", "Gas"])
    // Archivierte Unterkategorien anderer Buchungen erscheinen nicht.
    let (other, _) = try f.model(on: f.power)
    #expect(other.chipOptions.map(\.name) == ["Allgemein", "Strom"])
}

@MainActor @Test func aChipOfAnotherParentCannotBeSaved() throws {
    let f = try SubEditFixture()
    let (m, _) = try f.model(on: f.food)
    m.categoryId = UUID()
    #expect(!m.canSave)
}
