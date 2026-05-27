import Foundation
import CoreBluetooth
import Combine
import BlueChatCore

/// Dual-Role-BLE-Transport: betreibt gleichzeitig einen `CBCentralManager`
/// (scannen, verbinden, schreiben) und einen `CBPeripheralManager`
/// (advertisen, Writes empfangen, notifien).
///
/// Verantwortung NUR Transport: rohe Bytes zuverlässig zwischen Geräten in
/// Funkreichweite bewegen, inkl. MTU-Fragmentierung/Reassemblierung. Es kennt
/// KEINE Verschlüsselung, KEIN Routing – das macht die `MessengerEngine`.
///
/// Threading: alle CoreBluetooth-Callbacks laufen auf `bleQueue` (seriell).
/// Veröffentlichte Subjects werden auf den Main-Actor umgeleitet, bevor die
/// UI sie konsumiert.
final class BluetoothService: NSObject {

    // MARK: - Öffentliche Event-Streams (Combine)

    struct DiscoveredPeer {
        let peripheralID: UUID
        let rssi: Int
        let advertisedName: String?
    }

    /// Ein vollständig reassembliertes, rohes Paket nebst Herkunft (Peripheral-ID).
    let inboundPackets = PassthroughSubject<(data: Data, fromPeripheral: UUID?), Never>()
    let discoveredPeers = PassthroughSubject<DiscoveredPeer, Never>()
    let connectionChanged = PassthroughSubject<(peripheralID: UUID, connected: Bool), Never>()
    let bluetoothState = CurrentValueSubject<CBManagerState, Never>(.unknown)

    // MARK: - Interner Zustand

    private let bleQueue = DispatchQueue(label: "app.bluechat.ble", qos: .userInitiated)
    private var central: CBCentralManager!
    private var peripheral: CBPeripheralManager!

    /// Verbundene Peripherals (wir = Central), inkl. ihrer Characteristics.
    private var connectedPeripherals: [UUID: CBPeripheral] = [:]
    private var rxCharacteristics: [UUID: CBCharacteristic] = [:] // zum Schreiben an den Peer
    /// Reassembler pro Gegenstelle (Peripheral- oder Central-ID).
    private var reassemblers: [UUID: Reassembler] = [:]
    /// Verbundene Centrals (wir = Peripheral), die unsere tx-Notify abonniert haben.
    private var subscribedCentrals: [UUID: CBCentral] = [:]
    private var txCharacteristic: CBMutableCharacteristic!
    /// Ausgehende Notify-Warteschlange (falls `updateValue` Backpressure meldet).
    private var pendingNotifications: [(data: Data, central: CBCentral?)] = []

    private var scanTimer: DispatchSourceTimer?

    // MARK: - Lifecycle

    func start() {
        // Restoration-IDs aktivieren State Preservation: iOS relauncht die App
        // im Hintergrund bei relevanten BLE-Events und liefert den Zustand zurück.
        central = CBCentralManager(delegate: self, queue: bleQueue, options: [
            CBCentralManagerOptionRestoreIdentifierKey: BLE.centralRestoreID,
            CBCentralManagerOptionShowPowerAlertKey: true
        ])
        peripheral = CBPeripheralManager(delegate: self, queue: bleQueue, options: [
            CBPeripheralManagerOptionRestoreIdentifierKey: BLE.peripheralRestoreID
        ])
    }

    // MARK: - Senden

    /// Sendet rohe Paket-Bytes an eine bestimmte Gegenstelle (per Peripheral-ID)
    /// oder – wenn `peripheralID` nil ist – an ALLE Verbundenen (Flooding/Broadcast).
    func send(_ packetBytes: Data, toPeripheral peripheralID: UUID?) {
        bleQueue.async { [weak self] in
            guard let self else { return }
            if let pid = peripheralID {
                self.sendToOne(packetBytes, peripheralID: pid)
            } else {
                // An alle verbundenen Peripherals schreiben …
                for pid in self.connectedPeripherals.keys { self.sendToOne(packetBytes, peripheralID: pid) }
                // … und an alle abonnierten Centrals notifien.
                self.notify(packetBytes, to: nil)
            }
        }
    }

    private func sendToOne(_ packetBytes: Data, peripheralID: UUID) {
        guard let peer = connectedPeripherals[peripheralID],
              let rx = rxCharacteristics[peripheralID] else {
            // Wir kennen den Peer nur als abonnierten Central -> per Notify pushen.
            if let central = subscribedCentrals[peripheralID] {
                notify(packetBytes, to: central)
            }
            return
        }
        let mtu = max(BLE.conservativeMTU, peer.maximumWriteValueLength(for: .withResponse))
        let chunks = Fragmenter.fragment(packetBytes, mtu: mtu)
        for chunk in chunks {
            // Write with Response = zuverlässige Übertragung (Anforderung).
            peer.writeValue(chunk, for: rx, type: .withResponse)
        }
    }

    /// Push an einen (oder alle) abonnierten Central(s) via Notify.
    private func notify(_ packetBytes: Data, to central: CBCentral?) {
        let mtu = central?.maximumUpdateValueLength ?? BLE.conservativeMTU
        let chunks = Fragmenter.fragment(packetBytes, mtu: max(BLE.conservativeMTU, mtu))
        for chunk in chunks {
            let centrals = central.map { [$0] }
            let ok = peripheral.updateValue(chunk, for: txCharacteristic, onSubscribedCentrals: centrals)
            if !ok {
                // Backpressure: in Warteschlange legen, bis isReadyToUpdateSubscribers feuert.
                pendingNotifications.append((chunk, central))
            }
        }
    }

    // MARK: - Scannen (Duty-Cycling)

    fileprivate func startScanning() {
        guard central.state == .poweredOn else { return }
        // CBCentralManagerScanOptionAllowDuplicatesKey=false spart Akku; RSSI-Updates
        // kommen dann seltener, was fürs Duty-Cycling akzeptabel ist.
        central.scanForPeripherals(withServices: [BLE.serviceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
        scheduleDutyCycle()
    }

    private func scheduleDutyCycle() {
        scanTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: bleQueue)
        timer.schedule(deadline: .now() + BLE.scanActiveWindow)
        timer.setEventHandler { [weak self] in
            guard let self, self.central.state == .poweredOn else { return }
            self.central.stopScan()
            // Nach Idle-Fenster erneut scannen.
            self.bleQueue.asyncAfter(deadline: .now() + BLE.scanIdleWindow) { [weak self] in
                self?.startScanning()
            }
        }
        timer.resume()
        scanTimer = timer
    }

    fileprivate func startAdvertising() {
        guard peripheral.state == .poweredOn else { return }
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BLE.serviceUUID],
            // Lokaler Name nur im Vordergrund relevant; bewusst kurz/anonym halten.
            CBAdvertisementDataLocalNameKey: "BC"
        ])
    }

    fileprivate func reassembler(for id: UUID) -> Reassembler {
        if let r = reassemblers[id] { return r }
        let r = Reassembler()
        reassemblers[id] = r
        return r
    }
}

// MARK: - CBCentralManagerDelegate (wir scannen/verbinden/schreiben)

extension BluetoothService: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState.send(central.state)
        if central.state == .poweredOn { startScanning() }
    }

    /// State Restoration: iOS gibt uns nach Hintergrund-Relaunch die Peripherals zurück.
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for p in peripherals {
                p.delegate = self
                connectedPeripherals[p.identifier] = p
                if p.state == .connected { p.discoverServices([BLE.serviceUUID]) }
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        discoveredPeers.send(.init(
            peripheralID: peripheral.identifier,
            rssi: RSSI.intValue,
            advertisedName: advertisementData[CBAdvertisementDataLocalNameKey] as? String
        ))
        // Automatisch verbinden, um HELLO/Nachrichten auszutauschen.
        if connectedPeripherals[peripheral.identifier] == nil {
            connectedPeripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionChanged.send((peripheral.identifier, true))
        peripheral.discoverServices([BLE.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionChanged.send((peripheral.identifier, false))
        rxCharacteristics.removeValue(forKey: peripheral.identifier)
        // Reconnect-Strategie: bei unerwartetem Verlust erneut verbinden (iOS hält
        // den Connect-Request, bis das Gerät wieder in Reichweite ist).
        central.connect(peripheral, options: nil)
    }
}

// MARK: - CBPeripheralDelegate (Service/Char-Discovery beim verbundenen Peer)

extension BluetoothService: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == BLE.serviceUUID }) else { return }
        peripheral.discoverCharacteristics([BLE.rxCharacteristicUUID, BLE.txCharacteristicUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for ch in service.characteristics ?? [] {
            if ch.uuid == BLE.rxCharacteristicUUID {
                rxCharacteristics[peripheral.identifier] = ch
            } else if ch.uuid == BLE.txCharacteristicUUID {
                peripheral.setNotifyValue(true, for: ch) // tx-Notifies abonnieren
            }
        }
    }

    /// Empfang via tx-Notify (der Peer pusht uns Chunks).
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        ingestChunk(data, from: peripheral.identifier)
    }

    private func ingestChunk(_ data: Data, from id: UUID) {
        do {
            let chunk = try Fragmenter.parseChunk(data)
            if let full = reassembler(for: id).ingest(chunk) {
                inboundPackets.send((full, id))
            }
        } catch {
            // CRC-Fehler / Truncation: Chunk verwerfen. Write-with-Response sorgt
            // ohnehin für erneute Übertragung auf Link-Ebene.
        }
    }
}

// MARK: - CBPeripheralManagerDelegate (wir advertisen/empfangen/notifien)

extension BluetoothService: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else { return }
        let service = CBMutableService(type: BLE.serviceUUID, primary: true)
        let rx = CBMutableCharacteristic(
            type: BLE.rxCharacteristicUUID,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        txCharacteristic = CBMutableCharacteristic(
            type: BLE.txCharacteristicUUID,
            properties: [.notify],
            value: nil,
            permissions: [.readable]
        )
        service.characteristics = [rx, txCharacteristic]
        peripheral.add(service)
        startAdvertising()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        // Services werden in peripheralManagerDidUpdateState neu aufgebaut;
        // hier ggf. Advertisement-Daten wiederherstellen.
    }

    /// Eingehende Writes auf rx (ein verbundener Central schreibt uns Chunks).
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if let value = request.value {
                ingestChunk(value, from: request.central.identifier)
            }
            subscribedCentrals[request.central.identifier] = request.central
        }
        peripheral.respond(to: requests.first!, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        subscribedCentrals[central.identifier] = central
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribedCentrals.removeValue(forKey: central.identifier)
    }

    /// Notify-Backpressure aufgelöst: ausstehende Notifications nachsenden.
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        while !pendingNotifications.isEmpty {
            let item = pendingNotifications.first!
            let centrals = item.central.map { [$0] }
            if peripheral.updateValue(item.data, for: txCharacteristic, onSubscribedCentrals: centrals) {
                pendingNotifications.removeFirst()
            } else {
                break // wieder voll – auf nächstes Ready warten
            }
        }
    }
}
