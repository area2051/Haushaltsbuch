import Foundation
import Observation
import HaushaltsbuchCore
import HaushaltsbuchData

/// Zustand der Schnellerfassung: Betrag per Ziffernblock, Kategorie-Tipp speichert. Hat die Kategorie
/// Unterkategorien, zeigt der Tipp stattdessen deren Chips; ein Chip-Tipp speichert.
@MainActor @Observable
public final class QuickEntryModel {
    public enum SaveError: Error, Equatable {
        case invalidAmount
    }

    public var amount = AmountInput()
    public var kind: Kind = .expense {
        didSet {
            if kind != oldValue {
                chipParentId = nil
                reloadCategories()
            }
        }
    }
    public var day: CalendarDay
    public var paidBy: UUID
    public var note = ""
    public var detailsExpanded = false {
        // Ein verborgener Rhythmus würde den nächsten Kategorie-Tipp unbemerkt zur Regel machen.
        didSet { if !detailsExpanded { repeatRhythm = nil } }
    }
    /// Gesetzt: Speichern legt statt einer Buchung eine wiederkehrende Regel ab `day` an; die erste
    /// Buchung erzeugt der Server (ist `day` heute oder früher, sofort).
    public var repeatRhythm: Rhythm?

    /// Nicht archivierte Hauptkategorien der gewählten Art, nach jüngster Nutzung gerankt (Buchungen
    /// auf Unterkategorien zählen für die Hauptkategorie).
    public private(set) var categories: [CategoryValue] = []
    /// Hauptkategorie, deren Unterkategorie-Chips gezeigt werden.
    public private(set) var chipParentId: UUID?
    private var choice = CategoryChoice([])
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

    /// „Allgemein“ + Unterkategorien von `chipParentId`; ein Tipp speichert (`save(category:)`).
    var chipOptions: [SubcategoryOption] {
        chipParentId.map(choice.chips(for:)) ?? []
    }

    /// Tipp auf eine Hauptkategorie: ohne wählbare Unterkategorien speichern (`true`), sonst die Chips
    /// zeigen (`false`).
    @discardableResult
    public func tapCategory(_ id: UUID) throws -> Bool {
        if choice.chips(for: id).isEmpty {
            try save(category: id)
            return true
        }
        chipParentId = id
        return false
    }

    /// Optionen für „Bezahlt von“; der angemeldete Benutzer ist immer enthalten (auch vor dem ersten
    /// Sync der Mitglieder), damit die Auswahl einen passenden Tag hat.
    public var payerOptions: [(id: UUID, name: String)] {
        var options = members.map { (id: $0.id, name: $0.displayName) }
        if !options.contains(where: { $0.id == currentUserId }) {
            options.insert((id: currentUserId, name: "Ich"), at: 0)
        }
        return options
    }

    /// Legt die Buchung an (bzw. die Regel, wenn `repeatRhythm` gesetzt ist).
    /// Leere (oder nur aus Leerraum bestehende) Notiz → `nil`.
    public func save(category: UUID) throws {
        if didSave { return }
        guard amount.isValid else { throw SaveError.invalidAmount }
        if let rhythm = repeatRhythm {
            _ = try repository.saveRule(RuleDraft(amountCents: amount.cents, kind: kind, categoryId: category,
                                                  note: NoteLimit.normalized(note), paidBy: paidBy,
                                                  frequency: rhythm.frequency, interval: rhythm.interval,
                                                  startDate: day))
            didSave = true
            return
        }
        try repository.addTransaction(amountCents: amount.cents, kind: kind, categoryId: category,
                                      day: day, paidBy: paidBy, note: NoteLimit.normalized(note))
        didSave = true
    }

    private func reloadCategories() {
        choice = CategoryChoice(repository.activeCategories().map(\.value))
        let tree = choice.tree
        let txs = repository.activeTransactions().map { tx in
            var v = tx.value
            v.categoryId = tree.rootOf(v.categoryId)
            return v
        }
        let mains = tree.byId.values.filter { tree.rootOf($0.id) == $0.id }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        categories = Analytics.rankCategories(mains, txs: txs, kind: kind, today: today())
    }
}
