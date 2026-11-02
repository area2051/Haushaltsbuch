import SwiftUI

/// Schritt 2b: anmelden. Nach Ablauf der Sitzung mit dem letzten Benutzernamen vorausgefüllt;
/// lokale Daten bleiben erhalten.
struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var username: String
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var pendingToDiscard: Int?

    init(prefill: String) {
        _username = State(initialValue: prefill)
    }

    var body: some View {
        Form {
            if let server = model.auth.state.serverURL {
                Section {
                    LabeledContent("Server", value: server.absoluteString)
                }
            }
            Section {
                TextField("Benutzername", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("login.username")
                SecureField("Passwort", text: $password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit { submit(discard: false) }
                    .accessibilityIdentifier("login.password")
            }
            Section {
                Button { submit(discard: false) } label: {
                    HStack {
                        Text("Anmelden")
                        if busy { Spacer(); ProgressView() }
                    }
                }
                .disabled(busy || username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                .accessibilityIdentifier("login.submit")
                ErrorText(message: error)
            }
            Section {
                Button("Anderen Server wählen") { model.chooseOtherServer() }
                    .disabled(busy)
                    .accessibilityIdentifier("login.otherServer")
            }
        }
        .navigationTitle("Anmelden")
        .modifier(DiscardConfirmation(pending: $pendingToDiscard) { submit(discard: true) })
    }

    private func submit(discard: Bool) {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            do {
                let outcome = try await model.login(
                    username: username.trimmingCharacters(in: .whitespaces),
                    password: password, discardPending: discard)
                if case let .needsDiscardConfirmation(pending) = outcome { pendingToDiscard = pending }
            } catch {
                self.error = userMessage(for: error)
            }
            busy = false
        }
    }
}
