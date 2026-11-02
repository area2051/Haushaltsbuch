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
    let url = try ExportModel.writeFile(txs: txs, categories: [cat], members: [anna: "Anna"], range: range)
    #expect(url.lastPathComponent == "Haushaltsbuch_2026-11-01_2026-11-30.csv")
    let data = try Data(contentsOf: url)
    #expect(data == CSVExport.make(txs, categories: [cat.id: cat], members: [anna: "Anna"],
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
    #expect(RuleFormat.frequency(.weekly) == "wöchentlich")
    #expect(RuleFormat.frequency(.monthly) == "monatlich")
    #expect(RuleFormat.frequency(.yearly) == "jährlich")
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
}
