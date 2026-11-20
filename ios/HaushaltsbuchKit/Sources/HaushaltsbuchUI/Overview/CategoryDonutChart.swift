import Charts
import SwiftUI
import HaushaltsbuchCore

struct CategoryDonutChart: View {
    let slices: [ChartSlice]
    /// Hauptkategorien, deren Aufteilung aufgeklappt ist.
    @State private var expanded: Set<String> = []

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
                    if s.children.isEmpty {
                        row(s)
                    } else {
                        expandable(s)
                    }
                }
            }
        }
    }

    private func row(_ s: ChartSlice, chevron: Bool? = nil) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Color(hex: s.colorHex)).frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(s.name).lineLimit(1)
            if let chevron {
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(chevron ? 180 : 0))
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            Text(Money.format(cents: s.cents)).monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    /// Tipp klappt die Aufteilung auf („Allgemein“ + je Unterkategorie).
    @ViewBuilder private func expandable(_ s: ChartSlice) -> some View {
        let open = expanded.contains(s.id)
        Button {
            withAnimation(.snappy) { if open { expanded.remove(s.id) } else { expanded.insert(s.id) } }
        } label: {
            row(s, chevron: open).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(open ? "Aufteilung zuklappen" : "Aufteilung aufklappen")
        .accessibilityIdentifier("overview.category.\(s.name)")
        if open {
            VStack(spacing: 6) {
                ForEach(s.children) { sub in
                    HStack(spacing: 8) {
                        Text(sub.name).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(Money.format(cents: sub.cents)).monospacedDigit()
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.leading, 18)
            .accessibilityIdentifier("overview.breakdown.\(s.name)")
        }
    }
}
