import Foundation
import CoreBluetooth

/// Feste UUIDs und Tuning-Parameter der BLE-Schicht.
///
/// Wichtiger iOS-Hinweis: Im VORDERGRUND wird die Service-UUID im
/// Advertisement-Paket gesendet und andere Geräte können gezielt danach
/// scannen. Im HINTERGRUND entfernt iOS die Service-UUIDs aus dem
/// Advertisement und legt sie in ein spezielles „overflow area"-Feld, das
/// NUR von anderen iOS-Geräten gelesen werden kann, die explizit nach
/// genau dieser UUID scannen. Cross-Plattform-Discovery (Android) bricht
/// im Hintergrund daher praktisch zusammen (siehe README → Fallstricke).
enum BLE {
    /// Eigene 128-bit Service-UUID des Messengers (einmalig generiert).
    static let serviceUUID = CBUUID(string: "B1UEC4A7-0000-1000-8000-00805F9B34FB")

    /// Peers SCHREIBEN eingehende Chunks in diese Characteristic (.write / .writeWithoutResponse).
    static let rxCharacteristicUUID = CBUUID(string: "B1UEC4A7-0001-1000-8000-00805F9B34FB")

    /// Wir NOTIFY-en ausgehende Chunks an verbundene Centrals (.notify).
    static let txCharacteristicUUID = CBUUID(string: "B1UEC4A7-0002-1000-8000-00805F9B34FB")

    /// Restoration-Identifier für State Preservation (Hintergrund-Relaunch).
    static let centralRestoreID = "app.bluechat.central"
    static let peripheralRestoreID = "app.bluechat.peripheral"

    /// Fallback-MTU, falls die Aushandlung scheitert (ATT-Default 23 - 3 ATT-Header).
    static let conservativeMTU = 20

    /// Duty-Cycling: aktiv scannen X Sekunden, dann Y Sekunden pausieren, um
    /// Akku zu sparen. Im Hintergrund erzwingt iOS ohnehin lange Intervalle.
    static let scanActiveWindow: TimeInterval = 8
    static let scanIdleWindow: TimeInterval = 12

    /// Intervall für HEARTBEAT/HELLO-Re-Announce.
    static let heartbeatInterval: TimeInterval = 30
}
