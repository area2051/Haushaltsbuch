import os
import SwiftData
import SwiftUI
import HaushaltsbuchCore
import HaushaltsbuchData

private let logger = Logger(subsystem: "de.haushaltsbuch.app", category: "rules")

/// Wiederkehrende Buchungen (Daueraufträge). Buchungen daraus erzeugt nur der Server (Spec §5).
struct RecurringRulesView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<RecurringRuleEntity> { !$0.softDeleted }, sort: \RecurringRuleEntity.startDate)
    private var rules: [RecurringRuleEntity]
    /// Auch gelöschte: Namen alter Regeln bleiben lesbar.
    @Query private var categories: [CategoryEntity]

    @State private var editing: RuleSheet?
    @State private var confirmDelete: RecurringRuleEntity?
    @State private var errorMessage: String?
    @State private var rejected: RecurringRuleEntity?

    var body: some View {
        let byId = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        List {
            ForEach(rules.filter { !$0.deleted }) { rule in
                Button {
                    if rule.rejectionReason != nil { rejected = rule } else { editing = .edit(rule) }
                } label: { RuleRow(rule: rule, category: byId[rule.categoryId]) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("rules.row")
                    .swipeActions {
                        Button("Löschen", role: .destructive) { confirmDelete = rule }
                    }
            }
        }
        .accessibilityIdentifier("rules.list")
        .overlay {
            if rules.filter({ !$0.deleted }).isEmpty {
                ContentUnavailableView("Keine wiederkehrenden Buchungen", systemImage: "arrow.triangle.2.circlepath",
                                       description: Text("Zum Beispiel Miete oder Gehalt – der Server bucht sie automatisch."))
            }
        }
        .refreshable { await app.pullToRefresh() }
        .navigationTitle("Wiederkehrende")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = .new } label: { Label("Neue wiederkehrende Buchung", systemImage: "plus") }
                    .accessibilityIdentifier("rules.add")
            }
        }
        .sheet(item: $editing) { RuleEditView(target: $0) }
        .confirmationDialog("Konnte nicht gespeichert werden",
                            isPresented: Binding(get: { rejected != nil }, set: { if !$0 { rejected = nil } }),
                            titleVisibility: .visible, presenting: rejected) { rule in
            Button("Bearbeiten") { editing = .edit(rule) }
            Button("Verwerfen", role: .destructive) { discard(rule) }
            Button("Abbrechen", role: .cancel) {}
        } message: { rule in
            Text(RejectionText.german(rule.rejectionReason))
        }
        .confirmationDialog("Wiederkehrende Buchung löschen?",
                            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { if let r = confirmDelete { delete(r) } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Bereits erzeugte Buchungen bleiben erhalten.")
        }
        .alert("Fehler", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func discard(_ rule: RecurringRuleEntity) {
        do { try app.repository.discardRejected(rule) } catch {
            logger.error("Verwerfen fehlgeschlagen: \(String(describing: error), privacy: .public)")
            errorMessage = "Die Änderung konnte nicht verworfen werden."
        }
    }

    private func delete(_ rule: RecurringRuleEntity) {
        do {
            try app.repository.deleteRule(rule)
        } catch {
            logger.error("Regel löschen fehlgeschlagen: \(String(describing: error), privacy: .public)")
            errorMessage = "Die wiederkehrende Buchung konnte nicht gelöscht werden."
        }
    }
}

enum RuleSheet: Identifiable {
    case new
    case edit(RecurringRuleEntity)

    var id: String {
        switch self {
        case .new: "new"
        case let .edit(r): r.id.uuidString
        }
    }
}

private struct RuleRow: View {
    let rule: RecurringRuleEntity
    let category: CategoryEntity?

    private var period: String {
        var text = "\(RuleFormat.frequency(rule.frequencyValue).capitalized) ab \(RuleFormat.date(rule.startDay))"
        if let end = rule.endDay { text += " bis \(RuleFormat.date(end))" }
        return text
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category?.icon ?? "questionmark")
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color(hex: category?.color ?? "#9E9E9E")))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(rule.note ?? category?.name ?? "Unbekannt").font(.body)
                    Spacer()
                    Text(Money.formatSigned(cents: rule.amountCents, kind: rule.kindValue))
                        .monospacedDigit()
                        .foregroundStyle(rule.kindValue == .income ? .green : .primary)
                }
                if rule.note != nil, let name = category?.name {
                    Text(name).font(.caption).foregroundStyle(.secondary)
                }
                Text(period).font(.caption).foregroundStyle(.secondary)
                Text(RuleFormat.nextDue(rule.nextDueDay)).font(.caption).foregroundStyle(.secondary)
                if let reason = rule.rejectionReason {
                    Text("Konnte nicht gespeichert werden: \(RejectionText.german(reason))")
                        .font(.caption).foregroundStyle(.red)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
