import Foundation
import Security
import CryptoKit
import BlueChatCore

/// Speichert die privaten Identitätsschlüssel in der iOS-Keychain.
///
/// Designentscheidung: Private Schlüssel gehören NICHT in SwiftData/Dateien,
/// sondern in die Keychain mit Schutzklasse
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`:
/// - `AfterFirstUnlock`: nach dem ersten Entsperren auch im Hintergrund
///   lesbar – nötig, weil BLE-Events die App im Hintergrund aufwecken.
/// - `ThisDeviceOnly`: keine iCloud-Keychain-Sync, kein Backup-Transfer
///   (Datenminimierung; der Schlüssel verlässt das Gerät nie).
enum KeychainStore {
    enum KeychainError: Error { case unexpectedStatus(OSStatus) }

    private static let service = "app.bluechat.identity"
    private static let signingKeyTag = "signing"
    private static let agreementKeyTag = "agreement"

    // MARK: - Laden oder erzeugen

    /// Lädt die vorhandene Identität oder erzeugt beim ersten Start eine neue.
    static func loadOrCreateIdentity() throws -> CryptoService.IdentityKeyPair {
        if let signing = try read(tag: signingKeyTag),
           let agreement = try read(tag: agreementKeyTag) {
            return CryptoService.IdentityKeyPair(
                signing: try Curve25519.Signing.PrivateKey(rawRepresentation: signing),
                agreement: try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: agreement)
            )
        }
        let fresh = CryptoService.generateIdentity()
        try store(fresh.signing.rawRepresentation, tag: signingKeyTag)
        try store(fresh.agreement.rawRepresentation, tag: agreementKeyTag)
        return fresh
    }

    /// Panik-Modus: alle Schlüssel unwiderruflich entfernen.
    static func wipeIdentity() {
        delete(tag: signingKeyTag)
        delete(tag: agreementKeyTag)
    }

    // MARK: - Low-Level Keychain

    private static func store(_ data: Data, tag: String) throws {
        delete(tag: tag) // idempotent
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    private static func read(tag: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        return item as? Data
    }

    @discardableResult
    private static func delete(tag: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag
        ]
        return SecItemDelete(query as CFDictionary)
    }
}
