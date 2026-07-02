import Combine
import CoreBluetooth
import Foundation

enum BluetoothConnectionStatus: Equatable {
    case idle
    case bluetoothUnavailable(String)
    case scanning
    case connecting(String)
    case connected(String)
    case disconnected
    case syncing
    case failed(String)

    var title: String {
        switch self {
        case .idle: "Ready"
        case .bluetoothUnavailable: "Bluetooth Unavailable"
        case .scanning: "Searching"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .disconnected: "Disconnected"
        case .syncing: "Syncing"
        case .failed: "Needs Attention"
        }
    }

    var detail: String {
        switch self {
        case .idle:
            return "Ready to search for your clock."
        case .bluetoothUnavailable(let message):
            return message
        case .scanning:
            return "Looking for nearby WakeGuard or HM-10 clocks."
        case .connecting(let name):
            return "Connecting to \(name)."
        case .connected(let name):
            return "\(name) is connected."
        case .disconnected:
            return "Your clock is not connected."
        case .syncing:
            return "Synchronizing time, alarms, and settings."
        case .failed(let message):
            return message
        }
    }
}

final class BluetoothClockService: NSObject, ObservableObject {
    @Published private(set) var status: BluetoothConnectionStatus = .idle
    @Published private(set) var discoveredDevices: [ClockDevice] = []
    @Published private(set) var connectedDevice: ClockDevice?
    @Published private(set) var lastSyncDate: Date?
    @Published var developmentBypassPairing: Bool {
        didSet {
            defaults.set(developmentBypassPairing, forKey: bypassKey)
        }
    }

    private let defaults: UserDefaults
    private let bypassKey = "wakeguard.developmentBypassPairing"
    private var centralManager: CBCentralManager?
    private var peripheralsByIdentifier: [UUID: CBPeripheral] = [:]
    private var scanStopWorkItem: DispatchWorkItem?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        developmentBypassPairing = defaults.bool(forKey: bypassKey)
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    var isConnected: Bool {
        connectedDevice != nil
    }

    func startSearch() {
        guard let centralManager else {
            status = .failed("Bluetooth could not be initialized.")
            return
        }

        guard centralManager.state == .poweredOn else {
            status = .bluetoothUnavailable(message(for: centralManager.state))
            return
        }

        scanStopWorkItem?.cancel()
        discoveredDevices.removeAll()
        status = .scanning

        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        let workItem = DispatchWorkItem { [weak self] in
            self?.finishSearchIfNeeded()
        }
        scanStopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: workItem)
    }

    func stopSearch() {
        scanStopWorkItem?.cancel()
        centralManager?.stopScan()
        if status == .scanning {
            status = discoveredDevices.isEmpty ? .failed("No WakeGuard clocks were found nearby.") : .idle
        }
    }

    func connect(to device: ClockDevice) {
        guard let peripheral = peripheralsByIdentifier[device.id] else {
            status = .failed("That clock is no longer available. Search again to refresh nearby devices.")
            return
        }

        centralManager?.stopScan()
        scanStopWorkItem?.cancel()
        status = .connecting(device.displayName)
        centralManager?.connect(peripheral)
    }

    func disconnect() {
        guard let connectedDevice,
              let peripheral = peripheralsByIdentifier[connectedDevice.id] else {
            status = .disconnected
            self.connectedDevice = nil
            return
        }

        centralManager?.cancelPeripheralConnection(peripheral)
    }

    func syncNow(alarmStore: AlarmStore? = nil) {
        guard let connectedDevice else {
            status = .failed("Connect to your WakeGuard clock before syncing.")
            return
        }

        status = .syncing
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.lastSyncDate = .now
            alarmStore?.markAlarmsSynced()
            self?.status = .connected(connectedDevice.displayName)
        }
    }

    func clearDevelopmentBypass() {
        developmentBypassPairing = false
    }

    private func finishSearchIfNeeded() {
        guard status == .scanning else {
            return
        }

        centralManager?.stopScan()
        status = discoveredDevices.isEmpty ? .failed("No WakeGuard clocks were found nearby.") : .idle
    }

    private func message(for state: CBManagerState) -> String {
        switch state {
        case .unknown:
            return "Bluetooth is starting. Try again in a moment."
        case .resetting:
            return "Bluetooth is resetting. Try again shortly."
        case .unsupported:
            return "This device does not support Bluetooth Low Energy."
        case .unauthorized:
            return "Allow Bluetooth access in Settings to connect to your clock."
        case .poweredOff:
            return "Turn on Bluetooth to connect to your clock."
        case .poweredOn:
            return "Bluetooth is ready."
        @unknown default:
            return "Bluetooth is unavailable."
        }
    }

    private func shouldShowPeripheral(name: String?) -> Bool {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        let normalizedName = name.lowercased()
        return normalizedName.contains("wakeguard")
            || normalizedName.contains("hm-10")
            || normalizedName.contains("hmsoft")
            || normalizedName.contains("clock")
    }
}

extension BluetoothClockService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if status == .bluetoothUnavailable("Bluetooth is ready.") {
                status = .idle
            }
        case .unknown, .resetting:
            status = .bluetoothUnavailable(message(for: central.state))
        case .unsupported, .unauthorized, .poweredOff:
            status = .bluetoothUnavailable(message(for: central.state))
            discoveredDevices.removeAll()
            connectedDevice = nil
        @unknown default:
            status = .bluetoothUnavailable("Bluetooth is unavailable.")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? ""

        guard shouldShowPeripheral(name: name) else {
            return
        }

        peripheralsByIdentifier[peripheral.identifier] = peripheral
        let device = ClockDevice(
            id: peripheral.identifier,
            name: name,
            signalStrength: RSSI.intValue,
            lastSeen: .now
        )

        if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices[index] = device
        } else {
            discoveredDevices.append(device)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let device = ClockDevice(
            id: peripheral.identifier,
            name: peripheral.name ?? "WakeGuard Clock",
            signalStrength: nil,
            lastSeen: .now
        )
        connectedDevice = device
        status = .connected(device.displayName)
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        status = .failed(error?.localizedDescription ?? "Unable to connect to that clock.")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedDevice = nil
        if let error {
            status = .failed("Clock disconnected: \(error.localizedDescription)")
        } else {
            status = .disconnected
        }
    }
}

extension BluetoothClockService: CBPeripheralDelegate {}
