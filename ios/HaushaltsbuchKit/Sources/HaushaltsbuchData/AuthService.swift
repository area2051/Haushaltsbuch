import Foundation
import Observation
import OpenAPIRuntime
import UIKit
import HaushaltsbuchAPI

/// Server-Verbindung, Einrichtung, An- und Abmelden. Hält den authentifizierten `client`.
///
/// `@Observable` statt `ObservableObject`: passt zu Swift 6 / `@MainActor`, SwiftUI beobachtet
/// `state` und `client` direkt.
@MainActor @Observable
public final class AuthService {
    public typealias ClientFactory = @Sendable (URL, [any ClientMiddleware]) -> Client

    public static let lastUsernameKey = "auth.lastUsername"
    public static let lastServerURLKey = "auth.lastServerURL"

    public private(set) var state: AuthState
    /// Client mit `AuthMiddleware`; nur im Zustand `.loggedIn` gesetzt.
    public private(set) var client: Client?

    @ObservationIgnored private let store: any TokenStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let deviceName: String
    @ObservationIgnored private let clientFactory: ClientFactory
    @ObservationIgnored private var refresher: TokenRefresher?
    /// Identität des aktuellen Refreshers; Rückmeldungen eines alten Refreshers werden ignoriert.
    @ObservationIgnored private var refresherID = UUID()

    /// - Parameters:
    ///   - deviceName: für `POST /auth/login` (Server zeigt damit die Sitzungen an); Standard `UIDevice.current.name`.
    ///   - clientFactory: Standard `makeClient` (URLSession); Tests übergeben einen Fake-Transport.
    public init(store: any TokenStore = KeychainTokenStore(),
                defaults: UserDefaults = .standard,
                deviceName: String? = nil,
                clientFactory: @escaping ClientFactory = { makeClient(serverURL: $0, middlewares: $1) }) {
        self.store = store
        self.defaults = defaults
        self.deviceName = deviceName ?? UIDevice.current.name
        self.clientFactory = clientFactory
        if let session = store.load() {
            state = .loggedIn(session)
            client = nil
            activate(session)
        } else if let url = defaults.url(forKey: Self.lastServerURLKey) {
            state = .needsLogin(url)
        } else {
            state = .needsServer
        }
    }

    // MARK: Server

    /// `GET /health` → `.needsSetup(url)` oder `.needsLogin(url)`.
    public func connect(to url: URL) async throws {
        let output: Operations.getHealth.Output
        do {
            output = try await clientFactory(url, []).getHealth()
        } catch {
            throw APIError(error)
        }
        switch output {
        case let .ok(ok):
            let health: Components.Schemas.HealthResponse
            do { health = try ok.body.json } catch { throw APIError(error) }
            defaults.set(url, forKey: Self.lastServerURLKey)
            state = health.setupRequired ? .needsSetup(url) : .needsLogin(url)
        case let .internalServerError(r):
            throw (try? APIError(r.body.json)) ?? APIError.undocumented(500)
        case let .undocumented(statusCode, _):
            throw APIError.undocumented(statusCode)
        }
    }

    // MARK: Einrichtung

    /// `POST /setup` (erstes Admin-Konto), danach automatisch anmelden.
    public func setup(username: String, displayName: String, password: String) async throws {
        let url = try requireServerURL()
        let output: Operations.setup.Output
        do {
            output = try await clientFactory(url, []).setup(
                body: .json(.init(displayName: displayName, password: password, username: username)))
        } catch {
            throw APIError(error)
        }
        switch output {
        case .created:
            try await login(username: username, password: password)
        case let .conflict(r):
            // Jemand anderes hat den Server inzwischen eingerichtet.
            state = .needsLogin(url)
            throw (try? APIError(r.body.json)) ?? APIError.undocumented(409)
        case let .badRequest(r):
            throw (try? APIError(r.body.json)) ?? APIError.undocumented(400)
        case let .internalServerError(r):
            throw (try? APIError(r.body.json)) ?? APIError.undocumented(500)
        case let .undocumented(statusCode, _):
            throw APIError.undocumented(statusCode)
        }
    }

    // MARK: Anmelden

    public func login(username: String, password: String) async throws {
        let url = try requireServerURL()
        let output: Operations.login.Output
        do {
            output = try await clientFactory(url, []).login(
                body: .json(.init(deviceName: deviceName, password: password, username: username)))
        } catch {
            throw APIError(error)
        }
        let response: Components.Schemas.LoginResponse
        switch output {
        case let .ok(ok):
            do { response = try ok.body.json } catch { throw APIError(error) }
        case let .unauthorized(r):
            throw (try? APIError(r.body.json)) ?? APIError.undocumented(401)
        case let .tooManyRequests(r):
            throw (try? APIError(r.body.json)) ?? APIError.undocumented(429)
        case let .badRequest(r):
            throw (try? APIError(r.body.json)) ?? APIError.undocumented(400)
        case let .internalServerError(r):
            throw (try? APIError(r.body.json)) ?? APIError.undocumented(500)
        case let .undocumented(statusCode, _):
            throw APIError.undocumented(statusCode)
        }
        guard let userId = UUID(uuidString: response.user.id) else {
            throw APIError.unexpected("Ungültige Benutzer-ID \(response.user.id)")
        }
        let session = StoredSession(serverURL: url, accessToken: response.accessToken,
                                    refreshToken: response.refreshToken, userId: userId,
                                    username: response.user.username, isAdmin: response.user.isAdmin)
        // Anmeldung bei bestehender Sitzung: den alten Refresher zuerst stilllegen. Sonst könnte sein
        // noch laufender Refresh danach die neue Sitzung im Store mit den alten Tokens überschreiben.
        if let old = refresher {
            refresherID = UUID()
            refresher = nil
            await old.clear()
        }
        store.save(session)
        defaults.set(url, forKey: Self.lastServerURLKey)
        defaults.set(response.user.username, forKey: Self.lastUsernameKey)
        activate(session)
        state = .loggedIn(session)
    }

    /// `true`, wenn sich zuvor schon ein *anderer* Benutzer auf diesem Gerät angemeldet hat
    /// (dann müssen lokale Daten vorher synchronisiert oder verworfen werden).
    public func loginWouldSwitchUser(_ username: String) -> Bool {
        guard let last = defaults.string(forKey: Self.lastUsernameKey) else { return false }
        return Self.normalize(username) != Self.normalize(last)
    }

    // MARK: Abmelden

    /// Widerruft das Refresh-Token beim Server (best effort) und verwirft die Sitzung lokal –
    /// auch wenn der Server nicht erreichbar ist.
    public func logout() async {
        guard let refresher, let client else {
            clearSession()
            return
        }
        if let before = await refresher.currentSession() {
            _ = try? await client.logout(body: .json(.init(refreshToken: before.refreshToken)))
            // Lief während des Logouts ein Refresh (abgelaufenes Access-Token), enthielt die
            // Wiederholung noch das alte Refresh-Token; das neue ebenfalls widerrufen.
            if let after = await refresher.currentSession(), after.refreshToken != before.refreshToken {
                _ = try? await client.logout(body: .json(.init(refreshToken: after.refreshToken)))
            }
        }
        await refresher.clear()
        clearSession()
    }

    // MARK: Intern

    private func activate(_ session: StoredSession) {
        let id = UUID()
        refresherID = id
        let refresher = TokenRefresher(
            store: store,
            client: clientFactory(session.serverURL, []),
            onChange: { [weak self] session in
                await self?.refresherDidChange(session, id: id)
            })
        self.refresher = refresher
        client = clientFactory(session.serverURL, [AuthMiddleware(refresher: refresher)])
    }

    private func refresherDidChange(_ session: StoredSession?, id: UUID) {
        guard id == refresherID, case .loggedIn = state else { return }
        if let session {
            state = .loggedIn(session)
        } else {
            clearSession()
        }
    }

    private func clearSession() {
        let url = state.serverURL
        store.save(nil)
        refresherID = UUID()
        refresher = nil
        client = nil
        state = url.map { .needsLogin($0) } ?? .needsServer
    }

    private func requireServerURL() throws -> URL {
        guard let url = state.serverURL else { throw APIError.unexpected("Keine Server-Adresse") }
        return url
    }

    private static func normalize(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
