import Foundation
import HTTPTypes
import OpenAPIRuntime
import Synchronization
import HaushaltsbuchAPI
@testable import HaushaltsbuchData

/// Ein mitgeschnittener Request.
struct RecordedRequest: Sendable {
    let operationID: String
    let method: HTTPRequest.Method
    let path: String
    let authorization: String?
    let body: Data?

    /// Feld aus dem JSON-Body (nur Top-Level-Strings).
    func bodyString(_ key: String) -> String? {
        guard let body, let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        return obj[key] as? String
    }
}

/// Antwort des Fake-Transports.
enum FakeReply: Sendable {
    case json(Int, String)
    case empty(Int)
    case failure(any Error)

    static func error(_ status: Int, code: String, message: String = "msg") -> FakeReply {
        .json(status, #"{"error":{"code":"\#(code)","message":"\#(message)"}}"#)
    }
}

/// Fake-`ClientTransport`: liefert pro operationID Antworten aus einer FIFO-Queue (oder über einen
/// dynamischen Responder) und schneidet alle Requests mit.
final class FakeTransport: ClientTransport, Sendable {
    typealias Responder = @Sendable (RecordedRequest) async throws -> FakeReply

    private struct State {
        var queues: [String: [FakeReply]] = [:]
        var responders: [String: Responder] = [:]
        var log: [RecordedRequest] = []
    }

    private let state = Mutex(State())

    func enqueue(_ operationID: String, _ replies: FakeReply...) {
        state.withLock { $0.queues[operationID, default: []].append(contentsOf: replies) }
    }

    func respond(_ operationID: String, with responder: @escaping Responder) {
        state.withLock { $0.responders[operationID] = responder }
    }

    var log: [RecordedRequest] { state.withLock { $0.log } }

    func requests(_ operationID: String) -> [RecordedRequest] {
        log.filter { $0.operationID == operationID }
    }

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL,
              operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        var data: Data?
        if let body { data = try await Data(collecting: body, upTo: 10 * 1024 * 1024) }
        let recorded = RecordedRequest(operationID: operationID, method: request.method,
                                       path: request.path ?? "",
                                       authorization: request.headerFields[.authorization], body: data)
        let (queued, responder): (FakeReply?, Responder?) = state.withLock { s in
            s.log.append(recorded)
            if var q = s.queues[operationID], !q.isEmpty {
                let first = q.removeFirst()
                s.queues[operationID] = q
                return (first, nil)
            }
            return (nil, s.responders[operationID])
        }
        let reply: FakeReply
        if let queued {
            reply = queued
        } else if let responder {
            reply = try await responder(recorded)
        } else {
            fatalError("FakeTransport: keine Antwort für \(operationID)")
        }
        switch reply {
        case let .json(status, json):
            var response = HTTPResponse(status: .init(code: status))
            response.headerFields[.contentType] = "application/json; charset=utf-8"
            return (response, HTTPBody(Data(json.utf8)))
        case let .empty(status):
            return (HTTPResponse(status: .init(code: status)), nil)
        case let .failure(error):
            throw error
        }
    }
}

/// Lässt `count` Aufrufer warten, bis alle angekommen sind.
actor Gate {
    private let count: Int
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(count: Int) { self.count = count }

    func arrive() async {
        if waiting.count + 1 >= count {
            let all = waiting
            waiting = []
            all.forEach { $0.resume() }
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }
}

enum Fixtures {
    static let serverURL = URL(string: "http://nas.local:3000")!
    static let userId = UUID(uuidString: "0F8FAD5B-D9CB-469F-A165-70867728950E")!

    static func session(access: String = "a1", refresh: String = "r1") -> StoredSession {
        StoredSession(serverURL: serverURL, accessToken: access, refreshToken: refresh,
                      userId: userId, username: "anna", isAdmin: true)
    }

    static let userJSON = #"{"id":"0f8fad5b-d9cb-469f-a165-70867728950e","username":"anna","displayName":"Anna","isAdmin":true}"#

    static func tokens(access: String, refresh: String) -> FakeReply {
        .json(200, #"{"accessToken":"\#(access)","refreshToken":"\#(refresh)"}"#)
    }

    static func loginOK(access: String = "a1", refresh: String = "r1") -> FakeReply {
        .json(200, #"{"accessToken":"\#(access)","refreshToken":"\#(refresh)","user":\#(userJSON)}"#)
    }

    static func health(setupRequired: Bool) -> FakeReply {
        .json(200, #"{"status":"ok","setupRequired":\#(setupRequired)}"#)
    }

    static let meOK = FakeReply.json(200, userJSON)
}
