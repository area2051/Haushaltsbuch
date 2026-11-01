import Foundation
import Testing
@testable import HaushaltsbuchCore

private let nov = MonthKey(year: 2026, month: 11)
private func day(_ s: String) -> CalendarDay { CalendarDay(string: s)! }

private func tx(_ cents: Int, _ kind: Kind = .expense, cat: UUID = UUID(), day d: String = "2026-11-10",
                by: UUID = UUID()) -> TxValue {
    TxValue(id: UUID(), amountCents: cents, kind: kind, categoryId: cat, day: day(d), paidBy: by, note: nil)
}

private func cat(_ sort: Int, kind: Kind = .expense, archived: Bool = false) -> CategoryValue {
    CategoryValue(id: UUID(), name: "C\(sort)", icon: "tag", color: "#000000", kind: kind,
                  sortOrder: sort, archived: archived)
}

@Test func summaryOnlyCountsMonth() {
    let txs = [
        tx(1000, .income, day: "2026-11-01"),
        tx(250, .expense, day: "2026-11-30"),
        tx(300, .expense, day: "2026-11-15"),
        tx(9999, .income, day: "2026-10-31"),
        tx(9999, .expense, day: "2026-12-01"),
    ]
    let s = Analytics.summary(txs, month: nov)
    #expect(s == MonthSummary(incomeCents: 1000, expenseCents: 550))
    #expect(s.balanceCents == 450)
    #expect(Analytics.summary([], month: nov).balanceCents == 0)
}

@Test func expensesByCategoryIgnoresIncomeAndSortsDescending() {
    let a = UUID(), b = UUID(), c = UUID()
    let txs = [
        tx(100, cat: a), tx(200, cat: a),
        tx(500, cat: b),
        tx(50, cat: c),
        tx(9000, .income, cat: c),
        tx(7000, cat: a, day: "2026-10-31"),
    ]
    let r = Analytics.expensesByCategory(txs, month: nov)
    #expect(r == [CategoryTotal(categoryId: b, cents: 500),
                  CategoryTotal(categoryId: a, cents: 300),
                  CategoryTotal(categoryId: c, cents: 50)])
}

@Test func expensesByPersonGroupsByPaidBy() {
    let u1 = UUID(), u2 = UUID()
    let txs = [tx(100, by: u1), tx(300, by: u2), tx(250, by: u1),
               tx(5000, .income, by: u2), tx(5000, day: "2026-10-01", by: u2)]
    let r = Analytics.expensesByPerson(txs, month: nov)
    #expect(r == [PersonTotal(userId: u1, cents: 350), PersonTotal(userId: u2, cents: 300)])
}

@Test func budgetLevelsAtThresholds() {
    func level(_ spent: Int) -> BudgetProgress.Level {
        let c = UUID()
        let p = Analytics.budgetProgress([BudgetValue(categoryId: c, monthlyLimitCents: 100)],
                                         txs: [tx(spent, cat: c)], month: nov)
        return p[0].level
    }
    #expect(level(79) == .ok)
    #expect(level(80) == .warning)
    #expect(level(99) == .warning)
    #expect(level(100) == .exceeded)
    #expect(level(150) == .exceeded)
    #expect(level(0) == .ok)
}

@Test func budgetProgressValuesAndScope() {
    let c = UUID(), other = UUID()
    let txs = [tx(300, cat: c), tx(200, cat: c), tx(999, .income, cat: c),
               tx(999, cat: c, day: "2026-10-31"), tx(999, cat: other)]
    let p = Analytics.budgetProgress([BudgetValue(categoryId: c, monthlyLimitCents: 1000)], txs: txs, month: nov)
    #expect(p.count == 1)
    #expect(p[0].categoryId == c)
    #expect(p[0].spentCents == 500)
    #expect(p[0].limitCents == 1000)
    #expect(p[0].ratio == 0.5)
}

@Test func rankCategoriesUsesLast90DaysThenSortOrder() {
    let today = day("2026-11-01")
    let a = cat(1), b = cat(2), c = cat(3), d = cat(4)
    let txs = [
        tx(1, cat: c.id, day: "2026-11-01"),            // heute zählt
        tx(1, cat: c.id, day: "2026-08-04"),            // vor 89 Tagen zählt
        tx(1, cat: b.id, day: "2026-11-01"),
        tx(1, cat: a.id, day: "2026-08-03"),            // vor 90 Tagen zählt nicht
        tx(1, cat: a.id, day: "2026-07-31"),            // vor 93 Tagen zählt nicht
        tx(1, cat: a.id, day: "2026-11-02"),            // Zukunft zählt nicht
    ]
    let r = Analytics.rankCategories([a, b, c, d], txs: txs, kind: .expense, today: today)
    #expect(r.map(\.id) == [c.id, b.id, a.id, d.id])
}

@Test func rankCategoriesExcludesArchivedAndOtherKind() {
    let e1 = cat(2), e2 = cat(1), arch = cat(0, archived: true), inc = cat(3, kind: .income)
    let txs = [tx(1, cat: arch.id), tx(1, cat: arch.id), tx(1, .income, cat: inc.id)]
    let r = Analytics.rankCategories([e1, e2, arch, inc], txs: txs, kind: .expense, today: day("2026-11-01"))
    #expect(r.map(\.id) == [e2.id, e1.id])
    let ri = Analytics.rankCategories([e1, e2, arch, inc], txs: txs, kind: .income, today: day("2026-11-01"))
    #expect(ri.map(\.id) == [inc.id])
}
