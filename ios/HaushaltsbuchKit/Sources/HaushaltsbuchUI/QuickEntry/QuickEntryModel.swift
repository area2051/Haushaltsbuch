import Foundation
import Observation
import HaushaltsbuchCore
import HaushaltsbuchData

/// Zustand der Schnellerfassung: Betrag per Ziffernblock, Kategorie-Tipp speichert.
@MainActor @Observable
public final class QuickEntryModel {
    public enum SaveError: Error, Equatable {
        case invalidAmount
    }

    public var amount = AmountInput()
    public var kind: Kind = .expense {
        didSet { if kind != oldValue { reloadCategories() } }
    }
    public var day: CalendarDay
    public var paidBy: UUID
    public var note = ""
    public var detailsExpanded = false

    /// Nicht archivierte Kategorien der gewählten Art, nach jüngster Nutzung gerankt.
    public private(set) var categories: [CategoryValue] = []
    /// Aktive Haushaltsmitglieder für „Bezahlt von“.
    public private(set) var members: [MemberEntity] = []

    @ObservationIgnored private let repository: Repository
    @ObservationIgnored private let today: () -> CalendarDay

    public init(repository: Repository, currentUserId: UUID,
                today: @escaping () -> CalendarDay = { CalendarDay.today() }) {
        self.repository = repository
        self.today = today
        self.paidBy = currentUserId
        self.day = today()
        self.members = repository.activeMembers()
        reloadCategories()
    }

    public var canSave: Bool { amount.isValid }

    /// Legt die Buchung an. Leere (oder nur aus Leerraum bestehende) Notiz → `nil`.
    public func save(category: UUID) throws {
        guard canSave else { throw SaveError.invalidAmount }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try repository.addTransaction(amountCents: amount.cents, kind: kind, categoryId: category,
                                      day: day, paidBy: paidBy, note: trimmed.isEmpty ? nil : trimmed)
    }

    private func reloadCategories() {
        categories = Analytics.rankCategories(
            repository.activeCategories().map(\.value),
            txs: repository.activeTransactions().map(\.value),
            kind: kind, today: today())
    }
}
