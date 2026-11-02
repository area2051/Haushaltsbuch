import Foundation
import Testing
import HaushaltsbuchAPI
@testable import HaushaltsbuchData

private let bertJSON = #"{"id":"7c9e6679-7425-40de-944b-e07fc1f90ae7","username":"bert","displayName":"Bert","isAdmin":false}"#
private let bertId = UUID(uuidString: "7C9E6679-7425-40DE-944B-E07FC1F90AE7")!

private func admin(_ t: FakeTransport) -> MemberAdmin {
    MemberAdmin(client: Client(serverURL: Fixtures.serverURL, transport: t))
}

@Test func memberAdminListsUsers() async throws {
    let t = FakeTransport()
    t.enqueue("listUsers", .json(200, "[\(Fixtures.userJSON),\(bertJSON)]"))
    let users = try await admin(t).list()
    #expect(users.map(\.username) == ["anna", "bert"])
    #expect(users[1] == MemberInfo(id: bertId, username: "bert", displayName: "Bert", isAdmin: false))
}

@Test func memberAdminCreatesUser() async throws {
    let t = FakeTransport()
    t.enqueue("createUser", .json(201, bertJSON))
    let bert = try await admin(t).create(username: "bert", displayName: "Bert", password: "geheim123", isAdmin: false)
    #expect(bert.id == bertId)
    let body = try #require(t.requests("createUser").first)
    #expect(body.bodyString("username") == "bert")
    #expect(body.bodyString("password") == "geheim123")
}

@Test func memberAdminMapsConflict() async throws {
    let t = FakeTransport()
    t.enqueue("createUser", .error(409, code: "username_taken"))
    await #expect(throws: APIError.server(code: "username_taken", message: "msg")) {
        _ = try await admin(t).create(username: "bert", displayName: "Bert", password: "geheim123", isAdmin: false)
    }
}

@Test func memberAdminUpdatesAndDeletes() async throws {
    let t = FakeTransport()
    t.enqueue("updateUser", .json(200, bertJSON), .error(409, code: "last_admin"))
    _ = try await admin(t).update(id: bertId, displayName: "Bert K.", password: nil, isAdmin: true)
    let first = try #require(t.requests("updateUser").first)
    #expect(first.path.hasSuffix("/users/7c9e6679-7425-40de-944b-e07fc1f90ae7"))
    #expect(first.bodyString("displayName") == "Bert K.")
    let json = try #require(first.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
    #expect(json["password"] == nil)
    #expect(json["isAdmin"] as? Bool == true)

    await #expect(throws: APIError.server(code: "last_admin", message: "msg")) {
        try await admin(t).remove(id: bertId)
    }
    let second = try #require(t.requests("updateUser").last)
    let json2 = try #require(second.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
    #expect(json2["deleted"] as? Bool == true)
}

@Test func memberAdminOfflineIsUnreachable() async throws {
    let t = FakeTransport()
    t.enqueue("listUsers", .failure(URLError(.cannotConnectToHost)))
    await #expect(throws: APIError.unreachable) { _ = try await admin(t).list() }
    t.enqueue("listUsers", .error(403, code: "forbidden"))
    await #expect(throws: APIError.server(code: "forbidden", message: "msg")) { _ = try await admin(t).list() }
}
