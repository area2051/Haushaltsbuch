import Foundation
import Synchronization

/// Angemeldete Sitzung; liegt JSON-kodiert im Schlüsselbund.
public struct StoredSession: Codable, Sendable, Hashable {
    public var serverURL: URL
    public var accessToken: String
    public var refreshToken: String
    public var userId: UUID
    public var username: String
    public var isAdmin: Bool

    public init(serverURL: URL, accessToken: String, refreshToken: String,
                userId: UUID, username: String, isAdmin: Bool) {
        self.serverURL = serverURL
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.userId = userId
        self.username = username
        self.isAdmin = isAdmin
    }
}

/// Persistenz der Sitzung. `save(nil)` löscht sie.
public protocol TokenStore: Sendable {
    func load() -> StoredSession?
    func save(_ s: StoredSession?)
}

/// Flüchtiger Store für Tests und Vorschauen.
public final class InMemoryTokenStore: TokenStore {
    private let value: Mutex<StoredSession?>

    public init(_ session: StoredSession? = nil) {
        value = Mutex(session)
    }

    public func load() -> StoredSession? {
        value.withLock { $0 }
    }

    public func save(_ s: StoredSession?) {
        value.withLock { $0 = s }
    }
}

/// Anmeldezustand der App.
public enum AuthState: Equatable, Sendable {
    case needsServer
    case needsSetup(URL)
    case needsLogin(URL)
    case loggedIn(StoredSession)

    /// Bekannte Server-Adresse, falls vorhanden.
    public var serverURL: URL? {
        switch self {
        case .needsServer: nil
        case let .needsSetup(url), let .needsLogin(url): url
        case let .loggedIn(session): session.serverURL
        }
    }
}
