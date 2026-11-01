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
