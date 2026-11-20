import os
import SwiftUI
import UIKit
import HaushaltsbuchCore
import HaushaltsbuchData

/// Schnellerfassung als Sheet: Betrag tippen, Kategorie tippen, fertig.
private let logger = Logger(subsystem: "de.haushaltsbuch.app", category: "quickEntry")

struct QuickEntryView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: QuickEntryModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    QuickEntryContent(model: model, onSaved: finish)
                } else if app.currentUserId == nil {
                    ContentUnavailableView("Benutzer unbekannt – bitte neu anmelden.",
                                           systemImage: "person.crop.circle.badge.exclamationmark")
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Neue Buchung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("quickEntrySheet")
        .presentationDetents([.large])
        .presentationSizing(.page)
        .task {
            guard model == nil, let userId = app.currentUserId else { return }
            model = QuickEntryModel(repository: app.repository, currentUserId: userId)
        }
    }

    private func finish() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

private struct QuickEntryContent: View {
    @Bindable var model: QuickEntryModel
    let onSaved: () -> Void
    @State private var errorMessage: String?

    private var dayBinding: Binding<Date> {
        Binding(
            get: { CalendarDay.pickerDate(model.day) },
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
                    .foregroundStyle(model.canSave ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .accessibilityIdentifier("quickEntry.amount")

                KeypadView(amount: $model.amount)

                CategoryGridView(categories: model.categories, enabled: model.canSave,
                                 selectedId: model.chipParentId) { category in
                    attempt { try model.tapCategory(category.id) }
                }

                if !model.chipOptions.isEmpty {
                    // Ein Chip-Tipp speichert sofort („Allgemein“ = die Hauptkategorie selbst).
                    SubcategoryChipsView(options: model.chipOptions, selectedId: nil,
                                         caption: "Unterkategorie antippen zum Speichern") { id in
                        attempt { try model.save(category: id); return true }
                    }
                    .disabled(!model.canSave)
                    .opacity(model.canSave ? 1 : 0.4)
                }

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }

                details
            }
            .padding(.horizontal)
            .padding(.bottom)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    /// Führt einen Speicherversuch aus; `true` aus `action` = gespeichert, Sheet schließen.
    private func attempt(_ action: () throws -> Bool) {
        errorMessage = nil
        do {
            if try action() { onSaved() }
        } catch {
            logger.error("Speichern fehlgeschlagen: \(String(describing: error), privacy: .public)")
            if case let RepositoryError.invalid(message) = error {
                errorMessage = message
            } else {
                errorMessage = model.repeatRhythm == nil
                    ? "Die Buchung konnte nicht gespeichert werden."
                    : "Die wiederkehrende Buchung konnte nicht gespeichert werden."
            }
        }
    }

    private var details: some View {
        DisclosureGroup(isExpanded: $model.detailsExpanded) {
            VStack(spacing: 12) {
                Picker("Art", selection: $model.kind) {
                    Text("Ausgabe").tag(Kind.expense)
                    Text("Einnahme").tag(Kind.income)
                }
                .pickerStyle(.segmented)

                DatePicker("Datum", selection: dayBinding, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "de_DE"))

                // Gesetzt: Speichern legt eine wiederkehrende Regel ab diesem Datum an.
                RhythmPickerView(rhythm: $model.repeatRhythm, allowNone: true)

                HStack {
                    Text("Bezahlt von")
                    Spacer()
                    Picker("Bezahlt von", selection: $model.paidBy) {
                        ForEach(model.payerOptions, id: \.id) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                    .labelsHidden()
                }

                TextField("Notiz", text: $model.note)
                    .textFieldStyle(.roundedBorder)
                    .limitNote($model.note)
            }
            .padding(.top, 8)
        } label: {
            Text("Details").font(.headline)
        }
        .accessibilityIdentifier("quickEntry.details")
    }
}
