import Foundation
import CryptoKit

/// Baut, signiert und verifiziert Pakete – die Brücke zwischen reinem
/// Protokoll (`Packet`) und Kryptographie (`CryptoService`).
///
/// Signatur-Designentscheidung: Signiert werden die kanonischen Header+Payload-
/// Bytes (siehe `Packet.signableBytes()`). Da TTL Teil des Headers ist und sich
/// beim Forwarding ändert, gilt: Zwischenknoten dürfen das Paket NICHT neu
/// signieren – die Signatur authentifiziert ausschließlich den Urheber. Beim
/// Verifizieren wird TTL daher aus den signierten Bytes herausgerechnet
/// (auf den Originalwert normalisiert ist nicht möglich, deshalb signieren wir
/// über alle Felder AUSSER TTL – siehe `canonicalForSigning`).
public struct PacketFactory {
    public let identity: CryptoService.IdentityKeyPair

    public init(identity: CryptoService.IdentityKeyPair) {
        self.identity = identity
    }

    /// Kanonische Signatur-Bytes: Header+Payload, aber mit TTL auf 0 genullt,
    /// damit das Verändern der TTL beim Hop die Signatur nicht bricht.
    static func canonicalForSigning(_ packet: Packet) -> Data {
        var p = packet
        p.ttl = 0
        p.signature = nil
        return p.signableBytes()
    }

    /// Signiert ein Paket mit dem Identity-Key und setzt das `.signed`-Flag.
    public func signed(_ packet: Packet) throws -> Packet {
        var p = packet
        p.flags.insert(.signed)
        let sig = try CryptoService.sign(Self.canonicalForSigning(p), with: identity.signing)
        p.signature = sig
        return p
    }

    /// Verifiziert die Signatur gegen den bekannten Signing-Public-Key des Senders.
    public static func verify(_ packet: Packet, senderSigningKey: Curve25519.Signing.PublicKey) -> Bool {
        guard packet.flags.contains(.signed), let sig = packet.signature else { return false }
        return CryptoService.verify(sig, of: canonicalForSigning(packet), publicKey: senderSigningKey)
    }

    // MARK: - Convenience-Builder

    public func makeHello(displayName: String, ttl: UInt8 = 1) throws -> Packet {
        let payload = HelloPayload(
            displayName: displayName,
            identitySigningKey: identity.signing.publicKey.rawRepresentation,
            identityAgreementKey: identity.agreement.publicKey.rawRepresentation
        )
        let packet = Packet(
            type: .hello, flags: [], ttl: ttl,
            senderID: identity.peerID, recipientID: .broadcast,
            payload: try PayloadCodec.encode(payload)
        )
        return try signed(packet)
    }

    public func makeKeyExchange(to recipient: PeerID, ephemeral: Curve25519.KeyAgreement.PrivateKey, ttl: UInt8 = 7) throws -> Packet {
        let payload = KeyExchangePayload(
            ephemeralKey: ephemeral.publicKey.rawRepresentation,
            identityAgreementKey: identity.agreement.publicKey.rawRepresentation
        )
        let packet = Packet(
            type: .keyExchange, flags: [], ttl: ttl,
            senderID: identity.peerID, recipientID: recipient,
            payload: try PayloadCodec.encode(payload)
        )
        return try signed(packet)
    }

    public func makeAck(to recipient: PeerID, messageID: UUID, kind: AckPayload.Kind, ttl: UInt8 = 7) throws -> Packet {
        let payload = AckPayload(messageID: messageID, kind: kind)
        let packet = Packet(
            type: .ack, flags: [], ttl: ttl,
            senderID: identity.peerID, recipientID: recipient,
            payload: try PayloadCodec.encode(payload)
        )
        return try signed(packet)
    }

    /// Baut ein verschlüsseltes MESSAGE-Paket. Der `ciphertext` stammt aus
    /// dem Double-Ratchet/AES-GCM; hier wird er nur in ein signiertes Paket gehüllt.
    public func makeMessage(to recipient: PeerID, ciphertext: Data, messageID: UUID = UUID(), ttl: UInt8 = 7, ephemeral: Bool = false, channel: Bool = false, requiresAck: Bool = true) throws -> Packet {
        var flags: PacketFlags = [.encrypted]
        if requiresAck { flags.insert(.requiresAck) }
        if ephemeral { flags.insert(.ephemeral) }
        if channel { flags.insert(.channel) }
        let packet = Packet(
            type: .message, flags: flags, ttl: ttl,
            messageID: messageID,
            senderID: identity.peerID, recipientID: recipient,
            payload: ciphertext
        )
        return try signed(packet)
    }
}
