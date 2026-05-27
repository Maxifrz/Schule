import Foundation

/// Typisierte Payload-Strukturen der Steuerpakete.
///
/// Designentscheidung: Steuer-Payloads (HELLO, KEY_EXCHANGE, ACK) sind selten
/// und klein – hier ist Codable/JSON ein vertretbarer Kompromiss zwischen
/// Lesbarkeit und Effizienz. Der häufige, große MESSAGE-Payload hingegen ist
/// ein reiner AES-GCM-Ciphertext (Binär, kein JSON-Overhead).

public struct HelloPayload: Codable, Equatable, Sendable {
    public var displayName: String
    /// Langlebiger Ed25519-Identity-Public-Key (raw, base64 in JSON).
    public var identitySigningKey: Data
    /// Langlebiger X25519-Agreement-Public-Key (raw).
    public var identityAgreementKey: Data
    public var protocolVersion: UInt8

    public init(displayName: String, identitySigningKey: Data, identityAgreementKey: Data, protocolVersion: UInt8 = Packet.currentVersion) {
        self.displayName = displayName
        self.identitySigningKey = identitySigningKey
        self.identityAgreementKey = identityAgreementKey
        self.protocolVersion = protocolVersion
    }
}

public struct KeyExchangePayload: Codable, Equatable, Sendable {
    /// Ephemerer X25519-Public-Key des Senders für diese Session.
    public var ephemeralKey: Data
    /// Der eigene Identity-Agreement-Key (für X3DH-artige Bindung).
    public var identityAgreementKey: Data

    public init(ephemeralKey: Data, identityAgreementKey: Data) {
        self.ephemeralKey = ephemeralKey
        self.identityAgreementKey = identityAgreementKey
    }
}

public struct AckPayload: Codable, Equatable, Sendable {
    public enum Kind: UInt8, Codable, Sendable { case delivered = 1, read = 2 }
    public var messageID: UUID
    public var kind: Kind
    public init(messageID: UUID, kind: Kind) { self.messageID = messageID; self.kind = kind }
}

/// Klartext-Inhalt einer Chat-Nachricht VOR der Verschlüsselung.
/// Wird serialisiert, dann per AES-GCM/Double-Ratchet zum MESSAGE-Payload.
public struct ChatContent: Codable, Equatable, Sendable {
    public enum Body: Codable, Equatable, Sendable {
        case text(String)
        case image(Data)   // bereits komprimiert, <= 50 KB
    }
    public var body: Body
    public var sentAt: Date
    /// Optionale Verfallszeit (Sekunden ab Empfang) für selbstlöschende Nachrichten.
    public var expiresAfter: TimeInterval?
    /// Channel-Name, falls Broadcast-Channel.
    public var channel: String?

    public init(body: Body, sentAt: Date = Date(), expiresAfter: TimeInterval? = nil, channel: String? = nil) {
        self.body = body
        self.sentAt = sentAt
        self.expiresAfter = expiresAfter
        self.channel = channel
    }
}

/// Kleiner Wrapper für JSON-(De)Serialisierung der Payloads.
public enum PayloadCodec {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    public static func encode<T: Encodable>(_ value: T) throws -> Data { try encoder.encode(value) }
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T { try decoder.decode(type, from: data) }
}
