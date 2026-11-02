import SwiftUI
import HaushaltsbuchCore

/// Ziffernblock 3×4: 1–9, Platzhalter, 0, Löschen.
struct KeypadView: View {
    @Binding var amount: AmountInput

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(1...9, id: \.self) { digit in
                key(digit)
            }
            Color.clear.frame(height: 56)
                .accessibilityHidden(true)
            key(0)
            Button {
                amount.deleteLast()
            } label: {
                Image(systemName: "delete.left")
                    .font(.title2)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            .accessibilityLabel("Löschen")
            .accessibilityIdentifier("quickEntry.key.delete")
        }
    }

    private func key(_ digit: Int) -> some View {
        Button {
            amount.append(digit: digit)
        } label: {
            Text("\(digit)")
                .font(.title.weight(.medium))
                .monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.bordered)
        .tint(.primary)
        .accessibilityLabel("Ziffer \(digit)")
        .accessibilityIdentifier("quickEntry.key.\(digit)")
    }
}
