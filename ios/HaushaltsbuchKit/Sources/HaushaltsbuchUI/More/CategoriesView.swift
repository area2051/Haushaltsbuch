import os
import SwiftData
import SwiftUI
import HaushaltsbuchCore
import HaushaltsbuchData

private let logger = Logger(subsystem: "de.haushaltsbuch.app", category: "categories")

/// Kategorien je Art: bearbeiten, anlegen, verschieben, entfernen (archivieren oder löschen).
struct CategoriesView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<CategoryEntity> { !$0.softDeleted }, sort: \CategoryEntity.sortOrder)
    private var all: [CategoryEntity]

    @State private var kind: Kind = .expense
    @State private var editing: CategorySheet?
    @State private var message: String?
    @State private var rejected: CategoryEntity?
    @State private var errorMessage: String?

    private var ofKind: [CategoryEntity] {
        all.filter { !$0.deleted && $0.kindValue == kind }
    }
    private var active: [CategoryEntity] { ofKind.filter { !$0.archived } }
    private var archived: [CategoryEntity] { ofKind.filter(\.archived) }

    var body: some View {
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
                ForEach(active) { c in
                    Button { open(c) } label: { CategoryRow(category: c) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("categories.row")
                        .swipeActions {
                            Button("Entfernen", role: .destructive) { remove(c) }
                        }
                }
                .onMove(perform: move)
            } footer: {
                Text("Entfernen archiviert Kategorien mit Buchungen oder wiederkehrenden Buchungen; unbenutzte werden gelöscht.")
            }
            if !archived.isEmpty {
                Section("Archiviert") {
                    ForEach(archived) { c in
                        if c.rejectionReason != nil {
                            Button { rejected = c } label: { CategoryRow(category: c).foregroundStyle(.secondary) }
                                .buttonStyle(.plain)
                        } else {
                            CategoryRow(category: c).foregroundStyle(.secondary)
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
            Text(c.rejectionReason ?? "")
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

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = active
        ordered.move(fromOffsets: source, toOffset: destination)
        do {
            try app.repository.moveCategories(ordered + archived)
        } catch {
            logger.error("Verschieben fehlgeschlagen: \(String(describing: error), privacy: .public)")
            message = "Die Reihenfolge konnte nicht gespeichert werden."
        }
    }

    private func remove(_ c: CategoryEntity) {
        do {
            try app.repository.removeCategory(c)
            message = CategoryForm.removalMessage(archived: c.archived && !c.deleted)
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.icon)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color(hex: category.color)))
                .accessibilityHidden(true)
            Text(category.name)
            Spacer(minLength: 0)
            if let reason = category.rejectionReason {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Vom Server abgelehnt: \(reason)")
            }
        }
        .contentShape(Rectangle())
    }
}
