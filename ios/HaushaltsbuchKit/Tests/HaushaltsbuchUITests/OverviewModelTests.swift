import Foundation
import Testing
import HaushaltsbuchCore
@testable import HaushaltsbuchUI

private let anna = UUID()
private let bert = UUID()
private let ghost = UUID()
private let nov = MonthKey(year: 2026, month: 11)

private func cat(_ name: String, kind: Kind = .expense, sort: Int = 0, archived: Bool = false) -> CategoryValue {
    CategoryValue(id: UUID(), name: name, icon: "cart", color: "#4CAF50", kind: kind, sortOrder: sort, archived: archived)
}

private func tx(_ cents: Int, _ day: Int, _ c: CategoryValue, month: Int = 11, by: UUID = anna) -> TxValue {
    TxValue(id: UUID(), amountCents: cents, kind: c.kind, categoryId: c.id,
            day: CalendarDay(year: 2026, month: month, day: day)!, paidBy: by, note: nil)
}

private let members = [anna: "Anna", bert: "Bert"]

@Test func overviewWarningsOnlyWarningAndExceeded() {
    let ok = cat("Frei"), warn = cat("Essen"), over = cat("Auto")
    let txs = [tx(1000, 1, ok), tx(850, 2, warn), tx(2000, 3, over)]
    let budgets = [BudgetValue(categoryId: ok.id, monthlyLimitCents: 10000),
                   BudgetValue(categoryId: warn.id, monthlyLimitCents: 1000),
                   BudgetValue(categoryId: over.id, monthlyLimitCents: 1500)]
    let data = OverviewModel.make(txs: txs, categories: [ok, warn, over], members: members, budgets: budgets, month: nov)
    #expect(Set(data.warnings.map(\.categoryId)) == [warn.id, over.id])
    #expect(data.warnings.first?.level == .exceeded)  // schlimmste zuerst
}

@Test func recentLimitedToFiveOfMonth() {
    let c = cat("Essen")
    var txs = (1...7).map { tx(100 * $0, $0, c) }
    txs.append(tx(999, 28, c, month: 10))
    let data = OverviewModel.make(txs: txs, categories: [c], members: members, budgets: [], month: nov)
    #expect(data.recent.count == 5)
    #expect(data.recent.map(\.day.day) == [7, 6, 5, 4, 3])
    #expect(data.recent.allSatisfy { nov.contains($0.day) })
}

@Test func byPersonUsesDisplayNames() {
    let c = cat("Essen")
    let txs = [tx(500, 1, c, by: anna), tx(900, 2, c, by: bert), tx(100, 3, c, by: ghost)]
    let data = OverviewModel.make(txs: txs, categories: [c], members: members, budgets: [], month: nov)
    #expect(data.byPerson.map(\.name) == ["Bert", "Anna", "Unbekannt"])
    #expect(data.byPerson.map(\.cents) == [900, 500, 100])
}

@Test func byCategoryGroupsBeyondSixAsWeitere() {
    let cats = (0..<8).map { cat("K\($0)", sort: $0) }
    let txs = cats.enumerated().map { tx(1000 - $0.offset * 10, 1, $0.element) }
    let data = OverviewModel.make(txs: txs, categories: cats, members: members, budgets: [], month: nov)
    #expect(data.byCategory.count == 7)
    #expect(data.byCategory.last?.name == "Weitere")
    #expect(data.byCategory.last?.cents == 940 + 930)
    #expect(data.byCategory.first?.name == "K0")
}

@Test func emptyMonthIsEmpty() {
    let data = OverviewModel.make(txs: [], categories: [], members: members, budgets: [], month: nov)
    #expect(data.isEmpty)
    #expect(data.summary.balanceCents == 0)
}

@Test func budgetRowsCoverNonArchivedExpenseCategories() {
    let food = cat("Essen", sort: 1), rent = cat("Miete", sort: 0), old = cat("Alt", archived: true), pay = cat("Gehalt", kind: .income)
    let txs = [tx(12000, 3, food)]
    let rows = BudgetsModel.rows(categories: [food, rent, old, pay], budgets: [BudgetValue(categoryId: food.id, monthlyLimitCents: 30000)],
                                 txs: txs, month: nov)
    #expect(rows.map(\.category.name) == ["Miete", "Essen"])
    #expect(rows[0].progress == nil)
    #expect(rows[1].progress?.spentCents == 12000)
    #expect(rows[1].progress?.level == .ok)
    #expect(rows[1].detail == "\(Money.format(cents: 12000)) von \(Money.format(cents: 30000))")
    #expect(rows[0].detail == "Kein Budget")
}
