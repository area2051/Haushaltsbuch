import Foundation
import SwiftData

/// Haushaltsmitglied (nur lesend vom Server; nie dirty).
@Model
public final class MemberEntity {
    @Attribute(.unique) public var id: UUID
    public var username: String
    public var displayName: String
    public var isAdmin: Bool
    /// Persistiert als `softDeleted`: der Name `deleted` wird von SwiftData/Core Data überschrieben
    /// (Wert springt nach `save()` auf false zurück).
    public var softDeleted: Bool
    public var deleted: Bool {
        get { softDeleted }
        set { softDeleted = newValue }
    }
    public var version: Int?

    public init(id: UUID, username: String, displayName: String, isAdmin: Bool,
                deleted: Bool = false, version: Int? = nil) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.isAdmin = isAdmin
        self.softDeleted = deleted
        self.version = version
    }
}
