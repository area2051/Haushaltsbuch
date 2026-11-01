import Foundation
import SwiftData
import HaushaltsbuchCore

@Model
public final class CategoryEntity: SyncTracked {
    @Attribute(.unique) public var id: UUID
    public var version: Int?
    /// Persistiert als `softDeleted`: der Name `deleted` wird von SwiftData/Core Data überschrieben
    /// (Wert springt nach `save()` auf false zurück).
    public var softDeleted: Bool
    public var deleted: Bool {
        get { softDeleted }
        set { softDeleted = newValue }
    }
    public var isDirty: Bool
    public var dirtyGeneration: Int
    public var rejectionReason: String?

    public var name: String
    public var icon: String
    public var color: String
    /// `Kind.rawValue`
    public var kind: String
    public var sortOrder: Int
    public var archived: Bool

    public init(id: UUID = UUID(), name: String, icon: String, color: String, kind: Kind,
                sortOrder: Int, archived: Bool = false, version: Int? = nil,
                deleted: Bool = false, isDirty: Bool = false) {
        self.id = id
        self.version = version
        self.softDeleted = deleted
        self.isDirty = isDirty
        self.dirtyGeneration = 0
        self.rejectionReason = nil
        self.name = name
        self.icon = icon
        self.color = color
        self.kind = kind.rawValue
        self.sortOrder = sortOrder
        self.archived = archived
    }

    public var kindValue: Kind { Kind(rawValue: kind) ?? .expense }

    public var value: CategoryValue {
        CategoryValue(id: id, name: name, icon: icon, color: color, kind: kindValue,
                      sortOrder: sortOrder, archived: archived)
    }
}
