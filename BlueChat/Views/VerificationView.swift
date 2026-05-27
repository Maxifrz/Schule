import SwiftUI
import CryptoKit
import CoreImage.CIFilterBuiltins
import BlueChatCore

/// Fingerprint-Verifizierung zum Schutz vor Man-in-the-Middle.
///
/// Zwei gleichwertige Wege: QR-Code anzeigen/scannen ODER den 60-stelligen
/// Zahlencode laut vorlesen und vergleichen. Stimmt der Code auf beiden
/// Geräten überein, ist garantiert, dass kein Angreifer die Schlüssel
/// ausgetauscht hat.
struct VerificationView: View {
    @EnvironmentObject var appState: AppState
    let peerID: PeerID
    let peerName: String
    @State private var verified = false

    private var fingerprint: Data? {
        let local = appState.engine.identity.signing.publicKey.rawRepresentation
        // Echter, gespeicherter Signing-Key des Peers (aus dem HELLO).
        guard let remote = appState.engine.signingKeyData(for: peerID) else { return nil }
        return Fingerprint.combined(localSigningKey: local, remoteSigningKey: remote)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Sicherheitscode mit \(peerName) vergleichen")
                    .font(.headline).multilineTextAlignment(.center)

                if let fp = fingerprint {
                    QRCodeView(text: fp.base64EncodedString())
                        .frame(width: 200, height: 200)

                    Text(Fingerprint.numericCode(from: fp))
                        .font(.system(.title3, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text("Kurz-Fingerprint: \(Fingerprint.shortHex(from: fp))")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Noch kein Schlüssel von \(peerName) empfangen. Sobald das Gerät in Reichweite ist (HELLO), erscheint hier der Sicherheitscode.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }

                Text("Vergleicht die Zahlenfolge persönlich oder per QR-Scan. Stimmt sie überein, tippt auf „Als verifiziert markieren".")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)

                Toggle("Als verifiziert markieren", isOn: $verified)
                    .padding(.horizontal)
                    .disabled(fingerprint == nil)
                    .onChange(of: verified) { _, newValue in
                        appState.engine.setVerified(peerID, newValue)
                    }
            }
            .padding()
        }
        .navigationTitle("Verifizieren")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { verified = appState.engine.isVerified(peerID) }
    }
}

/// Erzeugt einen QR-Code aus Text via CoreImage (kein Drittanbieter nötig).
struct QRCodeView: View {
    let text: String
    var body: some View {
        if let image = Self.generate(text) {
            Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
        } else {
            Color.gray.opacity(0.2)
        }
    }

    static func generate(_ text: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
