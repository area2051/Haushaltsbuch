import Foundation
import HaushaltsbuchCore
import HaushaltsbuchData

/// Filter der Buchungsliste.
struct TransactionFilter: Equatable {
    var search = ""
    var categoryId: UUID?
    var paidBy: UUID?
    var kind: Kind?

    var isActive: Bool { categoryId != nil || paidBy != nil || kind != nil }
}

/// Reine Logik der Buchungsliste: Filtern und Gruppieren nach Tag.
enum TransactionListModel {
    /// Gelöschte Buchungen ausgeschlossen (TxValue kennt kein Löschkennzeichen).
    static func activeValues(of entities: [TransactionEntity]) -> [TxValue] {
        entities.filter { !$0.deleted }.map(\.value)
    }

    /// Absteigend nach Tag (innerhalb eines Tags Reihenfolge der Eingabe). Suche: case-insensitiv in
    /// Notiz und Kategorie-Label („Wohnen · Strom“). Filter auf eine Hauptkategorie umfasst ihre
    /// Unterkategorien, auf eine Unterkategorie nur diese.
    static func sections(_ txs: [TxValue], filter: TransactionFilter,
                         tree: CategoryTree) -> [(day: CalendarDay, items: [TxValue])] {
        let query = filter.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = txs.filter { tx in
            if let kind = filter.kind, tx.kind != kind { return false }
            if let id = filter.categoryId, tx.categoryId != id, tree.rootOf(tx.categoryId) != id { return false }
            if let id = filter.paidBy, tx.paidBy != id { return false }
            guard !query.isEmpty else { return true }
            let fields = [tx.note ?? "", tree.byId[tx.categoryId] != nil ? tree.label(tx.categoryId) : ""]
            return fields.contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        var order: [CalendarDay] = []
        var groups: [CalendarDay: [TxValue]] = [:]
        for tx in matching {
            if groups[tx.day] == nil { order.append(tx.day) }
            groups[tx.day, default: []].append(tx)
        }
        return order.sorted(by: >).map { (day: $0, items: groups[$0]!) }
    }

    /// Kategorien für den Filter, nach Label sortiert (Unterkategorien folgen ihrer Hauptkategorie).
    static func filterOptions(_ tree: CategoryTree) -> [(id: UUID, label: String)] {
        tree.byId.keys.map { (id: $0, label: tree.label($0)) }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    /// „Montag, 2. November“; Jahr nur, wenn nicht das aktuelle.
    static func header(for day: CalendarDay, today: CalendarDay = .today()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))!
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.dateFormat = day.year == today.year ? "EEEE, d. MMMM" : "EEEE, d. MMMM yyyy"
        return f.string(from: date)
    }
}
