// swift-tools-version: 5.9
import PackageDescription

// BlueChatCore bündelt die plattformunabhängige Kernlogik des Messengers:
// - das binäre Wire-Protokoll (Packet + Codec + CRC)
// - die Kryptographie (CryptoKit: Curve25519, AES-GCM, Double-Ratchet)
// - das Mesh-Routing (TTL, Loop-Schutz, Routing-Tabelle)
//
// Diese Logik hat KEINE Abhängigkeit zu CoreBluetooth, SwiftUI oder SwiftData
// und ist dadurch vollständig per XCTest testbar (siehe Tests/).
// CryptoKit ist auf iOS/macOS/tvOS/watchOS verfügbar – deshalb diese Plattformen.
let package = Package(
    name: "BlueChatCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "BlueChatCore", targets: ["BlueChatCore"])
    ],
    targets: [
        .target(
            name: "BlueChatCore",
            path: "Sources/BlueChatCore"
        ),
        .testTarget(
            name: "BlueChatCoreTests",
            dependencies: ["BlueChatCore"],
            path: "Tests/BlueChatCoreTests"
        )
    ]
)
