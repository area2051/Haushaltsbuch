import Foundation
import LocalAuthentication
import SwiftUI

/// Face ID / Touch ID mit Gerätecode als Rückfall (Tests ersetzen es).
@MainActor
public protocol BiometricAuthenticating: AnyObject {
    /// `false`, wenn kein Gerätecode eingerichtet ist (dann kann nie entsperrt werden).
    func canAuthenticate() -> Bool
    func authenticate(reason: String) async -> Bool
}

/// `LAContext` mit `.deviceOwnerAuthentication` (Face ID, sonst Gerätecode).
@MainActor
public final class DeviceOwnerAuthenticator: BiometricAuthenticating {
    public init() {}

    public func canAuthenticate() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    public func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}

/// App-Sperre („Face-ID-Sperre an/aus“, Spec §7 „Mehr“).
///
/// - `isEnabled` liegt in den UserDefaults (Geräteeinstellung, bleibt beim Abmelden erhalten).
/// - Gesperrt wird beim Kaltstart und bei `scenePhase == .background` – nicht bei `.inactive`
///   (Kontrollzentrum, Teilen-Menü, der Face-ID-Dialog selbst).
/// - Nach dem Sperren wird beim nächsten Aktivwerden genau einmal automatisch gefragt
///   (`autoPromptIfNeeded`); danach nur noch über „Entsperren“.
@MainActor
public final class AppLock: ObservableObject {
    public static let enabledKey = "appLock.enabled"
    static let reason = "Haushaltsbuch entsperren"

    @Published public private(set) var isEnabled: Bool
    @Published public private(set) var isLocked: Bool
    @Published public private(set) var isAuthenticating = false

    private let defaults: UserDefaults
    private let authenticator: any BiometricAuthenticating
    private var didAutoPrompt = false

    public init(defaults: UserDefaults = .standard, authenticator: (any BiometricAuthenticating)? = nil) {
        self.defaults = defaults
        self.authenticator = authenticator ?? DeviceOwnerAuthenticator()
        let enabled = defaults.bool(forKey: Self.enabledKey)
        isEnabled = enabled
        isLocked = enabled
    }

    /// Ein-/Ausschalten. Liefert eine deutsche Meldung, wenn das Einschalten nicht möglich ist.
    @discardableResult
    public func setEnabled(_ enabled: Bool) -> String? {
        if enabled && !authenticator.canAuthenticate() {
            return "Bitte zuerst in den Einstellungen einen Gerätecode festlegen."
        }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        if !enabled { isLocked = false }
        return nil
    }

    public func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            didAutoPrompt = false
            if isEnabled { isLocked = true }
        case .active:
            if isLocked && !didAutoPrompt { Task { await autoPromptIfNeeded() } }
        default:
            break
        }
    }

    /// Einmal pro Sperre automatisch nach Face ID fragen.
    public func autoPromptIfNeeded() async {
        guard isLocked, !didAutoPrompt else { return }
        didAutoPrompt = true
        await unlock()
    }

    public func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        // Gerätecode inzwischen entfernt: nie wieder entsperrbar → Sperre abschalten statt aussperren.
        guard authenticator.canAuthenticate() else {
            setEnabled(false)
            return
        }
        isAuthenticating = true
        defer { isAuthenticating = false }
        if await authenticator.authenticate(reason: Self.reason) {
            isLocked = false
        }
    }
}
