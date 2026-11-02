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

                CategoryGridView(categories: model.categories, enabled: model.canSave) { category in
                    errorMessage = nil
                    do {
                        try model.save(category: category.id)
                        onSaved()
                    } catch {
                        logger.error("Speichern fehlgeschlagen: \(String(describing: error), privacy: .public)")
                        errorMessage = "Die Buchung konnte nicht gespeichert werden."
                    }
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
            }
            .padding(.top, 8)
        } label: {
            Text("Details").font(.headline)
        }
        .accessibilityIdentifier("quickEntry.details")
    }
}
