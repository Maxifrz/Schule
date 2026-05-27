import Foundation
import CryptoKit
import BlueChatCore

/// Hält die flüchtige Zuordnung zwischen logischer `PeerID`, dem
/// BLE-`peripheralID` (UUID des CoreBluetooth-Objekts) und den bekannten
/// Public Keys eines Peers.
///
/// Warum getrennt vom persistenten `PeerRecord`? Die peripheralID ist eine
/// laufzeit-/gerätespezifische CoreBluetooth-UUID, die sich z. B. nach
/// Neustart ändern kann und nicht persistiert werden sollte. Die PeerID
/// (aus dem Public Key abgeleitet) ist dagegen stabil.
@MainActor
final class PeerDirectory {
    struct Entry {
        var peerID: PeerID
        var peripheralID: UUID?
        var signingKey: Curve25519.Signing.PublicKey
        var agreementKey: Curve25519.KeyAgreement.PublicKey
        var displayName: String
    }

    private var byPeerID: [PeerID: Entry] = [:]
    private var peerIDByPeripheral: [UUID: PeerID] = [:]

    func upsert(_ entry: Entry) {
        byPeerID[entry.peerID] = entry
        if let pid = entry.peripheralID { peerIDByPeripheral[pid] = entry.peerID }
    }

    func bind(peerID: PeerID, toPeripheral peripheralID: UUID) {
        peerIDByPeripheral[peripheralID] = peerID
        byPeerID[peerID]?.peripheralID = peripheralID
    }

    func entry(for peerID: PeerID) -> Entry? { byPeerID[peerID] }
    func peerID(forPeripheral peripheralID: UUID) -> PeerID? { peerIDByPeripheral[peripheralID] }
    func peripheralID(for peerID: PeerID) -> UUID? { byPeerID[peerID]?.peripheralID }
    var allEntries: [Entry] { Array(byPeerID.values) }
}
