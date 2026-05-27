import Foundation

/// Reine Routing-Logik des Mesh-Netzwerks – ohne jede BLE-Abhängigkeit,
/// damit Routing-Entscheidungen deterministisch testbar sind.
///
/// Der Router entscheidet pro eingehendem Paket eine von drei Aktionen:
/// - `.deliverLocally`        – wir sind der Empfänger (oder Broadcast/Channel)
/// - `.forward(to:)`          – an konkrete Nachbarn weiterreichen (TTL-1)
/// - `.drop(reason:)`         – verwerfen (TTL 0, Duplikat, eigenes Paket …)
///
/// Mehrere Aktionen können gleichzeitig zutreffen: ein Broadcast wird sowohl
/// lokal zugestellt ALS AUCH weitergeflutet. Deshalb gibt `handle` ein Set
/// von Aktionen zurück.
public final class MeshRouter {

    public struct Neighbor: Hashable {
        public let peerID: PeerID
        public init(peerID: PeerID) { self.peerID = peerID }
    }

    public enum Action: Hashable {
        case deliverLocally
        case forward(to: Set<PeerID>)
        case drop(reason: DropReason)
    }

    public enum DropReason: Hashable {
        case ttlExpired
        case duplicate
        case ownPacket
        case noRoute
    }

    /// Maximale Hop-Anzahl. Default 7 (Anforderung). Begrenzt Reichweite und
    /// schützt – zusammen mit dem ID-Cache – vor endlosem Kreisen im Mesh.
    public let maxTTL: UInt8
    private let myID: PeerID
    private let seenCache: MessageIDCache
    private var routingTable: [PeerID: RouteEntry] = [:]
    /// Aktuell direkt verbundene Nachbarn (1 Hop).
    public private(set) var neighbors: Set<PeerID> = []

    struct RouteEntry {
        var nextHop: PeerID
        var hopCount: UInt8
        var lastUpdated: Date
    }

    public init(myID: PeerID, maxTTL: UInt8 = 7, cacheCapacity: Int = 2048) {
        self.myID = myID
        self.maxTTL = maxTTL
        self.seenCache = MessageIDCache(capacity: cacheCapacity)
    }

    // MARK: - Nachbarschaft / Routen lernen

    public func addNeighbor(_ id: PeerID) {
        neighbors.insert(id)
        // Direkter Nachbar = beste Route mit Hop-Count 1.
        routingTable[id] = RouteEntry(nextHop: id, hopCount: 1, lastUpdated: Date())
    }

    public func removeNeighbor(_ id: PeerID) {
        neighbors.remove(id)
        // Alle Routen entfernen, die über diesen Nachbarn liefen.
        routingTable = routingTable.filter { $0.value.nextHop != id }
    }

    /// Lernt aus einem weitergeleiteten Paket: Absender ist über den Nachbarn,
    /// von dem wir es bekamen, in (maxTTL - ttl + 1) Hops erreichbar.
    public func learnRoute(to destination: PeerID, via neighbor: PeerID, observedTTL: UInt8) {
        guard destination != myID, !destination.isBroadcast else { return }
        let hops = UInt8(clamping: Int(maxTTL) - Int(observedTTL) + 1)
        if let existing = routingTable[destination], existing.hopCount <= hops {
            routingTable[destination]?.lastUpdated = Date()
            return
        }
        routingTable[destination] = RouteEntry(nextHop: neighbor, hopCount: hops, lastUpdated: Date())
    }

    public func nextHop(to destination: PeerID) -> PeerID? {
        routingTable[destination]?.nextHop
    }

    // MARK: - Kernentscheidung

    /// Verarbeitet ein empfangenes Paket. `arrivedFrom` ist der direkte
    /// Nachbar, über den das Paket kam (für Split-Horizon: nicht dorthin zurück).
    public func handle(_ packet: Packet, arrivedFrom: PeerID?, now: Date = Date()) -> Set<Action> {
        var actions = Set<Action>()

        // Eigene Pakete, die zu uns zurückkommen, ignorieren.
        if packet.senderID == myID {
            return [.drop(reason: .ownPacket)]
        }

        // Duplikat? (Loop-Schutz). Nur einmal pro Message-ID handeln.
        if seenCache.contains(packet.messageID) {
            return [.drop(reason: .duplicate)]
        }
        seenCache.insert(packet.messageID, at: now)

        // Routenwissen aus diesem Paket ableiten.
        if let from = arrivedFrom {
            learnRoute(to: packet.senderID, via: from, observedTTL: packet.ttl)
        }

        let forBroadcastOrChannel = packet.recipientID.isBroadcast || packet.flags.contains(.channel)
        let forMe = packet.recipientID == myID

        if forMe || forBroadcastOrChannel {
            actions.insert(.deliverLocally)
        }
        // Unicast direkt an uns: nicht weiterleiten.
        if forMe && !forBroadcastOrChannel {
            return actions
        }

        // Weiterleitung prüfen.
        guard packet.ttl > 1 else {
            actions.insert(.drop(reason: .ttlExpired))
            return actions
        }

        let targets = forwardingTargets(for: packet, arrivedFrom: arrivedFrom)
        if targets.isEmpty {
            if !forBroadcastOrChannel { actions.insert(.drop(reason: .noRoute)) }
        } else {
            actions.insert(.forward(to: targets))
        }
        return actions
    }

    /// Wählt die Nachbarn, an die weitergeleitet wird.
    private func forwardingTargets(for packet: Packet, arrivedFrom: PeerID?) -> Set<PeerID> {
        var candidates = neighbors
        if let from = arrivedFrom { candidates.remove(from) } // Split-Horizon

        // Gerichtetes Routing, falls eine Route bekannt ist (effizienter als Flooding).
        if !packet.recipientID.isBroadcast, !packet.flags.contains(.channel),
           let hop = nextHop(to: packet.recipientID), candidates.contains(hop) {
            return [hop]
        }
        // Sonst Flood-Routing als Fallback an alle übrigen Nachbarn.
        return candidates
    }

    /// Bereitet ein Paket fürs Weiterleiten vor: TTL um 1 verringern.
    public func decrementedForForwarding(_ packet: Packet) -> Packet {
        var p = packet
        p.ttl = packet.ttl > 0 ? packet.ttl - 1 : 0
        return p
    }
}
