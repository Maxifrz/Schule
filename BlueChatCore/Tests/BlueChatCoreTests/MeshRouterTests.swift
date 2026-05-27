import XCTest
@testable import BlueChatCore

final class MeshRouterTests: XCTestCase {

    private let me = PeerID(bytes: [0,0,0,0,0,0,0,1])
    private let alice = PeerID(bytes: [0,0,0,0,0,0,0,2])
    private let bob = PeerID(bytes: [0,0,0,0,0,0,0,3])
    private let carol = PeerID(bytes: [0,0,0,0,0,0,0,4])

    private func packet(from: PeerID, to: PeerID, ttl: UInt8, id: UUID = UUID()) -> Packet {
        Packet(type: .message, ttl: ttl, messageID: id, senderID: from, recipientID: to)
    }

    func testDeliversToSelf() {
        let router = MeshRouter(myID: me)
        let actions = router.handle(packet(from: alice, to: me, ttl: 7), arrivedFrom: alice)
        XCTAssertTrue(actions.contains(.deliverLocally))
        XCTAssertFalse(actions.contains { if case .forward = $0 { return true } else { return false } })
    }

    func testDropsOwnPacket() {
        let router = MeshRouter(myID: me)
        let actions = router.handle(packet(from: me, to: alice, ttl: 7), arrivedFrom: alice)
        XCTAssertEqual(actions, [.drop(reason: .ownPacket)])
    }

    func testDropsDuplicate() {
        let router = MeshRouter(myID: me)
        router.addNeighbor(alice)
        let p = packet(from: bob, to: carol, ttl: 7)
        _ = router.handle(p, arrivedFrom: alice)
        let second = router.handle(p, arrivedFrom: alice)
        XCTAssertEqual(second, [.drop(reason: .duplicate)])
    }

    func testDropsOnTTLExpired() {
        let router = MeshRouter(myID: me)
        router.addNeighbor(alice)
        let actions = router.handle(packet(from: bob, to: carol, ttl: 1), arrivedFrom: alice)
        XCTAssertTrue(actions.contains(.drop(reason: .ttlExpired)))
    }

    func testFloodsBroadcastToOtherNeighbors() {
        let router = MeshRouter(myID: me)
        router.addNeighbor(alice)
        router.addNeighbor(bob)
        let actions = router.handle(packet(from: carol, to: .broadcast, ttl: 7), arrivedFrom: alice)
        XCTAssertTrue(actions.contains(.deliverLocally))
        // Split-Horizon: nicht zurück an Alice, nur an Bob.
        XCTAssertTrue(actions.contains(.forward(to: [bob])))
    }

    func testDirectedRoutingUsesLearnedNextHop() {
        let router = MeshRouter(myID: me)
        router.addNeighbor(alice)
        router.addNeighbor(bob)
        // Lernen: carol ist über alice erreichbar (Paket kam von alice).
        _ = router.handle(packet(from: carol, to: me, ttl: 6), arrivedFrom: alice)
        XCTAssertEqual(router.nextHop(to: carol), alice)

        // Neues Paket an carol -> gerichtet über alice, nicht geflutet an bob.
        let actions = router.handle(packet(from: bob, to: carol, ttl: 7), arrivedFrom: bob)
        XCTAssertTrue(actions.contains(.forward(to: [alice])))
    }

    func testTTLDecrement() {
        let router = MeshRouter(myID: me)
        let p = packet(from: alice, to: bob, ttl: 7)
        XCTAssertEqual(router.decrementedForForwarding(p).ttl, 6)
    }
}
