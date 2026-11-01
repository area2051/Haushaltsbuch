import Foundation
import Testing
@testable import HaushaltsbuchCore

private let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
private let header = "Datum;Art;Kategorie;Betrag;Notiz;Bezahlt von"
private let catId = UUID(), userId = UUID()
private let cats = [catId: CategoryValue(id: catId, name: "Lebensmittel", icon: "cart", color: "#fff",
                                         kind: .expense, sortOrder: 0, archived: false)]
private let members = [userId: "Anna"]

private func tx(_ cents: Int, _ day: String, kind: Kind = .expense, cat: UUID = catId, by: UUID = userId,
                note: String? = nil) -> TxValue {
    TxValue(id: UUID(), amountCents: cents, kind: kind, categoryId: cat, day: CalendarDay(string: day)!,
            paidBy: by, note: note)
}

private func csv(_ txs: [TxValue], from: String = "2026-01-01", to: String = "2026-12-31") -> String {
    let data = CSVExport.make(txs, categories: cats, members: members,
                              from: CalendarDay(string: from)!, to: CalendarDay(string: to)!)
    #expect(Array(data.prefix(3)) == bom)
    return String(decoding: data.dropFirst(3), as: UTF8.self)
}

@Test func startsWithBOMAndHeader() {
    let data = CSVExport.make([], categories: [:], members: [:],
                              from: CalendarDay(string: "2026-11-01")!, to: CalendarDay(string: "2026-11-30")!)
    #expect(Array(data.prefix(3)) == bom)
    #expect(String(decoding: data.dropFirst(3), as: UTF8.self) == header + "\r\n")
}

@Test func formatsRowGerman() {
    let out = csv([tx(1250, "2026-11-01", note: "Wocheneinkauf"),
                   tx(123456, "2026-11-02", kind: .income)])
    #expect(out == header + "\r\n"
        + "01.11.2026;Ausgabe;Lebensmittel;12,50;Wocheneinkauf;Anna\r\n"
        + "02.11.2026;Einnahme;Lebensmittel;1234,56;;Anna\r\n")
}

@Test func formatsSmallAmountsAndSortsByDate() {
    let out = csv([tx(5, "2026-11-03"), tx(100, "2026-02-01"), tx(7, "2026-11-03")])
    let lines = out.components(separatedBy: "\r\n")
    #expect(lines[1].hasPrefix("01.02.2026;Ausgabe;Lebensmittel;1,00;"))
    #expect(lines[2].contains(";0,05;"))
    #expect(lines[3].contains(";0,07;"))   // stabil bei gleichem Datum
}

@Test func escapesSemicolonQuoteAndNewline() {
    let out = csv([tx(100, "2026-11-01", note: "a;b"),
                   tx(100, "2026-11-02", note: "sag \"hi\""),
                   tx(100, "2026-11-03", note: "zwei\nZeilen")])
    #expect(out.contains(";\"a;b\";"))
    #expect(out.contains(";\"sag \"\"hi\"\"\";"))
    #expect(out.contains(";\"zwei\nZeilen\";"))
}

@Test func quotesCRLFInNote() {
    #expect(csv([tx(100, "2026-11-01", note: "a\r\nb")]).contains(";\"a\r\nb\";"))
}

@Test func unknownCategoryAndPersonAreEmpty() {
    let out = csv([tx(100, "2026-11-01", cat: UUID(), by: UUID())])
    #expect(out.contains("01.11.2026;Ausgabe;;1,00;;\r\n"))
}

@Test func filtersRangeInclusive() {
    let out = csv([tx(1, "2026-10-31"), tx(2, "2026-11-01"), tx(3, "2026-11-30"), tx(4, "2026-12-01")],
                  from: "2026-11-01", to: "2026-11-30")
    let lines = out.components(separatedBy: "\r\n").filter { !$0.isEmpty }
    #expect(lines.count == 3)
    #expect(lines[1].hasPrefix("01.11.2026"))
    #expect(lines[2].hasPrefix("30.11.2026"))
}

@Test func fileNameUsesRange() {
    #expect(CSVExport.fileName(from: CalendarDay(string: "2026-11-01")!, to: CalendarDay(string: "2026-11-30")!)
            == "Haushaltsbuch_2026-11-01_2026-11-30.csv")
}
