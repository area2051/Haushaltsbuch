import SwiftUI

/// Die Bereiche der Hauptnavigation.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case overview, transactions, budgets, more

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Übersicht"
        case .transactions: "Buchungen"
        case .budgets: "Budgets"
        case .more: "Mehr"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "chart.pie"
        case .transactions: "list.bullet"
        case .budgets: "gauge.with.dots.needle.33percent"
        case .more: "ellipsis.circle"
        }
    }
}

/// Inhalt eines Bereichs.
struct SectionScreen: View {
    let section: AppSection

    var body: some View {
        switch section {
        case .more: MoreView()
        case .transactions: TransactionListView()
        case .overview: OverviewView()
        case .budgets: BudgetsView()
        }
    }
}
