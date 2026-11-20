import Foundation
import Testing
import HaushaltsbuchCore
import HaushaltsbuchData
@testable import HaushaltsbuchUI

private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d)! }

// MARK: Export

@Test func exportRanges() {
    let today = day(2026, 3, 15)
    #expect(ExportPeriod.thisMonth.range(today: today) == ExportRange(from: day(2026, 3, 1), to: day(2026, 3, 31)))
    #expect(ExportPeriod.lastMonth.range(today: today) == ExportRange(from: day(2026, 2, 1), to: day(2026, 2, 28)))
    #expect(ExportPeriod.lastMonth.range(today: day(2026, 1, 10)) == ExportRange(from: day(2025, 12, 1), to: day(2025, 12, 31)))
    #expect(ExportPeriod.thisYear.range(today: today) == ExportRange(from: day(2026, 1, 1), to: day(2026, 12, 31)))
    #expect(ExportPeriod.custom.range(today: today, customFrom: day(2026, 1, 5), customTo: day(2026, 2, 6))
            == ExportRange(from: day(2026, 1, 5), to: day(2026, 2, 6)))
    #expect(ExportPeriod.custom.range(today: today, customFrom: day(2026, 2, 6), customTo: day(2026, 1, 5)) == nil)
    #expect(ExportPeriod.allCases.map(\.title) == ["Dieser Monat", "Letzter Monat", "Dieses Jahr", "Frei"])
}

@Test func exportWritesTemporaryCSVFile() throws {
    let cat = CategoryValue(id: UUID(), name: "Essen", icon: "cart", color: "#4CAF50", kind: .expense, sortOrder: 0, archived: false)
    let anna = UUID()
    let txs = [TxValue(id: UUID(), amountCents: 1250, kind: .expense, categoryId: cat.id, day: day(2026, 11, 2), paidBy: anna, note: "Brot"),
               TxValue(id: UUID(), amountCents: 999, kind: .expense, categoryId: cat.id, day: day(2026, 10, 31), paidBy: anna, note: nil)]
    let range = ExportRange(from: day(2026, 11, 1), to: day(2026, 11, 30))
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ExportTest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let old = try ExportModel.writeFile(txs: txs, categories: [cat], members: [anna: "Anna"],
                                        range: ExportRange(from: day(2026, 10, 1), to: day(2026, 10, 31)), directory: dir)
    let url = try ExportModel.writeFile(txs: txs, categories: [cat], members: [anna: "Anna"], range: range, directory: dir)
    // Vor jedem Export werden ältere Dateien gelöscht.
    #expect(!FileManager.default.fileExists(atPath: old.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == [url.lastPathComponent])
    #expect(url.lastPathComponent == "Haushaltsbuch_2026-11-01_2026-11-30.csv")
    let data = try Data(contentsOf: url)
    #expect(data == CSVExport.make(txs, tree: CategoryTree([cat]), members: [anna: "Anna"],
                                   from: range.from, to: range.to))
    #expect(ExportModel.rowCount(txs: txs, range: range) == 1)
}

// MARK: Kategorien

@Test func categoryNameValidation() {
    #expect(CategoryForm.validationMessage(name: "   ") == "Bitte einen Namen eingeben.")
    #expect(CategoryForm.validationMessage(name: String(repeating: "a", count: 41)) == "Der Name darf höchstens 40 Zeichen lang sein.")
    #expect(CategoryForm.validationMessage(name: " " + String(repeating: "a", count: 40) + " ") == nil)
    #expect(CategoryForm.symbols.count >= 30)
    #expect(Set(CategoryForm.symbols).count == CategoryForm.symbols.count)
    #expect(CategoryForm.palette.count == 12)
    #expect(Set(CategoryForm.palette).count == 12)
    #expect(CategoryForm.palette.allSatisfy { $0.hasPrefix("#") && $0.count == 7 })
}

@Test func categoryRemovalMessages() {
    #expect(CategoryForm.removalMessage(archived: true) == "Kategorie archiviert – sie wird in alten Buchungen weiter angezeigt.")
    #expect(CategoryForm.removalMessage(archived: false) == "Kategorie gelöscht.")
}

// MARK: Wiederkehrende

@Test func ruleLabels() {
    #expect(RuleFormat.nextDue(day(2026, 12, 1)) == "Nächster Termin: 01.12.2026")
    #expect(RuleFormat.nextDue(nil) == "Nächster Termin: wird vom Server berechnet")
}

// MARK: Mitglieder

@Test func memberErrorMessages() {
    #expect(MembersModel.message(for: APIError.server(code: "username_taken", message: "x")) == "Benutzername ist bereits vergeben.")
    #expect(MembersModel.message(for: APIError.server(code: "last_admin", message: "x"))
            == "Der letzte Admin kann nicht entfernt oder herabgestuft werden.")
    #expect(MembersModel.message(for: APIError.server(code: "cannot_delete_self", message: "x")) == "Du kannst dich nicht selbst entfernen.")
    #expect(MembersModel.message(for: APIError.unreachable) == "Nur mit Verbindung zum Server möglich")
    #expect(MembersModel.message(for: APIError.server(code: "forbidden", message: "x")) == "Dafür fehlen dir die Rechte.")
}

@Test func memberFormValidation() {
    #expect(MembersModel.validationMessage(username: "Bert", displayName: "Bert", password: "geheim123")
            == "Benutzername: 3–32 Zeichen, nur a–z, 0–9, Punkt, Unterstrich, Bindestrich.")
    #expect(MembersModel.validationMessage(username: "bert", displayName: " ", password: "geheim123") == "Bitte einen Anzeigenamen eingeben.")
    #expect(MembersModel.validationMessage(username: "bert", displayName: "Bert", password: "kurz") == "Das Passwort muss mindestens 8 Zeichen haben.")
    #expect(MembersModel.validationMessage(username: "bert.k-1_", displayName: "Bert", password: "geheim123") == nil)
    #expect(MembersModel.validationMessage(displayName: "Bert", password: "") == nil)     // Bearbeiten: Passwort optional
    #expect(MembersModel.validationMessage(displayName: "Bert", password: "kurz") == "Das Passwort muss mindestens 8 Zeichen haben.")
}

// MARK: Server & Sync, Abmelden

@Test func serverStatusTexts() {
    #expect(ServerStatusText.status(.idle) == "Noch nicht synchronisiert")
    #expect(ServerStatusText.status(.syncing) == "Synchronisiert …")
    #expect(ServerStatusText.status(.offline(pending: 2)) == "Server nicht erreichbar")
    #expect(ServerStatusText.status(.error("Kaputt", pending: 0)) == "Fehler: Kaputt")
    #expect(ServerStatusText.status(.upToDate(Date())).hasPrefix("Aktuell (zuletzt "))
    #expect(ServerStatusText.pending(0) == "Keine ausstehenden Änderungen")
    #expect(ServerStatusText.pending(1) == "1 ausstehende Änderung")
    #expect(ServerStatusText.pending(3) == "3 ausstehende Änderungen")
    #expect(ServerStatusText.logoutWarning(1) == "1 ungesendete Änderung geht verloren")
    #expect(ServerStatusText.logoutWarning(3) == "3 ungesendete Änderungen gehen verloren")
    #expect(ServerStatusText.logoutDetail(1) == "1 Änderung konnte nicht übertragen werden und geht beim Abmelden verloren.")
    #expect(ServerStatusText.logoutDetail(3) == "3 Änderungen konnten nicht übertragen werden und gehen beim Abmelden verloren.")
}

// MARK: Unterkategorien verwalten

private func cv(_ name: String, kind: Kind = .expense, parent: UUID? = nil, sort: Int = 0, archived: Bool = false) -> CategoryValue {
    CategoryValue(id: UUID(), name: name, icon: "tag", color: "#112233", kind: kind, sortOrder: sort, archived: archived,
                  parentId: parent)
}

@Test func parentOptionsAreActiveSameKindMainCategoriesOtherThanItself() {
    let a = cv("A", sort: 0), b = cv("B", sort: 1), inc = cv("Inc", kind: .income), old = cv("Alt", archived: true)
    let kid = cv("Kind", parent: a.id)
    let all = [a, b, inc, old, kid]
    #expect(CategoryForm.parentOptions(for: b, all: all, kind: .expense).map(\.id) == [a.id])
    #expect(CategoryForm.parentOptions(for: nil, all: all, kind: .expense).map(\.id) == [a.id, b.id])
    #expect(CategoryForm.parentOptions(for: a, all: all, kind: .expense).isEmpty)   // hat selbst Kinder
    #expect(CategoryForm.parentOptions(for: kid, all: all, kind: .expense).map(\.id) == [a.id, b.id])
    #expect(CategoryForm.parentOptions(for: nil, all: all, kind: .income).map(\.id) == [inc.id])
}

@Test func budgetHintWhenMovingUnderAParent() {
    let food = cv("Essen"), home = cv("Wohnen")
    let own = BudgetValue(categoryId: food.id, monthlyLimitCents: 100)
    let parents = BudgetValue(categoryId: home.id, monthlyLimitCents: 100)
    #expect(CategoryForm.budgetHint(for: food, parent: home, budgets: []) == nil)
    #expect(CategoryForm.budgetHint(for: food, parent: nil, budgets: [own]) == nil)
    #expect(CategoryForm.budgetHint(for: food, parent: home, budgets: [own]) == "Das Budget geht auf Wohnen über.")
    #expect(CategoryForm.budgetHint(for: food, parent: home, budgets: [own, parents])
            == "Das Budget dieser Kategorie wird gelöscht, weil Wohnen schon eins hat.")
    let kid = cv("Kind", parent: home.id)
    #expect(CategoryForm.budgetHint(for: kid, parent: home, budgets: [BudgetValue(categoryId: kid.id, monthlyLimitCents: 1), parents]) == nil)
}

@Test func removalIsBlockedWhileChildrenExist() {
    let home = cv("Wohnen"), kid = cv("Strom", parent: home.id)
    #expect(CategoryForm.hasChildren(home.id, in: [home, kid]))
    #expect(!CategoryForm.hasChildren(kid.id, in: [home, kid]))
    #expect(CategoryForm.removalBlockedText == "Erst Unterkategorien entfernen")
}

@Test func categoryListIndentsChildrenAndTreatsChildrenOfArchivedParentsAsArchived() {
    let home = cv("Wohnen", sort: 1), food = cv("Essen", sort: 0)
    let power = cv("Strom", parent: home.id, sort: 1), water = cv("Wasser", parent: home.id, sort: 0)
    let gas = cv("Gas", parent: home.id, sort: 2, archived: true)
    let old = cv("Alt", sort: 2, archived: true), oldKid = cv("Kind", parent: old.id)
    let inc = cv("Gehalt", kind: .income)
    let all = [home, food, power, water, gas, old, oldKid, inc]
    let rows = CategoryList.activeRows(all, kind: .expense)
    #expect(rows.map(\.category.name) == ["Essen", "Wohnen", "Wasser", "Strom"])
    #expect(rows.map(\.isChild) == [false, false, true, true])
    #expect(CategoryList.archived(all, kind: .expense).map(\.name) == ["Alt", "Kind", "Gas"])
}

@Test func reorderingKeepsChildrenUnderTheirParent() {
    let a = cv("A", sort: 0), b = cv("B", sort: 1), c = cv("C", sort: 2)
    let a1 = cv("A1", parent: a.id, sort: 0), a2 = cv("A2", parent: a.id, sort: 1)
    let rows = CategoryList.activeRows([a, b, c, a1, a2], kind: .expense)   // A, A1, A2, B, C
    let names = { (ids: [UUID]?) in ids?.map { id in [a, b, c, a1, a2].first { $0.id == id }!.name } }
    // Hauptkategorie wandert mit ihren Kindern.
    #expect(names(CategoryList.reordered(rows, from: [0], to: 4)) == ["B", "A", "A1", "A2", "C"])
    #expect(names(CategoryList.reordered(rows, from: [4], to: 0)) == ["C", "A", "A1", "A2", "B"])
    // Ziel mitten in einer Kinderliste: hinter die Hauptkategorie samt Kindern.
    #expect(names(CategoryList.reordered(rows, from: [3], to: 2)) == ["A", "A1", "A2", "B", "C"])
    // Unterkategorien nur innerhalb ihrer Geschwister.
    #expect(names(CategoryList.reordered(rows, from: [2], to: 1)) == ["A", "A2", "A1", "B", "C"])
    #expect(CategoryList.reordered(rows, from: [1], to: 5) == nil)
    #expect(CategoryList.reordered(rows, from: [1], to: 0) == nil)
}
