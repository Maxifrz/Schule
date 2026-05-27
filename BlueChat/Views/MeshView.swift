import SwiftUI
import BlueChatCore

/// Einfache Mesh-Visualisierung: das eigene Gerät im Zentrum, Peers ringförmig
/// angeordnet, Linienstärke/-farbe nach Hop-Distanz. Bewusst mit reinem
/// SwiftUI-Canvas umgesetzt (keine Drittbibliothek).
struct MeshView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        GeometryReader { geo in
            let peers = appState.engine.nearbyPeers
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 - 60

            ZStack {
                // Verbindungslinien
                ForEach(Array(peers.enumerated()), id: \.element.id) { idx, peer in
                    let pos = position(idx: idx, total: peers.count, center: center, radius: radius)
                    Path { p in p.move(to: center); p.addLine(to: pos) }
                        .stroke(peer.hopCount == 1 ? Color.green : Color.orange,
                                style: StrokeStyle(lineWidth: peer.hopCount == 1 ? 2 : 1, dash: peer.hopCount == 1 ? [] : [4]))
                }
                // Peers
                ForEach(Array(peers.enumerated()), id: \.element.id) { idx, peer in
                    let pos = position(idx: idx, total: peers.count, center: center, radius: radius)
                    NodeView(label: peer.displayName, subtitle: peer.hopCount == 1 ? "direkt" : "\(peer.hopCount) Hops", color: .blue)
                        .position(pos)
                }
                // Eigener Knoten
                NodeView(label: "Ich", subtitle: appState.displayName, color: .green)
                    .position(center)
            }
        }
        .navigationTitle("Mesh-Netzwerk")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func position(idx: Int, total: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        guard total > 0 else { return center }
        let angle = (2 * Double.pi / Double(total)) * Double(idx) - .pi / 2
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }
}

private struct NodeView: View {
    let label: String
    let subtitle: String
    let color: Color
    var body: some View {
        VStack(spacing: 2) {
            Circle().fill(color.gradient).frame(width: 44, height: 44)
                .overlay(Text(String(label.prefix(1)).uppercased()).foregroundStyle(.white).bold())
            Text(label).font(.caption2.bold())
            Text(subtitle).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
