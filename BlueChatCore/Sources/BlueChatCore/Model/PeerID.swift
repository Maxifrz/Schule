import Foundation
import CryptoKit

/// Kompakter 8-Byte-Identifier eines Geräts/Peers.
///
/// Designentscheidung: Im Funkprotokoll wollen wir keine vollständigen 32-Byte
/// Public Keys mitschicken (Bandbreite ist bei BLE knapp). Stattdessen leiten
/// wir aus dem langlebigen Identity-Public-Key einen kurzen, kollisionsarmen
/// Identifier ab: die ersten 8 Bytes von SHA-256(publicKey).
///
/// 8 Bytes = 64 Bit. Für die typische Größenordnung eines lokalen Mesh
/// (Dutzende bis wenige Hundert Geräte in Reichweite) ist die Kollisions-
/// wahrscheinlichkeit vernachlässigbar. Der volle Schlüssel wird beim
/// KEY_EXCHANGE einmalig ausgetauscht und danach lokal der PeerID zugeordnet.
public struct PeerID: Hashable, Codable, CustomStringConvertible, Sendable {
    public static let byteCount = 8

    /// Die 8 Roh-Bytes des Identifiers.
    public let bytes: [UInt8]

    public init(bytes: [UInt8]) {
        precondition(bytes.count == PeerID.byteCount, "PeerID muss exakt \(PeerID.byteCount) Bytes haben")
        self.bytes = bytes
    }

    /// Sonderwert: Alle Bytes = 0 bedeutet "Broadcast an alle".
    public static let broadcast = PeerID(bytes: [UInt8](repeating: 0, count: byteCount))

    public var isBroadcast: Bool { bytes.allSatisfy { $0 == 0 } }

    /// Leitet die PeerID aus einem (Curve25519/Ed25519) Public Key ab.
    public static func derive(fromPublicKey publicKey: Data) -> PeerID {
        let digest = SHA256.hash(data: publicKey)
        return PeerID(bytes: Array(digest.prefix(byteCount)))
    }

    /// Hex-Repräsentation, z. B. "a1b2c3d4e5f60718".
    public var hex: String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    public var description: String { hex }

    public init?(hex: String) {
        guard hex.count == PeerID.byteCount * 2 else { return nil }
        var out = [UInt8]()
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let b = UInt8(hex[idx..<next], radix: 16) else { return nil }
            out.append(b)
            idx = next
        }
        self.init(bytes: out)
    }
}
