import SwiftUI
import HaushaltsbuchCore

/// Monatsauswahl mit Pfeilen. Nicht über den aktuellen Monat hinaus.
struct MonthPicker: View {
    @Binding var month: MonthKey
    let current: MonthKey

    private var canGoForward: Bool { month < current }

    var body: some View {
        HStack {
            Button { month = month.adding(months: -1) } label: {
                Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Vorheriger Monat")
            .accessibilityIdentifier("overview.prevMonth")
            Spacer()
            Text(month.title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("overview.monthTitle")
            Spacer()
            Button { if canGoForward { month = month.adding(months: 1) } } label: {
                Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
            }
            .disabled(!canGoForward)
            .accessibilityLabel("Nächster Monat")
            .accessibilityIdentifier("overview.nextMonth")
        }
    }

    /// Wischgeste: nach links = nächster Monat, nach rechts = vorheriger.
    static func swipe(translation: CGSize, month: MonthKey, current: MonthKey) -> MonthKey {
        guard abs(translation.width) > 50, abs(translation.width) > abs(translation.height) else { return month }
        if translation.width < 0 { return month < current ? month.adding(months: 1) : month }
        return month.adding(months: -1)
    }
}
