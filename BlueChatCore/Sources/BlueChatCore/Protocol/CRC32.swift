import Foundation

/// Standard CRC-32 (IEEE 802.3, Polynom 0xEDB88820), wie in zlib/PNG.
///
/// Wird in der Transport-Schicht (Fragmenter) pro Chunk und über die
/// reassemblierte Gesamtnachricht berechnet, um Bitfehler/fehlende
/// Fragmente zu erkennen, bevor das Paket geparst wird.
public enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB8_8820 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    public static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[idx] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}
