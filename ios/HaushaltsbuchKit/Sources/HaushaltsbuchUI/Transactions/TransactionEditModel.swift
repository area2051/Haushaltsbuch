import Foundation
import Observation
import HaushaltsbuchCore
import HaushaltsbuchData

/// Zustand des Bearbeiten-Formulars einer Buchung.
@MainActor @Observable
final class TransactionEditModel {
    enum SaveError: Error, Equatable {
        case invalidInput
        /// Die Buchung wurde inzwischen gelöscht (z. B. per Sync).
        case gone
    }

    /// Gelöscht, während das Formular offen ist: Sheet schließen, nichts mehr anfassen.
    var isGone: Bool { transaction.isGone }

    var amount: AmountInput
    var kind: Kind {
        didSet { if kind != oldValue { kindChanged() } }
    }
    var categoryId: UUID?
    var day: CalendarDay
    var paidBy: UUID
    var note: String

    private(set) var members: [MemberEntity]
    /// Kategorien (nicht gelöscht); die ursprüngliche bleibt wählbar, auch archiviert.
    private let choice: CategoryChoice

    @ObservationIgnored private let transaction: TransactionEntity
    @ObservationIgnored private let repository: Repository
    @ObservationIgnored private let currentUserId: UUID?
    @ObservationIgnored private let originalCategoryId: UUID

    init(transaction: TransactionEntity, repository: Repository, currentUserId: UUID?) {
        self.transaction = transaction
        self.repository = repository
        self.currentUserId = currentUserId
        self.originalCategoryId = transaction.categoryId
        self.amount = AmountInput(cents: transaction.amountCents)
        self.kind = transaction.kindValue
        self.categoryId = transaction.categoryId
        self.day = transaction.calendarDay
        self.paidBy = transaction.paidBy
        self.note = transaction.note ?? ""
        self.choice = CategoryChoice(repository.activeCategories().map(\.value), keep: transaction.categoryId)
        self.members = repository.activeMembers()
    }

    /// Hauptkategorien der gewählten Art fürs Raster; Unterkategorien wählen die Chips.
    var categories: [CategoryValue] { choice.mains(kind: kind) }

    /// Im Raster markierte Hauptkategorie.
    var mainId: UUID? { categoryId.map(choice.tree.rootOf) }

    /// „Allgemein“ + Unterkategorien der gewählten Hauptkategorie; ein Tipp setzt nur `categoryId`.
    var chipOptions: [SubcategoryOption] { mainId.map(choice.chips(for:)) ?? [] }

    /// Andere Hauptkategorie: beginnt bei „Allgemein“; dieselbe: Unterkategorie bleibt.
    func selectMain(_ id: UUID) {
        if id != mainId { categoryId = id }
    }

    /// Mitglieder; der zugeordnete Zahler und der angemeldete Benutzer sind immer enthalten.
    var payerOptions: [(id: UUID, name: String)] {
        var options = members.map { (id: $0.id, name: $0.displayName) }
        if let me = currentUserId, !options.contains(where: { $0.id == me }) {
            options.insert((id: me, name: "Ich"), at: 0)
        }
        if !options.contains(where: { $0.id == paidBy }) {
            options.append((id: paidBy, name: "Unbekannt"))
        }
        return options
    }

    var canSave: Bool {
        guard amount.isValid, let categoryId else { return false }
        return choice.isValid(categoryId, kind: kind)
    }

    func save() throws {
        guard !isGone else { throw SaveError.gone }
        guard canSave, let categoryId else { throw SaveError.invalidInput }
        try repository.update(transaction, amountCents: amount.cents, kind: kind, categoryId: categoryId,
                              day: day, paidBy: paidBy, note: NoteLimit.normalized(note))
    }

    func delete() throws {
        guard !isGone else { throw SaveError.gone }
        try repository.delete(transaction)
    }

    private func kindChanged() {
        if let id = categoryId, choice.isValid(id, kind: kind) { return }
        categoryId = choice.isValid(originalCategoryId, kind: kind) ? originalCategoryId : nil
    }
}
