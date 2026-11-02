import SwiftUI
import HaushaltsbuchData

/// Mitgliederverwaltung (nur Admins, nur online).
struct MembersView: View {
    @Environment(AppModel.self) private var app
    @State private var members: [MemberInfo] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var editing: MemberSheet?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("members.error")
                    Button("Erneut versuchen") { Task { await load() } }
                }
            }
            Section {
                ForEach(members) { member in
                    Button { editing = .edit(member) } label: { row(member) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("members.row")
                }
            }
        }
        .overlay {
            if loading && members.isEmpty { ProgressView() }
        }
        .refreshable { await load() }
        .navigationTitle("Mitglieder")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = .new } label: { Label("Neues Mitglied", systemImage: "person.badge.plus") }
                    .disabled(errorMessage != nil && members.isEmpty)
                    .accessibilityIdentifier("members.add")
            }
        }
        .sheet(item: $editing) { target in
            MemberEditView(target: target, isSelf: target.member?.id == app.currentUserId) {
                // Änderung am Server: Liste neu laden und Sync anstoßen (MemberEntity, „Bezahlt von“).
                await load()
                await app.engine?.syncNow()
            }
        }
        .task { await load() }
    }

    private func row(_ m: MemberInfo) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(m.displayName + (m.id == app.currentUserId ? " (du)" : ""))
                Text(m.username).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if m.isAdmin {
                Text("Admin")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        guard let client = app.auth.client else {
            errorMessage = MembersModel.offlineMessage
            return
        }
        loading = true
        defer { loading = false }
        do {
            members = try await MemberAdmin(client: client).list()
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            errorMessage = nil
        } catch {
            if APIError(error) == .cancelled { return }
            errorMessage = MembersModel.message(for: error)
        }
    }
}

enum MemberSheet: Identifiable {
    case new
    case edit(MemberInfo)

    var id: String {
        switch self {
        case .new: "new"
        case let .edit(m): m.id.uuidString
        }
    }

    var member: MemberInfo? {
        if case let .edit(m) = self { m } else { nil }
    }
}
