import os
import SwiftData
import SwiftUI
import HaushaltsbuchCore
import HaushaltsbuchData

private let logger = Logger(subsystem: "de.haushaltsbuch.app", category: "categories")

/// Kategorien je Art: bearbeiten, anlegen, verschieben, entfernen (archivieren oder löschen).
/// Unterkategorien stehen eingerückt unter ihrer Hauptkategorie.
struct CategoriesView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<CategoryEntity> { !$0.softDeleted }, sort: \CategoryEntity.sortOrder)
    private var all: [CategoryEntity]

    @State private var kind: Kind = .expense
    @State private var editing: CategorySheet?
    @State private var message: String?
    @State private var rejected: CategoryEntity?
    @State private var errorMessage: String?

    private var values: [CategoryValue] { all.filter { !$0.deleted }.map(\.value) }
    private var byId: [UUID: CategoryEntity] {
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        let values = values
        let tree = CategoryTree(values)
        let byId = byId
        let rows = CategoryList.activeRows(values, kind: kind)
        let archived = CategoryList.archived(values, kind: kind).compactMap { byId[$0.id] }
        List {
            Section {
                Picker("Art", selection: $kind) {
                    Text("Ausgaben").tag(Kind.expense)
                    Text("Einnahmen").tag(Kind.income)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                ForEach(rows) { row in
                    if let c = byId[row.id] {
                        Button { open(c) } label: {
                            CategoryRow(category: c, label: c.name, colorHex: tree.byId[tree.rootOf(c.id)]?.color ?? c.color)
                                .padding(.leading, row.isChild ? 28 : 0)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(row.isChild ? "categories.subrow" : "categories.row")
                        .swipeActions {
                            if CategoryForm.hasChildren(c.id, in: values) {
                                Button(CategoryForm.removalBlockedText) {}
                                    .disabled(true)
                            } else {
                                Button("Entfernen", role: .destructive) { remove(c) }
                            }
                        }
                    }
                }
                .onMove { move(rows, from: $0, to: $1, archived: archived) }
            } footer: {
                Text("Entfernen archiviert Kategorien mit Buchungen oder wiederkehrenden Buchungen; unbenutzte werden gelöscht. Hauptkategorien mit Unterkategorien lassen sich erst entfernen, wenn diese entfernt sind.")
            }
            if !archived.isEmpty {
                Section("Archiviert") {
                    ForEach(archived) { c in
                        let row = CategoryRow(category: c, label: tree.label(c.id),
                                              colorHex: tree.byId[tree.rootOf(c.id)]?.color ?? c.color)
                        if c.rejectionReason != nil {
                            Button { rejected = c } label: { row.foregroundStyle(.secondary) }
                                .buttonStyle(.plain)
                        } else {
                            row.foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("categories.list")
        .navigationTitle("Kategorien")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { editing = .new(kind) } label: { Label("Neue Kategorie", systemImage: "plus") }
                    .accessibilityIdentifier("categories.add")
                EditButton()
            }
        }
        .sheet(item: $editing) { CategoryEditView(target: $0) }
        .confirmationDialog("Konnte nicht gespeichert werden",
                            isPresented: Binding(get: { rejected != nil }, set: { if !$0 { rejected = nil } }),
                            titleVisibility: .visible, presenting: rejected) { c in
            Button("Bearbeiten") { editing = .edit(c) }
            Button("Verwerfen", role: .destructive) { discard(c) }
            Button("Abbrechen", role: .cancel) {}
        } message: { c in
            Text(RejectionText.german(c.rejectionReason))
        }
        .alert("Fehler", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Kategorie entfernt", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        } message: {
            Text(message ?? "")
        }
    }

    private func open(_ c: CategoryEntity) {
        if c.rejectionReason != nil { rejected = c } else { editing = .edit(c) }
    }

    private func discard(_ c: CategoryEntity) {
        do { try app.repository.discardRejected(c) } catch {
            logger.error("Verwerfen fehlgeschlagen: \(String(describing: error), privacy: .public)")
            errorMessage = "Die Änderung konnte nicht verworfen werden."
        }
    }

    private func move(_ rows: [CategoryList.Row], from source: IndexSet, to destination: Int, archived: [CategoryEntity]) {
        // Unterkategorien nur innerhalb ihrer Hauptkategorie verschieben.
        guard let ids = CategoryList.reordered(rows, from: source, to: destination) else { return }
        let byId = byId
        do {
            try app.repository.moveCategories(ids.compactMap { byId[$0] } + archived)
        } catch {
            logger.error("Verschieben fehlgeschlagen: \(String(describing: error), privacy: .public)")
            message = "Die Reihenfolge konnte nicht gespeichert werden."
        }
    }

    private func remove(_ c: CategoryEntity) {
        do {
            try app.repository.removeCategory(c)
            message = CategoryForm.removalMessage(archived: c.archived && !c.deleted)
        } catch RepositoryError.hasChildren {
            errorMessage = CategoryForm.removalBlockedText
        } catch {
            logger.error("Entfernen fehlgeschlagen: \(String(describing: error), privacy: .public)")
            message = "Die Kategorie konnte nicht entfernt werden."
        }
    }
}

enum CategorySheet: Identifiable {
    case new(Kind)
    case edit(CategoryEntity)

    var id: String {
        switch self {
        case let .new(kind): "new-\(kind.rawValue)"
        case let .edit(c): c.id.uuidString
        }
    }
}

struct CategoryRow: View {
    let category: CategoryEntity
    /// Name bzw. „Wohnen · Strom“.
    let label: String
    /// Farbe der Hauptkategorie (Unterkategorien zeigen sie).
    let colorHex: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.icon)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color(hex: colorHex)))
                .accessibilityHidden(true)
            Text(label)
            Spacer(minLength: 0)
            if let reason = category.rejectionReason {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Konnte nicht gespeichert werden: \(RejectionText.german(reason))")
            }
        }
        .contentShape(Rectangle())
    }
}
