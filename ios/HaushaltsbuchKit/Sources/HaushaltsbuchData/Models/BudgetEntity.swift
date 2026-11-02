import Foundation
import SwiftData
import HaushaltsbuchCore

@Model
public final class BudgetEntity: SyncTracked {
    @Attribute(.unique) public var id: UUID
    public var version: Int?
    /// Persistiert als `softDeleted`: der Name `deleted` wird von SwiftData/Core Data überschrieben
    /// (Wert springt nach `save()` auf false zurück).
    public var softDeleted: Bool
    public var deleted: Bool {
        get { softDeleted }
        set { softDeleted = newValue }
    }
    public var isDirty: Bool
    public var dirtyGeneration: Int
    public var rejectionReason: String?

    public var categoryId: UUID
    public var monthlyLimitCents: Int

    public init(id: UUID = UUID(), categoryId: UUID, monthlyLimitCents: Int, version: Int? = nil,
                deleted: Bool = false, isDirty: Bool = false) {
        self.id = id
        self.version = version
        self.softDeleted = deleted
        self.isDirty = isDirty
        self.dirtyGeneration = 0
        self.rejectionReason = nil
        self.categoryId = categoryId
        self.monthlyLimitCents = monthlyLimitCents
    }

    public var value: BudgetValue {
        BudgetValue(categoryId: categoryId, monthlyLimitCents: monthlyLimitCents)
    }
}

extension BudgetEntity {
    /// Höchstens ein Budget je Kategorie. Zwei aktive Budgets für eine Kategorie entstehen, wenn zwei
    /// Geräte gleichzeitig eins anlegen: der Server lehnt das zweite ab (Unique-Index), das andere
    /// kommt per Pull. Bevorzugt wird das synchronisierte (höchste `version`), sonst ein nicht
    /// abgelehntes, sonst das mit der höheren `dirtyGeneration` (zuletzt bearbeitet); bei Gleichstand
    /// entscheidet die ID (stabile Anzeige). Gelöschte werden ignoriert.
    public static func onePerCategory(_ budgets: [BudgetEntity]) -> [BudgetEntity] {
        var best: [UUID: BudgetEntity] = [:]
        for b in budgets where !b.deleted {
            if let current = best[b.categoryId], !b.isPreferred(over: current) { continue }
            best[b.categoryId] = b
        }
        return best.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func isPreferred(over other: BudgetEntity) -> Bool {
        switch (version, other.version) {
        case let (a?, b?) where a != b: return a > b
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        let rejected = rejectionReason != nil, otherRejected = other.rejectionReason != nil
        if rejected != otherRejected { return !rejected }
        if dirtyGeneration != other.dirtyGeneration { return dirtyGeneration > other.dirtyGeneration }
        return id.uuidString < other.id.uuidString
    }
}
