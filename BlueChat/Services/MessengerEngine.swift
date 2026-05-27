import Foundation
import Combine
import CryptoKit
import SwiftData
import BlueChatCore

/// Das „Gehirn" der App: verbindet Transport (BluetoothService), Routing
/// (MeshRouter), Kryptographie (CryptoService/Double-Ratchet) und Persistenz
/// (MessageStore). Veröffentlicht beobachtbaren Zustand für die ViewModels.
///
/// Verarbeitungspfad eingehend:
///   Bytes → Reassembly (Bluetooth) → decode → Signatur prüfen → MeshRouter →
///   { lokal zustellen: entschlüsseln + speichern + ACK }  und/oder  { forward }
///
/// Verarbeitungspfad ausgehend:
///   Klartext → ChatContent → Double-Ratchet (AES-GCM) → signiertes MESSAGE →
///   Routing-Ziel bestimmen → fragmentieren + senden → Zustand „sent".
@MainActor
final class MessengerEngine: ObservableObject {

    // MARK: - Beobachtbarer Zustand
    @Published private(set) var nearbyPeers: [PeerViewState] = []
    @Published private(set) var bluetoothReady = false

    struct PeerViewState: Identifiable {
        let id: PeerID
        var displayName: String
        var rssi: Int?
        var hopCount: Int
        var isVerified: Bool
        var isConnected: Bool
    }

    // MARK: - Abhängigkeiten
    let identity: CryptoService.IdentityKeyPair
    private let factory: PacketFactory
    private let router: MeshRouter
    private let bluetooth: BluetoothService
    private let store: MessageStore
    private let sessions: SessionManager
    private let directory = PeerDirectory()
    private var cancellables = Set<AnyCancellable>()
    private var heartbeatTimer: AnyCancellable?
    private var isStarted = false

    var displayName: String

    init(identity: CryptoService.IdentityKeyPair, displayName: String, store: MessageStore,
         bluetooth: BluetoothService = BluetoothService()) {
        self.identity = identity
        self.displayName = displayName
        self.factory = PacketFactory(identity: identity)
        self.router = MeshRouter(myID: identity.peerID, maxTTL: 7)
        self.bluetooth = bluetooth
        self.store = store
        self.sessions = SessionManager(identity: identity, context: store.context)
    }

    // MARK: - Start

    func start() {
        guard !isStarted else { return } // Mehrfaches Starten vermeiden (z. B. nach Re-Onboarding).
        isStarted = true
        wireBluetooth()
        bluetooth.start()
        NotificationService.requestAuthorization()
        try? store.purgeExpired()
        // Periodisch HELLO/HEARTBEAT senden, damit Nachbarn uns kennen, und
        // abgelaufene (selbstlöschende) Nachrichten entfernen.
        heartbeatTimer = Timer.publish(every: BLE.heartbeatInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.announce()
                    try? self?.store.purgeExpired()
                }
            }
    }

    // MARK: - Verifizierung (Schutz vor MITM)

    /// Roh-Bytes des langlebigen Signing-Public-Keys eines bekannten Peers
    /// (für die Fingerprint-Berechnung in der VerificationView).
    func signingKeyData(for peerID: PeerID) -> Data? {
        directory.entry(for: peerID)?.signingKey.rawRepresentation
    }

    func isVerified(_ peerID: PeerID) -> Bool {
        store.isVerified(peerIDHex: peerID.hex)
    }

    func setVerified(_ peerID: PeerID, _ verified: Bool) {
        try? store.setVerified(peerIDHex: peerID.hex, verified)
        refreshPeerList()
    }

    // Hinweis: Die Subjects feuern auf der BLE-Queue. Da MessengerEngine
    // @MainActor-isoliert ist, hüllen wir die Handler in `Task { @MainActor }`,
    // damit der Zugriff thread-/aktorsicher erfolgt (kompatibel ab iOS 16).
    private func wireBluetooth() {
        bluetooth.bluetoothState
            .sink { [weak self] state in
                Task { @MainActor in
                    self?.bluetoothReady = (state == .poweredOn)
                    if state == .poweredOn { self?.announce() }
                }
            }
            .store(in: &cancellables)

        bluetooth.inboundPackets
            .sink { [weak self] payload in
                Task { @MainActor in self?.handleInbound(payload.data, fromPeripheral: payload.fromPeripheral) }
            }
            .store(in: &cancellables)

        bluetooth.discoveredPeers
            .sink { [weak self] peer in
                Task { @MainActor in self?.updateRSSI(peripheralID: peer.peripheralID, rssi: peer.rssi) }
            }
            .store(in: &cancellables)

        bluetooth.connectionChanged
            .sink { [weak self] change in
                Task { @MainActor in self?.handleConnection(change.peripheralID, connected: change.connected) }
            }
            .store(in: &cancellables)
    }

    // MARK: - Announcements

    private func announce() {
        guard let hello = try? factory.makeHello(displayName: displayName, ttl: 1) else { return }
        bluetooth.send(PacketCodec.encode(hello), toPeripheral: nil) // Broadcast an alle Verbundenen
    }

    // MARK: - Senden einer Chat-Nachricht (1:1)

    func sendText(_ text: String, to peerID: PeerID, expiresAfter: TimeInterval? = nil) {
        let messageID = UUID()
        let title = directory.entry(for: peerID)?.displayName ?? peerID.hex
        let expiresAt = expiresAfter.map { Date().addingTimeInterval($0) }

        // Zuerst lokal als „queued" persistieren – so überlebt die Nachricht
        // auch, wenn der Empfänger gerade (noch) nicht erreichbar ist. Sie wird
        // bei der nächsten Entdeckung (HELLO) automatisch erneut gesendet.
        if let chat = try? store.chat(forDirect: peerID.hex, title: title) {
            let record = MessageRecord(id: messageID, direction: .outgoing, senderIDHex: identity.peerID.hex,
                                       text: text, deliveryState: .queued, expiresAt: expiresAt)
            try? store.append(record, to: chat)
        }
        transmit(messageID: messageID, text: text, to: peerID, expiresAfter: expiresAfter)
    }

    /// Verschlüsselt und sendet eine bereits persistierte Nachricht. Ist der
    /// Peer noch unbekannt, bleibt sie „queued" (Store-and-Forward).
    private func transmit(messageID: UUID, text: String, to peerID: PeerID, expiresAfter: TimeInterval?) {
        guard let entry = directory.entry(for: peerID) else { return }
        do {
            let content = ChatContent(body: .text(text), expiresAfter: expiresAfter)
            let plaintext = try PayloadCodec.encode(content)

            let ratchet = try sessions.establish(with: peerID, peerAgreementKey: entry.agreementKey)
            let ratchetMsg = try ratchet.encrypt(plaintext)
            try sessions.persist(peerID)

            // Ratchet-Metadaten (Counter) dem Ciphertext voranstellen.
            let wireCiphertext = encodeRatchetMessage(ratchetMsg)
            let packet = try factory.makeMessage(to: peerID, ciphertext: wireCiphertext, messageID: messageID, ttl: router.maxTTL, ephemeral: expiresAfter != nil, requiresAck: true)

            route(packet, preferredRecipient: peerID)
            try store.updateDeliveryState(messageID: messageID, to: .sent)
        } catch {
            // Bei Fehler bleibt die Nachricht „queued" und wird später erneut versucht.
        }
    }

    // MARK: - Routing/Senden eines fertigen Pakets

    private func route(_ packet: Packet, preferredRecipient: PeerID?) {
        let bytes = PacketCodec.encode(packet)
        if let target = preferredRecipient,
           let hop = router.nextHop(to: target),
           let pid = directory.peripheralID(for: hop) {
            bluetooth.send(bytes, toPeripheral: pid)
        } else {
            // Keine bekannte Route → Flooding an alle Verbundenen.
            bluetooth.send(bytes, toPeripheral: nil)
        }
    }

    // MARK: - Eingang

    private func handleInbound(_ data: Data, fromPeripheral peripheralID: UUID?) {
        guard let packet = try? PacketCodec.decode(data) else { return }
        let arrivedFrom = peripheralID.flatMap { directory.peerID(forPeripheral: $0) }

        // Signatur prüfen, falls Sender bekannt (HELLO etabliert den Key).
        if let entry = directory.entry(for: packet.senderID), packet.flags.contains(.signed) {
            guard PacketFactory.verify(packet, senderSigningKey: entry.signingKey) else { return }
        }

        let actions = router.handle(packet, arrivedFrom: arrivedFrom)
        for action in actions {
            switch action {
            case .deliverLocally:
                deliver(packet, viaPeripheral: peripheralID)
            case .forward(let targets):
                forward(packet, to: targets)
            case .drop:
                break
            }
        }
    }

    private func deliver(_ packet: Packet, viaPeripheral peripheralID: UUID?) {
        switch packet.type {
        case .hello:       handleHello(packet, peripheralID: peripheralID)
        case .keyExchange: handleKeyExchange(packet)
        case .message:     handleMessage(packet)
        case .ack:         handleAck(packet)
        case .heartbeat:   break // Routing-Tabelle wurde bereits in handle() aktualisiert
        case .relay:       break // Relay wird über forward() abgewickelt
        }
    }

    private func forward(_ packet: Packet, to targets: Set<PeerID>) {
        let forwarded = router.decrementedForForwarding(packet)
        let bytes = PacketCodec.encode(forwarded)
        if targets.isEmpty {
            bluetooth.send(bytes, toPeripheral: nil)
        } else {
            for t in targets {
                if let pid = directory.peripheralID(for: t) {
                    bluetooth.send(bytes, toPeripheral: pid)
                } else {
                    bluetooth.send(bytes, toPeripheral: nil) // unbekannt → fluten
                }
            }
        }
    }

    // MARK: - Typ-spezifische Verarbeitung

    private func handleHello(_ packet: Packet, peripheralID: UUID?) {
        guard let payload = try? PayloadCodec.decode(HelloPayload.self, from: packet.payload),
              let signingKey = try? Curve25519.Signing.PublicKey(rawRepresentation: payload.identitySigningKey),
              let agreementKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: payload.identityAgreementKey)
        else { return }

        // Signatur des HELLO gegen den mitgelieferten Key prüfen (Self-attestation +
        // später per Fingerprint verifizierbar).
        guard PacketFactory.verify(packet, senderSigningKey: signingKey) else { return }

        directory.upsert(.init(
            peerID: packet.senderID, peripheralID: peripheralID,
            signingKey: signingKey, agreementKey: agreementKey,
            displayName: payload.displayName
        ))
        if let pid = peripheralID {
            directory.bind(peerID: packet.senderID, toPeripheral: pid)
            router.addNeighbor(packet.senderID)
        }
        // Kontakt persistieren (Verifizierungsstatus bleibt erhalten), damit
        // Name/Keys einen Neustart überdauern und verifizierte Peers erkannt werden.
        try? store.upsertPeer(
            peerIDHex: packet.senderID.hex, displayName: payload.displayName,
            signingKey: payload.identitySigningKey, agreementKey: payload.identityAgreementKey
        )
        refreshPeerList()
        flushQueuedMessages(for: packet.senderID)
    }

    private func handleKeyExchange(_ packet: Packet) {
        guard let payload = try? PayloadCodec.decode(KeyExchangePayload.self, from: packet.payload),
              let agreementKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: payload.identityAgreementKey)
        else { return }
        _ = try? sessions.establish(with: packet.senderID, peerAgreementKey: agreementKey)
        try? sessions.persist(packet.senderID)
    }

    private func handleMessage(_ packet: Packet) {
        guard let entry = directory.entry(for: packet.senderID),
              let ratchet = try? sessions.establish(with: packet.senderID, peerAgreementKey: entry.agreementKey),
              let ratchetMsg = decodeRatchetMessage(packet.payload),
              let plaintext = try? ratchet.decrypt(ratchetMsg),
              let content = try? PayloadCodec.decode(ChatContent.self, from: plaintext)
        else { return }
        try? sessions.persist(packet.senderID)

        do {
            let chat = try store.chat(forDirect: packet.senderID.hex, title: entry.displayName)
            let expiresAt = content.expiresAfter.map { Date().addingTimeInterval($0) }
            let record: MessageRecord
            switch content.body {
            case .text(let t):
                record = MessageRecord(id: packet.messageID, direction: .incoming, senderIDHex: packet.senderID.hex, text: t, sentAt: content.sentAt, receivedAt: Date(), deliveryState: .delivered, expiresAt: expiresAt)
            case .image(let d):
                record = MessageRecord(id: packet.messageID, direction: .incoming, senderIDHex: packet.senderID.hex, imageData: d, sentAt: content.sentAt, receivedAt: Date(), deliveryState: .delivered, expiresAt: expiresAt)
            }
            try store.append(record, to: chat)

            // Lokale Benachrichtigung (kein Server/Push verfügbar).
            let preview: String = {
                switch content.body {
                case .text(let t): return t
                case .image:       return "Bild"
                }
            }()
            NotificationService.notifyNewMessage(from: entry.displayName, preview: preview)

            // Delivery-ACK zurücksenden, falls gefordert.
            if packet.flags.contains(.requiresAck) {
                if let ack = try? factory.makeAck(to: packet.senderID, messageID: packet.messageID, kind: .delivered, ttl: router.maxTTL) {
                    route(ack, preferredRecipient: packet.senderID)
                }
            }
        } catch { }
    }

    private func handleAck(_ packet: Packet) {
        guard let ack = try? PayloadCodec.decode(AckPayload.self, from: packet.payload) else { return }
        let newState: DeliveryState = ack.kind == .read ? .read : .delivered
        try? store.updateDeliveryState(messageID: ack.messageID, to: newState)
    }

    // MARK: - Store-and-Forward

    /// Wenn ein Peer (wieder) erreichbar wird, ausstehende Nachrichten erneut senden.
    private func flushQueuedMessages(for peerID: PeerID) {
        guard let queued = try? store.queuedOutgoing() else { return }
        for record in queued where record.chat?.counterpartKey == peerID.hex {
            if let text = record.text {
                // Bestehenden Datensatz erneut senden (gleiche Message-ID) – kein
                // Duplikat. Der Empfänger dedupliziert ohnehin über die Message-ID.
                transmit(messageID: record.id, text: text, to: peerID,
                         expiresAfter: record.expiresAt.map { $0.timeIntervalSinceNow })
            }
        }
    }

    // MARK: - Peer-Liste / UI

    private func handleConnection(_ peripheralID: UUID, connected: Bool) {
        if connected {
            // Frisch verbunden: sofort HELLO senden, damit der Erstkontakt nicht
            // bis zum nächsten Heartbeat (30 s) warten muss.
            announce()
        } else if let peerID = directory.peerID(forPeripheral: peripheralID) {
            router.removeNeighbor(peerID)
        }
        refreshPeerList()
    }

    private func updateRSSI(peripheralID: UUID, rssi: Int) {
        // RSSI im Directory ablegen (überlebt refreshPeerList) …
        guard let peerID = directory.setRSSI(rssi, forPeripheral: peripheralID) else { return }
        // … und die bereits sichtbare Zeile direkt aktualisieren.
        if let idx = nearbyPeers.firstIndex(where: { $0.id == peerID }) {
            nearbyPeers[idx].rssi = rssi
        }
    }

    private func refreshPeerList() {
        nearbyPeers = directory.allEntries.map { e in
            PeerViewState(
                id: e.peerID, displayName: e.displayName, rssi: e.rssi,
                hopCount: router.nextHop(to: e.peerID) == e.peerID ? 1 : 2,
                isVerified: store.isVerified(peerIDHex: e.peerID.hex),
                isConnected: e.peripheralID != nil
            )
        }
    }

    // MARK: - Ratchet-Message-Wire-Format
    // Layout: counter(4 BE) | ciphertext

    private func encodeRatchetMessage(_ m: DoubleRatchet.RatchetMessage) -> Data {
        var w = ByteWriterShim()
        w.u32(m.counter)
        w.data(m.ciphertext)
        return w.out
    }

    private func decodeRatchetMessage(_ data: Data) -> DoubleRatchet.RatchetMessage? {
        guard data.count >= 4 else { return nil }
        var idx = data.startIndex
        var counter: UInt32 = 0
        for _ in 0..<4 { counter = (counter << 8) | UInt32(data[idx]); idx += 1 }
        let ct = data.subdata(in: idx..<data.endIndex)
        return DoubleRatchet.RatchetMessage(counter: counter, ciphertext: ct)
    }

    // MARK: - Panik-Modus

    func panicWipe() {
        try? store.wipeEverything()
        KeychainStore.wipeIdentity()
    }
}

/// Kleiner big-endian Writer (App-seitig, da ByteWriter im Core internal ist).
private struct ByteWriterShim {
    var out = Data()
    mutating func u8(_ v: UInt8) { out.append(v) }
    mutating func u32(_ v: UInt32) {
        out.append(UInt8(truncatingIfNeeded: v >> 24))
        out.append(UInt8(truncatingIfNeeded: v >> 16))
        out.append(UInt8(truncatingIfNeeded: v >> 8))
        out.append(UInt8(truncatingIfNeeded: v))
    }
    mutating func data(_ d: Data) { out.append(d) }
}
