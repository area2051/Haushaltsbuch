import Foundation
import SwiftData
import HaushaltsbuchCore

@Model
public final class RecurringRuleEntity: SyncTracked {
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
    public var note: String?
    public var paidBy: UUID
    /// `Frequency.rawValue`
    public var frequency: String
    /// `YYYY-MM-DD`
    public var startDate: String
    public var endDate: String?
    /// Setzt nur der Server.
    public var nextDueDate: String?

    public init(id: UUID = UUID(), amountCents: Int, kind: Kind, categoryId: UUID, note: String?,
                paidBy: UUID, frequency: Frequency, startDate: CalendarDay, endDate: CalendarDay?,
                nextDueDate: CalendarDay? = nil, version: Int? = nil, deleted: Bool = false,
                isDirty: Bool = false) {
        self.id = id
        self.version = version
        self.softDeleted = deleted
        self.isDirty = isDirty
        self.dirtyGeneration = 0
        self.rejectionReason = nil
        self.amountCents = amountCents
        self.kind = kind.rawValue
        self.categoryId = categoryId
        self.note = note
        self.paidBy = paidBy
        self.frequency = frequency.rawValue
        self.startDate = startDate.string
        self.endDate = endDate?.string
        self.nextDueDate = nextDueDate?.string
    }

    public var kindValue: Kind { Kind(rawValue: kind) ?? .expense }
    public var frequencyValue: Frequency { Frequency(rawValue: frequency) ?? .monthly }
    public var startDay: CalendarDay { CalendarDay(string: startDate) ?? CalendarDay(year: 2000, month: 1, day: 1)! }
    public var endDay: CalendarDay? { endDate.flatMap { CalendarDay(string: $0) } }
    public var nextDueDay: CalendarDay? { nextDueDate.flatMap { CalendarDay(string: $0) } }

    public var value: RuleValue {
        RuleValue(id: id, amountCents: amountCents, kind: kindValue, categoryId: categoryId, note: note,
                  paidBy: paidBy, frequency: frequencyValue, startDate: startDay, endDate: endDay,
                  nextDueDate: nextDueDay)
    }
}

/// Wert-Sicht auf eine Dauerauftrags-Regel (Core hat dafür keinen eigenen Typ).
public struct RuleValue: Sendable, Equatable {
    public var id: UUID
    public var amountCents: Int
    public var kind: Kind
    public var categoryId: UUID
    public var note: String?
    public var paidBy: UUID
    public var frequency: Frequency
    public var startDate: CalendarDay
    public var endDate: CalendarDay?
    public var nextDueDate: CalendarDay?
}
