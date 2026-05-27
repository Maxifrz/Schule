# BlueChat – Architektur- & Sequenzdiagramme

> Diagramme in [Mermaid](https://mermaid.js.org). GitHub rendert sie direkt.

## 1. Schichtenarchitektur (MVVM + Core)

```mermaid
flowchart TB
    subgraph UI["UI-Schicht (SwiftUI)"]
        V1[OnboardingView]
        V2[PeerListView]
        V3[ChatView]
        V4[VerificationView]
        V5[MeshView]
        V6[SettingsView]
    end
    subgraph VM["ViewModels (Combine, @MainActor)"]
        VM1[ChatViewModel]
        VM2[AppState]
    end
    subgraph ENG["Orchestrierung"]
        E[MessengerEngine]
        SM[SessionManager]
        PD[PeerDirectory]
    end
    subgraph CORE["BlueChatCore (plattformunabhängig, getestet)"]
        P[PacketCodec / Fragmenter]
        C[CryptoService / DoubleRatchet]
        M[MeshRouter]
    end
    subgraph PLAT["Plattform-Dienste"]
        BT[BluetoothService<br/>CoreBluetooth Dual-Role]
        ST[MessageStore<br/>SwiftData]
        KC[KeychainStore]
        NS[NotificationService]
    end

    UI --> VM
    VM --> E
    E --> SM & PD
    E --> P & C & M
    E --> BT & ST & NS
    SM --> C & ST
    KC --> C
```

## 2. Discovery & Verbindungsaufbau (Dual-Role)

```mermaid
sequenceDiagram
    participant A as Gerät A
    participant B as Gerät B
    Note over A,B: Beide laufen als Central UND Peripheral
    A->>A: startAdvertising(serviceUUID)
    B->>B: startScanning(serviceUUID)
    B-->>A: didDiscover (RSSI)
    B->>A: connect()
    A-->>B: didConnect
    B->>A: discoverServices / Characteristics
    B->>A: subscribe(tx-Notify)
    Note over A,B: Kanal steht – jetzt HELLO austauschen
    A->>B: HELLO (signiert, Identity-Keys)
    B->>A: HELLO (signiert, Identity-Keys)
    Note over A,B: PeerDirectory + Routing-Tabelle aktualisiert
```

## 3. Schlüsselaustausch & verschlüsselte Nachricht

```mermaid
sequenceDiagram
    participant A as Alice
    participant B as Bob
    A->>B: KEY_EXCHANGE (ephem. X25519 + Identity-Agreement)
    B->>B: deriveSharedKey (X25519 + HKDF) -> Root
    B->>B: DoubleRatchet(root) anlegen
    A->>A: DoubleRatchet(root) anlegen
    A->>A: ratchet.encrypt(ChatContent) -> AES-GCM
    A->>B: MESSAGE (encrypted, signed, requiresAck, TTL=7)
    B->>B: Signatur prüfen -> ratchet.decrypt -> speichern
    B->>A: ACK(delivered)
    A->>A: Zustellstatus = delivered
    B->>A: ACK(read) (wenn gelesen)
    A->>A: Zustellstatus = read
```

## 4. Mesh-Multi-Hop-Weiterleitung

```mermaid
sequenceDiagram
    participant A as Alice (Quelle)
    participant R as Relais (Zwischenknoten)
    participant C as Carol (Ziel)
    Note over A,C: A und C sind NICHT in direkter Reichweite
    A->>R: MESSAGE (recipient=Carol, TTL=7)
    R->>R: MeshRouter.handle()<br/>nicht für mich, kein Duplikat
    R->>R: TTL 7 -> 6, Route lernen
    Note right of R: Inhalt bleibt verschlüsselt –<br/>Relais kann nicht mitlesen
    R->>C: MESSAGE (TTL=6)
    C->>C: deliverLocally -> decrypt
    C->>R: ACK(delivered) (TTL=7)
    R->>A: ACK (TTL=6)
```

## 5. Eingehender Paketfluss (Entscheidungsbaum)

```mermaid
flowchart TD
    IN[Chunk empfangen] --> RA[Reassembler]
    RA -->|vollständig| DEC[PacketCodec.decode]
    DEC --> SIG{signiert & Sender bekannt?}
    SIG -->|ja, ungültig| DROP1[verwerfen]
    SIG -->|ok| MR[MeshRouter.handle]
    MR -->|ownPacket / duplicate / ttlExpired| DROP2[drop]
    MR -->|deliverLocally| TYPE{PacketType}
    MR -->|forward| FWD[TTL-1, an Nachbarn senden]
    TYPE -->|HELLO| H[Peer lernen, Queue leeren]
    TYPE -->|KEY_EXCHANGE| K[Session aufbauen]
    TYPE -->|MESSAGE| MSG[decrypt, speichern, ACK]
    TYPE -->|ACK| ACK[Zustellstatus update]
```
