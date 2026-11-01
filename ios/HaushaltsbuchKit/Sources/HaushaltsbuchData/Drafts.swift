import Foundation
import HaushaltsbuchCore

public struct CategoryDraft: Sendable {
    public var id: UUID?
    public var name: String
    public var icon: String
    public var color: String
    public var kind: Kind

    public init(id: UUID? = nil, name: String, icon: String, color: String, kind: Kind) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.kind = kind
    }
}

public struct RuleDraft: Sendable {
    public var id: UUID?
    public var amountCents: Int
    public var kind: Kind
    public var categoryId: UUID
    public var note: String?
    public var paidBy: UUID
    public var frequency: Frequency
    public var startDate: CalendarDay
    public var endDate: CalendarDay?

    public init(id: UUID? = nil, amountCents: Int, kind: Kind, categoryId: UUID, note: String? = nil,
                paidBy: UUID, frequency: Frequency, startDate: CalendarDay, endDate: CalendarDay? = nil) {
        self.id = id
        self.amountCents = amountCents
        self.kind = kind
        self.categoryId = categoryId
        self.note = note
        self.paidBy = paidBy
        self.frequency = frequency
        self.startDate = startDate
        self.endDate = endDate
    }

    /// Deutsche Fehlermeldung oder `nil`, wenn gültig.
    public func validationError() -> String? {
        if amountCents <= 0 { return "Bitte einen Betrag eingeben." }
        if startDate < CalendarDay(year: 2000, month: 1, day: 1)! {
            return "Der Start darf nicht vor dem 01.01.2000 liegen."
        }
        if let endDate, endDate < startDate { return "Das Ende darf nicht vor dem Start liegen." }
        return nil
    }
}
