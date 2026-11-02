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
    /// Nach erfolgreichem Speichern `true`: weitere `save`-Aufrufe sind wirkungslos.
    public private(set) var didSave = false

    @ObservationIgnored private let currentUserId: UUID
    @ObservationIgnored private let repository: Repository
    @ObservationIgnored private let today: () -> CalendarDay

    public init(repository: Repository, currentUserId: UUID,
                today: @escaping () -> CalendarDay = { CalendarDay.today() }) {
        self.repository = repository
        self.today = today
        self.paidBy = currentUserId
        self.currentUserId = currentUserId
        self.day = today()
        self.members = repository.activeMembers()
        reloadCategories()
    }

    public var canSave: Bool { amount.isValid && !didSave }

    /// Optionen für „Bezahlt von“; der angemeldete Benutzer ist immer enthalten (auch vor dem ersten
    /// Sync der Mitglieder), damit die Auswahl einen passenden Tag hat.
    public var payerOptions: [(id: UUID, name: String)] {
        var options = members.map { (id: $0.id, name: $0.displayName) }
        if !options.contains(where: { $0.id == currentUserId }) {
            options.insert((id: currentUserId, name: "Ich"), at: 0)
        }
        return options
    }

    /// Legt die Buchung an. Leere (oder nur aus Leerraum bestehende) Notiz → `nil`.
    public func save(category: UUID) throws {
        if didSave { return }
        guard amount.isValid else { throw SaveError.invalidAmount }
        try repository.addTransaction(amountCents: amount.cents, kind: kind, categoryId: category,
                                      day: day, paidBy: paidBy, note: NoteLimit.normalized(note))
        didSave = true
    }

    private func reloadCategories() {
        categories = Analytics.rankCategories(
            repository.activeCategories().map(\.value),
            txs: repository.activeTransactions().map(\.value),
            kind: kind, today: today())
    }
}
