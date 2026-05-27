import Foundation
import CryptoKit

/// Bündelt alle kryptographischen Primitive des Messengers.
///
/// Trennung der Schlüsselrollen (bewusste Designentscheidung):
/// - `Curve25519.Signing` (Ed25519): langlebige IDENTITÄT. Signiert Pakete,
///   bildet die Grundlage des Fingerprints. Wechselt nie (außer bei Reset).
/// - `Curve25519.KeyAgreement` (X25519): Diffie-Hellman zum Ableiten von
///   Shared Secrets. Es gibt ein langlebiges Agreement-Paar plus ephemere
///   Paare pro Session (Forward Secrecy).
///
/// Alle Methoden sind statisch/pur und damit gut testbar. Die persistente
/// Schlüsselhaltung übernimmt der App-seitige Keychain-Store.
public enum CryptoService {

    // MARK: - Schlüsselerzeugung

    public struct IdentityKeyPair {
        public let signing: Curve25519.Signing.PrivateKey
        public let agreement: Curve25519.KeyAgreement.PrivateKey

        public init(
            signing: Curve25519.Signing.PrivateKey = .init(),
            agreement: Curve25519.KeyAgreement.PrivateKey = .init()
        ) {
            self.signing = signing
            self.agreement = agreement
        }

        /// PeerID wird aus dem Signing-Public-Key abgeleitet (stabil über die Lebensdauer).
        public var peerID: PeerID { PeerID.derive(fromPublicKey: signing.publicKey.rawRepresentation) }
    }

    /// Erzeugt ein frisches Identitätsschlüsselpaar.
    public static func generateIdentity() -> IdentityKeyPair { IdentityKeyPair() }

    /// Frisches ephemeres X25519-Paar für eine neue Session/Ratchet-Runde.
    public static func generateEphemeral() -> Curve25519.KeyAgreement.PrivateKey { .init() }

    // MARK: - Signatur (Ed25519)

    public static func sign(_ data: Data, with key: Curve25519.Signing.PrivateKey) throws -> Data {
        try key.signature(for: data)
    }

    public static func verify(_ signature: Data, of data: Data, publicKey: Curve25519.Signing.PublicKey) -> Bool {
        publicKey.isValidSignature(signature, for: data)
    }

    // MARK: - Diffie-Hellman + HKDF

    /// X25519-Schlüsselvereinbarung, anschließend HKDF-SHA256 auf 32 Byte.
    /// `salt`/`info` binden den abgeleiteten Schlüssel an Kontext (Domain-Separation).
    public static func deriveSharedKey(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        peerPublicKey: Curve25519.KeyAgreement.PublicKey,
        salt: Data = Data(),
        info: Data = Data("BlueChat-v1".utf8)
    ) throws -> SymmetricKey {
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
        return shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: info,
            outputByteCount: 32
        )
    }

    // MARK: - AES-GCM Symmetrische Verschlüsselung

    /// Verschlüsselt `plaintext` mit AES-GCM-256.
    /// `aad` (Additional Authenticated Data) bindet z. B. den Paket-Header
    /// kryptographisch an den Ciphertext, ohne ihn zu verschlüsseln.
    public static func encrypt(_ plaintext: Data, key: SymmetricKey, aad: Data = Data()) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: aad)
        // combined = nonce(12) || ciphertext || tag(16)
        guard let combined = sealed.combined else { throw CryptoError.sealFailed }
        return combined
    }

    public static func decrypt(_ ciphertext: Data, key: SymmetricKey, aad: Data = Data()) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: key, authenticating: aad)
    }

    public enum CryptoError: Error { case sealFailed }
}
