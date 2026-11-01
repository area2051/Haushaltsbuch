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
