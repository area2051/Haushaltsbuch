import SwiftUI

/// Schritt 2a (`setupRequired`): erstes Admin-Konto anlegen, danach automatisch angemeldet.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @State private var username = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var pendingToDiscard: Int?

    var body: some View {
        Form {
            Section {
                TextField("Benutzername", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("setup.username")
                TextField("Anzeigename", text: $displayName)
                    .textContentType(.name)
                    .accessibilityIdentifier("setup.displayName")
                SecureField("Passwort", text: $password)
                    .textContentType(.newPassword)
                    .accessibilityIdentifier("setup.password")
            } footer: {
                Text("Dieses Konto wird Administrator des Haushalts.")
            }
            Section {
                Button { submit(discard: false) } label: {
                    HStack {
                        Text("Einrichten")
                        if busy { Spacer(); ProgressView() }
                    }
                }
                .disabled(busy || !isComplete)
                .accessibilityIdentifier("setup.submit")
                ErrorText(message: error)
            }
            Section {
                Button("Anderen Server wählen") { model.chooseOtherServer() }
                    .disabled(busy)
                    .accessibilityIdentifier("setup.otherServer")
            }
        }
        .navigationTitle("Haushalt einrichten")
        .modifier(DiscardConfirmation(pending: $pendingToDiscard) { submit(discard: true) })
    }

    private var isComplete: Bool {
        ![username, displayName].contains { $0.trimmingCharacters(in: .whitespaces).isEmpty } && !password.isEmpty
    }

    private func submit(discard: Bool) {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            do {
                let outcome = try await model.setup(
                    username: username.trimmingCharacters(in: .whitespaces),
                    displayName: displayName.trimmingCharacters(in: .whitespaces),
                    password: password, discardPending: discard)
                if case let .needsDiscardConfirmation(pending) = outcome { pendingToDiscard = pending }
            } catch {
                self.error = userMessage(for: error)
            }
            busy = false
        }
    }
}
