import SwiftUI
import HaushaltsbuchData

/// Sync-Hinweis nur bei Problemen (Spec §7 „Allgemein“): offline oder Fehler.
public struct SyncStatusBanner: View {
    @ObservedObject var engine: SyncEngine

    public init(engine: SyncEngine) {
        self.engine = engine
    }

    /// Text für den Status; `nil` = kein Hinweis.
    nonisolated static func message(for status: SyncStatus) -> String? {
        let pending: Int
        switch status {
        case let .offline(p), let .error(_, p): pending = p
        case .idle, .syncing, .upToDate: return nil
        }
        let changes = pending == 1 ? "1 Änderung" : "\(pending) Änderungen"
        return "Nicht mit NAS verbunden – \(changes) ausstehend"
    }

    public var body: some View {
        if let message = Self.message(for: engine.status) {
            VStack(alignment: .leading, spacing: 2) {
                Label(message, systemImage: "wifi.exclamationmark")
                    .font(.footnote.weight(.semibold))
                if case let .error(detail, _) = engine.status {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.orange.opacity(0.2))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("syncStatusBanner")
        }
    }
}
