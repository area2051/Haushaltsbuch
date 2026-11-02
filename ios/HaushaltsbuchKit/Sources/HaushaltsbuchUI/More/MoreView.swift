import SwiftUI
import HaushaltsbuchData

/// „Mehr“ (Spec §7): Kategorien, Wiederkehrende, Export, Mitglieder (Admin), Server & Sync,
/// Face-ID-Sperre, Abmelden.
struct MoreView: View {
    @Environment(AppModel.self) private var app
    @State private var loggingOut = false
    @State private var discardPending: PendingChanges?
    @State private var failure: String?

    var body: some View {
        List {
            Section("Haushalt") {
                NavigationLink { CategoriesView() } label: {
                    Label("Kategorien", systemImage: "square.grid.2x2")
                }
                .accessibilityIdentifier("more.categories")
                NavigationLink { RecurringRulesView() } label: {
                    Label("Wiederkehrende Buchungen", systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("more.rules")
                NavigationLink { ExportView() } label: {
                    Label("CSV-Export", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("more.export")
                if app.session?.isAdmin == true {
                    NavigationLink { MembersView() } label: {
                        Label("Mitglieder", systemImage: "person.2")
                    }
                    .accessibilityIdentifier("more.members")
                }
            }
            Section {
                NavigationLink { ServerStatusView() } label: {
                    Label("Server & Sync", systemImage: "server.rack")
                }
                .accessibilityIdentifier("more.server")
                AppLockToggle(lock: app.appLock)
            } header: {
                Text("App")
            } footer: {
                Text("Mit Face-ID-Sperre wird die App gesperrt, sobald sie in den Hintergrund geht.")
            }
            Section {
                Button(role: .destructive) {
                    logout(discard: false)
                } label: {
                    HStack {
                        Text("Abmelden")
                        if loggingOut {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(loggingOut)
                .accessibilityIdentifier("more.logout")
                .confirmationDialog(
                    discardPending.map { ServerStatusText.logoutWarning($0.unsent, rejected: $0.rejected) } ?? "",
                    isPresented: Binding(get: { discardPending != nil }, set: { if !$0 { discardPending = nil } }),
                    titleVisibility: .visible
                ) {
                    Button("Trotzdem abmelden", role: .destructive) { logout(discard: true) }
                    Button("Abbrechen", role: .cancel) {}
                } message: {
                    Text(discardPending.map { ServerStatusText.logoutDetail($0.unsent, rejected: $0.rejected) } ?? "")
                }
            }
        }
        .navigationTitle("Mehr")
        .alert("Abmelden nicht möglich", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") {}
        } message: {
            Text(failure ?? "")
        }
    }

    private func logout(discard: Bool) {
        loggingOut = true
        Task {
            let outcome = await app.logout(discardPending: discard)
            loggingOut = false
            switch outcome {
            case let .needsDiscardConfirmation(pending, rejected):
                discardPending = PendingChanges(unsent: pending, rejected: rejected)
            case let .failed(message):
                failure = message
            case .loggedOut:
                break
            }
        }
    }
}

private struct AppLockToggle: View {
    @ObservedObject var lock: AppLock
    @State private var message: String?

    var body: some View {
        Toggle(isOn: Binding(get: { lock.isEnabled }, set: { message = lock.setEnabled($0) })) {
            Label("Face-ID-Sperre", systemImage: "faceid")
        }
        .accessibilityIdentifier("more.faceID")
        .alert("Face-ID-Sperre", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        } message: {
            Text(message ?? "")
        }
    }
}
