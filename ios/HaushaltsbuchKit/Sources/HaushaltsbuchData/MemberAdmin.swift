import Foundation
import OpenAPIRuntime
import HaushaltsbuchAPI

/// Mitglied, wie `GET /users` es liefert (nur online; die lokale Liste kommt per Sync als `MemberEntity`).
public struct MemberInfo: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var username: String
    public var displayName: String
    public var isAdmin: Bool

    public init(id: UUID, username: String, displayName: String, isAdmin: Bool) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.isAdmin = isAdmin
    }

    init(_ dto: Components.Schemas.UserDto) throws {
        guard let id = UUID(uuidString: dto.id) else { throw APIError.unexpected("Ungültige Benutzer-ID") }
        self.init(id: id, username: dto.username, displayName: dto.displayName, isAdmin: dto.isAdmin)
    }
}

/// Mitgliederverwaltung (nur Admins, nur online) über den authentifizierten `AuthService.client`.
/// Alle Fehler kommen als `APIError` (Server-Codes `username_taken`, `last_admin`,
/// `cannot_delete_self`, `forbidden` …; offline `.unreachable`).
public struct MemberAdmin: Sendable {
    private let client: Client

    public init(client: Client) {
        self.client = client
    }

    public func list() async throws -> [MemberInfo] {
        let output: Operations.listUsers.Output
        do { output = try await client.listUsers() } catch { throw APIError(error) }
        switch output {
        case let .ok(ok):
            let users: [Components.Schemas.UserDto]
            do { users = try ok.body.json } catch { throw APIError(error) }
            return try users.map(MemberInfo.init)
        case .unauthorized:
            throw APIError.unauthorized
        case let .forbidden(r):
            throw (try? APIError(r.body.json)) ?? APIError.undocumented(403)
        case let .internalServerError(r):
            throw (try? APIError(r.body.json)) ?? APIError.undocumented(500)
        case let .undocumented(statusCode, _):
            throw APIError.undocumented(statusCode)
        }
    }

    public func create(username: String, displayName: String, password: String,
                       isAdmin: Bool) async throws -> MemberInfo {
        let output: Operations.createUser.Output
        do {
            output = try await client.createUser(body: .json(.init(
                displayName: displayName, isAdmin: isAdmin, password: password, username: username)))
        } catch {
            throw APIError(error)
        }
        switch output {
        case let .created(r):
            do { return try MemberInfo(r.body.json) } catch { throw APIError(error) }
        case .unauthorized:
            throw APIError.unauthorized
        case let .badRequest(r):
            throw (try? APIError(r.body.json)) ?? APIError.undocumented(400)
        case let .forbidden(r):
            throw (try? APIError(r.body.json)) ?? APIError.undocumented(403)
        case let .conflict(r):
            throw (try? APIError(r.body.json)) ?? APIError.undocumented(409)
        case let .internalServerError(r):
            throw (try? APIError(r.body.json)) ?? APIError.undocumented(500)
        case let .undocumented(statusCode, _):
            throw APIError.undocumented(statusCode)
        }
    }

    /// Nur gesetzte Felder werden gesendet (`password` = Zurücksetzen durch den Admin).
    @discardableResult
    public func update(id: UUID, displayName: String? = nil, password: String? = nil,
                       isAdmin: Bool? = nil) async throws -> MemberInfo {
        try await patch(id: id, .init(displayName: displayName, isAdmin: isAdmin, password: password))
    }

    /// Entfernt das Mitglied (`deleted: true`; Server: Soft-Delete, Tokens widerrufen).
    public func remove(id: UUID) async throws {
        _ = try await patch(id: id, .init(deleted: true))
    }

    private func patch(id: UUID, _ body: Components.Schemas.UpdateUserRequest) async throws -> MemberInfo {
        let output: Operations.updateUser.Output
        do {
            output = try await client.updateUser(path: .init(id: id.uuidString.lowercased()), body: .json(body))
        } catch {
            throw APIError(error)
        }
        switch output {
        case let .ok(r):
            do { return try MemberInfo(r.body.json) } catch { throw APIError(error) }
        case .unauthorized:
            throw APIError.unauthorized
        case let .badRequest(r):
            throw (try? APIError(r.body.json)) ?? APIError.undocumented(400)
        case let .forbidden(r):
            throw (try? APIError(r.body.json)) ?? APIError.undocumented(403)
        case let .notFound(r):
            throw (try? APIError(r.body.json)) ?? APIError.undocumented(404)
        case let .conflict(r):
            throw (try? APIError(r.body.json)) ?? APIError.undocumented(409)
        case let .internalServerError(r):
            throw (try? APIError(r.body.json)) ?? APIError.undocumented(500)
        case let .undocumented(statusCode, _):
            throw APIError.undocumented(statusCode)
        }
    }
}
