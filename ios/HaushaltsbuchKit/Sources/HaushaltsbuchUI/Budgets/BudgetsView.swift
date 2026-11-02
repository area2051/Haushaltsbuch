import os
import SwiftData
import SwiftUI
import HaushaltsbuchCore
import HaushaltsbuchData

private let logger = Logger(subsystem: "de.haushaltsbuch.app", category: "budgets")

struct BudgetsView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TransactionEntity> { !$0.softDeleted })
    private var entities: [TransactionEntity]
    @Query(filter: #Predicate<CategoryEntity> { !$0.softDeleted })
    private var categoryEntities: [CategoryEntity]
    @Query(filter: #Predicate<BudgetEntity> { !$0.softDeleted })
    private var budgetEntities: [BudgetEntity]

    @State private var editing: EditTarget?
    @State private var rejected: BudgetRowData?
    @State private var errorMessage: String?

    /// Höchstens ein Budget je Kategorie (Dubletten nach abgelehntem gleichzeitigem Anlegen).
    private var effective: [BudgetEntity] { BudgetEntity.onePerCategory(budgetEntities) }

    var body: some View {
        let rejections = Dictionary(budgetEntities.compactMap { b in b.rejectionReason.map { (b.categoryId, $0) } },
                                    uniquingKeysWith: { a, _ in a })
        let rows = BudgetsModel.rows(
            categories: categoryEntities.map(\.value), budgets: effective.map(\.value),
            txs: TransactionListModel.activeValues(of: entities), month: CalendarDay.today().monthKey,
            rejections: rejections)
        List(rows) { row in
            Button {
                if row.rejectionReason != nil { rejected = row } else { editing = EditTarget(category: row.category) }
            } label: { BudgetRow(row: row) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("budgets.row")
        }
        .accessibilityIdentifier("budgets.list")
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView("Keine Kategorien", systemImage: "gauge.with.dots.needle.33percent")
            }
        }
        .refreshable { await app.pullToRefresh() }
        .navigationTitle("Budgets")
        .sheet(item: $editing) { target in
            BudgetEditView(category: target.category,
                           currentLimit: effective.first { $0.categoryId == target.category.id }?.monthlyLimitCents)
        }
        .confirmationDialog("Konnte nicht gespeichert werden",
                            isPresented: Binding(get: { rejected != nil }, set: { if !$0 { rejected = nil } }),
                            titleVisibility: .visible, presenting: rejected) { row in
            Button("Bearbeiten") { editing = EditTarget(category: row.category) }
            Button("Verwerfen", role: .destructive) { discard(categoryId: row.category.id) }
            Button("Abbrechen", role: .cancel) {}
        } message: { row in
            Text(row.rejectionReason ?? "")
        }
        .alert("Fehler", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func discard(categoryId: UUID) {
        do {
            for b in budgetEntities where b.categoryId == categoryId && b.rejectionReason != nil {
                try app.repository.discardRejected(b)
            }
        } catch {
            logger.error("Verwerfen fehlgeschlagen: \(String(describing: error), privacy: .public)")
            errorMessage = "Die Änderung konnte nicht verworfen werden."
        }
    }
}

private struct EditTarget: Identifiable {
    let category: CategoryValue
    var id: UUID { category.id }
}

private struct BudgetRow: View {
    let row: BudgetRowData

    private var tint: Color {
        switch row.progress?.level {
        case .exceeded: .red
        case .warning: .orange
        default: .green
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.category.icon)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color(hex: row.category.color)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.category.name).font(.body)
                Text(row.detail).font(.caption).foregroundStyle(.secondary)
                if row.rejectionReason != nil {
                    Label("Konnte nicht gespeichert werden", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                if let p = row.progress {
                    ProgressView(value: min(Double(p.spentCents), Double(max(p.limitCents, 1))),
                                 total: Double(max(p.limitCents, 1)))
                        .tint(tint)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
