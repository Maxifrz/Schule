import Foundation

/// Transport-Schicht: zerlegt ein serialisiertes Paket in MTU-konforme
/// Chunks und setzt empfangene Chunks wieder zusammen.
///
/// Warum eine eigene Schicht? Eine GATT-Characteristic kann pro Write nur
/// `ATT_MTU - 3` Bytes übertragen (typisch 20 Bytes bei iOS-Default, bis
/// ~244–509 nach MTU-Verhandlung). Größere Pakete – z. B. KEY_EXCHANGE mit
/// Signatur oder Bilder – müssen aufgeteilt werden. Jeder Chunk trägt einen
/// kleinen Header für Reassemblierung und Fehlererkennung.
///
/// Chunk-Layout (big-endian):
/// ```
///  Offset  Größe  Feld
///   0      16     Transfer-ID (UUID)   – eindeutig pro großem Transfer
///   16     2      Index                – 0-basierte Fragmentnummer
///   18     2      Total                – Gesamtzahl der Fragmente
///   20     2      Chunk-Payload-Länge
///   22     4      CRC32(Chunk-Payload) – Integrität dieses Fragments
///   26     M      Chunk-Payload
/// ```
public enum Fragmenter {
    /// Größe des Chunk-Headers in Bytes.
    public static let chunkHeaderSize = 26

    /// Zerlegt `packetBytes` in Chunks, die jeweils höchstens `mtu` Bytes groß sind.
    /// - Parameter mtu: Nutzbare Payload-Größe pro GATT-Write (ATT_MTU - 3).
    public static func fragment(_ packetBytes: Data, mtu: Int, transferID: UUID = UUID()) -> [Data] {
        let usable = max(1, mtu - chunkHeaderSize)
        // Aufteilen in Stücke der Größe `usable`.
        var pieces: [Data] = []
        var idx = packetBytes.startIndex
        while idx < packetBytes.endIndex {
            let end = packetBytes.index(idx, offsetBy: usable, limitedBy: packetBytes.endIndex) ?? packetBytes.endIndex
            pieces.append(packetBytes.subdata(in: idx..<end))
            idx = end
        }
        if pieces.isEmpty { pieces = [Data()] } // leeres Paket -> ein leerer Chunk

        let total = UInt16(pieces.count)
        let idBytes = PacketCodec.uuidBytes(transferID)

        return pieces.enumerated().map { (i, piece) in
            var w = ByteWriter()
            w.writeBytes(idBytes)
            w.writeU16(UInt16(i))
            w.writeU16(total)
            w.writeU16(UInt16(piece.count))
            w.writeU32(CRC32.checksum(piece))
            w.writeData(piece)
            return w.data
        }
    }

    /// Geparster Chunk-Header + Nutzdaten.
    public struct Chunk: Equatable {
        public let transferID: UUID
        public let index: UInt16
        public let total: UInt16
        public let payload: Data
    }

    /// Parst einen einzelnen empfangenen Chunk und prüft dessen CRC.
    public static func parseChunk(_ data: Data) throws -> Chunk {
        var r = ByteReader(data)
        let id = PacketCodec.uuid(from: try r.readBytes(16))
        let index = try r.readU16()
        let total = try r.readU16()
        let len = Int(try r.readU16())
        let crc = try r.readU32()
        guard r.remaining >= len else { throw WireError.truncated }
        let payload = try r.readData(len)
        guard CRC32.checksum(payload) == crc else { throw WireError.crcMismatch }
        return Chunk(transferID: id, index: index, total: total, payload: payload)
    }
}

/// Sammelt Chunks eines Transfers, bis alle eingegangen sind, und gibt
/// dann das reassemblierte Paket zurück. Threadsicherheit wird vom Aufrufer
/// (BluetoothService, auf seiner seriellen Queue) sichergestellt.
public final class Reassembler {
    private struct Pending {
        var total: UInt16
        var fragments: [UInt16: Data]
        var firstSeen: Date
    }

    private var pending: [UUID: Pending] = [:]
    /// Transfers, die nach diesem Timeout unvollständig sind, werden verworfen.
    public let transferTimeout: TimeInterval

    public init(transferTimeout: TimeInterval = 30) {
        self.transferTimeout = transferTimeout
    }

    /// Fügt einen Chunk hinzu. Liefert die vollständigen Paket-Bytes zurück,
    /// sobald der Transfer komplett ist – sonst nil.
    public func ingest(_ chunk: Fragmenter.Chunk, now: Date = Date()) -> Data? {
        purgeExpired(now: now)

        var entry = pending[chunk.transferID] ?? Pending(total: chunk.total, fragments: [:], firstSeen: now)
        entry.fragments[chunk.index] = chunk.payload
        pending[chunk.transferID] = entry

        guard entry.fragments.count == Int(entry.total) else { return nil }

        // Alle Fragmente da -> in Reihenfolge zusammensetzen.
        var assembled = Data()
        for i in 0..<entry.total {
            guard let part = entry.fragments[i] else { return nil } // Lücke -> warten
            assembled.append(part)
        }
        pending.removeValue(forKey: chunk.transferID)
        return assembled
    }

    private func purgeExpired(now: Date) {
        pending = pending.filter { now.timeIntervalSince($0.value.firstSeen) < transferTimeout }
    }
}
