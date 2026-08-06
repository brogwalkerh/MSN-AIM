import Foundation
import Security

/// A generic-password wrapper, deliberately small.
///
/// Spotify's refresh token is a long-lived credential that grants control of the user's
/// account playback until revoked. `UserDefaults` would be simpler and is where this sort
/// of thing usually ends up, but it is a plist inside the app container: readable from a
/// file-system dump, and included in unencrypted backups. The Keychain is the difference
/// between "someone got your phone" and "someone got your Spotify".
///
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` is chosen over the default:
/// - *AfterFirstUnlock* because the app refreshes tokens in the background while the
///   phone sits locked in a car mount, and `WhenUnlocked` would fail exactly then.
/// - *ThisDeviceOnly* because a credential has no business travelling to a new phone in
///   an iCloud restore.
public enum Keychain {
    public enum Error: Swift.Error, Equatable {
        case unexpectedStatus(OSStatus)
    }

    /// Namespaced so a Spotify token can never collide with anything added later.
    private static let service = "com.brogwalkerh.cardash.credentials"

    public static func set(_ data: Data, for key: String) throws {
        // SecItemUpdate on a missing item fails, and SecItemAdd on an existing one fails
        // with errSecDuplicateItem. Deleting first is the only shape that is correct for
        // both, and a delete that finds nothing is not an error.
        try? remove(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw Error.unexpectedStatus(status) }
    }

    public static func data(for key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    public static func remove(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Error.unexpectedStatus(status)
        }
    }

    // MARK: - Codable convenience

    public static func store<Value: Encodable>(_ value: Value, for key: String) throws {
        try set(try JSONEncoder().encode(value), for: key)
    }

    public static func load<Value: Decodable>(_ type: Value.Type, for key: String) -> Value? {
        guard let data = data(for: key) else { return nil }
        // A credential written by an older build with a different shape is not worth
        // reporting; it simply means signing in again.
        return try? JSONDecoder().decode(type, from: data)
    }
}
