import os
import SwiftUI
import HaushaltsbuchCore
import HaushaltsbuchData

private let logger = Logger(subsystem: "de.haushaltsbuch.app", category: "transactionEdit")

/// Bearbeiten einer Buchung (Sheet): gleiche Bausteine wie die Schnellerfassung.
struct TransactionEditView: View {
    let transaction: TransactionEntity
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: TransactionEditModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    EditContent(model: model, onDone: { dismiss() })
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Buchung")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("transactionEditSheet")
        .presentationDetents([.large])
        .presentationSizing(.page)
        .task {
            guard model == nil else { return }
            model = TransactionEditModel(transaction: transaction, repository: app.repository,
                                         currentUserId: app.currentUserId)
        }
    }
}

private struct EditContent: View {
    @Bindable var model: TransactionEditModel
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    private var dayBinding: Binding<Date> {
        Binding(get: { CalendarDay.pickerDate(model.day) },
                set: { model.day = CalendarDay.from(pickerDate: $0) })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(model.amount.display)
                    .font(.largeTitle.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(model.amount.isValid ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .accessibilityIdentifier("edit.amount")

                KeypadView(amount: $model.amount)

                Picker("Art", selection: $model.kind) {
                    Text("Ausgabe").tag(Kind.expense)
                    Text("Einnahme").tag(Kind.income)
                }
                .pickerStyle(.segmented)

                CategoryGridView(categories: model.categories, enabled: true,
                                 selectedId: model.categoryId) { category in
                    model.categoryId = category.id
                }

                VStack(spacing: 12) {
                    DatePicker("Datum", selection: dayBinding, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "de_DE"))
                    HStack {
                        Text("Bezahlt von")
                        Spacer()
                        Picker("Bezahlt von", selection: $model.paidBy) {
                            ForEach(model.payerOptions, id: \.id) { Text($0.name).tag($0.id) }
                        }
                        .labelsHidden()
                    }
                    TextField("Notiz", text: $model.note)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("edit.note")
                }

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }

                Button("Löschen", role: .destructive) { confirmDelete = true }
                    .buttonStyle(.bordered)
                    .padding(.top, 8)
                    .accessibilityIdentifier("edit.delete")
            }
            .padding(.horizontal)
            .padding(.bottom)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") { save() }
                    .disabled(!model.canSave)
                    .accessibilityIdentifier("edit.save")
            }
        }
        .confirmationDialog("Buchung löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { delete() }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private func save() {
        do {
            try model.save()
            onDone()
        } catch {
            logger.error("Sichern fehlgeschlagen: \(String(describing: error), privacy: .public)")
            errorMessage = "Die Buchung konnte nicht gespeichert werden."
        }
    }

    private func delete() {
        do {
            try model.delete()
            onDone()
        } catch {
            logger.error("Löschen fehlgeschlagen: \(String(describing: error), privacy: .public)")
            errorMessage = "Die Buchung konnte nicht gelöscht werden."
        }
    }
}
