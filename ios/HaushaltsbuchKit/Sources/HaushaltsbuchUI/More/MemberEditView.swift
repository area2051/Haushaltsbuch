import SwiftUI
import HaushaltsbuchData

/// Mitglied anlegen oder bearbeiten: Anzeigename, Admin, Passwort zurücksetzen, entfernen.
struct MemberEditView: View {
    let target: MemberSheet
    let isSelf: Bool
    let onChange: () async -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var isAdmin = false
    @State private var loaded = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var confirmRemove = false

    private var existing: MemberInfo? { target.member }

    private var validation: String? {
        if existing == nil {
            return MembersModel.validationMessage(username: username, displayName: displayName, password: password)
        }
        return MembersModel.validationMessage(displayName: displayName, password: password)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let existing {
                        LabeledContent("Benutzername", value: existing.username)
                    } else {
                        TextField("Benutzername", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("member.username")
                    }
                    TextField("Anzeigename", text: $displayName)
                        .accessibilityIdentifier("member.displayName")
                    Toggle("Admin", isOn: $isAdmin)
                        .accessibilityIdentifier("member.admin")
                }
                Section {
                    SecureField(existing == nil ? "Passwort" : "Neues Passwort", text: $password)
                        // Passwort eines anderen Mitglieds: `.oneTimeCode` verhindert, dass iOS anbietet,
                        // es als Anmeldung des Admins im Schlüsselbund zu sichern.
                        .textContentType(.oneTimeCode)
                        .accessibilityIdentifier("member.password")
                } header: {
                    Text(existing == nil ? "Passwort" : "Passwort zurücksetzen")
                } footer: {
                    Text(existing == nil ? "Mindestens 8 Zeichen." : "Leer lassen, um das Passwort nicht zu ändern. Zurücksetzen meldet das Mitglied auf allen Geräten ab.")
                }
                if let message = errorMessage ?? (hasInput ? validation : nil) {
                    Text(message).foregroundStyle(.red)
                        .accessibilityIdentifier("member.error")
                }
                if existing != nil {
                    Section {
                        Button("Mitglied entfernen", role: .destructive) { confirmRemove = true }
                            .disabled(busy)
                            .accessibilityIdentifier("member.remove")
                    } footer: {
                        if isSelf { Text("Du kannst dich nicht selbst entfernen.") }
                    }
                }
            }
            .disabled(busy)
            .navigationTitle(existing == nil ? "Neues Mitglied" : existing!.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { close() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button("Sichern") { Task { await save() } }
                            .disabled(validation != nil)
                            .accessibilityIdentifier("member.save")
                    }
                }
            }
            .confirmationDialog("\(existing?.displayName ?? "Mitglied") entfernen?", isPresented: $confirmRemove,
                                titleVisibility: .visible) {
                Button("Entfernen", role: .destructive) { Task { await remove() } }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Das Mitglied kann sich nicht mehr anmelden. Seine Buchungen bleiben erhalten.")
            }
        }
        .accessibilityIdentifier("memberEditSheet")
        .onChange(of: "\(username)|\(displayName)|\(password)|\(isAdmin)") { errorMessage = nil }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let existing {
                displayName = existing.displayName
                isAdmin = existing.isAdmin
            }
        }
    }

    /// Passwortfeld vor dem Schließen leeren: verschwindet ein gefülltes Passwortfeld, bietet iOS
    /// sonst an, es als Anmeldung des Admins zu sichern.
    private func close() {
        password = ""
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            dismiss()
        }
    }

    private var hasInput: Bool {
        existing == nil ? !(username.isEmpty && displayName.isEmpty && password.isEmpty) : true
    }

    private func save() async {
        await perform { admin in
            let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing {
                try await admin.update(id: existing.id,
                                       displayName: name != existing.displayName ? name : nil,
                                       password: password.isEmpty ? nil : password,
                                       isAdmin: isAdmin != existing.isAdmin ? isAdmin : nil)
            } else {
                _ = try await admin.create(username: username, displayName: name, password: password, isAdmin: isAdmin)
            }
        }
    }

    private func remove() async {
        guard let existing else { return }
        await perform { try await $0.remove(id: existing.id) }
    }

    private func perform(_ action: (MemberAdmin) async throws -> Void) async {
        guard let client = app.auth.client else {
            errorMessage = MembersModel.offlineMessage
            return
        }
        busy = true
        defer { busy = false }
        do {
            try await action(MemberAdmin(client: client))
            close()
            await onChange()
        } catch {
            errorMessage = MembersModel.message(for: error)
        }
    }
}
