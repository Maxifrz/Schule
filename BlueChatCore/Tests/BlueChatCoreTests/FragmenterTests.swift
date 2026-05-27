import XCTest
@testable import BlueChatCore

final class FragmenterTests: XCTestCase {

    func testFragmentAndReassemble() throws {
        let original = Data((0..<1000).map { UInt8($0 % 256) })
        let chunks = Fragmenter.fragment(original, mtu: 100)
        XCTAssertGreaterThan(chunks.count, 1)

        let reassembler = Reassembler()
        var result: Data?
        for raw in chunks {
            let chunk = try Fragmenter.parseChunk(raw)
            if let done = reassembler.ingest(chunk) { result = done }
        }
        XCTAssertEqual(result, original)
    }

    func testReassembleOutOfOrder() throws {
        let original = Data((0..<500).map { UInt8($0 % 256) })
        let chunks = Fragmenter.fragment(original, mtu: 64).shuffled()

        let reassembler = Reassembler()
        var result: Data?
        for raw in chunks {
            let chunk = try Fragmenter.parseChunk(raw)
            if let done = reassembler.ingest(chunk) { result = done }
        }
        XCTAssertEqual(result, original)
    }

    func testCorruptedChunkFailsCRC() throws {
        let chunks = Fragmenter.fragment(Data([1,2,3,4,5,6,7,8]), mtu: 64)
        var corrupted = chunks[0]
        corrupted[corrupted.count - 1] ^= 0xFF // letztes Payload-Byte kippen
        XCTAssertThrowsError(try Fragmenter.parseChunk(corrupted)) { error in
            XCTAssertEqual(error as? WireError, .crcMismatch)
        }
    }

    func testSinglePacketFitsOneChunk() throws {
        let small = Data([1,2,3])
        let chunks = Fragmenter.fragment(small, mtu: 200)
        XCTAssertEqual(chunks.count, 1)
        let chunk = try Fragmenter.parseChunk(chunks[0])
        XCTAssertEqual(chunk.total, 1)
        XCTAssertEqual(chunk.payload, small)
    }
}
