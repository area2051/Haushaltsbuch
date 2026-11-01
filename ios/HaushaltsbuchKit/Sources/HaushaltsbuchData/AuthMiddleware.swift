import Foundation
import HTTPTypes
import OpenAPIRuntime
import HaushaltsbuchAPI

/// Hält die aktuellen Tokens und erneuert sie single-flight.
///
/// - Die Tokens leben im Actor-Zustand (beim Start aus dem `TokenStore` geladen); jede Rotation wird
///   sofort im Store gespeichert, denn der Server macht das alte Refresh-Token dabei ungültig.
/// - Es läuft höchstens ein `POST /auth/refresh` gleichzeitig. Parallele Aufrufer warten auf denselben
///   Task. Der Refresh läuft in einem unstrukturierten Task, damit ein abgebrochener Aufrufer ihn nicht
///   mitten in der Rotation abbricht (die neue Token-Antwort ginge sonst verloren).
/// - `clear()` (Abmelden) erhöht eine Generation; ein danach eintreffendes Refresh-Ergebnis wird
///   verworfen statt die Sitzung wiederzubeleben.
public actor TokenRefresher {
    private let store: any TokenStore
    private let client: Client
    private let onChange: @Sendable (StoredSession?) async -> Void
    private var current: StoredSession?
    private var inFlight: Task<StoredSession, any Error>?
    private var generation = 0

    /// - Parameters:
    ///   - client: Client **ohne** `AuthMiddleware` (nur für `POST /auth/refresh`).
    ///   - onChange: wird nach jeder Rotation (neue Sitzung) bzw. nach Verlust der Sitzung (`nil`)
    ///     aufgerufen und abgewartet, bevor der Aufrufer das Ergebnis erhält.
    public init(store: any TokenStore, client: Client,
                onChange: @escaping @Sendable (StoredSession?) async -> Void = { _ in }) {
        self.store = store
        self.client = client
        self.onChange = onChange
        self.current = store.load()
    }

    public func currentSession() -> StoredSession? {
        current
    }

    /// Aktuelles Access-Token; wartet ggf. auf einen laufenden Refresh.
    public func validAccessToken() async throws -> String {
        if let inFlight { return try await inFlight.value.accessToken }
        guard let current else { throw APIError.unauthorized }
        return current.accessToken
    }

    /// Nach einem 401 mit `failedToken`: erneuert genau einmal, auch bei parallelen Aufrufern.
    /// Ist das Token inzwischen schon erneuert, wird das neue ohne Request zurückgegeben.
    public func refreshAfterUnauthorized(failedToken: String) async throws -> String {
        if let inFlight { return try await inFlight.value.accessToken }
        guard let current else { throw APIError.unauthorized }
        if current.accessToken != failedToken { return current.accessToken }

        let gen = generation
        let task = Task { try await self.performRefresh(of: current, generation: gen) }
        inFlight = task
        return try await task.value.accessToken
    }

    /// Verwirft die Sitzung (Abmelden). Ein laufender Refresh wird nicht mehr übernommen.
    public func clear() {
        generation += 1
        inFlight = nil
        current = nil
        store.save(nil)
    }

    private func performRefresh(of session: StoredSession, generation gen: Int) async throws -> StoredSession {
        defer { if generation == gen { inFlight = nil } }

        let output: Operations.refresh.Output
        do {
            output = try await client.refresh(body: .json(.init(refreshToken: session.refreshToken)))
        } catch {
            // Netz-/Transportfehler: Sitzung behalten, später erneut versuchen.
            throw APIError(error)
        }
        guard generation == gen else { throw APIError.unauthorized }

        switch output {
        case let .ok(ok):
            let pair: Components.Schemas.TokenPair
            do { pair = try ok.body.json } catch { throw APIError(error) }
            var renewed = session
            renewed.accessToken = pair.accessToken
            renewed.refreshToken = pair.refreshToken
            current = renewed
            store.save(renewed)
            await onChange(renewed)
            return renewed
        case .unauthorized:
            // invalid_refresh_token: abgelaufen, widerrufen oder schon rotiert → neu anmelden.
            current = nil
            store.save(nil)
            await onChange(nil)
            throw APIError.unauthorized
        case let .badRequest(r):
            throw (try? APIError(r.body.json)) ?? APIError.undocumented(400)
        case let .internalServerError(r):
            throw (try? APIError(r.body.json)) ?? APIError.undocumented(500)
        case let .undocumented(statusCode, _):
            throw APIError.undocumented(statusCode)
        }
    }
}

/// Setzt `Authorization: Bearer …` für alle geschützten Operationen und erneuert bei 401 einmal
/// das Token und wiederholt den Request.
public struct AuthMiddleware: ClientMiddleware {
    /// Operationen ohne Access-Token.
    static let publicOperations: Set<String> = ["getHealth", "setup", "login", "refresh"]

    private let refresher: TokenRefresher

    public init(refresher: TokenRefresher) {
        self.refresher = refresher
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        guard !Self.publicOperations.contains(operationID) else {
            return try await next(request, body, baseURL)
        }

        // Für die mögliche Wiederholung muss der Body zweimal lesbar sein.
        var body = body
        if let single = body, single.iterationBehavior == .single {
            body = HTTPBody(try await Data(collecting: single, upTo: 16 * 1024 * 1024))
        }

        var request = request
        let token = try await refresher.validAccessToken()
        request.headerFields[.authorization] = "Bearer \(token)"
        let (response, responseBody) = try await next(request, body, baseURL)
        guard response.status == .unauthorized else { return (response, responseBody) }

        let renewed = try await refresher.refreshAfterUnauthorized(failedToken: token)
        request.headerFields[.authorization] = "Bearer \(renewed)"
        return try await next(request, body, baseURL)
    }
}
