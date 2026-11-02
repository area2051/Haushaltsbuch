import Foundation
import HaushaltsbuchCore

struct ChartSlice: Equatable, Identifiable {
    var id: String
    var name: String
    var colorHex: String
    var cents: Int
}

struct ChartBar: Equatable, Identifiable {
    var id: UUID
    var name: String
    var cents: Int
}

struct OverviewData: Equatable {
    var summary: MonthSummary
    var byCategory: [ChartSlice]
    var byPerson: [ChartBar]
    /// Nur .warning/.exceeded aktiver (nicht archivierter/gelöschter) Kategorien, schlimmste zuerst.
    var warnings: [BudgetProgress]
    /// Letzte 5 Buchungen des Monats (neueste zuerst).
    var recent: [TxValue]
    var hasTransactions: Bool

    var isEmpty: Bool { !hasTransactions }
}

enum OverviewModel {
    static let maxSlices = 6
    static let othersColor = "#9E9E9E"

    static func make(txs: [TxValue], categories: [CategoryValue], members: [UUID: String],
                     budgets: [BudgetValue], month: MonthKey) -> OverviewData {
        let monthTxs = txs.filter { month.contains($0.day) }
        let catById = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        let totals = Analytics.expensesByCategory(txs, month: month)
        var slices = totals.prefix(maxSlices).map { t in
            ChartSlice(id: t.categoryId.uuidString, name: catById[t.categoryId]?.name ?? "Unbekannt",
                       colorHex: catById[t.categoryId]?.color ?? othersColor, cents: t.cents)
        }
        let rest = totals.dropFirst(maxSlices).reduce(0) { $0 + $1.cents }
        if rest > 0 { slices.append(ChartSlice(id: "others", name: "Weitere", colorHex: othersColor, cents: rest)) }

        let bars = Analytics.expensesByPerson(txs, month: month).map {
            ChartBar(id: $0.userId, name: members[$0.userId] ?? "Unbekannt", cents: $0.cents)
        }

        // Nur Budgets aktiver Kategorien: archivierte/gelöschte (fehlen in `categories`) nicht warnen.
        let liveBudgets = budgets.filter { catById[$0.categoryId].map { !$0.archived } ?? false }
        let warnings = Analytics.budgetProgress(liveBudgets, txs: txs, month: month)
            .filter { $0.level != .ok }
            .sorted { $0.ratio > $1.ratio }

        let recent = monthTxs.enumerated()
            .sorted { ($0.element.day, $1.offset) > ($1.element.day, $0.offset) }
            .prefix(5).map(\.element)

        return OverviewData(summary: Analytics.summary(txs, month: month), byCategory: slices, byPerson: bars,
                            warnings: warnings, recent: Array(recent), hasTransactions: !monthTxs.isEmpty)
    }

    /// „85 % von 300,00 €“
    static func percentText(_ p: BudgetProgress) -> String {
        let pct = p.limitCents > 0 ? Int((Double(p.spentCents) / Double(p.limitCents) * 100).rounded(.down)) : 100
        return "\(pct) % von \(Money.format(cents: p.limitCents))"
    }
}

struct BudgetRowData: Equatable, Identifiable {
    var category: CategoryValue
    var progress: BudgetProgress?
    /// Vom Server abgelehntes Budget dieser Kategorie (Rohgrund).
    var rejectionReason: String? = nil
    var id: UUID { category.id }

    var detail: String {
        guard let progress else { return "Kein Budget" }
        return "\(Money.format(cents: progress.spentCents)) von \(Money.format(cents: progress.limitCents))"
    }
}

enum BudgetsModel {
    /// `budgets` höchstens eins je Kategorie (`BudgetEntity.onePerCategory`); `rejections` je Kategorie-ID.
    static func rows(categories: [CategoryValue], budgets: [BudgetValue], txs: [TxValue],
                     month: MonthKey, rejections: [UUID: String] = [:]) -> [BudgetRowData] {
        let progress = Dictionary(Analytics.budgetProgress(budgets, txs: txs, month: month).map { ($0.categoryId, $0) },
                                  uniquingKeysWith: { a, _ in a })
        return categories.filter { $0.kind == .expense && !$0.archived }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
            .map { BudgetRowData(category: $0, progress: progress[$0.id], rejectionReason: rejections[$0.id]) }
    }
}
