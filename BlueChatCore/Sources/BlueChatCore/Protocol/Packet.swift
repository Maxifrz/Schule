import Foundation

/// Ein logisches BlueChat-Protokollpaket.
///
/// Wire-Layout (alle Mehrbyte-Felder big-endian):
///
/// ```
///  Offset  Größe  Feld
///  ------  -----  --------------------------------------------------
///   0      2      Magic            = 0x42 0x43  ("BC")
///   2      1      Version          = aktuelle Protokollversion
///   3      1      Type             = PacketType
///   4      1      Flags            = PacketFlags (Bitmaske)
///   5      1      TTL              = verbleibende Hops (Mesh)
///   6      16     Message-ID       = UUID (eindeutig pro Originalnachricht)
///   22     8      Sender-ID        = PeerID des Urhebers
///   30     8      Recipient-ID     = PeerID des Ziels (0…0 = Broadcast)
///   38     2      Sequence         = laufende Nummer (Ordnung/Dedup)
///   40     2      Payload-Length   = Länge des Payloads in Bytes (N)
///   42     N      Payload          = (ggf. verschlüsselte) Nutzdaten
///   42+N   [64]   Signature        = Ed25519-Signatur, nur wenn .signed gesetzt
/// ```
///
/// Designentscheidung – warum ein eigenes Binärformat statt JSON/Protobuf?
/// 1. BLE-Bandbreite ist extrem knapp; jedes Byte zählt bei MTU ~185.
/// 2. Deterministisches Layout erleichtert das Signieren (kanonische Bytes).
/// 3. Keine externen Abhängigkeiten, volle Kontrolle über Versionierung.
public struct Packet: Equatable, Sendable {
    public static let magic: [UInt8] = [0x42, 0x43] // "BC"
    public static let currentVersion: UInt8 = 1
    public static let signatureLength = 64
    /// Größe des festen Headers (ohne Payload und Signatur).
    public static let headerSize = 42

    public var version: UInt8
    public var type: PacketType
    public var flags: PacketFlags
    public var ttl: UInt8
    public var messageID: UUID
    public var senderID: PeerID
    public var recipientID: PeerID
    public var sequence: UInt16
    public var payload: Data
    /// 64-Byte Ed25519-Signatur über Header+Payload, falls `flags` `.signed` enthält.
    public var signature: Data?

    public init(
        version: UInt8 = Packet.currentVersion,
        type: PacketType,
        flags: PacketFlags = [],
        ttl: UInt8,
        messageID: UUID = UUID(),
        senderID: PeerID,
        recipientID: PeerID,
        sequence: UInt16 = 0,
        payload: Data = Data(),
        signature: Data? = nil
    ) {
        self.version = version
        self.type = type
        self.flags = flags
        self.ttl = ttl
        self.messageID = messageID
        self.senderID = senderID
        self.recipientID = recipientID
        self.sequence = sequence
        self.payload = payload
        self.signature = signature
    }

    /// Bytes über die signiert wird: das komplette Paket OHNE die Signatur selbst.
    /// (Wird sowohl beim Signieren als auch beim Verifizieren identisch erzeugt.)
    public func signableBytes() -> Data {
        PacketCodec.encodeHeaderAndPayload(self)
    }
}
