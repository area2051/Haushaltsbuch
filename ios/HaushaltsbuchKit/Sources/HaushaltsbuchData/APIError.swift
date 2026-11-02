import Foundation
import OpenAPIRuntime
import HaushaltsbuchAPI

/// Fehler aus der Kommunikation mit dem Server, in einer für die Oberfläche brauchbaren Form.
public enum APIError: Error, Equatable, Sendable {
    /// Fehler-Envelope des Servers `{ "error": { "code", "message" } }`.
    case server(code: String, message: String)
    /// Server nicht erreichbar (kein Netz, falsche Adresse, Timeout, kein VPN).
    case unreachable
    /// Keine gültige Sitzung (mehr) – Anmeldung nötig.
    case unauthorized
    /// Alles andere (unerwarteter Status, Dekodierfehler …).
    case unexpected(String)
    /// Vom Aufrufer abgebrochen (Task-Abbruch, `URLError.cancelled`) – kein Fehler für die Oberfläche.
    case cancelled

    static let unreachableCodes: Set<URLError.Code> = [
        .cannotConnectToHost, .cannotFindHost, .timedOut,
        .notConnectedToInternet, .networkConnectionLost, .dnsLookupFailed,
    ]

    /// Ordnet beliebige Fehler zu; entpackt `ClientError` des OpenAPI-Clients
    /// (Transport- und Middleware-Fehler kommen darin verpackt an).
    public init(_ error: any Error) {
        switch error {
        case let e as APIError:
            self = e
        case let e as ClientError:
            self = APIError(e.underlyingError)
        case is CancellationError:
            self = .cancelled
        case let e as URLError where e.code == .cancelled:
            self = .cancelled
        case let e as URLError where Self.unreachableCodes.contains(e.code):
            self = .unreachable
        default:
            self = .unexpected(String(describing: error))
        }
    }

    init(_ payload: Components.Schemas.ErrorResponse) {
        self = .server(code: payload.error.code, message: payload.error.message)
    }

    static func undocumented(_ statusCode: Int) -> APIError {
        .unexpected("HTTP \(statusCode)")
    }

    public var germanMessage: String {
        switch self {
        case .unreachable:
            return "Server nicht erreichbar. Bist du im Heimnetz oder per VPN verbunden?"
        case .unauthorized:
            return "Sitzung abgelaufen – bitte erneut anmelden."
        case .cancelled:
            return "Abgebrochen."
        case .unexpected:
            return "Unerwarteter Fehler bei der Kommunikation mit dem Server."
        case let .server(code, message):
            switch code {
            case "invalid_credentials": return "Benutzername oder Passwort falsch."
            case "too_many_attempts": return "Zu viele Versuche – bitte eine Minute warten."
            case "invalid_refresh_token": return "Sitzung abgelaufen – bitte erneut anmelden."
            case "setup_already_done": return "Der Server ist bereits eingerichtet."
            case "username_taken": return "Dieser Benutzername ist bereits vergeben."
            case "last_admin": return "Der letzte Administrator kann nicht entfernt werden."
            case "cannot_delete_self": return "Du kannst dein eigenes Konto nicht löschen."
            case "payload_too_large": return "Zu viele Daten auf einmal – bitte erneut versuchen."
            case "forbidden": return "Dafür fehlen dir die Rechte."
            case "user_not_found": return "Benutzer nicht gefunden."
            case "wrong_password": return "Das aktuelle Passwort ist falsch."
            case "internal": return "Interner Serverfehler – bitte später erneut versuchen."
            case "validation_failed", "bad_request": return "Ungültige Eingabe: \(message)"
            default: return "Serverfehler (\(code)): \(message)"
            }
        }
    }
}
