import Charts
import SwiftUI
import HaushaltsbuchCore

struct PersonBarChart: View {
    let bars: [ChartBar]

    private var summary: String {
        "Ausgaben nach Person: " + bars.map { "\($0.name) \(Money.format(cents: $0.cents))" }.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ausgaben nach Person").font(.headline)
            Chart(bars) { b in
                BarMark(x: .value("Betrag", b.cents), y: .value("Person", b.name))
                    .foregroundStyle(Color.accentColor)
                    .annotation(position: .trailing) {
                        Text(Money.format(cents: b.cents)).font(.caption).foregroundStyle(.secondary)
                    }
            }
            .chartXAxis(.hidden)
            .chartXScale(domain: 0...(Double(bars.map(\.cents).max() ?? 1) * 1.6))
            .frame(height: CGFloat(max(bars.count, 1)) * 44 + 8)
            .accessibilityElement()
            .accessibilityLabel(summary)
        }
    }
}
