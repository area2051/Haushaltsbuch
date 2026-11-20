import Foundation
import HaushaltsbuchCore

public struct CategoryDraft: Sendable {
    public var id: UUID?
    public var name: String
    public var icon: String
    public var color: String
    public var kind: Kind
    /// Hauptkategorie; Unterkategorien übernehmen deren Farbe und Art.
    public var parentId: UUID?

    public init(id: UUID? = nil, name: String, icon: String, color: String, kind: Kind, parentId: UUID? = nil) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.kind = kind
        self.parentId = parentId
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
    /// Alle N Einheiten (1–24), z. B. monatlich × 3 = vierteljährlich.
    public var interval: Int
    public var startDate: CalendarDay
    public var endDate: CalendarDay?

    public init(id: UUID? = nil, amountCents: Int, kind: Kind, categoryId: UUID, note: String? = nil,
                paidBy: UUID, frequency: Frequency, interval: Int = 1, startDate: CalendarDay,
                endDate: CalendarDay? = nil) {
        self.id = id
        self.amountCents = amountCents
        self.kind = kind
        self.categoryId = categoryId
        self.note = note
        self.paidBy = paidBy
        self.frequency = frequency
        self.interval = interval
        self.startDate = startDate
        self.endDate = endDate
    }

    /// Deutsche Fehlermeldung oder `nil`, wenn gültig.
    public func validationError() -> String? {
        if amountCents <= 0 { return "Bitte einen Betrag eingeben." }
        if !(1...Rhythm.maxInterval).contains(interval) { return "Bitte als Intervall eine Zahl von 1 bis 24 wählen." }
        if startDate < CalendarDay(year: 2000, month: 1, day: 1)! {
            return "Der Start darf nicht vor dem 01.01.2000 liegen."
        }
        if let endDate, endDate < startDate { return "Das Ende darf nicht vor dem Start liegen." }
        return nil
    }
}
