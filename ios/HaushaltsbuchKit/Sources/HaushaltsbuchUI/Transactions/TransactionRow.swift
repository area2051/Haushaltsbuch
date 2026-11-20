import SwiftUI
import HaushaltsbuchCore

/// Zeile der Buchungsliste: Symbol der Kategorie in der Farbe ihrer Hauptkategorie, Label „Wohnen · Strom“.
struct TransactionRow: View {
    let tx: TxValue
    let tree: CategoryTree
    let payerName: String?
    let rejectionReason: String?

    private var category: CategoryValue? { tree.byId[tx.categoryId] }
    private var colorHex: String? { tree.byId[tree.rootOf(tx.categoryId)]?.color }
    private var categoryName: String { tree.label(tx.categoryId) }
    private var trimmedNote: String { tx.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category?.icon ?? "questionmark")
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(colorHex.map { Color(hex: $0) } ?? .gray))
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
