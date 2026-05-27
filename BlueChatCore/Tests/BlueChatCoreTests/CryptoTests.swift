import XCTest
import CryptoKit
@testable import BlueChatCore

final class CryptoTests: XCTestCase {

    func testAESGCMRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("Treffen um 19 Uhr am Haupteingang".utf8)
        let aad = Data("header".utf8)
        let ct = try CryptoService.encrypt(plaintext, key: key, aad: aad)
        let pt = try CryptoService.decrypt(ct, key: key, aad: aad)
        XCTAssertEqual(pt, plaintext)
    }

    func testAESGCMFailsWithWrongAAD() throws {
        let key = SymmetricKey(size: .bits256)
        let ct = try CryptoService.encrypt(Data("geheim".utf8), key: key, aad: Data("a".utf8))
        XCTAssertThrowsError(try CryptoService.decrypt(ct, key: key, aad: Data("b".utf8)))
    }

    func testDiffieHellmanProducesSharedKey() throws {
        let alice = CryptoService.generateEphemeral()
        let bob = CryptoService.generateEphemeral()
        let kAlice = try CryptoService.deriveSharedKey(privateKey: alice, peerPublicKey: bob.publicKey)
        let kBob = try CryptoService.deriveSharedKey(privateKey: bob, peerPublicKey: alice.publicKey)
        XCTAssertEqual(kAlice.rawData, kBob.rawData)
    }

    func testSignatureVerifies() throws {
        let id = CryptoService.generateIdentity()
        let msg = Data("authentisch".utf8)
        let sig = try CryptoService.sign(msg, with: id.signing)
        XCTAssertTrue(CryptoService.verify(sig, of: msg, publicKey: id.signing.publicKey))
        XCTAssertFalse(CryptoService.verify(sig, of: Data("manipuliert".utf8), publicKey: id.signing.publicKey))
    }

    func testPacketSignatureSurvivesTTLDecrement() throws {
        // Kernanforderung: Forwarding (TTL-1) darf die Signatur NICHT brechen.
        let id = CryptoService.generateIdentity()
        let factory = PacketFactory(identity: id)
        let packet = try factory.makeHello(displayName: "Knoten A", ttl: 7)

        var forwarded = packet
        forwarded.ttl = 6 // simulierter Hop
        XCTAssertTrue(PacketFactory.verify(forwarded, senderSigningKey: id.signing.publicKey))
    }

    func testFingerprintIsSymmetric() {
        let a = CryptoService.generateIdentity().signing.publicKey.rawRepresentation
        let b = CryptoService.generateIdentity().signing.publicKey.rawRepresentation
        let fpAB = Fingerprint.combined(localSigningKey: a, remoteSigningKey: b)
        let fpBA = Fingerprint.combined(localSigningKey: b, remoteSigningKey: a)
        XCTAssertEqual(fpAB, fpBA)
        XCTAssertEqual(Fingerprint.numericCode(from: fpAB), Fingerprint.numericCode(from: fpBA))
    }

    func testDoubleRatchetEndToEnd() throws {
        // Gemeinsames Root-Secret aus DH – beide Seiten erhalten denselben Root.
        let aEph = CryptoService.generateEphemeral()
        let bEph = CryptoService.generateEphemeral()
        let rootA = try CryptoService.deriveSharedKey(privateKey: aEph, peerPublicKey: bEph.publicKey)
        let rootB = try CryptoService.deriveSharedKey(privateKey: bEph, peerPublicKey: aEph.publicKey)
        XCTAssertEqual(rootA.rawData, rootB.rawData)

        let alice = DoubleRatchet(rootKey: rootA, role: .initiator)
        let bob = DoubleRatchet(rootKey: rootB, role: .responder)

        let m1 = try alice.encrypt(Data("Hallo Bob".utf8))
        XCTAssertEqual(try bob.decrypt(m1), Data("Hallo Bob".utf8))

        let m2 = try alice.encrypt(Data("Zweite Nachricht".utf8))
        XCTAssertEqual(try bob.decrypt(m2), Data("Zweite Nachricht".utf8))

        // Gegenrichtung nutzt die andere Chain.
        let m3 = try bob.encrypt(Data("Antwort".utf8))
        XCTAssertEqual(try alice.decrypt(m3), Data("Antwort".utf8))
    }

    func testDoubleRatchetToleratesLostMessage() throws {
        let aEph = CryptoService.generateEphemeral()
        let bEph = CryptoService.generateEphemeral()
        let root = try CryptoService.deriveSharedKey(privateKey: aEph, peerPublicKey: bEph.publicKey)
        let alice = DoubleRatchet(rootKey: root, role: .initiator)
        let bob = DoubleRatchet(rootKey: root, role: .responder)

        _ = try alice.encrypt(Data("geht verloren".utf8)) // counter 0 wird nie zugestellt
        let m2 = try alice.encrypt(Data("kommt an".utf8))  // counter 1
        XCTAssertEqual(try bob.decrypt(m2), Data("kommt an".utf8))
    }

    func testDoubleRatchetMessageKeysAreUnique() throws {
        let aEph = CryptoService.generateEphemeral()
        let bEph = CryptoService.generateEphemeral()
        let root = try CryptoService.deriveSharedKey(privateKey: aEph, peerPublicKey: bEph.publicKey)
        let alice = DoubleRatchet(rootKey: root, role: .initiator)

        let c1 = try alice.encrypt(Data("x".utf8)).ciphertext
        let c2 = try alice.encrypt(Data("x".utf8)).ciphertext
        XCTAssertNotEqual(c1, c2, "Gleicher Klartext muss bei Forward Secrecy unterschiedliche Ciphertexte ergeben")
    }
}
