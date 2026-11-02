import os
import SwiftData
import SwiftUI
import HaushaltsbuchCore
import HaushaltsbuchData

private let logger = Logger(subsystem: "de.haushaltsbuch.app", category: "export")

/// CSV-Export aus den lokalen Daten über das Teilen-Menü (Spec §7 „CSV-Export“).
struct ExportView: View {
    @Query(filter: #Predicate<TransactionEntity> { !$0.softDeleted })
    private var entities: [TransactionEntity]
    /// Auch gelöschte/archivierte: alte Buchungen behalten ihren Kategorie- bzw. Personennamen.
    @Query private var categories: [CategoryEntity]
    @Query private var members: [MemberEntity]

    @State private var period: ExportPeriod = .thisMonth
    @State private var customFrom = CalendarDay.today().monthKey.firstDay
    @State private var customTo = CalendarDay.today()
    @State private var fileURL: URL?
    @State private var errorMessage: String?

    private var range: ExportRange? {
        period.range(today: .today(), customFrom: customFrom, customTo: customTo)
    }

    private var txs: [TxValue] { TransactionListModel.activeValues(of: entities) }

    /// Neu schreiben bei anderem Zeitraum oder geänderten Buchungen.
    private var fileKey: String {
        let r = range.map { "\($0.from.string)_\($0.to.string)" } ?? "-"
        let stamp = entities.reduce(0) { $0 &+ ($1.version ?? 0) &+ $1.dirtyGeneration }
        return "\(r)|\(entities.count)|\(stamp)"
    }

    private func dateBinding(_ value: Binding<CalendarDay>) -> Binding<Date> {
        Binding(get: { CalendarDay.pickerDate(value.wrappedValue) },
                set: { value.wrappedValue = CalendarDay.from(pickerDate: $0) })
    }

    var body: some View {
        Form {
            Section("Zeitraum") {
                Picker("Zeitraum", selection: $period) {
                    ForEach(ExportPeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("export.period")
                if period == .custom {
                    DatePicker("Von", selection: dateBinding($customFrom), displayedComponents: .date)
                    DatePicker("Bis", selection: dateBinding($customTo), displayedComponents: .date)
                }
            }
            .environment(\.locale, Locale(identifier: "de_DE"))
            Section {
                if let range {
                    LabeledContent("Von", value: RuleFormat.date(range.from))
                    LabeledContent("Bis", value: RuleFormat.date(range.to))
                    LabeledContent("Buchungen", value: "\(ExportModel.rowCount(txs: txs, range: range))")
                        .accessibilityIdentifier("export.count")
                } else {
                    Text("Das Ende darf nicht vor dem Start liegen.").foregroundStyle(.red)
                }
            }
            Section {
                if let fileURL, range != nil {
                    ShareLink(item: fileURL) {
                        Label("CSV teilen", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("export.share")
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            } footer: {
                Text("Semikolon-getrennt, Dezimalkomma, UTF-8 – öffnet sich direkt in Excel und Numbers.")
            }
        }
        .navigationTitle("CSV-Export")
        .task(id: fileKey) { writeFile() }
    }

    private func writeFile() {
        guard let range else {
            fileURL = nil
            return
        }
        let names = Dictionary(members.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        do {
            fileURL = try ExportModel.writeFile(txs: txs, categories: categories.map(\.value),
                                                members: names, range: range)
            errorMessage = nil
        } catch {
            logger.error("Export fehlgeschlagen: \(String(describing: error), privacy: .public)")
            fileURL = nil
            errorMessage = "Die Exportdatei konnte nicht erstellt werden."
        }
    }
}

extension MonthKey {
    var firstDay: CalendarDay { CalendarDay(year: year, month: month, day: 1)! }
}
