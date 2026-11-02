import SwiftUI

/// Schritt 1: Server-Adresse eingeben → `GET /health`.
struct ServerView: View {
    @Environment(AppModel.self) private var model
    @State private var address: String
    @State private var busy = false
    @State private var error: String?

    init(initialAddress: String = "") {
        _address = State(initialValue: initialAddress)
    }

    var body: some View {
        Form {
            Section {
                // `verbatim`: als LocalizedStringKey würde die URL im Platzhalter als Link dargestellt.
                TextField(text: $address, prompt: Text(verbatim: "z. B. http://nas.local:3000")) {
                    Text("Server-Adresse")
                }
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit(connect)
                    .accessibilityIdentifier("server.address")
            } header: {
                Text("Server-Adresse")
            } footer: {
                Text("Adresse deines Haushaltsbuch-Servers im Heimnetz oder per VPN.")
            }
            Section {
                Button(action: connect) {
                    HStack {
                        Text("Verbinden")
                        if busy { Spacer(); ProgressView() }
                    }
                }
                .disabled(busy || address.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("server.connect")
                ErrorText(message: error)
            }
        }
        .navigationTitle("Server verbinden")
    }

    private func connect() {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            do {
                try await model.connect(serverInput: address)
            } catch {
                self.error = userMessage(for: error)
            }
            busy = false
        }
    }
}
