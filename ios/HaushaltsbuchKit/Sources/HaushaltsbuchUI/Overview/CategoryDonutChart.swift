import Charts
import SwiftUI
import HaushaltsbuchCore

struct CategoryDonutChart: View {
    let slices: [ChartSlice]

    private var summary: String {
        "Ausgaben nach Kategorie: " + slices.map { "\($0.name) \(Money.format(cents: $0.cents))" }.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ausgaben nach Kategorie").font(.headline)
            Chart(slices) { s in
                SectorMark(angle: .value("Betrag", s.cents), innerRadius: .ratio(0.6), angularInset: 1)
                    .foregroundStyle(Color(hex: s.colorHex))
            }
            .frame(height: 200)
            .accessibilityElement()
            .accessibilityLabel(summary)
            VStack(spacing: 6) {
                ForEach(slices) { s in
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: s.colorHex)).frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                        Text(s.name).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(Money.format(cents: s.cents)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
