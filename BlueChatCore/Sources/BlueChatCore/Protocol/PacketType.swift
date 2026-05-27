import Foundation

/// Die sechs Pakettypen des BlueChat-Wire-Protokolls.
///
/// Bewusst als 1-Byte-Enum (RawValue UInt8) modelliert, damit der Header
/// kompakt bleibt. Werte sind explizit fixiert – sie sind Teil des
/// Wire-Formats und dürfen zwischen Versionen NICHT verschoben werden.
public enum PacketType: UInt8, Codable, Sendable, CaseIterable {
    /// Peer-Announcement: "Ich bin hier", enthält PeerID + Display-Name + Identity-PubKey-Fingerprint.
    case hello = 1
    /// Diffie-Hellman-Schlüsselaustausch (ephemere + langlebige Public Keys).
    case keyExchange = 2
    /// Verschlüsselte Nutzdaten (Chat-Nachricht). Payload ist AES-GCM-Ciphertext.
    case message = 3
    /// Bestätigung (delivery / read). Payload referenziert die bestätigte Message-ID.
    case ack = 4
    /// Mesh-Weiterleitung: kapselt ein anderes Paket für Multi-Hop-Forwarding.
    case relay = 5
    /// Lebenszeichen / Keep-Alive zur Aufrechterhaltung der Routing-Tabelle.
    case heartbeat = 6
}

/// Bitflags im Header-Flags-Byte. Mehrere können kombiniert werden.
public struct PacketFlags: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    /// Payload ist Ende-zu-Ende-verschlüsselt (AES-GCM).
    public static let encrypted = PacketFlags(rawValue: 1 << 0)
    /// Header+Payload sind mit dem Identity-Key des Senders signiert (64-Byte Ed25519 angehängt).
    public static let signed = PacketFlags(rawValue: 1 << 1)
    /// Empfänger soll ein ACK senden (zuverlässige Zustellung).
    public static let requiresAck = PacketFlags(rawValue: 1 << 2)
    /// Nachricht ist selbstlöschend (Verfallszeit im Payload kodiert).
    public static let ephemeral = PacketFlags(rawValue: 1 << 3)
    /// Paket ist für einen Broadcast-Channel ("Raum") bestimmt.
    public static let channel = PacketFlags(rawValue: 1 << 4)
}
