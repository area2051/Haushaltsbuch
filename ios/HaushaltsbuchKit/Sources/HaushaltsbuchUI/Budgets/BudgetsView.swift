import os
import SwiftData
import SwiftUI
import HaushaltsbuchCore
import HaushaltsbuchData

struct BudgetsView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TransactionEntity> { !$0.softDeleted })
    private var entities: [TransactionEntity]
    @Query(filter: #Predicate<CategoryEntity> { !$0.softDeleted })
    private var categoryEntities: [CategoryEntity]
    @Query(filter: #Predicate<BudgetEntity> { !$0.softDeleted })
    private var budgetEntities: [BudgetEntity]

    @State private var editing: EditTarget?

    var body: some View {
        let rows = BudgetsModel.rows(
            categories: categoryEntities.map(\.value), budgets: budgetEntities.map(\.value),
            txs: TransactionListModel.activeValues(of: entities), month: CalendarDay.today().monthKey)
        List(rows) { row in
            Button { editing = EditTarget(category: row.category) } label: { BudgetRow(row: row) }
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
                           currentLimit: budgetEntities.first { $0.categoryId == target.category.id }?.monthlyLimitCents)
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
