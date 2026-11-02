import SwiftUI
import HaushaltsbuchData

/// Fehlertext für die Oberfläche; `nil` bei Abbruch.
func userMessage(for error: any Error) -> String? {
    if let input = error as? AppModel.InputError { return input.germanMessage }
    let api = APIError(error)
    return api == .cancelled ? nil : api.germanMessage
}

/// Inline-Fehlerzeile unter einem Formular.
struct ErrorText: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityIdentifier("onboarding.error")
        }
    }
}

/// Rückfrage vor dem Verwerfen ungesendeter Änderungen beim Benutzerwechsel.
struct DiscardConfirmation: ViewModifier {
    @Binding var pending: Int?
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.alert(
            "\(pending ?? 0) ungesendete Änderungen verwerfen?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
        ) {
            Button("Verwerfen", role: .destructive) {
                pending = nil
                onConfirm()
            }
            Button("Abbrechen", role: .cancel) { pending = nil }
        } message: {
            Text("Auf diesem Gerät liegen noch Änderungen eines anderen Kontos, die nicht an den Server gesendet wurden.")
        }
    }
}
