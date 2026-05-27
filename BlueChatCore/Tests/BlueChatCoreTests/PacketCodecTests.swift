import XCTest
@testable import BlueChatCore

final class PacketCodecTests: XCTestCase {

    private func sampleSender() -> PeerID { PeerID(bytes: [1,2,3,4,5,6,7,8]) }
    private func sampleRecipient() -> PeerID { PeerID(bytes: [9,10,11,12,13,14,15,16]) }

    func testRoundTripPreservesAllFields() throws {
        let id = UUID()
        let packet = Packet(
            type: .message,
            flags: [.encrypted, .requiresAck],
            ttl: 7,
            messageID: id,
            senderID: sampleSender(),
            recipientID: sampleRecipient(),
            sequence: 42,
            payload: Data([0xDE, 0xAD, 0xBE, 0xEF])
        )
        let encoded = PacketCodec.encode(packet)
        let decoded = try PacketCodec.decode(encoded)

        XCTAssertEqual(decoded.type, .message)
        XCTAssertEqual(decoded.flags.rawValue, packet.flags.rawValue)
        XCTAssertEqual(decoded.ttl, 7)
        XCTAssertEqual(decoded.messageID, id)
        XCTAssertEqual(decoded.senderID, sampleSender())
        XCTAssertEqual(decoded.recipientID, sampleRecipient())
        XCTAssertEqual(decoded.sequence, 42)
        XCTAssertEqual(decoded.payload, Data([0xDE, 0xAD, 0xBE, 0xEF]))
        XCTAssertNil(decoded.signature)
    }

    func testHeaderSizeIsStable() throws {
        let packet = Packet(type: .heartbeat, ttl: 1, senderID: sampleSender(), recipientID: .broadcast)
        let encoded = PacketCodec.encode(packet)
        XCTAssertEqual(encoded.count, Packet.headerSize) // leerer Payload, unsigniert
    }

    func testBroadcastRecipient() throws {
        let packet = Packet(type: .hello, ttl: 1, senderID: sampleSender(), recipientID: .broadcast)
        let decoded = try PacketCodec.decode(PacketCodec.encode(packet))
        XCTAssertTrue(decoded.recipientID.isBroadcast)
    }

    func testRejectsBadMagic() {
        var bytes = PacketCodec.encode(Packet(type: .ack, ttl: 1, senderID: sampleSender(), recipientID: .broadcast))
        bytes[0] = 0x00
        XCTAssertThrowsError(try PacketCodec.decode(bytes)) { error in
            XCTAssertEqual(error as? WireError, .badMagic)
        }
    }

    func testRejectsTruncatedPayload() {
        var bytes = PacketCodec.encode(Packet(type: .message, ttl: 1, senderID: sampleSender(), recipientID: .broadcast, payload: Data([1,2,3,4,5])))
        bytes.removeLast(2) // Payload abschneiden
        XCTAssertThrowsError(try PacketCodec.decode(bytes)) { error in
            XCTAssertEqual(error as? WireError, .truncated)
        }
    }

    func testRejectsUnknownType() {
        var bytes = PacketCodec.encode(Packet(type: .hello, ttl: 1, senderID: sampleSender(), recipientID: .broadcast))
        bytes[3] = 0xFF // Type-Byte
        XCTAssertThrowsError(try PacketCodec.decode(bytes)) { error in
            XCTAssertEqual(error as? WireError, .unknownType(0xFF))
        }
    }

    func testPeerIDHexRoundTrip() {
        let id = sampleSender()
        XCTAssertEqual(PeerID(hex: id.hex), id)
    }
}
