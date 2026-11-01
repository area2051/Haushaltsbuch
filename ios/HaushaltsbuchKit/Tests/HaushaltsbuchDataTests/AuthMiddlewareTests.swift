import Foundation
import OpenAPIRuntime
import Testing
import HaushaltsbuchAPI
@testable import HaushaltsbuchData

private struct MiddlewareFixture {
    let transport = FakeTransport()
    let store: InMemoryTokenStore
    let refresher: TokenRefresher
    let client: Client

    init(session: StoredSession? = Fixtures.session()) {
        store = InMemoryTokenStore(session)
        let plain = Client(serverURL: Fixtures.serverURL, transport: transport, middlewares: [])
        refresher = TokenRefresher(store: store, client: plain)
        client = Client(serverURL: Fixtures.serverURL, transport: transport,
                        middlewares: [AuthMiddleware(refresher: refresher)])
    }
}

@Test func addsBearerTokenToProtectedRoutes() async throws {
    let f = MiddlewareFixture()
    f.transport.enqueue("getMe", Fixtures.meOK)
    let output = try await f.client.getMe()
    #expect(try output.ok.body.json.username == "anna")
    #expect(f.transport.log.map(\.authorization) == ["Bearer a1"])
}

@Test func doesNotAddTokenToLogin() async throws {
    let f = MiddlewareFixture()
    f.transport.enqueue("login", Fixtures.loginOK())
    f.transport.enqueue("getHealth", Fixtures.health(setupRequired: false))
    f.transport.enqueue("refresh", Fixtures.tokens(access: "a2", refresh: "r2"))
    f.transport.enqueue("setup", .error(409, code: "setup_already_done"))
    _ = try await f.client.login(body: .json(.init(password: "geheim123", username: "anna")))
    _ = try await f.client.getHealth()
    _ = try await f.client.refresh(body: .json(.init(refreshToken: "r1")))
    _ = try await f.client.setup(body: .json(.init(displayName: "A", password: "geheim123", username: "anna")))
    #expect(f.transport.log.map(\.operationID) == ["login", "getHealth", "refresh", "setup"])
    #expect(f.transport.log.allSatisfy { $0.authorization == nil })
}

@Test func refreshesOnceOn401AndRetries() async throws {
    let f = MiddlewareFixture()
    f.transport.enqueue("getMe", .error(401, code: "unauthorized"), Fixtures.meOK)
    f.transport.enqueue("refresh", Fixtures.tokens(access: "a2", refresh: "r2"))

    let output = try await f.client.getMe()

    #expect(try output.ok.body.json.username == "anna")
    let log = f.transport.log
    #expect(log.map(\.operationID) == ["getMe", "refresh", "getMe"])
    #expect(log[0].authorization == "Bearer a1")
    #expect(log[1].authorization == nil)
    #expect(log[1].bodyString("refreshToken") == "r1")
    #expect(log[2].authorization == "Bearer a2")
    // Rotation sofort persistiert (altes Refresh-Token ist serverseitig ungültig).
    #expect(f.store.load() == Fixtures.session(access: "a2", refresh: "r2"))
    #expect(try await f.refresher.validAccessToken() == "a2")
}

@Test func retriesOnlyOnceWhenRetryIsUnauthorizedToo() async throws {
    let f = MiddlewareFixture()
    f.transport.enqueue("getMe", .error(401, code: "unauthorized"), .error(401, code: "unauthorized"))
    f.transport.enqueue("refresh", Fixtures.tokens(access: "a2", refresh: "r2"))

    let output = try await f.client.getMe()

    guard case .unauthorized = output else { Issue.record("expected 401, got \(output)"); return }
    #expect(f.transport.log.map(\.operationID) == ["getMe", "refresh", "getMe"])
}

@Test func parallelRequestsTriggerSingleRefresh() async throws {
    let f = MiddlewareFixture()
    let gate = Gate(count: 3)
    // Alle drei Requests mit dem alten Token warten, bis alle da sind → drei gleichzeitige 401.
    f.transport.respond("getMe") { req in
        if req.authorization == "Bearer a1" {
            await gate.arrive()
            return .error(401, code: "unauthorized")
        }
        return Fixtures.meOK
    }
    f.transport.respond("refresh") { _ in
        try await Task.sleep(for: .milliseconds(50))
        return Fixtures.tokens(access: "a2", refresh: "r2")
    }

    async let r1 = f.client.getMe()
    async let r2 = f.client.getMe()
    async let r3 = f.client.getMe()
    let outputs = try await [r1, r2, r3]

    for output in outputs { #expect(try output.ok.body.json.username == "anna") }
    #expect(f.transport.requests("refresh").count == 1)
    let me = f.transport.requests("getMe")
    #expect(me.count == 6)
    #expect(me.filter { $0.authorization == "Bearer a1" }.count == 3)
    #expect(me.filter { $0.authorization == "Bearer a2" }.count == 3)
    #expect(f.store.load()?.refreshToken == "r2")
}

@Test func failedRefreshClearsSessionAndThrowsUnauthorized() async throws {
    let f = MiddlewareFixture()
    f.transport.enqueue("getMe", .error(401, code: "unauthorized"))
    f.transport.enqueue("refresh", .error(401, code: "invalid_refresh_token"))

    let error = await #expect(throws: (any Error).self) { try await f.client.getMe() }

    #expect(error.map(APIError.init) == .unauthorized)
    #expect(f.store.load() == nil)
    await #expect(throws: APIError.unauthorized) { try await f.refresher.validAccessToken() }
    #expect(f.transport.log.map(\.operationID) == ["getMe", "refresh"])
}

@Test func refreshNetworkFailureKeepsSession() async throws {
    let f = MiddlewareFixture()
    f.transport.enqueue("getMe", .error(401, code: "unauthorized"))
    f.transport.enqueue("refresh", .failure(URLError(.timedOut)))

    let error = await #expect(throws: (any Error).self) { try await f.client.getMe() }

    #expect(error.map(APIError.init) == .unreachable)
    #expect(f.store.load() == Fixtures.session())
    #expect(try await f.refresher.validAccessToken() == "a1")
}

@Test func tokenAlreadyRenewedIsReturnedWithoutRefresh() async throws {
    let f = MiddlewareFixture(session: Fixtures.session(access: "a2", refresh: "r2"))
    #expect(try await f.refresher.refreshAfterUnauthorized(failedToken: "a1") == "a2")
    #expect(f.transport.log.isEmpty)
}

@Test func clearDuringRefreshDiscardsRotatedTokens() async throws {
    let f = MiddlewareFixture()
    let started = Gate(count: 2)
    let release = Gate(count: 2)
    f.transport.respond("refresh") { _ in
        await started.arrive()
        await release.arrive()
        return Fixtures.tokens(access: "a2", refresh: "r2")
    }

    let refresher = f.refresher
    let token = Task { try await refresher.refreshAfterUnauthorized(failedToken: "a1") }
    await started.arrive()
    await f.refresher.clear()
    await release.arrive()

    await #expect(throws: APIError.unauthorized) { try await token.value }
    #expect(f.store.load() == nil)
}

@Test func missingSessionThrowsUnauthorizedWithoutRequest() async throws {
    let f = MiddlewareFixture(session: nil)
    let error = await #expect(throws: (any Error).self) { try await f.client.getMe() }
    #expect(error.map(APIError.init) == .unauthorized)
    #expect(f.transport.log.isEmpty)
}
