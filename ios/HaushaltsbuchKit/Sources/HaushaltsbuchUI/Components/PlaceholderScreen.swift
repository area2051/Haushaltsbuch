import SwiftUI

/// Platzhalter für Bildschirme, die in späteren Tasks entstehen (Übersicht, Buchungen, Budgets, Mehr, Erfassung).
struct PlaceholderScreen: View {
    let title: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text("Folgt in Kürze."))
            .navigationTitle(title)
    }
}

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

/// Inhalt eines Bereichs (bis Tasks 10–13 Platzhalter).
struct SectionScreen: View {
    let section: AppSection

    var body: some View {
        switch section {
        case .more: MorePlaceholder()
        default: PlaceholderScreen(title: section.title, systemImage: section.systemImage)
        }
    }
}

/// „Mehr“ bis Task 13: nur Abmelden.
struct MorePlaceholder: View {
    @Environment(AppModel.self) private var model
    @State private var loggingOut = false

    var body: some View {
        List {
            Section {
                Button("Abmelden", role: .destructive) {
                    loggingOut = true
                    Task {
                        await model.logout()
                        loggingOut = false
                    }
                }
                .disabled(loggingOut)
            } footer: {
                Text("Weitere Einstellungen folgen.")
            }
        }
        .navigationTitle("Mehr")
    }
}
