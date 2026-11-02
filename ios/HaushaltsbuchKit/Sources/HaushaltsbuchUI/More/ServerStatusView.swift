import SwiftData
import SwiftUI
import HaushaltsbuchData

/// Server-Adresse, angemeldeter Benutzer, Sync-Status, ausstehende Änderungen, „Jetzt synchronisieren“.
struct ServerStatusView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<MemberEntity> { !$0.softDeleted })
    private var members: [MemberEntity]

    var body: some View {
        List {
            if let session = app.session {
                Section("Server") {
                    LabeledContent("Adresse", value: session.serverURL.absoluteString)
                        .accessibilityIdentifier("server.url")
                    Text("Angemeldet als \(displayName(session))")
                        .accessibilityIdentifier("server.user")
                    LabeledContent("Rolle", value: session.isAdmin ? "Admin" : "Mitglied")
                }
            }
            if let engine = app.engine {
                SyncSection(engine: engine) { await app.pullToRefresh() }
            }
        }
        .navigationTitle("Server & Sync")
    }

    private func displayName(_ session: StoredSession) -> String {
        guard let me = members.first(where: { $0.id == session.userId }) else { return session.username }
        return "\(me.displayName) (\(session.username))"
    }
}

private struct SyncSection: View {
    @ObservedObject var engine: SyncEngine
    /// Über den Scheduler (Backoff-Auswertung, endet mit dem Abmelden).
    let syncNow: () async -> Void

    var body: some View {
        Section("Synchronisation") {
            LabeledContent("Status", value: ServerStatusText.status(engine.status))
                .accessibilityIdentifier("server.status")
            LabeledContent("Ausstehend", value: ServerStatusText.pending(engine.pendingCount))
                .accessibilityIdentifier("server.pending")
            Button {
                Task { await syncNow() }
            } label: {
                Label("Jetzt synchronisieren", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(engine.status == .syncing)
            .accessibilityIdentifier("server.syncNow")
        }
    }
}
