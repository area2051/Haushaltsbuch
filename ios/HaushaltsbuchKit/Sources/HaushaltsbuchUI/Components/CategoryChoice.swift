import Foundation
import HaushaltsbuchCore

/// Ein Chip unter einer Hauptkategorie: „Allgemein“ (= die Hauptkategorie selbst) oder eine Unterkategorie.
struct SubcategoryOption: Equatable, Identifiable {
    var id: UUID
    var name: String
}

/// Auswahl Hauptkategorie (Raster) + Unterkategorie (Chips), wie im Web.
/// `keep`: bisherige Kategorie eines Formulars – bleibt wählbar, auch archiviert (bzw. Kind einer
/// archivierten Hauptkategorie), damit der aktuelle Wert sichtbar bleibt.
struct CategoryChoice {
    let tree: CategoryTree
    var keep: UUID?

    init(_ categories: [CategoryValue], keep: UUID? = nil) {
        tree = CategoryTree(categories)
        self.keep = keep
    }

    /// Hauptkategorien der Art (wählbar oder Hauptkategorie von `keep`), nach `sortOrder`, dann Name.
    func mains(kind: Kind) -> [CategoryValue] {
        let keptRoot = keep.map(tree.rootOf)
        return tree.byId.values
            .filter { $0.kind == kind && tree.rootOf($0.id) == $0.id && (!$0.archived || $0.id == keptRoot) }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    /// „Allgemein“ + wählbare Unterkategorien (und `keep`, falls es eine Unterkategorie von `parentId` ist);
    /// leer, wenn es keine Unterkategorie zur Auswahl gibt.
    func chips(for parentId: UUID) -> [SubcategoryOption] {
        let children = tree.childrenOf(parentId).filter { tree.isSelectable($0) || $0.id == keep }
        guard !children.isEmpty else { return [] }
        return [SubcategoryOption(id: parentId, name: "Allgemein")]
            + children.map { SubcategoryOption(id: $0.id, name: $0.name) }
    }

    /// Hauptkategorie aus `mains(kind:)` oder einer ihrer Chips.
    func isValid(_ id: UUID, kind: Kind) -> Bool {
        let main = tree.rootOf(id)
        guard mains(kind: kind).contains(where: { $0.id == main }) else { return false }
        return id == main || chips(for: main).contains { $0.id == id }
    }
}
