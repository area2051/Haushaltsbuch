import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Sendet `parentId: null` für Kategorien ohne Elternteil.
///
/// Der generierte Encoder lässt nil-Optionals weg, der Server wertet ein fehlendes `parentId` aber als
/// „Wert behalten“. Ohne diese Ergänzung käme das Entfernen eines Elternteils nie beim Server an.
/// Nur der JSON-Body der Operation `sync` wird angefasst; alles andere läuft unverändert durch.
public struct SyncParentIdMiddleware: ClientMiddleware {
    public init() {}

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        guard operationID == "sync", let body else { return try await next(request, body, baseURL) }
        let data = try await Data(collecting: body, upTo: 16 * 1024 * 1024)
        let patched = Self.addingNullParentIds(to: data)
        var request = request
        if request.headerFields[.contentLength] != nil {
            request.headerFields[.contentLength] = String(patched.count)
        }
        return try await next(request, HTTPBody(patched), baseURL)
    }

    /// Unverändert, wenn der Body kein JSON-Objekt mit `changes.categories` ist.
    static func addingNullParentIds(to data: Data) -> Data {
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var changes = root["changes"] as? [String: Any],
              var categories = changes["categories"] as? [[String: Any]],
              let patched = try? { () throws -> Data in
                  for i in categories.indices where categories[i]["parentId"] == nil {
                      categories[i]["parentId"] = NSNull()
                  }
                  changes["categories"] = categories
                  root["changes"] = changes
                  return try JSONSerialization.data(withJSONObject: root)
              }()
        else { return data }
        return patched
    }
}
