import Foundation
import SwiftData
import BlueChatCore

/// Dünne, testbare Fassade über den SwiftData-`ModelContext`.
///
/// Kapselt die wiederkehrenden Lese-/Schreibzugriffe (Chats finden/erzeugen,
/// Nachrichten anhängen, Zustellzustände aktualisieren, abgelaufene
/// Nachrichten löschen, Panik-Wipe). Läuft am Main-Actor, weil SwiftData-
/// Kontexte an ihren Erzeuger-Thread gebunden sind und die UI direkt liest.
@MainActor
final class MessageStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Chats

    func chat(forDirect peerIDHex: String, title: String) throws -> ChatRecord {
        if let existing = try fetchChat(counterpart: peerIDHex, kind: .direct) { return existing }
        let chat = ChatRecord(kind: .direct, title: title, counterpartKey: peerIDHex)
        context.insert(chat)
        try context.save()
        return chat
    }

    func channel(named name: String) throws -> ChatRecord {
        if let existing = try fetchChat(counterpart: name, kind: .channel) { return existing }
        let chat = ChatRecord(kind: .channel, title: "#\(name)", counterpartKey: name)
        context.insert(chat)
        try context.save()
        return chat
    }

    private func fetchChat(counterpart: String, kind: ChatKind) throws -> ChatRecord? {
        let descriptor = FetchDescriptor<ChatRecord>(
            predicate: #Predicate { $0.counterpartKey == counterpart && $0.kind == kind }
        )
        return try context.fetch(descriptor).first
    }

    // MARK: - Peers / Kontakte

    func peer(peerIDHex: String) throws -> PeerRecord? {
        let descriptor = FetchDescriptor<PeerRecord>(predicate: #Predicate { $0.peerIDHex == peerIDHex })
        return try context.fetch(descriptor).first
    }

    /// Legt einen Kontakt an oder aktualisiert seine Stammdaten (Name, Keys,
    /// zuletzt gesehen). Der Verifizierungsstatus bleibt dabei erhalten.
    @discardableResult
    func upsertPeer(peerIDHex: String, displayName: String, signingKey: Data, agreementKey: Data) throws -> PeerRecord {
        if let existing = try peer(peerIDHex: peerIDHex) {
            existing.displayName = displayName
            existing.signingPublicKey = signingKey
            existing.agreementPublicKey = agreementKey
            existing.lastSeen = Date()
            try context.save()
            return existing
        }
        let record = PeerRecord(peerIDHex: peerIDHex, displayName: displayName,
                                signingPublicKey: signingKey, agreementPublicKey: agreementKey, lastSeen: Date())
        context.insert(record)
        try context.save()
        return record
    }

    func setVerified(peerIDHex: String, _ verified: Bool) throws {
        guard let record = try peer(peerIDHex: peerIDHex) else { return }
        record.isVerified = verified
        try context.save()
    }

    func isVerified(peerIDHex: String) -> Bool {
        guard let record = try? peer(peerIDHex: peerIDHex) else { return false }
        return record?.isVerified ?? false
    }

    // MARK: - Nachrichten

    @discardableResult
    func append(_ message: MessageRecord, to chat: ChatRecord) throws -> MessageRecord {
        message.chat = chat
        chat.messages.append(message)
        chat.lastActivity = message.sentAt
        context.insert(message)
        try context.save()
        return message
    }

    func message(withID id: UUID) throws -> MessageRecord? {
        let descriptor = FetchDescriptor<MessageRecord>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    func updateDeliveryState(messageID: UUID, to state: DeliveryState) throws {
        guard let msg = try message(withID: messageID) else { return }
        msg.deliveryState = state
        try context.save()
    }

    /// Alle noch nicht zugestellten ausgehenden Nachrichten (Store-and-Forward-Queue).
    func queuedOutgoing() throws -> [MessageRecord] {
        let queued = DeliveryState.queued.rawValue
        let descriptor = FetchDescriptor<MessageRecord>(
            predicate: #Predicate { $0.deliveryStateRaw == queued && $0.direction == MessageDirection.outgoing }
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Verfallszeit / selbstlöschende Nachrichten

    func purgeExpired(now: Date = Date()) throws {
        let descriptor = FetchDescriptor<MessageRecord>(
            predicate: #Predicate { $0.expiresAt != nil && $0.expiresAt! < now }
        )
        for msg in try context.fetch(descriptor) { context.delete(msg) }
        try context.save()
    }

    // MARK: - Panik-Modus

    /// Löscht ALLE lokalen Daten unwiderruflich. Die Identitätsschlüssel in der
    /// Keychain müssen separat über `KeychainStore.wipeIdentity()` entfernt werden.
    func wipeEverything() throws {
        try context.delete(model: MessageRecord.self)
        try context.delete(model: ChatRecord.self)
        try context.delete(model: SessionRecord.self)
        try context.delete(model: PeerRecord.self)
        try context.save()
    }
}
