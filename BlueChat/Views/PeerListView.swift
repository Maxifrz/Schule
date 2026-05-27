import SwiftUI
import BlueChatCore

/// Liste der Peers in Reichweite, mit Signalstärke und Hop-Distanz.
struct PeerListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                if !appState.engine.bluetoothReady {
                    Label("Bluetooth ist aus oder ohne Berechtigung", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Section("In Reichweite") {
                    if appState.engine.nearbyPeers.isEmpty {
                        Text("Suche nach Geräten in der Nähe …")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(appState.engine.nearbyPeers) { peer in
                        NavigationLink {
                            ChatView(viewModel: ChatViewModel(peerID: peer.id, title: peer.displayName, engine: appState.engine))
                        } label: {
                            PeerRow(peer: peer)
                        }
                    }
                }
            }
            .navigationTitle("BlueChat")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { MeshView() } label: { Image(systemName: "point.3.connected.trianglepath.dotted") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                }
            }
        }
    }
}

private struct PeerRow: View {
    let peer: MessengerEngine.PeerViewState

    var body: some View {
        let quality = SignalQuality(rssi: peer.rssi)
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(peer.isConnected ? Color.green.opacity(0.2) : Color.gray.opacity(0.2)).frame(width: 40, height: 40)
                Text(String(peer.displayName.prefix(1)).uppercased()).bold()
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(peer.displayName).font(.body.weight(.medium))
                    if peer.isVerified {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue).font(.caption)
                    }
                }
                Text("\(peer.hopCount == 1 ? "Direkt" : "\(peer.hopCount) Hops") · \(quality.rawValue)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            SignalBars(level: quality.bars)
        }
        .padding(.vertical, 4)
    }
}

/// Kleine Signalstärke-Visualisierung (4 Balken).
private struct SignalBars: View {
    let level: Int
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i <= level ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 4, height: CGFloat(4 + i * 3))
            }
        }
    }
}
