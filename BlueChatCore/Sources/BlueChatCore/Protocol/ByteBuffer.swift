import Foundation

/// Fehler beim Parsen eines Pakets aus rohen Bytes.
public enum WireError: Error, Equatable {
    case truncated            // Buffer endete unerwartet
    case badMagic             // Magic-Bytes stimmen nicht
    case unknownType(UInt8)   // Unbekannter PacketType
    case unsupportedVersion(UInt8)
    case payloadLengthMismatch
    case crcMismatch
}

/// Schreibt primitive Werte big-endian (Network Byte Order) in einen Puffer.
///
/// Designentscheidung: Big-Endian ("Network Byte Order") ist der Konvention
/// für Wire-Protokolle entsprechend und unabhängig von der CPU-Endianness
/// der beteiligten Geräte.
struct ByteWriter {
    private(set) var data = Data()

    mutating func writeU8(_ v: UInt8) { data.append(v) }

    mutating func writeU16(_ v: UInt16) {
        data.append(UInt8(truncatingIfNeeded: v >> 8))
        data.append(UInt8(truncatingIfNeeded: v))
    }

    mutating func writeU32(_ v: UInt32) {
        data.append(UInt8(truncatingIfNeeded: v >> 24))
        data.append(UInt8(truncatingIfNeeded: v >> 16))
        data.append(UInt8(truncatingIfNeeded: v >> 8))
        data.append(UInt8(truncatingIfNeeded: v))
    }

    mutating func writeBytes(_ b: [UInt8]) { data.append(contentsOf: b) }
    mutating func writeData(_ d: Data) { data.append(d) }
}

/// Liest primitive Werte big-endian aus einem Puffer und prüft dabei Grenzen.
struct ByteReader {
    private let data: Data
    private var offset: Int

    init(_ data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    var remaining: Int { data.endIndex - offset }

    mutating func readU8() throws -> UInt8 {
        guard remaining >= 1 else { throw WireError.truncated }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readU16() throws -> UInt16 {
        guard remaining >= 2 else { throw WireError.truncated }
        let hi = UInt16(data[offset]); let lo = UInt16(data[offset + 1])
        offset += 2
        return (hi << 8) | lo
    }

    mutating func readU32() throws -> UInt32 {
        guard remaining >= 4 else { throw WireError.truncated }
        var v: UInt32 = 0
        for i in 0..<4 { v = (v << 8) | UInt32(data[offset + i]) }
        offset += 4
        return v
    }

    mutating func readBytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, remaining >= count else { throw WireError.truncated }
        defer { offset += count }
        return Array(data[offset..<(offset + count)])
    }

    mutating func readData(_ count: Int) throws -> Data {
        guard count >= 0, remaining >= count else { throw WireError.truncated }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }

    mutating func readRemaining() -> Data {
        defer { offset = data.endIndex }
        return data.subdata(in: offset..<data.endIndex)
    }
}
