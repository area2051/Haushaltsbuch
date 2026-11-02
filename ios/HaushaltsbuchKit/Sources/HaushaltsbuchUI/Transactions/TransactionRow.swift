import SwiftUI
import HaushaltsbuchCore

/// Zeile der Buchungsliste.
struct TransactionRow: View {
    let tx: TxValue
    let category: CategoryValue?
    let payerName: String?
    let rejectionReason: String?

    private var categoryName: String { category?.name ?? "Unbekannt" }
    private var trimmedNote: String { tx.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category?.icon ?? "questionmark")
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(category.map { Color(hex: $0.color) } ?? .gray))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(trimmedNote.isEmpty ? categoryName : trimmedNote)
                    .font(.body)
                    .lineLimit(1)
                if let secondary {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if rejectionReason != nil {
                    Label("Konnte nicht gespeichert werden", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(amountText)
                .font(.body.monospacedDigit())
                .foregroundStyle(tx.kind == .income ? Color.green : Color.primary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var secondary: String? {
        var parts: [String] = []
        if !trimmedNote.isEmpty { parts.append(categoryName) }
        if let payerName { parts.append(payerName) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var amountText: String {
        tx.kind == .income
            ? Money.formatSigned(cents: tx.amountCents, kind: .income)
            : Money.format(cents: tx.amountCents)
    }
}
