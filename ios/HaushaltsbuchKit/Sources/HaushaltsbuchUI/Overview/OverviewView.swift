import SwiftData
import SwiftUI
import HaushaltsbuchCore
import HaushaltsbuchData

struct OverviewView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(filter: #Predicate<TransactionEntity> { !$0.softDeleted },
           sort: \TransactionEntity.day, order: .reverse)
    private var entities: [TransactionEntity]
    @Query(filter: #Predicate<CategoryEntity> { !$0.softDeleted })
    private var categoryEntities: [CategoryEntity]
    @Query(filter: #Predicate<MemberEntity> { !$0.softDeleted })
    private var members: [MemberEntity]
    @Query(filter: #Predicate<BudgetEntity> { !$0.softDeleted })
    private var budgetEntities: [BudgetEntity]

    @State private var month = CalendarDay.today().monthKey
    @State private var editing: TransactionEntity?

    var body: some View {
        let current = CalendarDay.today().monthKey
        let categories = categoryEntities.map(\.value)
        let catById = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let names = Dictionary(members.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        let byId = Dictionary(entities.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let data = OverviewModel.make(
            txs: TransactionListModel.activeValues(of: entities), categories: categories, members: names,
            budgets: budgetEntities.filter { !$0.deleted }.map(\.value), month: month)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MonthPicker(month: $month, current: current)
                saldoCard(data.summary)
                if data.isEmpty {
                    ContentUnavailableView("Noch keine Buchungen in diesem Monat", systemImage: "tray",
                                           description: Text("Mit „+“ eine Buchung erfassen."))
                        .accessibilityIdentifier("overview.empty")
                } else {
                    if !data.byCategory.isEmpty || !data.byPerson.isEmpty {
                        charts(data)
                    }
                    if !data.warnings.isEmpty { warnings(data.warnings, catById) }
                    recent(data.recent, byId: byId, catById: catById, names: names)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                withAnimation { month = MonthPicker.swipe(translation: value.translation, month: month, current: current) }
            })
        .refreshable { await app.pullToRefresh() }
        .navigationTitle("Übersicht")
        .accessibilityIdentifier("overview.screen")
        .sheet(item: $editing) { TransactionEditView(transaction: $0) }
    }

    private func saldoCard(_ s: MonthSummary) -> some View {
        VStack(spacing: 12) {
            Text("Saldo").font(.subheadline).foregroundStyle(.secondary)
            Text(Money.format(cents: s.balanceCents))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.5).lineLimit(1)
                .foregroundStyle(s.balanceCents >= 0 ? Color.green : Color.red)
                .accessibilityIdentifier("overview.balance")
            HStack(alignment: .top) {
                figure("Einnahmen", s.incomeCents, .green)
                Spacer(minLength: 8)
                figure("Ausgaben", s.expenseCents, .primary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private func figure(_ title: String, _ cents: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Money.format(cents: cents)).font(.headline).monospacedDigit().foregroundStyle(color)
                .minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func charts(_ data: OverviewData) -> some View {
        let layout = sizeClass == .regular ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                                           : AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
        layout {
            if !data.byCategory.isEmpty { card { CategoryDonutChart(slices: data.byCategory) } }
            if !data.byPerson.isEmpty { card { PersonBarChart(bars: data.byPerson) } }
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func warnings(_ items: [BudgetProgress], _ catById: [UUID: CategoryValue]) -> some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Budget-Warnungen").font(.headline)
                ForEach(items, id: \.categoryId) { p in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: p.level == .exceeded ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(p.level == .exceeded ? Color.red : Color.orange)
                            .accessibilityHidden(true)
                        Text("\(catById[p.categoryId]?.name ?? "Unbekannt") – \(OverviewModel.percentText(p))")
                            .font(.subheadline)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("overview.warning")
                }
            }
        }
    }

    private func recent(_ txs: [TxValue], byId: [UUID: TransactionEntity], catById: [UUID: CategoryValue],
                        names: [UUID: String]) -> some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Letzte Buchungen").font(.headline)
                ForEach(txs, id: \.id) { tx in
                    if let entity = byId[tx.id] {
                        Button { editing = entity } label: {
                            TransactionRow(tx: tx, category: catById[tx.categoryId], payerName: names[tx.paidBy],
                                           rejectionReason: entity.rejectionReason)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("overview.recent")
                    }
                }
            }
        }
    }
}
