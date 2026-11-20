import os
import SwiftData
import SwiftUI
import HaushaltsbuchCore
import HaushaltsbuchData

private let logger = Logger(subsystem: "de.haushaltsbuch.app", category: "categoryEdit")

/// Name, Symbol, Farbe und Hauptkategorie („Gehört zu“) einer Kategorie; die Art ist nach dem Anlegen fest.
/// Unterkategorien übernehmen die Farbe der Hauptkategorie.
struct CategoryEditView: View {
    let target: CategorySheet
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<CategoryEntity> { !$0.softDeleted }, sort: \CategoryEntity.sortOrder)
    private var categories: [CategoryEntity]
    @Query(filter: #Predicate<BudgetEntity> { !$0.softDeleted })
    private var budgets: [BudgetEntity]

    @State private var name = ""
    @State private var icon = CategoryForm.symbols[0]
    @State private var color = CategoryForm.palette[8]
    @State private var kind: Kind = .expense
    @State private var parentId: UUID?
    @State private var loaded = false
    @State private var errorMessage: String?

    private var existing: CategoryEntity? {
        if case let .edit(c) = target { c } else { nil }
    }

    private var symbols: [String] {
        CategoryForm.symbols.contains(icon) ? CategoryForm.symbols : [icon] + CategoryForm.symbols
    }

    private var colors: [String] {
        CategoryForm.palette.contains(color) ? CategoryForm.palette : CategoryForm.palette + [color]
    }

    private let grid = [GridItem(.adaptive(minimum: 44), spacing: 10)]

    /// Werte der bearbeiteten Kategorie (nicht mehr lesen, wenn sie inzwischen weg ist).
    private var existingValue: CategoryValue? { existing.flatMap { $0.isGone ? nil : $0.value } }

    private var all: [CategoryValue] { categories.filter { !$0.deleted }.map(\.value) }
    private var parent: CategoryValue? { parentId.flatMap { id in all.first { $0.id == id } } }

    /// Mögliche Hauptkategorien; die aktuelle bleibt gelistet, auch wenn sie inzwischen archiviert ist.
    private var parents: [CategoryValue] {
        let options = CategoryForm.parentOptions(for: existingValue, all: all, kind: kind)
        guard let parent, !options.contains(where: { $0.id == parent.id }) else { return options }
        return [parent] + options
    }

    private var budgetHint: String? {
        guard let existingValue else { return nil }
        return CategoryForm.budgetHint(for: existingValue, parent: parent,
                                       budgets: BudgetEntity.onePerCategory(budgets).map(\.value))
    }

    private var shownColor: String { parent?.color ?? color }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: icon)
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(Color(hex: shownColor)))
                            .accessibilityHidden(true)
                        TextField("Name", text: $name)
                            .accessibilityIdentifier("category.name")
                    }
                    if existing == nil {
                        Picker("Art", selection: $kind) {
                            Text("Ausgabe").tag(Kind.expense)
                            Text("Einnahme").tag(Kind.income)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: kind) { parentId = nil }
                    } else {
                        LabeledContent("Art", value: kind == .income ? "Einnahme" : "Ausgabe")
                    }
                } footer: {
                    if let message = CategoryForm.validationMessage(name: name), !name.isEmpty {
                        Text(message).foregroundStyle(.red)
                    }
                }
                if !parents.isEmpty || parentId != nil {
                    Section {
                        Picker("Gehört zu", selection: $parentId) {
                            Text("Keine (Hauptkategorie)").tag(UUID?.none)
                            ForEach(parents, id: \.id) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                        .accessibilityIdentifier("category.parent")
                    } footer: {
                        if let budgetHint { Text(budgetHint) }
                    }
                }
                Section("Symbol") {
                    LazyVGrid(columns: grid, spacing: 10) {
                        ForEach(symbols, id: \.self) { symbol in
                            Button { icon = symbol } label: {
                                Image(systemName: symbol)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(RoundedRectangle(cornerRadius: 10)
                                        .fill(symbol == icon ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                            .accessibilityAddTraits(symbol == icon ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
                // Unterkategorien zeigen die Farbe ihrer Hauptkategorie.
                if parent == nil {
                    Section("Farbe") {
                        LazyVGrid(columns: grid, spacing: 10) {
                            ForEach(colors, id: \.self) { hex in
                                Button { color = hex } label: {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 36, height: 36)
                                        .overlay(Circle().strokeBorder(Color.primary, lineWidth: hex == color ? 3 : 0).padding(-4))
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Farbe \(hex)")
                                .accessibilityAddTraits(hex == color ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle(existing == nil ? "Neue Kategorie" : "Kategorie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(CategoryForm.validationMessage(name: name) != nil)
                        .accessibilityIdentifier("category.save")
                }
            }
        }
        .accessibilityIdentifier("categoryEditSheet")
        .onAppear(perform: load)
        // Kategorie inzwischen gelöscht (z. B. per Sync): Sheet schließen statt sie anzufassen.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            if existing?.isGone == true { dismiss() }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch target {
        case let .new(k):
            kind = k
        case let .edit(c):
            guard !c.isGone else { dismiss(); return }
            name = c.name
            icon = c.icon
            color = c.color
            kind = c.kindValue
            parentId = c.parentId
        }
    }

    private func save() {
        if existing?.isGone == true { dismiss(); return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try app.repository.saveCategory(CategoryDraft(id: existing?.id, name: trimmed, icon: icon,
                                                          color: shownColor, kind: existing?.kindValue ?? kind,
                                                          parentId: parentId))
            dismiss()
        } catch {
            logger.error("Kategorie speichern fehlgeschlagen: \(String(describing: error), privacy: .public)")
            errorMessage = "Die Kategorie konnte nicht gespeichert werden."
        }
    }
}
