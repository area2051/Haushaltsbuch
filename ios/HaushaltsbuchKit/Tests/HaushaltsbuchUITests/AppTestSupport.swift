import Foundation
import HTTPTypes
import OpenAPIRuntime
import SwiftData
import Synchronization
import HaushaltsbuchAPI
import HaushaltsbuchCore
import HaushaltsbuchData
@testable import HaushaltsbuchUI

/// Minimaler Fake-`ClientTransport`: Antworten je operationID aus einer FIFO-Queue.
final class StubClientTransport: ClientTransport, Sendable {
    enum Reply: Sendable {
        case json(Int, String)
        case empty(Int)
        case failure(URLError.Code)
    }

    private struct State {
        var queues: [String: [Reply]] = [:]
        var log: [String] = []
    }

    private let state = Mutex(State())

    func enqueue(_ operationID: String, _ replies: Reply...) {
        state.withLock { $0.queues[operationID, default: []].append(contentsOf: replies) }
    }

    func calls(_ operationID: String) -> Int {
        state.withLock { $0.log.filter { $0 == operationID }.count }
    }

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL,
              operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        let reply: Reply? = state.withLock { s in
            s.log.append(operationID)
            guard var q = s.queues[operationID], !q.isEmpty else { return nil }
            let first = q.removeFirst()
            s.queues[operationID] = q
            return first
        }
        switch reply {
        case let .json(status, json):
            var response = HTTPResponse(status: .init(code: status))
            response.headerFields[.contentType] = "application/json; charset=utf-8"
            return (response, HTTPBody(Data(json.utf8)))
        case let .empty(status):
            return (HTTPResponse(status: .init(code: status)), nil)
        case let .failure(code):
            throw URLError(code)
        case nil:
            throw URLError(.cannotConnectToHost)
        }
    }
}

/// Fake-`SyncTransport`: offline (Standard) oder leere Server-Antwort.
final class StubSyncTransport: SyncTransport {
    private let online = Mutex(false)
    private let count = Mutex(0)

    var isOnline: Bool {
        get { online.withLock { $0 } }
        set { online.withLock { $0 = newValue } }
    }

    var requests: Int { count.withLock { $0 } }

    func sync(_ request: Components.Schemas.SyncRequest) async throws -> Components.Schemas.SyncResponse {
        count.withLock { $0 += 1 }
        guard isOnline else { throw APIError.unreachable }
        return Components.Schemas.SyncResponse(
            changes: .init(budgets: [], categories: [], recurringRules: [], transactions: [], users: []),
            currentVersion: request.lastVersion, fullResync: false, rejected: [])
    }
}

/// Fake-`SyncTransport`, der nie antwortet (bis zum Abbruch) – simuliert einen hängenden Request.
final class HangingSyncTransport: SyncTransport {
    func sync(_ request: Components.Schemas.SyncRequest) async throws -> Components.Schemas.SyncResponse {
        while true {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// Zeichnet die Aufrufe des Schedulers auf, synchronisiert selbst nicht.
@MainActor
final class FakeScheduler: SyncScheduling {
    var starts = 0
    var stops = 0
    var activations = 0
    var localChanges = 0
    var refreshes = 0

    var isRunning: Bool { starts > stops }

    func start() { starts += 1 }
    func stop() { stops += 1 }
    func appDidBecomeActive() { activations += 1 }
    func localChange() { localChanges += 1 }
    func pullToRefresh() async { refreshes += 1 }
}

enum AppFixtures {
    static let serverURL = URL(string: "http://nas.local:3000")!
    static let annaId = UUID(uuidString: "0F8FAD5B-D9CB-469F-A165-70867728950E")!
    static let bertId = UUID(uuidString: "7C9E6679-7425-40DE-944B-E07FC1F90AE7")!

    static func session(access: String = "a1", refresh: String = "r1") -> StoredSession {
        StoredSession(serverURL: serverURL, accessToken: access, refreshToken: refresh,
                      userId: annaId, username: "anna", isAdmin: true)
    }

    static func health(setupRequired: Bool) -> StubClientTransport.Reply {
        .json(200, #"{"status":"ok","setupRequired":\#(setupRequired)}"#)
    }

    static func loginOK(id: UUID, username: String) -> StubClientTransport.Reply {
        let user = #"{"id":"\#(id.uuidString.lowercased())","username":"\#(username)","displayName":"\#(username)","isAdmin":true}"#
        return .json(200, #"{"accessToken":"a-\#(username)","refreshToken":"r-\#(username)","user":\#(user)}"#)
    }

    static func error(_ status: Int, code: String) -> StubClientTransport.Reply {
        .json(status, #"{"error":{"code":"\#(code)","message":"msg"}}"#)
    }
}

/// AppModel mit In-Memory-Store, Fake-Server und Fake-Scheduler.
@MainActor
final class AppFixture {
    let transport = StubClientTransport()
    let syncTransport = StubSyncTransport()
    let store: InMemoryTokenStore
    let defaults: UserDefaults
    let container: ModelContainer
    let auth: AuthService
    var schedulers: [FakeScheduler] = []
    var cursors: [String: InMemoryCursorStore] = [:]
    private(set) var model: AppModel!

    /// - Parameter realSyncTransport: `true` → `ClientSyncTransport` über den Fake-Client
    ///   (für Tests mit Token-Ablauf); sonst `syncTransport`.
    init(session: StoredSession? = nil, lastUsername: String? = nil, realSyncTransport: Bool = false,
         hangingSync: Bool = false, logoutSyncTimeout: Double = 5,
         wipe: (@MainActor (AppModel, ModelContext) throws -> Void)? = nil) throws {
        store = InMemoryTokenStore(session)
        defaults = UserDefaults(suiteName: "AppModelTests-\(UUID().uuidString)")!
        if let lastUsername { defaults.set(lastUsername, forKey: AuthService.lastUsernameKey) }
        if session != nil { defaults.set(AppFixtures.serverURL, forKey: AuthService.lastServerURLKey) }
        container = try ModelContainer.makeAppContainer(inMemory: true)
        let transport = self.transport
        auth = AuthService(store: store, defaults: defaults, deviceName: "Test",
                           clientFactory: { url, middlewares in
                               Client(serverURL: url, transport: transport, middlewares: middlewares)
                           })
        let syncTransport = self.syncTransport
        let deps = AppModel.Dependencies(
            makeTransport: { client in
                if hangingSync { return HangingSyncTransport() }
                return realSyncTransport ? ClientSyncTransport(client: client) as any SyncTransport : syncTransport
            },
            makeCursor: { [unowned self] url, user in
                self.cursor(url, user)
            },
            makeScheduler: { [unowned self] _ in
                let s = FakeScheduler()
                self.schedulers.append(s)
                return s
            },
            wipeStore: { [unowned self] context in
                if let wipe { try wipe(self.model, context) } else { try AppModel.deleteAllRecords(in: context) }
            },
            logoutSyncTimeout: logoutSyncTimeout)
        model = AppModel(container: container, auth: auth, defaults: defaults, dependencies: deps)
    }

    func cursor(_ url: URL, _ user: UUID) -> InMemoryCursorStore {
        let key = UserDefaultsCursorStore.key(serverURL: url, userId: user)
        if let c = cursors[key] { return c }
        let c = InMemoryCursorStore()
        cursors[key] = c
        return c
    }

    @discardableResult
    func addPendingTransaction() throws -> TransactionEntity {
        let cat = try model.repository.saveCategory(
            CategoryDraft(name: "Essen", icon: "cart", color: "#112233", kind: .expense))
        return try model.repository.addTransaction(
            amountCents: 1250, kind: .expense, categoryId: cat.id,
            day: CalendarDay(year: 2026, month: 11, day: 1)!, paidBy: AppFixtures.annaId, note: nil)
    }

    /// Sitzung läuft ab (Access-Token abgelehnt, Refresh-Token ungültig): der `AuthService` verwirft
    /// sie, lokale Daten bleiben, Phase `.locked`.
    func expireSession() async {
        transport.enqueue("listUsers", AppFixtures.error(401, code: "unauthorized"))
        transport.enqueue("refresh", AppFixtures.error(401, code: "invalid_refresh_token"))
        _ = try? await auth.client?.listUsers()
        await waitUntil { self.model.phase == .locked }
    }

    func count<T: PersistentModel>(_ type: T.Type) throws -> Int {
        try container.mainContext.fetchCount(FetchDescriptor<T>())
    }
}

/// Wartet (kooperativ) bis `condition` gilt; bricht nach ~2 s ab.
@MainActor
func waitUntil(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<2000 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
}
