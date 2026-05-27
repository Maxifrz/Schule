import Foundation
import Combine
import SwiftUI
import BlueChatCore

/// ViewModel für einen einzelnen 1:1-Chat. Hält den Entwurfstext und reicht
/// das Senden an die Engine weiter. Die Nachrichtenliste selbst lädt die View
/// reaktiv per @Query direkt aus SwiftData – kein doppelter State.
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var draft: String = ""
    @Published var expiryEnabled: Bool = false
    @Published var expirySeconds: Double = 300 // 5 Minuten Default

    let peerID: PeerID
    let title: String
    private let engine: MessengerEngine

    init(peerID: PeerID, title: String, engine: MessengerEngine) {
        self.peerID = peerID
        self.title = title
        self.engine = engine
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        engine.sendText(text, to: peerID, expiresAfter: expiryEnabled ? expirySeconds : nil)
        draft = ""
    }
}

/// Leitet aus dem RSSI eine grobe Entfernungs-/Signalstärke-Kategorie ab.
/// Hinweis: RSSI→Distanz ist physikalisch nur sehr grob (Pfadverlustmodell,
/// stark umgebungsabhängig) – daher nur qualitative Buckets, keine Meterangabe.
enum SignalQuality: String {
    case near = "Sehr nah", close = "Nah", medium = "Mittel", far = "Entfernt", unknown = "—"

    init(rssi: Int?) {
        guard let r = rssi else { self = .unknown; return }
        switch r {
        case (-50)...0:    self = .near
        case (-65)..<(-50): self = .close
        case (-80)..<(-65): self = .medium
        default:            self = .far
        }
    }

    var bars: Int {
        switch self {
        case .near: return 4
        case .close: return 3
        case .medium: return 2
        case .far: return 1
        case .unknown: return 0
        }
    }
}
