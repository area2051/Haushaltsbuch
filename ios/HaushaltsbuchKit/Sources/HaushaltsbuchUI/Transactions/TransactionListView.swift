import os
import SwiftData
import SwiftUI
import HaushaltsbuchCore
import HaushaltsbuchData

private let logger = Logger(subsystem: "de.haushaltsbuch.app", category: "transactions")

/// Buchungsliste, nach Tag gruppiert. `@Query` hält die Liste aktuell, wenn der Sync Datensätze schreibt.
struct TransactionListView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TransactionEntity> { !$0.softDeleted },
           sort: \TransactionEntity.day, order: .reverse)
    private var entities: [TransactionEntity]
    @Query(filter: #Predicate<CategoryEntity> { !$0.softDeleted })
    private var categoryEntities: [CategoryEntity]
    @Query(filter: #Predicate<MemberEntity> { !$0.softDeleted })
    private var members: [MemberEntity]

    @State private var filter = TransactionFilter()
    @State private var editing: TransactionEntity?
    @State private var rejected: TransactionEntity?
    @State private var errorMessage: String?

    private var categories: [UUID: CategoryValue] {
        Dictionary(categoryEntities.map { ($0.id, $0.value) }, uniquingKeysWith: { a, _ in a })
    }

    private var memberNames: [UUID: String] {
        Dictionary(members.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        let categories = categories
        let names = memberNames
        let byId = Dictionary(entities.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let sections = TransactionListModel.sections(
            TransactionListModel.activeValues(of: entities), filter: filter, categories: categories)
        let today = CalendarDay.today()

        List {
            ForEach(sections, id: \.day) { section in
                Section(TransactionListModel.header(for: section.day, today: today)) {
                    ForEach(section.items, id: \.id) { tx in
                        if let entity = byId[tx.id] {
                            row(tx, entity: entity, categories: categories, names: names)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("transactions.list")
        .overlay {
            if entities.isEmpty {
                ContentUnavailableView("Noch keine Buchungen", systemImage: "list.bullet",
                                       description: Text("Mit „+“ eine Buchung erfassen."))
            } else if sections.isEmpty {
                ContentUnavailableView("Keine Treffer", systemImage: "magnifyingglass",
                                       description: Text("Suche oder Filter anpassen."))
            }
        }
        .refreshable { await app.pullToRefresh() }
        .searchable(text: $filter.search, prompt: "Suchen")
        .navigationTitle("Buchungen")
        .toolbar { ToolbarItem(placement: .secondaryAction) { filterMenu(categories: categories) } }
        .sheet(item: $editing) { entity in
            TransactionEditView(transaction: entity)
        }
        .confirmationDialog("Konnte nicht gespeichert werden",
                            isPresented: Binding(get: { rejected != nil }, set: { if !$0 { rejected = nil } }),
                            titleVisibility: .visible, presenting: rejected) { entity in
            Button("Bearbeiten") { editing = entity }
            Button("Verwerfen", role: .destructive) { discard(entity) }
            Button("Abbrechen", role: .cancel) {}
        } message: { entity in
            Text(RejectionText.german(entity.rejectionReason))
        }
        .alert("Fehler", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func row(_ tx: TxValue, entity: TransactionEntity, categories: [UUID: CategoryValue],
                     names: [UUID: String]) -> some View {
        Button {
            if entity.rejectionReason != nil { rejected = entity } else { editing = entity }
        } label: {
            TransactionRow(tx: tx, category: categories[tx.categoryId], payerName: names[tx.paidBy],
                           rejectionReason: entity.rejectionReason)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete(entity)
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .accessibilityIdentifier("transactions.row")
    }

    private func filterMenu(categories: [UUID: CategoryValue]) -> some View {
        let sortedCategories = categories.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return Menu {
            Picker("Art", selection: $filter.kind) {
                Text("Alle").tag(Kind?.none)
                Text("Ausgaben").tag(Kind?.some(.expense))
                Text("Einnahmen").tag(Kind?.some(.income))
            }
            Picker("Kategorie", selection: $filter.categoryId) {
                Text("Alle").tag(UUID?.none)
                ForEach(sortedCategories, id: \.id) { Text($0.name).tag(UUID?.some($0.id)) }
            }
            Picker("Person", selection: $filter.paidBy) {
                Text("Alle").tag(UUID?.none)
                ForEach(members.sorted { $0.displayName < $1.displayName }, id: \.id) {
                    Text($0.displayName).tag(UUID?.some($0.id))
                }
            }
            if filter.isActive {
                Button("Filter zurücksetzen", role: .destructive) {
                    filter.kind = nil
                    filter.categoryId = nil
                    filter.paidBy = nil
                }
            }
        } label: {
            Label("Filter", systemImage: filter.isActive
                  ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("transactions.filter")
    }

    private func delete(_ entity: TransactionEntity) {
        do { try app.repository.delete(entity) } catch {
            logger.error("Löschen fehlgeschlagen: \(String(describing: error), privacy: .public)")
            errorMessage = "Die Buchung konnte nicht gelöscht werden."
        }
    }

    private func discard(_ entity: TransactionEntity) {
        do { try app.repository.discardRejected(entity) } catch {
            logger.error("Verwerfen fehlgeschlagen: \(String(describing: error), privacy: .public)")
            errorMessage = "Die Änderung konnte nicht verworfen werden."
        }
    }
}

extension TransactionEntity: Identifiable {}
