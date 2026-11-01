import Foundation
import SwiftData
import HaushaltsbuchCore

@Model
public final class TransactionEntity: SyncTracked {
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

    public var amountCents: Int
    /// `Kind.rawValue`
    public var kind: String
    public var categoryId: UUID
    /// `YYYY-MM-DD`
    public var day: String
    public var paidBy: UUID
    public var note: String?
    /// Nur vom Server erzeugte Buchungen; das Repository setzt es nie.
    public var recurringRuleId: UUID?

    public init(id: UUID = UUID(), amountCents: Int, kind: Kind, categoryId: UUID, day: CalendarDay,
                paidBy: UUID, note: String?, recurringRuleId: UUID? = nil, version: Int? = nil,
                deleted: Bool = false, isDirty: Bool = false) {
        self.id = id
        self.version = version
        self.softDeleted = deleted
        self.isDirty = isDirty
        self.dirtyGeneration = 0
        self.rejectionReason = nil
        self.amountCents = amountCents
        self.kind = kind.rawValue
        self.categoryId = categoryId
        self.day = day.string
        self.paidBy = paidBy
        self.note = note
        self.recurringRuleId = recurringRuleId
    }

    public var kindValue: Kind { Kind(rawValue: kind) ?? .expense }
    public var calendarDay: CalendarDay { CalendarDay(string: day) ?? CalendarDay(year: 2000, month: 1, day: 1)! }

    public var value: TxValue {
        TxValue(id: id, amountCents: amountCents, kind: kindValue, categoryId: categoryId,
                day: calendarDay, paidBy: paidBy, note: note)
    }
}
