# BlueChat 📡

Ein dezentraler **Offline-Messenger für iOS**, der ausschließlich über
**Bluetooth Low Energy (BLE)** kommuniziert – ohne Internet, ohne zentrale
Server. Nachrichten werden direkt zwischen Geräten in Funkreichweite
ausgetauscht und über **Mesh-Networking** (Multi-Hop) weitergeleitet.

> Einsatzszenarien: Festivals, Demonstrationen, Krisengebiete, Outdoor,
> überall ohne Mobilfunknetz.

---

## Inhaltsverzeichnis
- [Status & Hinweis](#status--hinweis)
- [Projektstruktur](#projektstruktur)
- [Build & Run](#build--run)
- [Technologie-Stack](#technologie-stack)
- [Protokolldesign](#protokolldesign)
- [Sicherheitsmodell](#sicherheitsmodell)
- [iOS-BLE-Fallstricke & Workarounds](#ios-ble-fallstricke--workarounds)
- [Tests](#tests)
- [DSGVO-Konformität](#dsgvo-konformität)
- [TestFlight-Verteilung](#testflight-verteilung)
- [Vergleich zu bestehenden Lösungen](#vergleich-zu-bestehenden-lösungen)
- [Erweiterungsideen](#erweiterungsideen)

---

## Status & Hinweis

Dies ist eine **Referenz-/Lernimplementierung** mit vollständiger Architektur,
echtem Wire-Protokoll, Kryptographie und ausführbaren Unit-Tests für die
plattformunabhängige Kernlogik.

⚠️ **Sicherheitshinweis:** Die Krypto (insb. der Double-Ratchet) ist kompakt
und gut lesbar gehalten, aber **nicht formal auditiert**. Für den
Produktiveinsatz in echten Hochrisiko-Szenarien sollte eine geprüfte
Bibliothek (z. B. `libsignal`) evaluiert werden.

Der Code kann **nicht auf Linux/CI** gebaut werden, da `CoreBluetooth`,
`CryptoKit`, `SwiftData` und `SwiftUI` Apple-exklusiv sind. Bauen und Testen
erfolgen in **Xcode auf macOS** (siehe unten).

---

## Projektstruktur

```
BlueChat/
├── README.md                     ← dieses Dokument
├── project.yml                   ← XcodeGen-Definition (erzeugt .xcodeproj)
├── docs/
│   └── architecture.md           ← Architektur- & Sequenzdiagramme (Mermaid)
│
├── BlueChatCore/                 ← plattformunabhängiges Swift-Package (getestet)
│   ├── Package.swift
│   ├── Sources/BlueChatCore/
│   │   ├── Model/      PeerID
│   │   ├── Protocol/   Packet, PacketType, PacketCodec, ByteBuffer,
│   │   │               CRC32, Fragmenter, Payloads
│   │   ├── Crypto/     CryptoService, DoubleRatchet, Fingerprint, PacketFactory
│   │   └── Mesh/       MeshRouter, MessageIDCache
│   └── Tests/BlueChatCoreTests/
│       ├── PacketCodecTests.swift
│       ├── CryptoTests.swift
│       ├── FragmenterTests.swift
│       └── MeshRouterTests.swift
│
└── BlueChat/                     ← iOS-App-Target
    ├── App/         BlueChatApp (Entry + AppState), Info.plist
    ├── Models/      SwiftData: Identity, Peer, Session, Chat, Message
    ├── Crypto/      KeychainStore (private Keys)
    ├── Bluetooth/   BluetoothConstants, BluetoothService (Dual-Role)
    ├── Persistence/ MessageStore (SwiftData-Fassade)
    ├── Services/    MessengerEngine, SessionManager, PeerDirectory,
    │                NotificationService
    ├── ViewModels/  ChatViewModel, SignalQuality
    └── Views/       Onboarding, PeerList, Chat, Verification, Settings, Mesh
```

**Warum die Zweiteilung Core ↔ App?** Die schwierige, fehleranfällige Logik
(Byte-Parsing, Krypto, Routing) lebt im Package `BlueChatCore` – ohne UI- oder
Bluetooth-Abhängigkeit und damit **deterministisch per XCTest testbar**. Die
App ist die dünne, plattformgebundene Hülle (CoreBluetooth, SwiftUI,
SwiftData).

---

## Build & Run

```bash
brew install xcodegen        # einmalig
cd BlueChat                  # Repo-Wurzel mit project.yml
xcodegen generate
open BlueChat.xcodeproj
```

Anschließend in Xcode auf einem **physischen Gerät** ausführen (der iOS-
Simulator unterstützt kein Bluetooth). Für sinnvolle Tests braucht man
**zwei echte Geräte**.

Core-Tests separat:
```bash
cd BlueChatCore && swift test     # auf macOS
```

---

## Technologie-Stack

| Bereich        | Wahl                                              |
|----------------|---------------------------------------------------|
| Sprache        | Swift 5.9                                          |
| UI             | SwiftUI (+ UIKit-Interop via `UIImpactFeedbackGenerator`, `UIImage`) |
| Min. iOS       | 16.0 (App-Target); SwiftData-Pfade ab 17.0        |
| Architektur    | MVVM + Combine                                     |
| Bluetooth      | CoreBluetooth, `CBCentralManager` + `CBPeripheralManager` (Dual-Role) |
| Persistenz     | SwiftData                                          |
| Krypto         | CryptoKit: Curve25519 (Ed25519 + X25519), AES-GCM-256, HKDF, HMAC-SHA256 |

> **Versionsstrategie iOS 16 vs. 17:** `@Model` (SwiftData) ist eine iOS-17-API.
> Das Deployment-Target bleibt 16, damit Onboarding/BLE auch dort laufen; die
> persistenz­abhängigen Codepfade sind mit `if #available(iOS 17, *)` zu
> kapseln bzw. man hebt das Target auf 17 an, wenn SwiftData zwingend ist.

---

## Protokolldesign

Zwei sauber getrennte Schichten:

### Logische Schicht – `Packet`
Eigenes **binäres** Wire-Format (kein JSON: BLE-Bandbreite ist knapp,
deterministische Bytes erleichtern das Signieren).

```
 Offset Größe Feld
 0      2     Magic = "BC"
 2      1     Version
 3      1     Type    (HELLO=1, KEY_EXCHANGE=2, MESSAGE=3, ACK=4, RELAY=5, HEARTBEAT=6)
 4      1     Flags   (encrypted | signed | requiresAck | ephemeral | channel)
 5      1     TTL     (max. 7 Hops)
 6      16    Message-ID (UUID)
 22     8     Sender-ID   (PeerID = SHA256(pubkey)[0..8])
 30     8     Recipient-ID (0…0 = Broadcast)
 38     2     Sequence
 40     2     Payload-Length (N)
 42     N     Payload  (bei MESSAGE: AES-GCM-Ciphertext)
 42+N   64    Signature (Ed25519, nur wenn signed-Flag)
```

**Signatur & Mesh:** Signiert werden die kanonischen Bytes **mit TTL=0**, damit
das TTL-Dekrement beim Forwarding die Signatur des Urhebers nicht bricht.
Zwischenknoten signieren nie neu.

### Transport-Schicht – `Fragmenter`
Ein serialisiertes Paket wird in **MTU-konforme Chunks** zerlegt. Jeder Chunk:
`Transfer-ID(16) | Index(2) | Total(2) | Len(2) | CRC32(4) | Payload`.
Der `Reassembler` setzt sie (auch out-of-order) zusammen, prüft CRC und liefert
das Paket erst bei Vollständigkeit. Zuverlässigkeit zusätzlich über GATT
**Write-with-Response**.

---

## Sicherheitsmodell

- **Identität:** langlebiges **Ed25519**-Paar (Signaturen, Fingerprint) +
  **X25519**-Paar (Key Agreement). Private Keys in der **Keychain**
  (`AfterFirstUnlockThisDeviceOnly`, kein iCloud-Sync, kein Backup).
- **Key Exchange:** X25519-Diffie-Hellman beim ersten Kontakt → HKDF → Root-Key.
- **Forward Secrecy:** **Double-Ratchet** (symmetrischer Chain-Ratchet pro
  Nachricht + DH-Ratchet bei Richtungswechsel). Gleicher Klartext ⇒
  unterschiedliche Ciphertexte.
- **Vertraulichkeit:** AES-GCM-256, Header als AAD gebunden.
- **MITM-Schutz:** **Fingerprint-Verifizierung** – 60-stelliger Zahlencode
  (wie Signal) oder QR-Code über einen Zweitkanal vergleichen.
- **Mesh-Privatsphäre:** Zwischenknoten leiten nur Ciphertext weiter und können
  Inhalte nicht lesen.
- **Panik-Modus:** löscht SwiftData-Store **und** Keychain-Schlüssel sofort.

---

## iOS-BLE-Fallstricke & Workarounds

### 1. Eingeschränkter Hintergrund-Betrieb
- **Service-UUID-Broadcasting im Hintergrund:** iOS entfernt im Hintergrund
  die Service-UUIDs aus dem Advertisement und legt sie in eine „overflow area",
  die **nur andere iOS-Geräte** lesen können, die **explizit** nach genau dieser
  UUID scannen. → *Workaround:* immer mit konkreter `serviceUUID` scannen
  (machen wir), Erwartungen an Hintergrund-Discovery niedrig halten,
  HEARTBEAT/HELLO im Vordergrund nutzen, um Routen aufzufrischen.
- **Background-Scan ist gedrosselt:** keine `AllowDuplicates`, lange Intervalle,
  CPU-Wakeups limitiert. → *Workaround:* `UIBackgroundModes`
  `bluetooth-central`/`bluetooth-peripheral` setzen, **State Preservation &
  Restoration** mit `RestoreIdentifier` aktivieren, damit iOS die App bei
  BLE-Events relauncht. Lokale Notifications statt Push.

### 2. Zufällige/rotierende MAC-Adressen
iOS zeigt keine echte MAC, sondern eine **rotierende, app-spezifische
`peripheral.identifier`-UUID**, die sich ändern kann. → *Workaround:* niemals
auf MAC/peripheral-UUID als stabile Identität verlassen. Unsere stabile Identität
ist die **PeerID** (aus dem Public Key), die per HELLO übertragen und im
`PeerDirectory` an die flüchtige peripheral-UUID gebunden wird.

### 3. MTU-Verhandlung
ATT-Default-MTU ist 23 (nutzbar 20 Byte/Write). Nach Verbindungsaufbau handelt
iOS automatisch eine größere MTU aus (bis ~185 oder 244–509). → *Workaround:*
`maximumWriteValueLength(for:)` bzw. `maximumUpdateValueLength` **erst nach**
Connect/Subscribe abfragen, konservativ auf 20 zurückfallen und immer
fragmentieren (Fragmenter). Niemals fixe Chunk-Größe annehmen.

### 4. Verbindungsverlust & Reconnect
BLE-Links brechen bei Reichweite/Interferenz häufig ab. → *Workaround:* bei
`didDisconnectPeripheral` sofort erneut `connect()` aufrufen – iOS hält den
Request „pending", bis das Gerät wieder auftaucht. Store-and-Forward-Queue
sorgt dafür, dass Nachrichten an offline Peers bei Re-Discovery (HELLO)
automatisch erneut gesendet werden.

### 5. Akkuverbrauch
Dauerhaftes Scannen + Advertisen kostet spürbar Energie. → *Workaround:*
**Duty-Cycling** (aktiv scannen `scanActiveWindow`, dann pausieren),
`AllowDuplicates=false`, Heartbeat-Intervall moderat (30 s), keine unnötigen
Notify-Bursts (Backpressure-Queue).

### 6. Cross-Plattform (warum Android-Interop schwierig ist)
- iOS versteckt Service-UUIDs im Hintergrund-Advertisement in einem
  Apple-proprietären Format → Android sieht sie dort nicht.
- GATT-MTU-Verhalten, Bonding und Advertisement-Strukturen unterscheiden sich.
- iOS erlaubt App-Entwicklern keinen Zugriff auf die rohe BLE-MAC.
→ *Konsequenz:* zuverlässige iOS↔Android-Discovery erfordert Vordergrund-
Betrieb auf der iOS-Seite und ein bewusst minimalistisches, auf beiden
Plattformen lesbares Advertisement. Echte Hintergrund-Interop ist praktisch
kaum robust herstellbar.

---

## Tests

Ausführbare XCTests für die Kernlogik (`BlueChatCore`):

| Datei | Deckt ab |
|-------|----------|
| `PacketCodecTests` | Round-Trip aller Header-Felder, Magic/Truncation/Unknown-Type-Fehler, Broadcast, PeerID-Hex |
| `CryptoTests` | AES-GCM (inkl. AAD-Manipulation), DH-Shared-Key, Ed25519-Signaturen, **Signatur überlebt TTL-Dekrement**, Fingerprint-Symmetrie, Double-Ratchet E2E + Key-Uniqueness |
| `FragmenterTests` | Fragmentierung/Reassemblierung, Out-of-Order, **CRC-Fehler**, Single-Chunk |
| `MeshRouterTests` | lokale Zustellung, Drop (own/duplicate/ttl), Broadcast-Flooding + Split-Horizon, gerichtetes Routing über gelernte Route, TTL-Dekrement |

```bash
cd BlueChatCore && swift test
```

---

## DSGVO-Konformität

**Datenminimierung ist hier Architekturprinzip, nicht Nachgedanke:**

- **Kein Server, keine Cloud, kein Backend** → keine zentrale Verarbeitung,
  kein Auftragsverarbeiter, keine Server-Logs.
- **Keine Konten, keine Telefonnummer, keine E-Mail** → nur ein frei wählbarer,
  pseudonymer Anzeigename. Identität ist ein lokal erzeugtes Schlüsselpaar.
- **Lokale Speicherung, verschlüsselt-at-rest** (Datei-Schutzklasse, Schlüssel
  in der Keychain `ThisDeviceOnly`, kein iCloud-Sync).
- **Ende-zu-Ende-Verschlüsselung**; Zwischenknoten sehen nur Ciphertext.
- **Recht auf Löschung** technisch trivial: Panik-Modus löscht alle Daten +
  Schlüssel unwiderruflich; selbstlöschende Nachrichten (Verfallszeit).
- **Keine Analytics, kein Tracking, keine Drittanbieter-SDKs.**

Hinweis: Metadaten (wer in Funkreichweite war) lassen sich physikalisch nicht
vollständig verbergen; das Protokoll vermeidet aber unnötige Klartext-Identifier
im Advertisement (nur generisches „BC").

---

## TestFlight-Verteilung

P2P-Messenger werden im App-Store-Review **erfahrungsgemäß streng** geprüft.
Empfehlung:

1. **Erst TestFlight, dann (ggf.) Store.** TestFlight-Builds durchlaufen nur ein
   leichtes Beta-App-Review – ideal für Felderprobung mit echten Geräten.
2. **Begründungen sauberhalten:** klarer `NSBluetoothAlwaysUsageDescription`,
   nur die wirklich nötigen `UIBackgroundModes`. Apple fragt bei Background-
   Bluetooth nach dem konkreten Nutzen → im Review-Notes-Feld erklären.
3. **Demo-Anleitung beilegen:** Da zwei Geräte nötig sind, dem Reviewer ein
   Video oder eine Schritt-für-Schritt-Anleitung mitgeben (App Review Notes).
4. **Verschlüsselungs-Export-Compliance:** Standard-Krypto (CryptoKit) →
   i. d. R. `ITSAppUsesNonExemptEncryption = false`-Erklärung bzw. die
   Self-Classification in App Store Connect ausfüllen.
5. **Keine versteckten Funktionen / kein „Internet-Bypass"-Marketing**, das
   Review-Ablehnungen provoziert; den legitimen Offline-Nutzen betonen.

---

## Vergleich zu bestehenden Lösungen

| Merkmal | **BlueChat** | **Bridgefy** | **Briar** | **Berty** |
|---|---|---|---|---|
| Plattform | iOS (dieses Projekt) | iOS/Android (SDK) | Android (+ Desktop) | iOS/Android |
| Transport | BLE-Mesh | BLE-Mesh | Tor / Wi-Fi / Bluetooth | BLE + Internet (libp2p) |
| Offline-Mesh | ✅ Multi-Hop | ✅ | ✅ (lokal) | ✅ |
| E2E-Verschlüsselung | ✅ (Double-Ratchet-ähnlich) | teils (in der Vergangenheit kritisiert) | ✅ (stark, Forward Secrecy) | ✅ (libp2p/Noise) |
| Server nötig | ❌ nie | ❌ (P2P), SDK kommerziell | ❌ | optional (Relay) |
| Open Source | dieses Projekt: ja | nein (proprietär) | ✅ | ✅ |
| Fokus | Lern-/Referenzprojekt | kommerzielles SDK (Events) | Aktivisten/Hochrisiko | dezentrales Protokoll |

Kurz: **Briar** ist der Goldstandard für Sicherheit (aber Android-zentriert,
nutzt Tor statt reinem BLE-Mesh). **Bridgefy** ist als kommerzielles SDK weit
verbreitet (Krypto historisch kritisiert). **Berty** setzt auf libp2p und mischt
BLE mit Internet-Transport. BlueChat positioniert sich als **schlankes,
iOS-natives, gut dokumentiertes Referenz-Mesh** mit Signal-ähnlicher Krypto.

---

## Erweiterungsideen

- **Wi-Fi Direct / Multipeer Connectivity als Zweittransport:** Apples
  `MultipeerConnectivity` (Wi-Fi + BLE) bietet höhere Bandbreite/Reichweite für
  Bilder. Architektur ist transport-agnostisch (Engine kennt nur „sende Bytes
  an Peer") → ein zweiter `Transport`-Adapter neben `BluetoothService` ließe
  sich sauber einhängen.
- **Ultraschall-Pairing:** kurzer hochfrequenter Audio-Burst (über
  `AVAudioEngine`) zur Übertragung des Fingerprints/Pairing-Tokens beim
  In-Person-Verify – bequeme Alternative zu QR/Zahlencode.
- **Bilder:** Pipeline für komprimierte Bilder ≤ 50 KB ist im Datenmodell
  (`MessageRecord.imageData`, `ChatContent.image`) bereits vorgesehen.
- **Gruppen- & Channel-Krypto:** Sender-Keys (wie Signal-Gruppen) statt
  paarweiser Sessions für effiziente Gruppenchats.
- **Adaptives Duty-Cycling:** Scan-Intervalle nach Akkustand/Bewegung
  (CoreMotion) dynamisch anpassen.

---

*BlueChat – kommunizieren, wenn das Netz schweigt.*
