import Foundation

/// Gemeinsame Sync-Felder aller vom Client schreibbaren Entities.
public protocol SyncTracked: AnyObject {
    var id: UUID { get set }
    /// `nil` = nie synchronisiert.
    var version: Int? { get set }
    var deleted: Bool { get set }
    var isDirty: Bool { get set }
    var dirtyGeneration: Int { get set }
    var rejectionReason: String? { get set }
}

extension SyncTracked {
    /// Markiert die Entity als lokal geändert (wird beim nächsten Sync gepusht).
    public func markDirty() {
        isDirty = true
        dirtyGeneration += 1
        rejectionReason = nil
    }
}

import SwiftData

extension SyncTracked where Self: PersistentModel {
    /// Nicht mehr bearbeitbar: hart gelöscht (z. B. Verwerfen, Full-Resync), aus dem Kontext entfernt
    /// oder soft-gelöscht (z. B. per Sync von einem anderen Gerät). Die Reihenfolge der Prüfungen
    /// zählt: Felder eines hart gelöschten Objekts werden nicht mehr gelesen.
    public var isGone: Bool {
        isDeleted || modelContext == nil || deleted
    }
}
