import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

/// Erzeugt den generierten API-Client für die gegebene Server-Adresse
/// (z. B. `http://192.168.1.10:3000`) mit URLSession als Transport.
public func makeClient(serverURL: URL, middlewares: [any ClientMiddleware]) -> Client {
    Client(
        serverURL: serverURL,
        transport: URLSessionTransport(),
        middlewares: middlewares
    )
}
