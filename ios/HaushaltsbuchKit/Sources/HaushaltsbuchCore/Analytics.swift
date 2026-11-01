import Foundation

/// Buchung als reiner Wert (Core kennt SwiftData nicht).
public struct TxValue: Sendable, Equatable {
    public var id: UUID
    public var amountCents: Int
    public var kind: Kind
    public var categoryId: UUID
    public var day: CalendarDay
    public var paidBy: UUID
    public var note: String?

    public init(id: UUID, amountCents: Int, kind: Kind, categoryId: UUID, day: CalendarDay, paidBy: UUID, note: String?) {
        self.id = id; self.amountCents = amountCents; self.kind = kind; self.categoryId = categoryId
        self.day = day; self.paidBy = paidBy; self.note = note
    }
}

public struct CategoryValue: Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var icon: String
    public var color: String
    public var kind: Kind
    public var sortOrder: Int
    public var archived: Bool

    public init(id: UUID, name: String, icon: String, color: String, kind: Kind, sortOrder: Int, archived: Bool) {
        self.id = id; self.name = name; self.icon = icon; self.color = color
        self.kind = kind; self.sortOrder = sortOrder; self.archived = archived
    }
}

public struct BudgetValue: Sendable, Equatable {
    public var categoryId: UUID
    public var monthlyLimitCents: Int

    public init(categoryId: UUID, monthlyLimitCents: Int) {
        self.categoryId = categoryId; self.monthlyLimitCents = monthlyLimitCents
    }
}

public struct MonthSummary: Equatable, Sendable {
    public var incomeCents: Int
    public var expenseCents: Int
    public var balanceCents: Int { incomeCents - expenseCents }

    public init(incomeCents: Int, expenseCents: Int) {
        self.incomeCents = incomeCents; self.expenseCents = expenseCents
    }
}

public struct CategoryTotal: Equatable, Sendable {
    public var categoryId: UUID
    public var cents: Int
    public init(categoryId: UUID, cents: Int) { self.categoryId = categoryId; self.cents = cents }
}

public struct PersonTotal: Equatable, Sendable {
    public var userId: UUID
    public var cents: Int
    public init(userId: UUID, cents: Int) { self.userId = userId; self.cents = cents }
}

public struct BudgetProgress: Equatable, Sendable {
    public enum Level: Sendable, Equatable { case ok, warning, exceeded }

    public var categoryId: UUID
    public var spentCents: Int
    public var limitCents: Int

    public init(categoryId: UUID, spentCents: Int, limitCents: Int) {
        self.categoryId = categoryId; self.spentCents = spentCents; self.limitCents = limitCents
    }

    /// spent / limit; bei Limit <= 0 gilt: 0 ohne Ausgaben, sonst unendlich.
    public var ratio: Double {
        guard limitCents > 0 else { return spentCents > 0 ? .infinity : 0 }
        return Double(spentCents) / Double(limitCents)
    }

    /// .ok < 80 %, .warning >= 80 %, .exceeded >= 100 % (exakte Ganzzahlvergleiche).
    public var level: Level {
        guard limitCents > 0 else { return spentCents > 0 ? .exceeded : .ok }
        if spentCents >= limitCents { return .exceeded }
        if spentCents * 5 >= limitCents * 4 { return .warning }
        return .ok
    }
}

public enum Analytics {
    public static func summary(_ txs: [TxValue], month: MonthKey) -> MonthSummary {
        var income = 0, expense = 0
        for t in txs where month.contains(t.day) {
            switch t.kind {
            case .income: income += t.amountCents
            case .expense: expense += t.amountCents
            }
        }
        return MonthSummary(incomeCents: income, expenseCents: expense)
    }

    /// Ausgaben des Monats je Kategorie, absteigend nach Betrag (Gleichstand: UUID-String für Stabilität).
    public static func expensesByCategory(_ txs: [TxValue], month: MonthKey) -> [CategoryTotal] {
        var sums: [UUID: Int] = [:]
        for t in txs where t.kind == .expense && month.contains(t.day) { sums[t.categoryId, default: 0] += t.amountCents }
        return sums.map { CategoryTotal(categoryId: $0.key, cents: $0.value) }
            .sorted { ($0.cents, $1.categoryId.uuidString) > ($1.cents, $0.categoryId.uuidString) }
    }

    /// Ausgaben des Monats je Zahler, absteigend nach Betrag.
    public static func expensesByPerson(_ txs: [TxValue], month: MonthKey) -> [PersonTotal] {
        var sums: [UUID: Int] = [:]
        for t in txs where t.kind == .expense && month.contains(t.day) { sums[t.paidBy, default: 0] += t.amountCents }
        return sums.map { PersonTotal(userId: $0.key, cents: $0.value) }
            .sorted { ($0.cents, $1.userId.uuidString) > ($1.cents, $0.userId.uuidString) }
    }

    /// Fortschritt je Budget (Reihenfolge der Eingabe) anhand der Ausgaben des Monats.
    public static func budgetProgress(_ budgets: [BudgetValue], txs: [TxValue], month: MonthKey) -> [BudgetProgress] {
        var spent: [UUID: Int] = [:]
        for t in txs where t.kind == .expense && month.contains(t.day) { spent[t.categoryId, default: 0] += t.amountCents }
        return budgets.map {
            BudgetProgress(categoryId: $0.categoryId, spentCents: spent[$0.categoryId] ?? 0, limitCents: $0.monthlyLimitCents)
        }
    }

    /// Nicht archivierte Kategorien der Art, sortiert nach Buchungen der letzten 90 Tage
    /// (today-89 ... today, inkl. heute) absteigend, Gleichstand nach `sortOrder`.
    public static func rankCategories(_ cats: [CategoryValue], txs: [TxValue], kind: Kind, today: CalendarDay) -> [CategoryValue] {
        let start = today.adding(days: -89)
        var counts: [UUID: Int] = [:]
        for t in txs where t.kind == kind && t.day >= start && t.day <= today { counts[t.categoryId, default: 0] += 1 }
        return cats.filter { $0.kind == kind && !$0.archived }
            .sorted {
                let (a, b) = (counts[$0.id] ?? 0, counts[$1.id] ?? 0)
                return a != b ? a > b : $0.sortOrder < $1.sortOrder
            }
    }
}
