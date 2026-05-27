import Foundation
import CryptoKit

/// Symmetrischer Schlüssel-Ratchet (Hash-Ratchet) für Forward Secrecy.
///
/// Aus einem gemeinsamen Root-Key (Ergebnis des X25519-Handshakes) werden zwei
/// gerichtete Chains abgeleitet ("A→B" und "B→A"). Welche Chain zum Senden bzw.
/// Empfangen dient, bestimmt die Rolle (Initiator/Responder) – so erhalten
/// beide Geräte aus demselben Root deterministisch dieselben Schlüssel.
///
/// Pro Nachricht erzeugt die Chain per HMAC einen Einweg-Message-Key und
/// ersetzt sich selbst. Ein geleakter Message-Key verrät weder frühere noch
/// spätere Keys ⇒ **Forward Secrecy**.
///
/// Bewusste Vereinfachung gegenüber dem vollen Signal-Double-Ratchet: Es fehlt
/// der DH-Ratchet-Schritt, der zusätzlich **Post-Compromise-Security**
/// (Selbstheilung) liefern würde. Das ist der dokumentierte nächste Ausbau-
/// schritt; die Wire-Struktur (Counter pro Nachricht) ist bereits darauf
/// vorbereitet. Diese Implementierung ist kompakt und gut testbar, aber nicht
/// formal auditiert.
public final class DoubleRatchet {

    public enum Role: String, Codable { case initiator, responder }

    /// Persistierbarer Zustand (enthält Schlüsselmaterial → verschlüsselt halten).
    public struct State: Codable, Equatable {
        public var sendChainKey: Data
        public var recvChainKey: Data
        public var sendCount: UInt32
        public var recvCount: UInt32
    }

    private(set) var state: State
    public var snapshot: State { state }

    public init(rootKey: SymmetricKey, role: Role) {
        let chainA = Self.kdfLabel(rootKey, label: "BlueChat-chain-A")
        let chainB = Self.kdfLabel(rootKey, label: "BlueChat-chain-B")
        switch role {
        case .initiator: state = State(sendChainKey: chainA, recvChainKey: chainB, sendCount: 0, recvCount: 0)
        case .responder: state = State(sendChainKey: chainB, recvChainKey: chainA, sendCount: 0, recvCount: 0)
        }
    }

    public init(state: State) { self.state = state }

    // MARK: - KDF-Helfer

    private static func kdfLabel(_ key: SymmetricKey, label: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(label.utf8), using: key))
    }

    /// Chain-KDF: aus einem Chain-Key (a) den Message-Key, (b) den nächsten Chain-Key.
    private static func kdfChain(_ chainKey: Data) -> (messageKey: SymmetricKey, nextChain: Data) {
        let ck = SymmetricKey(data: chainKey)
        let msg = HMAC<SHA256>.authenticationCode(for: Data([0x01]), using: ck)
        let next = HMAC<SHA256>.authenticationCode(for: Data([0x02]), using: ck)
        return (SymmetricKey(data: Data(msg)), Data(next))
    }

    // MARK: - Verschlüsseln / Entschlüsseln

    public struct RatchetMessage: Equatable, Sendable {
        public let counter: UInt32
        public let ciphertext: Data
        public init(counter: UInt32, ciphertext: Data) {
            self.counter = counter
            self.ciphertext = ciphertext
        }
    }

    public func encrypt(_ plaintext: Data, aad: Data = Data()) throws -> RatchetMessage {
        let (msgKey, next) = Self.kdfChain(state.sendChainKey)
        state.sendChainKey = next
        let counter = state.sendCount
        state.sendCount += 1
        let ct = try CryptoService.encrypt(plaintext, key: msgKey, aad: aad)
        return RatchetMessage(counter: counter, ciphertext: ct)
    }

    public func decrypt(_ message: RatchetMessage, aad: Data = Data()) throws -> Data {
        var chain = state.recvChainKey
        var key: SymmetricKey?
        var c = state.recvCount
        // Bis zum Counter vorspulen; fehlende Nachrichten werden übersprungen
        // (verlorene Pakete dürfen die Chain nicht dauerhaft blockieren).
        while c <= message.counter {
            let (mk, next) = Self.kdfChain(chain)
            chain = next
            if c == message.counter { key = mk }
            c += 1
        }
        state.recvChainKey = chain
        state.recvCount = message.counter + 1
        guard let mk = key else { throw RatchetError.keyDerivationFailed }
        return try CryptoService.decrypt(message.ciphertext, key: mk, aad: aad)
    }

    public enum RatchetError: Error { case keyDerivationFailed }
}

// MARK: - Komfort-Erweiterungen

extension SymmetricKey {
    /// Roh-Bytes des Schlüssels als Data.
    var rawData: Data { withUnsafeBytes { Data($0) } }
}

extension Digest {
    var rawData: Data { Data(self) }
}
