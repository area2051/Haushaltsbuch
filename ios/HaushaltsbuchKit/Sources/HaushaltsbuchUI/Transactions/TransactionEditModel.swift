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

    private(set) var allCategories: [CategoryValue]
    private(set) var members: [MemberEntity]

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
        self.allCategories = repository.activeCategories().map(\.value)
        self.members = repository.activeMembers()
    }

    /// Nicht archivierte Kategorien der gewählten Art; die ursprüngliche bleibt wählbar, auch archiviert.
    var categories: [CategoryValue] {
        allCategories.filter { $0.kind == kind && (!$0.archived || $0.id == originalCategoryId) }
            .sorted { $0.sortOrder < $1.sortOrder }
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
        return categories.contains { $0.id == categoryId }
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
        let ids = Set(categories.map(\.id))
        if let id = categoryId, ids.contains(id) { return }
        categoryId = ids.contains(originalCategoryId) ? originalCategoryId : nil
    }
}
