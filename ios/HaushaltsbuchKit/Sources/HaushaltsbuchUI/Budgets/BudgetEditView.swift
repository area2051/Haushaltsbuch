import os
import SwiftUI
import HaushaltsbuchCore
import HaushaltsbuchData

private let logger = Logger(subsystem: "de.haushaltsbuch.app", category: "budgets")

/// Monatslimit einer Kategorie setzen oder entfernen.
struct BudgetEditView: View {
    let category: CategoryValue
    let currentLimit: Int?
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var amount = AmountInput()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text(category.name).font(.headline).foregroundStyle(.secondary)
                    Text(amount.display)
                        .font(.largeTitle.weight(.semibold)).monospacedDigit()
                        .minimumScaleFactor(0.5).lineLimit(1)
                        .foregroundStyle(amount.isValid ? Color.primary : Color.secondary)
                        .accessibilityIdentifier("budget.amount")
                    Text("Monatslimit").font(.caption).foregroundStyle(.secondary)
                    KeypadView(amount: $amount)
                    if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                    Button("Sichern") { save(amount.cents) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(!amount.isValid)
                        .accessibilityIdentifier("budget.save")
                    if currentLimit != nil {
                        Button("Budget entfernen", role: .destructive) { save(nil) }
                            .accessibilityIdentifier("budget.remove")
                    }
                }
                .padding(16)
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
        }
        .accessibilityIdentifier("budgetEditSheet")
        .presentationDetents([.large])
        .onAppear { if let currentLimit { amount = AmountInput(cents: currentLimit) } }
    }

    private func save(_ cents: Int?) {
        do {
            try app.repository.setBudget(categoryId: category.id, monthlyLimitCents: cents)
            dismiss()
        } catch {
            logger.error("Budget speichern fehlgeschlagen: \(String(describing: error), privacy: .public)")
            errorMessage = "Das Budget konnte nicht gespeichert werden."
        }
    }
}
