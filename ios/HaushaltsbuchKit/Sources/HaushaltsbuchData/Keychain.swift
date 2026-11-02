import Foundation
import Security
import os

/// Sitzung als Generic-Password-Eintrag im Schlüsselbund, Account „session“, Daten = JSON.
/// `AfterFirstUnlockThisDeviceOnly`: auch bei gesperrtem Gerät lesbar (nach dem ersten Entsperren),
/// damit ein Sync im Hintergrund Tokens erneuern kann; nie in Backups/auf andere Geräte übertragen.
/// Beim Aktualisieren wird die Zugriffsklasse mitgeschrieben, so dass auch Einträge älterer
/// Versionen (`AfterFirstUnlock`) umgestellt werden.
public struct KeychainTokenStore: TokenStore {
    public static let defaultService = "de.haushaltsbuch.app.session"
    private static let account = "session"
    private static let logger = Logger(subsystem: "de.haushaltsbuch.app", category: "Keychain")

    private let service: String

    public init(service: String = KeychainTokenStore.defaultService) {
        self.service = service
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    public func load() -> StoredSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                Self.logger.error("Keychain load failed: \(status, privacy: .public)")
            }
            return nil
        }
        do {
            return try JSONDecoder().decode(StoredSession.self, from: data)
        } catch {
            Self.logger.error("Keychain session undecodable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func save(_ s: StoredSession?) {
        guard let s else {
            let status = SecItemDelete(baseQuery as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                Self.logger.error("Keychain delete failed: \(status, privacy: .public)")
            }
            return
        }
        let data: Data
        do {
            data = try JSONEncoder().encode(s)
        } catch {
            Self.logger.error("Session encoding failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            // Aktualisieren (inkl. Zugriffsklasse) nicht möglich: Eintrag neu anlegen.
            Self.logger.notice("Keychain update failed (\(status, privacy: .public)), re-adding")
            SecItemDelete(baseQuery as CFDictionary)
            status = errSecItemNotFound
        }
        if status == errSecItemNotFound {
            var add = baseQuery
            add.merge(attributes) { _, new in new }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        if status != errSecSuccess {
            Self.logger.error("Keychain save failed: \(status, privacy: .public)")
        }
    }
}
