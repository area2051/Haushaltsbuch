import Foundation
import Security
import OpenAPIRuntime
import Testing
import HaushaltsbuchAPI
@testable import HaushaltsbuchData

@MainActor
private struct ServiceFixture {
    let transport = FakeTransport()
    let store: InMemoryTokenStore
    let defaults: UserDefaults
    let auth: AuthService

    init(session: StoredSession? = nil) {
        store = InMemoryTokenStore(session)
        defaults = UserDefaults(suiteName: "AuthServiceTests-\(UUID().uuidString)")!
        let transport = self.transport
        auth = AuthService(store: store, defaults: defaults, deviceName: "Test-iPhone",
                           clientFactory: { url, middlewares in
                               Client(serverURL: url, transport: transport, middlewares: middlewares)
                           })
    }

    func connectToLogin() async throws {
        transport.enqueue("getHealth", Fixtures.health(setupRequired: false))
        try await auth.connect(to: Fixtures.serverURL)
    }

    func loggedIn() async throws {
        try await connectToLogin()
        transport.enqueue("login", Fixtures.loginOK())
        try await auth.login(username: "Anna", password: "geheim123")
    }
}

@MainActor @Test func startsWithoutServer() {
    let f = ServiceFixture()
    #expect(f.auth.state == .needsServer)
    #expect(f.auth.client == nil)
}

@MainActor @Test func restoresSessionFromStore() {
    let f = ServiceFixture(session: Fixtures.session())
    #expect(f.auth.state == .loggedIn(Fixtures.session()))
    #expect(f.auth.client != nil)
}

@MainActor @Test func connectReportsSetupRequired() async throws {
    let f = ServiceFixture()
    f.transport.enqueue("getHealth", Fixtures.health(setupRequired: true))
    try await f.auth.connect(to: Fixtures.serverURL)
    #expect(f.auth.state == .needsSetup(Fixtures.serverURL))
    #expect(f.transport.log.first?.authorization == nil)
}

@MainActor @Test func connectWithoutSetupNeedsLogin() async throws {
    let f = ServiceFixture()
    try await f.connectToLogin()
    #expect(f.auth.state == .needsLogin(Fixtures.serverURL))
}

@MainActor @Test func loginMapsInvalidCredentials() async throws {
    let f = ServiceFixture()
    try await f.connectToLogin()
    f.transport.enqueue("login", .error(401, code: "invalid_credentials", message: "Invalid username or password"))

    let error = await #expect(throws: APIError.self) {
        try await f.auth.login(username: "anna", password: "falsch")
    }

    #expect(error == .server(code: "invalid_credentials", message: "Invalid username or password"))
    #expect(error?.germanMessage == "Benutzername oder Passwort falsch.")
    #expect(f.auth.state == .needsLogin(Fixtures.serverURL))
    #expect(f.store.load() == nil)
}

@MainActor @Test func loginMapsTooManyAttempts() async throws {
    let f = ServiceFixture()
    try await f.connectToLogin()
    f.transport.enqueue("login", .error(429, code: "too_many_attempts"))
    let error = await #expect(throws: APIError.self) {
        try await f.auth.login(username: "anna", password: "falsch")
    }
    #expect(error?.germanMessage == "Zu viele Versuche – bitte eine Minute warten.")
}

@MainActor @Test func unreachableServerMapsToUnreachable() async throws {
    let f = ServiceFixture()
    f.transport.enqueue("getHealth", .failure(URLError(.cannotConnectToHost)))

    let error = await #expect(throws: APIError.self) { try await f.auth.connect(to: Fixtures.serverURL) }

    #expect(error == .unreachable)
    #expect(error?.germanMessage == "Server nicht erreichbar. Bist du im Heimnetz oder per VPN verbunden?")
    #expect(f.auth.state == .needsServer)
}

@MainActor @Test func loginStoresSessionAndLastUsername() async throws {
    let f = ServiceFixture()
    try await f.loggedIn()

    let session = Fixtures.session()
    #expect(f.auth.state == .loggedIn(session))
    #expect(f.store.load() == session)
    #expect(f.auth.client != nil)
    let login = try #require(f.transport.requests("login").first)
    #expect(login.bodyString("username") == "Anna")
    #expect(login.bodyString("deviceName") == "Test-iPhone")
    #expect(f.defaults.string(forKey: AuthService.lastUsernameKey) == "anna")
    #expect(f.auth.loginWouldSwitchUser("ANNA ") == false)
    #expect(f.auth.loginWouldSwitchUser("bert") == true)
}

@MainActor @Test func lastUsernameIsRememberedAfterLogout() async throws {
    let f = ServiceFixture()
    #expect(f.auth.lastUsername == nil)
    try await f.loggedIn()
    f.transport.enqueue("logout", .empty(204))
    await f.auth.logout()
    #expect(f.auth.lastUsername == "anna")
}

@MainActor @Test func forgetServerReturnsToServerInput() async throws {
    let f = ServiceFixture()
    try await f.connectToLogin()
    f.auth.forgetServer()
    #expect(f.auth.state == .needsServer)
    #expect(f.defaults.url(forKey: AuthService.lastServerURLKey) == nil)
}

@MainActor @Test func forgetServerIgnoredWhileLoggedIn() async throws {
    let f = ServiceFixture()
    try await f.loggedIn()
    f.auth.forgetServer()
    #expect(f.auth.state == .loggedIn(Fixtures.session()))
}

@MainActor @Test func firstLoginNeverCountsAsSwitch() {
    let f = ServiceFixture()
    #expect(f.auth.loginWouldSwitchUser("anna") == false)
}

@MainActor @Test func authenticatedClientSendsBearer() async throws {
    let f = ServiceFixture()
    try await f.loggedIn()
    f.transport.enqueue("getMe", Fixtures.meOK)
    _ = try await #require(f.auth.client).getMe()
    #expect(f.transport.requests("getMe").first?.authorization == "Bearer a1")
}

@MainActor @Test func setupLogsInAutomatically() async throws {
    let f = ServiceFixture()
    f.transport.enqueue("getHealth", Fixtures.health(setupRequired: true))
    try await f.auth.connect(to: Fixtures.serverURL)
    f.transport.enqueue("setup", .json(201, #"{"user":\#(Fixtures.userJSON)}"#))
    f.transport.enqueue("login", Fixtures.loginOK())

    try await f.auth.setup(username: "anna", displayName: "Anna", password: "geheim123")

    #expect(f.transport.log.map(\.operationID) == ["getHealth", "setup", "login"])
    #expect(f.transport.requests("setup").first?.bodyString("displayName") == "Anna")
    #expect(f.auth.state == .loggedIn(Fixtures.session()))
}

@MainActor @Test func setupAlreadyDoneSwitchesToLogin() async throws {
    let f = ServiceFixture()
    f.transport.enqueue("getHealth", Fixtures.health(setupRequired: true))
    try await f.auth.connect(to: Fixtures.serverURL)
    f.transport.enqueue("setup", .error(409, code: "setup_already_done"))

    let error = await #expect(throws: APIError.self) {
        try await f.auth.setup(username: "anna", displayName: "Anna", password: "geheim123")
    }

    #expect(error == .server(code: "setup_already_done", message: "msg"))
    #expect(f.auth.state == .needsLogin(Fixtures.serverURL))
}

@MainActor @Test func logoutRevokesRefreshTokenAndClearsSession() async throws {
    let f = ServiceFixture()
    try await f.loggedIn()
    f.transport.enqueue("logout", .empty(204))

    await f.auth.logout()

    let logout = try #require(f.transport.requests("logout").first)
    #expect(logout.authorization == "Bearer a1")
    #expect(logout.bodyString("refreshToken") == "r1")
    #expect(f.store.load() == nil)
    #expect(f.auth.state == .needsLogin(Fixtures.serverURL))
    #expect(f.auth.client == nil)
}

@MainActor @Test func logoutAlsoRevokesTokenRotatedDuringLogout() async throws {
    let f = ServiceFixture()
    try await f.loggedIn()
    // Access-Token abgelaufen: logout → 401 → Refresh (r1→r2) → Wiederholung mit altem Body (r1).
    f.transport.enqueue("logout", .error(401, code: "unauthorized"), .empty(204), .empty(204))
    f.transport.enqueue("refresh", Fixtures.tokens(access: "a2", refresh: "r2"))

    await f.auth.logout()

    #expect(f.transport.requests("logout").map { $0.bodyString("refreshToken") } == ["r1", "r1", "r2"])
    #expect(f.store.load() == nil)
}

@MainActor @Test func logoutWhileOfflineStillClearsLocally() async throws {
    let f = ServiceFixture()
    try await f.loggedIn()
    f.transport.enqueue("logout", .failure(URLError(.notConnectedToInternet)))

    await f.auth.logout()

    #expect(f.store.load() == nil)
    #expect(f.auth.state == .needsLogin(Fixtures.serverURL))
}

@MainActor @Test func expiredRefreshTokenMovesToLogin() async throws {
    let f = ServiceFixture()
    try await f.loggedIn()
    f.transport.enqueue("getMe", .error(401, code: "unauthorized"))
    f.transport.enqueue("refresh", .error(401, code: "invalid_refresh_token"))

    await #expect(throws: (any Error).self) { try await #require(f.auth.client).getMe() }

    #expect(f.auth.state == .needsLogin(Fixtures.serverURL))
    #expect(f.auth.client == nil)
    #expect(f.store.load() == nil)
}

@MainActor @Test func rotationUpdatesLoggedInState() async throws {
    let f = ServiceFixture()
    try await f.loggedIn()
    f.transport.enqueue("getMe", .error(401, code: "unauthorized"), Fixtures.meOK)
    f.transport.enqueue("refresh", Fixtures.tokens(access: "a2", refresh: "r2"))

    _ = try await #require(f.auth.client).getMe()

    #expect(f.auth.state == .loggedIn(Fixtures.session(access: "a2", refresh: "r2")))
}

@Test func germanMessagesForCommonErrors() {
    #expect(APIError.unauthorized.germanMessage == "Sitzung abgelaufen – bitte erneut anmelden.")
    #expect(APIError.server(code: "setup_already_done", message: "x").germanMessage
            == "Der Server ist bereits eingerichtet.")
    #expect(APIError(URLError(.timedOut)) == .unreachable)
    #expect(APIError(URLError(.dnsLookupFailed)) == .unreachable)
    #expect(APIError(URLError(.badURL)) != .unreachable)
}

/// Ohne Host-App (Package-Tests im xctest-Prozess) fehlt das Keychain-Entitlement:
/// `SecItem*` liefert `errSecMissingEntitlement` (-34018). Dann wird der Smoke-Test übersprungen.
private let keychainAvailable: Bool = {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "de.haushaltsbuch.app.session.probe",
        kSecAttrAccount as String: "probe",
    ]
    return SecItemCopyMatching(query as CFDictionary, nil) != errSecMissingEntitlement
}()

@Test(.enabled(if: keychainAvailable, "Keychain im Test-Prozess ohne Host-App nicht verfügbar (-34018)"))
func keychainStoreRoundTrip() throws {
    let store = KeychainTokenStore(service: "de.haushaltsbuch.app.session.tests-\(UUID().uuidString)")
    defer { store.save(nil) }
    #expect(store.load() == nil)
    store.save(Fixtures.session())
    #expect(store.load() == Fixtures.session())
    store.save(Fixtures.session(access: "a2", refresh: "r2"))
    #expect(store.load() == Fixtures.session(access: "a2", refresh: "r2"))
    store.save(nil)
    #expect(store.load() == nil)
}

@MainActor @Test func reloginDiscardsRefreshOfPreviousSession() async throws {
    let f = ServiceFixture(session: Fixtures.session())
    let oldClient = try #require(f.auth.client)
    // Alte Sitzung: getMe → 401 → Refresh hängt, bis die neue Anmeldung durch ist.
    // (Zweite Antwort nur für den Fall, dass der alte Refresh fälschlich übernommen wird.)
    f.transport.enqueue("getMe", .error(401, code: "unauthorized"), Fixtures.meOK)
    let gate = Gate(count: 2)
    f.transport.respond("refresh") { _ in
        await gate.arrive()
        return Fixtures.tokens(access: "a-old2", refresh: "r-old2")
    }
    let pending = Task { try? await oldClient.getMe() }
    while f.transport.requests("refresh").isEmpty { try await Task.sleep(for: .milliseconds(5)) }

    f.transport.enqueue("login", Fixtures.loginOK(access: "a9", refresh: "r9"))
    try await f.auth.login(username: "anna", password: "geheim123")
    await gate.arrive()
    _ = await pending.value

    #expect(f.store.load() == Fixtures.session(access: "a9", refresh: "r9"))
    #expect(f.auth.state == .loggedIn(Fixtures.session(access: "a9", refresh: "r9")))
}

@Test func storedSessionDescriptionsRedactTokens() {
    let s = Fixtures.session(access: "SECRET-ACCESS", refresh: "SECRET-REFRESH")
    var dumped = ""
    dump(s, to: &dumped)
    for text in [String(describing: s), String(reflecting: s), "\(AuthState.loggedIn(s))",
                 String(reflecting: AuthState.loggedIn(s)), dumped] {
        #expect(!text.contains("SECRET"), "\(text)")
        #expect(text.contains("anna"))
    }
}
