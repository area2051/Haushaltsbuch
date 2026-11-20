import Foundation
import Observation
import HaushaltsbuchCore
import HaushaltsbuchData

/// Zustand des Formulars einer wiederkehrenden Buchung (neu oder bearbeiten).
/// Validierung: `RuleDraft.validationError()` (wie der Server).
@MainActor @Observable
final class RuleEditModel {
    var amount: AmountInput
    var kind: Kind {
        didSet { if kind != oldValue { kindChanged() } }
    }
    var categoryId: UUID?
    var note: String
    var paidBy: UUID?
    var rhythm: Rhythm
    var startDate: CalendarDay
    var hasEndDate: Bool
    var endDate: CalendarDay

    private(set) var members: [MemberEntity]
    /// Kategorien (nicht gelöscht); die bisherige der Regel bleibt wählbar, auch archiviert.
    private let choice: CategoryChoice

    @ObservationIgnored let rule: RecurringRuleEntity?
    @ObservationIgnored private let repository: Repository
    @ObservationIgnored private let currentUserId: UUID?

    var isNew: Bool { rule == nil }

    init(rule: RecurringRuleEntity?, repository: Repository, currentUserId: UUID?,
         today: CalendarDay = .today()) {
        self.rule = rule
        self.repository = repository
        self.currentUserId = currentUserId
        choice = CategoryChoice(repository.activeCategories().map(\.value), keep: rule?.categoryId)
        members = repository.activeMembers()
        if let rule {
            amount = AmountInput(cents: rule.amountCents)
            kind = rule.kindValue
            categoryId = rule.categoryId
            note = rule.note ?? ""
            paidBy = rule.paidBy
            rhythm = rule.rhythm
            startDate = rule.startDay
            hasEndDate = rule.endDay != nil
            endDate = rule.endDay ?? rule.startDay
        } else {
            amount = AmountInput()
            kind = .expense
            categoryId = nil
            note = ""
            paidBy = currentUserId
            rhythm = Rhythm(frequency: .monthly, interval: 1)
            startDate = today
            hasEndDate = false
            endDate = today
            categoryId = categories.first?.id
        }
    }

    /// Hauptkategorien der Art fürs Raster; Unterkategorien wählen die Chips.
    var categories: [CategoryValue] { choice.mains(kind: kind) }

    /// Im Raster markierte Hauptkategorie.
    var mainId: UUID? { categoryId.map(choice.tree.rootOf) }

    /// „Allgemein“ + Unterkategorien der gewählten Hauptkategorie; ein Tipp setzt nur `categoryId`.
    var chipOptions: [SubcategoryOption] { mainId.map(choice.chips(for:)) ?? [] }

    /// Andere Hauptkategorie: beginnt bei „Allgemein“; dieselbe: Unterkategorie bleibt.
    func selectMain(_ id: UUID) {
        if id != mainId { categoryId = id }
    }

    /// Mitglieder; angemeldeter Benutzer und bisheriger Zahler sind immer enthalten.
    var payerOptions: [(id: UUID, name: String)] {
        var options = members.map { (id: $0.id, name: $0.displayName) }
        if let me = currentUserId, !options.contains(where: { $0.id == me }) {
            options.insert((id: me, name: "Ich"), at: 0)
        }
        if let paidBy, !options.contains(where: { $0.id == paidBy }) {
            options.append((id: paidBy, name: "Unbekannt"))
        }
        return options
    }

    private var draft: RuleDraft? {
        guard let categoryId, let paidBy else { return nil }
        return RuleDraft(id: rule?.id, amountCents: amount.cents, kind: kind, categoryId: categoryId,
                         note: NoteLimit.normalized(note), paidBy: paidBy, frequency: rhythm.frequency,
                         interval: rhythm.interval,
                         startDate: startDate, endDate: hasEndDate ? endDate : nil)
    }

    var validationMessage: String? {
        guard let draft else { return "Bitte eine Kategorie wählen." }
        if !choice.isValid(draft.categoryId, kind: kind) { return "Bitte eine Kategorie wählen." }
        return draft.validationError()
    }

    var canSave: Bool { validationMessage == nil }

    /// Wirft `RepositoryError.invalid` mit der deutschen Meldung, wenn ungültig.
    /// Bearbeitete Regel inzwischen gelöscht (z. B. per Sync): Sheet schließen.
    var isGone: Bool { rule?.isGone ?? false }

    func save() throws {
        if isGone { throw RepositoryError.notFound }
        if let message = validationMessage { throw RepositoryError.invalid(message) }
        guard let draft else { return }
        try repository.saveRule(draft)
    }

    func delete() throws {
        guard let rule, !rule.isGone else { return }
        try repository.deleteRule(rule)
    }

    private func kindChanged() {
        if let id = categoryId, choice.isValid(id, kind: kind) { return }
        categoryId = categories.first?.id
    }
}
