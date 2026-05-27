import Foundation
import CryptoKit

/// Erzeugt menschenlesbare Verifizierungsdaten zum Schutz vor
/// Man-in-the-Middle-Angriffen beim ersten Kontakt.
///
/// Hintergrund: Ein DH-Schlüsselaustausch allein authentifiziert die
/// Gegenseite nicht – ein Angreifer könnte sich dazwischenschalten. Indem
/// zwei Nutzer ihre Fingerprints über einen zweiten Kanal vergleichen
/// (QR-Code anzeigen/scannen oder Zahlencode vorlesen), stellen sie sicher,
/// dass sie wirklich denselben Schlüssel sehen.
public enum Fingerprint {

    /// Stabiler 32-Byte-Fingerprint aus beiden Identity-Public-Keys.
    /// Symmetrisch: beide Seiten erhalten denselben Wert, egal wer "lokal" ist
    /// (die Keys werden vor dem Hashen sortiert).
    public static func combined(localSigningKey: Data, remoteSigningKey: Data) -> Data {
        let pair = [localSigningKey, remoteSigningKey].sorted { $0.lexicographicallyPrecedes($1) }
        var hasher = SHA256()
        hasher.update(data: Data("BlueChat-fingerprint-v1".utf8))
        pair.forEach { hasher.update(data: $0) }
        return Data(hasher.finalize())
    }

    /// 60-stelliger numerischer Sicherheitscode (wie Signal), in 12 Blöcken
    /// zu je 5 Ziffern – gut zum Vorlesen.
    public static func numericCode(from fingerprint: Data) -> String {
        // Je 5 Bytes -> eine 5-stellige Gruppe (mod 100000).
        var groups: [String] = []
        var i = fingerprint.startIndex
        while i < fingerprint.endIndex && groups.count < 12 {
            let end = fingerprint.index(i, offsetBy: 5, limitedBy: fingerprint.endIndex) ?? fingerprint.endIndex
            let slice = fingerprint[i..<end]
            var value: UInt64 = 0
            for b in slice { value = (value << 8) | UInt64(b) }
            groups.append(String(format: "%05d", value % 100_000))
            i = end
        }
        return groups.joined(separator: " ")
    }

    /// Kurzform für die UI (erste 8 Bytes als Hex-Quartette), z. B. "A1B2 C3D4 E5F6 0718".
    public static func shortHex(from fingerprint: Data) -> String {
        let hex = fingerprint.prefix(8).map { String(format: "%02X", $0) }.joined()
        return stride(from: 0, to: hex.count, by: 4).map { off -> String in
            let s = hex.index(hex.startIndex, offsetBy: off)
            let e = hex.index(s, offsetBy: 4, limitedBy: hex.endIndex) ?? hex.endIndex
            return String(hex[s..<e])
        }.joined(separator: " ")
    }
}
