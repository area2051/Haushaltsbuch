import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
import HaushaltsbuchAPI
@testable import HaushaltsbuchData

private func run(_ json: String, path: String = "/sync", operationID: String = "sync",
                 contentType: String = "application/json") async throws -> [String: Any]? {
    var request = HTTPRequest(method: .post, scheme: nil, authority: nil, path: path)
    request.headerFields[.contentType] = contentType
    let captured = Captured()
    _ = try await SyncParentIdMiddleware().intercept(
        request, body: HTTPBody(Data(json.utf8)), baseURL: URL(string: "http://x")!, operationID: operationID
    ) { req, body, _ in
        if let body { await captured.set(try await Data(collecting: body, upTo: 1_000_000)) }
        return (HTTPResponse(status: .ok), nil)
    }
    guard let data = await captured.data else { return nil }
    return try JSONSerialization.jsonObject(with: data) as? [String: Any]
}

private actor Captured {
    var data: Data?
    func set(_ d: Data) { data = d }
}

private func categories(_ o: [String: Any]?) -> [[String: Any]] {
    ((o?["changes"] as? [String: Any])?["categories"] as? [[String: Any]]) ?? []
}

@Test func addsNullParentIdWhenMissing() async throws {
    let out = try await run(#"{"lastVersion":0,"changes":{"categories":[{"id":"a","name":"X"}]}}"#)
    let c = try #require(categories(out).first)
    #expect(c["parentId"] is NSNull)
    #expect(c["name"] as? String == "X")
}

@Test func keepsExistingParentId() async throws {
    let out = try await run(#"{"changes":{"categories":[{"id":"a","parentId":"p"},{"id":"b","parentId":null}]}}"#)
    let cs = categories(out)
    #expect(cs[0]["parentId"] as? String == "p")
    #expect(cs[1]["parentId"] is NSNull)
}

@Test func leavesBodyWithoutCategoriesUnchanged() async throws {
    let out = try await run(#"{"lastVersion":3,"changes":{"budgets":[{"id":"a"}]}}"#)
    #expect(out?["changes"] as? [String: Any] != nil)
    #expect((out?["changes"] as? [String: Any])?["categories"] == nil)
    #expect(out?["lastVersion"] as? Int == 3)
}

@Test func leavesOtherOperationsUnchanged() async throws {
    let out = try await run(#"{"changes":{"categories":[{"id":"a"}]}}"#, path: "/other", operationID: "login")
    #expect(categories(out).first?["parentId"] == nil)
}

@Test func passesNonJsonBodyThrough() async throws {
    var request = HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/sync")
    request.headerFields[.contentType] = "application/json"
    let captured = Captured()
    _ = try await SyncParentIdMiddleware().intercept(
        request, body: HTTPBody(Data("kein json".utf8)), baseURL: URL(string: "http://x")!, operationID: "sync"
    ) { _, body, _ in
        if let body { await captured.set(try await Data(collecting: body, upTo: 1000)) }
        return (HTTPResponse(status: .ok), nil)
    }
    #expect(await captured.data.flatMap { String(data: $0, encoding: .utf8) } == "kein json")
}

/// Ende-zu-Ende: der generierte Encoder lässt `parentId: nil` weg; die Middleware muss es als `null`
/// senden, damit das Entfernen des Elternteils beim Server ankommt.
@Test func clearedParentIdIsSentAsNullThroughClient() async throws {
    let transport = FakeTransport()
    transport.enqueue("sync", .json(200, #"{"currentVersion":1,"fullResync":false,"changes":{"categories":[],"transactions":[],"budgets":[],"recurringRules":[],"users":[]},"rejected":[]}"#))
    let client = Client(serverURL: URL(string: "http://x")!, transport: transport,
                        middlewares: [SyncParentIdMiddleware()])
    let record = Components.Schemas.CategoryRecord(archived: false, color: "#000000", deleted: false, icon: "bolt",
                                                   id: UUID().uuidString.lowercased(), kind: .expense,
                                                   name: "Strom", parentId: nil, sortOrder: 0)
    _ = try? await client.sync(body: .json(.init(changes: .init(categories: [record]), lastVersion: 0)))
    let sent = try #require(transport.requests("sync").first?.body)
    let obj = try #require(try JSONSerialization.jsonObject(with: sent) as? [String: Any])
    let c = try #require(categories(obj).first)
    #expect(c["parentId"] is NSNull)
}
