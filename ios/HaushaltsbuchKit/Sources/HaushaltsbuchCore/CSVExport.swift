import Foundation

/// CSV-Export für Excel (DE): UTF-8 mit BOM, `;`-getrennt, `\r\n`-Zeilenenden.
public enum CSVExport {
    static let header = "Datum;Art;Kategorie;Unterkategorie;Betrag;Notiz;Bezahlt von"

    /// Spalte „Kategorie“ = Hauptkategorie, „Unterkategorie“ nur bei Buchungen auf einer Unterkategorie.
    public static func make(_ txs: [TxValue], tree: CategoryTree, members: [UUID: String],
                            from: CalendarDay, to: CalendarDay) -> Data {
        let rows = txs.enumerated()
            .filter { $0.element.day >= from && $0.element.day <= to }
            .sorted { ($0.element.day, $0.offset) < ($1.element.day, $1.offset) }   // stabil
            .map { $0.element }

        var out = header + "\r\n"
        for t in rows {
            let root = tree.byId[tree.rootOf(t.categoryId)]
            let own = tree.byId[t.categoryId]
            let fields = [
                germanDate(t.day),
                t.kind == .income ? "Einnahme" : "Ausgabe",
                root?.name ?? "",
                own.flatMap { $0.id == root?.id ? nil : $0.name } ?? "",
                amount(t.amountCents),
                t.note ?? "",
                members[t.paidBy] ?? "",
            ]
            out += fields.map(escape).joined(separator: ";") + "\r\n"
        }
        return Data([0xEF, 0xBB, 0xBF]) + Data(out.utf8)
    }

    /// `Haushaltsbuch_2026-11-01_2026-11-30.csv`
    public static func fileName(from: CalendarDay, to: CalendarDay) -> String {
        "Haushaltsbuch_\(from.string)_\(to.string).csv"
    }

    private static func germanDate(_ d: CalendarDay) -> String {
        String(format: "%02d.%02d.%04d", d.day, d.month, d.year)
    }

    /// 123456 → "1234,56" (ohne Tausenderpunkt und Währungszeichen).
    private static func amount(_ cents: Int) -> String {
        let sign = cents < 0 ? "-" : ""
        let a = abs(cents)
        return sign + "\(a / 100),\(String(format: "%02d", a % 100))"
    }

    private static func escape(_ s: String) -> String {
        guard s.unicodeScalars.contains(where: { $0 == ";" || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
