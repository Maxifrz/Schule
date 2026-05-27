import Foundation
import CryptoKit
import SwiftData
import BlueChatCore

/// Verwaltet die Double-Ratchet-Sessions pro Peer und persistiert ihren
/// Zustand (verschlüsselt-at-rest) im SwiftData-Store.
///
/// Eine Session entsteht beim ersten KEY_EXCHANGE. Der Ratchet-Zustand wird
/// nach jeder ver-/entschlüsselten Nachricht gespeichert, damit nach einem
/// App-Neustart keine Schlüsselsynchronität verloren geht.
@MainActor
final class SessionManager {
    private let identity: CryptoService.IdentityKeyPair
    private let context: ModelContext
    private var ratchets: [PeerID: DoubleRatchet] = [:]

    init(identity: CryptoService.IdentityKeyPair, context: ModelContext) {
        self.identity = identity
        self.context = context
    }

    /// Stellt eine Session her bzw. lädt sie.
    ///
    /// Die Rolle wird DETERMINISTISCH aus dem Vergleich der PeerIDs bestimmt
    /// (kleinere ID = Initiator). So einigen sich beide Geräte unabhängig von
    /// der Nachrichtenreihenfolge auf dieselbe Sende-/Empfangs-Chain – auch
    /// wenn beide gleichzeitig die erste Nachricht senden.
    func establish(with peerID: PeerID, peerAgreementKey: Curve25519.KeyAgreement.PublicKey) throws -> DoubleRatchet {
        if let r = ratchets[peerID] { return r }
        if let restored = try loadState(peerID) {
            let r = DoubleRatchet(state: restored)
            ratchets[peerID] = r
            return r
        }
        // X3DH-vereinfacht: gemeinsames Root-Secret aus DH(eigener Agreement, fremder Agreement).
        // DH ist symmetrisch -> beide Seiten leiten denselben Root ab.
        let root = try CryptoService.deriveSharedKey(
            privateKey: identity.agreement,
            peerPublicKey: peerAgreementKey,
            info: Data("BlueChat-session".utf8)
        )
        let role: DoubleRatchet.Role = identity.peerID.hex < peerID.hex ? .initiator : .responder
        let ratchet = DoubleRatchet(rootKey: root, role: role)
        ratchets[peerID] = ratchet
        try saveState(peerID, ratchet: ratchet)
        return ratchet
    }

    func ratchet(for peerID: PeerID) -> DoubleRatchet? { ratchets[peerID] }

    func persist(_ peerID: PeerID) throws {
        guard let r = ratchets[peerID] else { return }
        try saveState(peerID, ratchet: r)
    }

    // MARK: - Persistenz

    private func loadState(_ peerID: PeerID) throws -> DoubleRatchet.State? {
        let hex = peerID.hex
        let descriptor = FetchDescriptor<SessionRecord>(predicate: #Predicate { $0.peerIDHex == hex })
        guard let record = try context.fetch(descriptor).first else { return nil }
        return try JSONDecoder().decode(DoubleRatchet.State.self, from: record.ratchetState)
    }

    private func saveState(_ peerID: PeerID, ratchet: DoubleRatchet) throws {
        let data = try JSONEncoder().encode(ratchet.snapshot)
        let hex = peerID.hex
        let descriptor = FetchDescriptor<SessionRecord>(predicate: #Predicate { $0.peerIDHex == hex })
        if let record = try context.fetch(descriptor).first {
            record.ratchetState = data
            record.updatedAt = Date()
        } else {
            context.insert(SessionRecord(peerIDHex: hex, ratchetState: data))
        }
        try context.save()
    }
}
