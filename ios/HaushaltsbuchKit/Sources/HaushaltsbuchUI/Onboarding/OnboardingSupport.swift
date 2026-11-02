import SwiftUI
import HaushaltsbuchData

/// Fehlertext für die Oberfläche; `nil` bei Abbruch.
func userMessage(for error: any Error) -> String? {
    if let input = error as? AppModel.InputError { return input.germanMessage }
    if let failed = error as? AppModel.SwitchError { return failed.germanMessage }
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
    @Binding var pending: PendingChanges?
    let onConfirm: () -> Void

    static func title(_ p: PendingChanges) -> String {
        p.rejected == 0 ? "\(p.unsent) ungesendete Änderungen verwerfen?" : "\(p.total) Änderungen verwerfen?"
    }

    static func message(_ p: PendingChanges) -> String {
        let base = "Auf diesem Gerät liegen noch Änderungen eines anderen Kontos, die nicht an den Server gesendet wurden."
        guard p.rejected > 0 else { return base }
        return base + (p.rejected == 1 ? " 1 davon wurde vom Server abgelehnt."
                       : " \(p.rejected) davon wurden vom Server abgelehnt.")
    }

    func body(content: Content) -> some View {
        content.alert(
            pending.map(Self.title) ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
        ) {
            Button("Verwerfen", role: .destructive) {
                pending = nil
                onConfirm()
            }
            Button("Abbrechen", role: .cancel) { pending = nil }
        } message: {
            Text(pending.map(Self.message) ?? "")
        }
    }
}
