import os
import SwiftData
import SwiftUI
import HaushaltsbuchCore
import HaushaltsbuchData

private let logger = Logger(subsystem: "de.haushaltsbuch.app", category: "ruleEdit")

/// Anlegen/Bearbeiten einer wiederkehrenden Buchung (Sheet).
struct RuleEditView: View {
    let target: RuleSheet
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: RuleEditModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    RuleForm(model: model, onDone: { dismiss() })
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(model?.isNew == false ? "Wiederkehrende Buchung" : "Neue wiederkehrende Buchung")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("ruleEditSheet")
        .presentationDetents([.large])
        .presentationSizing(.page)
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            if case let .edit(r) = target, r.isGone { dismiss() }
        }
        .task {
            guard model == nil else { return }
            let rule: RecurringRuleEntity? = if case let .edit(r) = target { r } else { nil }
            if let rule, rule.isGone { dismiss(); return }
            model = RuleEditModel(rule: rule, repository: app.repository, currentUserId: app.currentUserId)
        }
    }
}

private struct RuleForm: View {
    @Bindable var model: RuleEditModel
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    private func dateBinding(_ keyPath: ReferenceWritableKeyPath<RuleEditModel, CalendarDay>) -> Binding<Date> {
        Binding(get: { CalendarDay.pickerDate(model[keyPath: keyPath]) },
                set: { model[keyPath: keyPath] = CalendarDay.from(pickerDate: $0) })
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
                    .accessibilityIdentifier("rule.amount")

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
                    Picker("Häufigkeit", selection: $model.frequency) {
                        ForEach(Frequency.allCases, id: \.self) { Text(RuleFormat.frequency($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("rule.frequency")
                    DatePicker("Start", selection: dateBinding(\.startDate), displayedComponents: .date)
                    Toggle("Enddatum", isOn: $model.hasEndDate)
                    if model.hasEndDate {
                        DatePicker("Ende", selection: dateBinding(\.endDate), displayedComponents: .date)
                    }
                    HStack {
                        Text("Bezahlt von")
                        Spacer()
                        Picker("Bezahlt von", selection: $model.paidBy) {
                            ForEach(model.payerOptions, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                        }
                        .labelsHidden()
                    }
                    TextField("Notiz, z. B. Miete", text: $model.note)
                        .textFieldStyle(.roundedBorder)
                        .limitNote($model.note)
                        .accessibilityIdentifier("rule.note")
                }
                .environment(\.locale, Locale(identifier: "de_DE"))

                if let message = model.validationMessage, model.amount.isValid {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
                Text("Die Buchungen erzeugt der Server – ab dem Start bis heute sofort nach dem nächsten Sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if !model.isNew {
                    Button("Löschen", role: .destructive) { confirmDelete = true }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("rule.delete")
                }
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
                    .accessibilityIdentifier("rule.save")
            }
        }
        .confirmationDialog("Wiederkehrende Buchung löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { delete() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Bereits erzeugte Buchungen bleiben erhalten.")
        }
    }

    private func save() {
        do {
            try model.save()
            onDone()
        } catch RepositoryError.invalid(let message) {
            errorMessage = message
        } catch {
            logger.error("Regel sichern fehlgeschlagen: \(String(describing: error), privacy: .public)")
            errorMessage = "Die wiederkehrende Buchung konnte nicht gespeichert werden."
        }
    }

    private func delete() {
        do {
            try model.delete()
            onDone()
        } catch {
            logger.error("Regel löschen fehlgeschlagen: \(String(describing: error), privacy: .public)")
            errorMessage = "Die wiederkehrende Buchung konnte nicht gelöscht werden."
        }
    }
}
