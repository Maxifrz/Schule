import Foundation
import SwiftData

// MARK: - SwiftData-Datenmodelle
//
// Designentscheidung: SwiftData (iOS 17+ API, App-Target iOS 16 fällt für
// diese Modelle auf eine Mindestlaufzeit von 17 zurück – siehe README zur
// Versionsstrategie) hält den lokalen Zustand: Identität, Kontakte (Peers),
// Sessions, Chats und Nachrichten. ALLE Klartextinhalte liegen ausschließlich
// lokal und verschlüsselt-at-rest (Dateisystem-Schutzklasse complete). Es gibt
// keinen Server, keine Cloud-Sync – Datenminimierung als Architekturprinzip
// (DSGVO, siehe README).

/// Lokale Geräte-Identität. Nur die Public Keys werden hier gehalten – die
/// privaten Schlüssel liegen in der Keychain (siehe KeychainStore), niemals
/// im SwiftData-Store.
@Model
final class IdentityRecord {
    /// 8-Byte PeerID als Hex (Primärschlüssel-Charakter).
    @Attribute(.unique) var peerIDHex: String
    var displayName: String
    var signingPublicKey: Data
    var agreementPublicKey: Data
    var createdAt: Date

    init(peerIDHex: String, displayName: String, signingPublicKey: Data, agreementPublicKey: Data, createdAt: Date = Date()) {
        self.peerIDHex = peerIDHex
        self.displayName = displayName
        self.signingPublicKey = signingPublicKey
        self.agreementPublicKey = agreementPublicKey
        self.createdAt = createdAt
    }
}

/// Ein bekannter anderer Teilnehmer (Kontakt).
@Model
final class PeerRecord {
    @Attribute(.unique) var peerIDHex: String
    var displayName: String
    var signingPublicKey: Data
    var agreementPublicKey: Data
    /// Vom Nutzer per Fingerprint-Abgleich bestätigt? (Schutz vor MITM)
    var isVerified: Bool
    var lastSeen: Date?
    /// Letzte bekannte Signalstärke (für UI; nicht persistenzkritisch).
    var lastRSSI: Int?
    /// Hop-Distanz aus der Routing-Tabelle (1 = direkter Nachbar).
    var hopCount: Int

    init(peerIDHex: String, displayName: String, signingPublicKey: Data, agreementPublicKey: Data,
         isVerified: Bool = false, lastSeen: Date? = nil, lastRSSI: Int? = nil, hopCount: Int = 0) {
        self.peerIDHex = peerIDHex
        self.displayName = displayName
        self.signingPublicKey = signingPublicKey
        self.agreementPublicKey = agreementPublicKey
        self.isVerified = isVerified
        self.lastSeen = lastSeen
        self.lastRSSI = lastRSSI
        self.hopCount = hopCount
    }
}

/// Persistierter Double-Ratchet-Zustand pro Konversationspartner.
/// Der serialisierte Zustand enthält Schlüsselmaterial -> wird verschlüsselt
/// gehalten (Datei-Schutzklasse) und beim Panik-Modus mitgelöscht.
@Model
final class SessionRecord {
    @Attribute(.unique) var peerIDHex: String
    /// JSON-kodierter DoubleRatchet.State.
    var ratchetState: Data
    var establishedAt: Date
    var updatedAt: Date

    init(peerIDHex: String, ratchetState: Data, establishedAt: Date = Date(), updatedAt: Date = Date()) {
        self.peerIDHex = peerIDHex
        self.ratchetState = ratchetState
        self.establishedAt = establishedAt
        self.updatedAt = updatedAt
    }
}

enum ChatKind: Int, Codable {
    case direct = 0      // 1:1
    case group = 1       // Gruppe (alle in Mesh-Reichweite)
    case channel = 2     // anonymer Broadcast-Channel mit gemeinsamem Schlüssel
}

@Model
final class ChatRecord {
    @Attribute(.unique) var id: UUID
    var kind: ChatKind
    var title: String
    /// Bei .direct: PeerID-Hex der Gegenseite. Bei .channel: Channel-Name.
    var counterpartKey: String
    var createdAt: Date
    var lastActivity: Date
    @Relationship(deleteRule: .cascade, inverse: \MessageRecord.chat)
    var messages: [MessageRecord]

    init(id: UUID = UUID(), kind: ChatKind, title: String, counterpartKey: String,
         createdAt: Date = Date(), lastActivity: Date = Date(), messages: [MessageRecord] = []) {
        self.id = id
        self.kind = kind
        self.title = title
        self.counterpartKey = counterpartKey
        self.createdAt = createdAt
        self.lastActivity = lastActivity
        self.messages = messages
    }
}

enum MessageDirection: Int, Codable { case incoming = 0, outgoing = 1 }

enum DeliveryState: Int, Codable {
    case queued = 0      // wartet (Store-and-Forward, Empfänger offline)
    case sent = 1        // ins Funknetz gegeben
    case delivered = 2   // ACK(delivered) erhalten
    case read = 3        // ACK(read) erhalten
    case failed = 4
}

@Model
final class MessageRecord {
    @Attribute(.unique) var id: UUID
    var chat: ChatRecord?
    var direction: MessageDirection
    var senderIDHex: String
    var text: String?
    /// Optionales kleines Bild (komprimiert, <= 50 KB).
    @Attribute(.externalStorage) var imageData: Data?
    var sentAt: Date
    var receivedAt: Date?
    var deliveryStateRaw: Int
    /// Zeitpunkt der automatischen Löschung (selbstlöschende Nachricht), falls gesetzt.
    var expiresAt: Date?

    var deliveryState: DeliveryState {
        get { DeliveryState(rawValue: deliveryStateRaw) ?? .queued }
        set { deliveryStateRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), direction: MessageDirection, senderIDHex: String,
         text: String? = nil, imageData: Data? = nil, sentAt: Date = Date(),
         receivedAt: Date? = nil, deliveryState: DeliveryState = .queued, expiresAt: Date? = nil) {
        self.id = id
        self.direction = direction
        self.senderIDHex = senderIDHex
        self.text = text
        self.imageData = imageData
        self.sentAt = sentAt
        self.receivedAt = receivedAt
        self.deliveryStateRaw = deliveryState.rawValue
        self.expiresAt = expiresAt
    }
}
