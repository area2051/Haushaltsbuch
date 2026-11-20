import Foundation

/// Haupt- und Unterkategorien (genau eine Ebene) als Nachschlagestruktur.
public struct CategoryTree: Sendable {
    public let byId: [UUID: CategoryValue]
    private let children: [UUID: [CategoryValue]]

    public init(_ cats: [CategoryValue]) {
        byId = Dictionary(cats.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var children: [UUID: [CategoryValue]] = [:]
        for c in byId.values {
            if let parentId = c.parentId { children[parentId, default: []].append(c) }
        }
        self.children = children.mapValues { $0.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) } }
    }

    private func parent(of c: CategoryValue?) -> CategoryValue? {
        c?.parentId.flatMap { byId[$0] }
    }

    /// Hauptkategorie von `id` (sie selbst bei Hauptkategorien und unbekannten IDs).
    public func rootOf(_ id: UUID) -> UUID {
        parent(of: byId[id])?.id ?? id
    }

    /// Direkte Unterkategorien, nach `sortOrder`, dann Name.
    public func childrenOf(_ id: UUID) -> [CategoryValue] {
        children[id] ?? []
    }

    /// „Wohnen · Strom“, der Name einer Hauptkategorie, „Unbekannt“ für unbekannte IDs.
    public func label(_ id: UUID) -> String {
        guard let c = byId[id] else { return "Unbekannt" }
        guard let p = parent(of: c) else { return c.name }
        return "\(p.name) · \(c.name)"
    }

    /// Nicht archiviert und die Hauptkategorie (falls vorhanden) auch nicht.
    public func isSelectable(_ c: CategoryValue) -> Bool {
        !c.archived && !(parent(of: c)?.archived ?? false)
    }
}
