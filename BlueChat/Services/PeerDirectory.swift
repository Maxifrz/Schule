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
        /// Zuletzt gemessene Signalstärke (RSSI), für die UI.
        var rssi: Int? = nil
    }

    private var byPeerID: [PeerID: Entry] = [:]
    private var peerIDByPeripheral: [UUID: PeerID] = [:]

    func upsert(_ entry: Entry) {
        var merged = entry
        // Bereits bekannte, flüchtige Werte (RSSI, peripheralID) nicht durch ein
        // HELLO ohne diese Angaben überschreiben.
        if let existing = byPeerID[entry.peerID] {
            if merged.rssi == nil { merged.rssi = existing.rssi }
            if merged.peripheralID == nil { merged.peripheralID = existing.peripheralID }
        }
        byPeerID[entry.peerID] = merged
        if let pid = merged.peripheralID { peerIDByPeripheral[pid] = entry.peerID }
    }

    /// Aktualisiert die Signalstärke anhand der flüchtigen Peripheral-ID.
    /// Liefert die zugehörige PeerID zurück, falls bereits gebunden.
    @discardableResult
    func setRSSI(_ rssi: Int, forPeripheral peripheralID: UUID) -> PeerID? {
        guard let peerID = peerIDByPeripheral[peripheralID] else { return nil }
        byPeerID[peerID]?.rssi = rssi
        return peerID
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
