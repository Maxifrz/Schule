import Foundation

/// LRU-artiger Cache bereits gesehener Message-IDs zum Schutz vor
/// Routing-Loops und doppelter Zustellung im Flood-Routing.
///
/// Designentscheidung: Kapazitätsbegrenzung + Zeitfenster. Ältere Einträge
/// fallen heraus, sobald die Kapazität überschritten wird – so bleibt der
/// Speicherbedarf auch bei hohem Durchsatz konstant.
public final class MessageIDCache {
    private let capacity: Int
    private var order: [UUID] = []          // Einfügereihenfolge (FIFO-Verdrängung)
    private var timestamps: [UUID: Date] = [:]

    public init(capacity: Int = 2048) {
        self.capacity = max(1, capacity)
    }

    public func contains(_ id: UUID) -> Bool { timestamps[id] != nil }

    public func insert(_ id: UUID, at date: Date = Date()) {
        if timestamps[id] != nil {
            timestamps[id] = date
            return
        }
        timestamps[id] = date
        order.append(id)
        if order.count > capacity {
            let evicted = order.removeFirst()
            timestamps.removeValue(forKey: evicted)
        }
    }

    public var count: Int { order.count }
}
