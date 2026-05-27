import Foundation

/// Serialisiert `Packet`-Werte zu Bytes und zurück.
///
/// Der Codec ist zustandslos und rein – das macht ihn trivial testbar
/// (siehe PacketCodecTests). Encoding und Decoding sind exakt invers
/// zueinander; ein Round-Trip muss bytegleich sein.
public enum PacketCodec {

    // MARK: - Encoding

    /// Kodiert Header + Payload (ohne Signatur). Diese Bytes sind die
    /// kanonische Grundlage für die Signatur.
    static func encodeHeaderAndPayload(_ p: Packet) -> Data {
        var w = ByteWriter()
        w.writeBytes(Packet.magic)
        w.writeU8(p.version)
        w.writeU8(p.type.rawValue)
        w.writeU8(p.flags.rawValue)
        w.writeU8(p.ttl)
        w.writeBytes(uuidBytes(p.messageID))
        w.writeBytes(p.senderID.bytes)
        w.writeBytes(p.recipientID.bytes)
        w.writeU16(p.sequence)
        precondition(p.payload.count <= Int(UInt16.max), "Payload zu groß für 16-Bit-Längenfeld")
        w.writeU16(UInt16(p.payload.count))
        w.writeData(p.payload)
        return w.data
    }

    /// Vollständige Serialisierung inklusive optionaler Signatur.
    public static func encode(_ p: Packet) -> Data {
        var data = encodeHeaderAndPayload(p)
        if p.flags.contains(.signed), let sig = p.signature {
            precondition(sig.count == Packet.signatureLength, "Signatur muss \(Packet.signatureLength) Bytes haben")
            data.append(sig)
        }
        return data
    }

    // MARK: - Decoding

    public static func decode(_ data: Data) throws -> Packet {
        var r = ByteReader(data)

        let magic = try r.readBytes(2)
        guard magic == Packet.magic else { throw WireError.badMagic }

        let version = try r.readU8()
        guard version == Packet.currentVersion else { throw WireError.unsupportedVersion(version) }

        let rawType = try r.readU8()
        guard let type = PacketType(rawValue: rawType) else { throw WireError.unknownType(rawType) }

        let flags = PacketFlags(rawValue: try r.readU8())
        let ttl = try r.readU8()
        let messageID = uuid(from: try r.readBytes(16))
        let senderID = PeerID(bytes: try r.readBytes(PeerID.byteCount))
        let recipientID = PeerID(bytes: try r.readBytes(PeerID.byteCount))
        let sequence = try r.readU16()
        let payloadLength = Int(try r.readU16())

        guard r.remaining >= payloadLength else { throw WireError.truncated }
        let payload = try r.readData(payloadLength)

        var signature: Data? = nil
        if flags.contains(.signed) {
            guard r.remaining >= Packet.signatureLength else { throw WireError.truncated }
            signature = try r.readData(Packet.signatureLength)
        }

        return Packet(
            version: version, type: type, flags: flags, ttl: ttl,
            messageID: messageID, senderID: senderID, recipientID: recipientID,
            sequence: sequence, payload: payload, signature: signature
        )
    }

    // MARK: - UUID <-> Bytes

    static func uuidBytes(_ uuid: UUID) -> [UInt8] {
        let u = uuid.uuid
        return [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7,
                u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15]
    }

    static func uuid(from bytes: [UInt8]) -> UUID {
        precondition(bytes.count == 16)
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
