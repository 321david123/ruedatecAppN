import Foundation
import CoreBluetooth
import Combine

final class BluetoothManager: NSObject, ObservableObject {

    // MARK: - Nordic UART Service UUIDs
    static let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let rxUUID      = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") // write to ESP32
    static let txUUID      = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") // notify from ESP32

    /// Origen de un comando de movimiento. El toque siempre puede quitarle
    /// el control a la voz; la voz nunca se lo quita al toque.
    enum MoveSource {
        case touch, voice
    }

    // MARK: - Published State
    @Published var bluetoothState: CBManagerState = .unknown
    @Published var isScanning = false
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var connectedDevice: CBPeripheral?
    @Published var isConnected = false
    @Published var isReconnecting = false
    @Published var statusMessage = "Desconectado"
    @Published var lastReceivedMessage: String?

    /// Dirección de movimiento activa (táctil o por voz). Única fuente de verdad.
    @Published private(set) var activeDirection: DriveDirection?
    @Published private(set) var movementSource: MoveSource?
    @Published var brakeActive = false
    @Published var currentSpeed = 3

    /// Intensidad de señal en dBm, actualizada periódicamente mientras hay conexión.
    @Published var rssi: Int?
    @Published var connectedSince: Date?

    /// Telemetría opcional del firmware v2 (si el hardware la reporta).
    @Published var batteryLevel: Int?
    @Published var firmwareVersion: String?

    /// Registro de comandos/eventos para la consola de diagnóstico.
    @Published var log: [LogEntry] = []

    /// Nombre del último dispositivo conectado (para reconexión rápida).
    @Published var lastKnownDeviceName: String?

    // MARK: - Types
    struct DiscoveredDevice: Identifiable, Equatable {
        let id: UUID
        let peripheral: CBPeripheral
        let name: String
        var rssi: Int
        var advertisesRuedaTecService: Bool

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    }

    struct LogEntry: Identifiable {
        enum Kind { case sent, received, event }
        let id = UUID()
        let date: Date
        let kind: Kind
        let text: String
    }

    // MARK: - Private
    private var centralManager: CBCentralManager!
    private var writeCharacteristic: CBCharacteristic?
    private var scanTimer: Timer?
    private var keepaliveTimer: Timer?
    private var rssiTimer: Timer?
    private var connectTimeoutTimer: Timer?
    private var reconnectWorkItem: DispatchWorkItem?
    private var touchPulseWorkItem: DispatchWorkItem?
    private var lastKeepaliveSend = Date.distantPast
    private var lastStopSend = Date.distantPast
    private var reconnectAttempts = 0
    private var userInitiatedDisconnect = false
    /// CoreBluetooth exige mantener una referencia fuerte al periférico recuperado.
    private var pendingPeripheral: CBPeripheral?
    private let settings: SettingsStore

    private enum Keys {
        static let lastPeripheralUUID = "ble.lastPeripheralUUID"
        static let lastPeripheralName = "ble.lastPeripheralName"
    }

    /// Intervalo del keepalive: reenvía la dirección activa para que el
    /// watchdog del firmware v2 sepa que la app sigue viva. Inocuo con firmware v1.
    private let keepaliveInterval: TimeInterval = 0.3
    /// Si el keepalive estuvo parado más que esto (run loop bloqueado, etc.),
    /// el firmware ya nos detuvo: no reanudar el movimiento en silencio.
    private let keepaliveStallLimit: TimeInterval = 0.9
    private let connectTimeout: TimeInterval = 10
    private let maxReconnectAttempts = 3

    // MARK: - Init
    init(settings: SettingsStore) {
        self.settings = settings
        super.init()
        lastKnownDeviceName = UserDefaults.standard.string(forKey: Keys.lastPeripheralName)
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Scan
    func startScan() {
        guard centralManager.state == .poweredOn else {
            statusMessage = "Bluetooth no disponible"
            return
        }
        discoveredDevices.removeAll()
        isScanning = true
        statusMessage = "Buscando dispositivos…"
        addLog(.event, "Escaneo iniciado")
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        scanTimer?.invalidate()
        scanTimer = makeTimer(interval: 12, repeats: false) { [weak self] in
            self?.stopScan()
        }
    }

    func stopScan() {
        centralManager.stopScan()
        isScanning = false
        scanTimer?.invalidate()
        statusMessage = discoveredDevices.isEmpty
            ? "No se encontraron dispositivos"
            : "Escaneo completado"
    }

    // MARK: - Connect / Disconnect
    func connect(to device: DiscoveredDevice) {
        stopScan()
        beginConnection(to: device.peripheral, name: device.name, reconnecting: false)
    }

    /// Reconecta al último dispositivo emparejado sin necesidad de escanear.
    func reconnectToLastDevice() {
        guard centralManager.state == .poweredOn,
              let uuidString = UserDefaults.standard.string(forKey: Keys.lastPeripheralUUID),
              let uuid = UUID(uuidString: uuidString) else { return }
        let known = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        guard let peripheral = known.first else {
            statusMessage = "Dispositivo anterior no disponible"
            return
        }
        addLog(.event, "Reconexión rápida")
        beginConnection(
            to: peripheral,
            name: lastKnownDeviceName ?? peripheral.name ?? "dispositivo",
            reconnecting: true
        )
    }

    private func beginConnection(to peripheral: CBPeripheral, name: String, reconnecting: Bool) {
        // Cancela cualquier conexión o intento anterior para no terminar
        // enlazados a dos sillas a la vez.
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        if let current = connectedDevice, current !== peripheral {
            centralManager.cancelPeripheralConnection(current)
        }
        if let pending = pendingPeripheral, pending !== peripheral {
            centralManager.cancelPeripheralConnection(pending)
        }

        userInitiatedDisconnect = false
        if !reconnecting {
            reconnectAttempts = 0
        }
        isReconnecting = reconnecting
        statusMessage = reconnecting ? "Reconectando a \(name)…" : "Conectando a \(name)…"
        addLog(.event, "Conectando a \(name)")
        pendingPeripheral = peripheral
        centralManager.connect(peripheral, options: nil)
        startConnectTimeout()
    }

    private func startConnectTimeout() {
        connectTimeoutTimer?.invalidate()
        connectTimeoutTimer = makeTimer(interval: connectTimeout, repeats: false) { [weak self] in
            guard let self, !self.isConnected, let pending = self.pendingPeripheral else { return }
            self.centralManager.cancelPeripheralConnection(pending)
            self.pendingPeripheral = nil
            self.isReconnecting = false
            self.statusMessage = "No se pudo conectar. ¿La silla está encendida?"
            self.addLog(.event, "Tiempo de conexión agotado")
        }
    }

    func disconnect() {
        guard let peripheral = connectedDevice else { return }
        userInitiatedDisconnect = true
        setDirection(nil)
        sendCommand("S")
        // Pequeña espera para que el "S" salga antes de cortar el enlace.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    // MARK: - Driving API (punto único de control de movimiento)

    /// Cambia la dirección de movimiento. `nil` detiene la silla.
    /// Devuelve `true` si el comando se aplicó. Reglas:
    /// - Con freno activo, los comandos de movimiento se bloquean.
    /// - El toque siempre toma el control; la voz no puede quitárselo al toque.
    @discardableResult
    func setDirection(_ direction: DriveDirection?, source: MoveSource = .touch) -> Bool {
        guard let direction else {
            stopKeepalive()
            let wasMoving = activeDirection != nil
            if wasMoving { activeDirection = nil }
            if movementSource != nil { movementSource = nil }
            touchPulseWorkItem?.cancel()
            // Redundancia defensiva: se reenvía "S" aunque el estado local diga
            // "detenida" (por si firmware y app se desincronizan), pero limitado
            // a 2 Hz para no inundar el enlace desde la zona muerta del pad.
            if wasMoving || Date().timeIntervalSince(lastStopSend) > 0.5 {
                lastStopSend = Date()
                sendCommand("S", logged: wasMoving)
            }
            return true
        }

        if brakeActive {
            Haptics.warning()
            statusMessage = "Freno activado: desactívalo para moverte"
            return false
        }

        if direction == activeDirection {
            // Misma dirección: solo puede cambiar la propiedad del movimiento.
            // La voz no le quita el control a una mano que ya está en el pad.
            if source == .voice && movementSource == .touch {
                return false
            }
            if movementSource != source {
                movementSource = source
            }
            return true
        }

        if source == .voice && movementSource == .touch {
            // El usuario está conduciendo con la mano: se ignora la voz ambiental.
            return false
        }

        activeDirection = direction
        movementSource = source
        sendCommand(String(direction.command))
        startKeepalive()
        return true
    }

    /// Impulso de movimiento con auto-paro (usado por las acciones de
    /// accesibilidad de VoiceOver).
    func pulseMove(_ direction: DriveDirection, duration: TimeInterval) {
        guard setDirection(direction, source: .touch) else { return }
        touchPulseWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.activeDirection == direction {
                self.setDirection(nil)
            }
        }
        touchPulseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    func setSpeed(_ speed: Int) {
        // 1 es el mínimo conducible; el 0 del protocolo dejaría la silla
        // "moviéndose" sin moverse (estado muerto silencioso).
        let clamped = max(1, min(9, speed))
        currentSpeed = clamped
        sendCommand("\(clamped)")
    }

    func setBrake(_ active: Bool) {
        brakeActive = active
        if active {
            setDirection(nil)
        }
        sendCommand(active ? "W" : "w")
    }

    /// Paro de emergencia: detiene el movimiento Y activa el freno total.
    func emergencyStop() {
        stopKeepalive()
        activeDirection = nil
        movementSource = nil
        touchPulseWorkItem?.cancel()
        brakeActive = true
        sendCommand("S")
        sendCommand("W")
        addLog(.event, "PARO DE EMERGENCIA")
        Haptics.error()
    }

    /// Paro silencioso al pasar a segundo plano (no activa el freno).
    func safetyStop() {
        guard isConnected else { return }
        stopKeepalive()
        activeDirection = nil
        movementSource = nil
        touchPulseWorkItem?.cancel()
        sendCommand("S")
        addLog(.event, "Paro de seguridad (app en segundo plano)")
    }

    func sendCommand(_ command: String, logged: Bool = true) {
        guard let characteristic = writeCharacteristic,
              let peripheral = connectedDevice,
              let data = command.data(using: .utf8) else { return }
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        if logged {
            addLog(.sent, command)
        }
    }

    func clearLog() {
        log.removeAll()
    }

    // MARK: - Timers
    /// Timer registrado en modo .common: sigue disparando mientras el usuario
    /// arrastra un ScrollView (el modo .default se congela durante el tracking,
    /// lo que mataría el keepalive en pleno movimiento).
    private func makeTimer(interval: TimeInterval, repeats: Bool, block: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { _ in block() }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    // MARK: - Keepalive
    private func startKeepalive() {
        keepaliveTimer?.invalidate()
        lastKeepaliveSend = Date()
        keepaliveTimer = makeTimer(interval: keepaliveInterval, repeats: true) { [weak self] in
            guard let self, let direction = self.activeDirection else { return }
            let now = Date()
            if now.timeIntervalSince(self.lastKeepaliveSend) > self.keepaliveStallLimit {
                // El hilo estuvo bloqueado: el watchdog del firmware ya detuvo
                // la silla. No reanudar el movimiento en silencio.
                self.setDirection(nil)
                self.statusMessage = "Movimiento detenido por seguridad"
                self.addLog(.event, "Keepalive interrumpido: paro de seguridad")
                return
            }
            self.lastKeepaliveSend = now
            self.sendCommand(String(direction.command), logged: false)
        }
    }

    private func stopKeepalive() {
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
    }

    // MARK: - RSSI
    private func startRSSIMonitoring() {
        rssiTimer?.invalidate()
        rssiTimer = makeTimer(interval: 2.0, repeats: true) { [weak self] in
            self?.connectedDevice?.readRSSI()
        }
        connectedDevice?.readRSSI()
    }

    private func stopRSSIMonitoring() {
        rssiTimer?.invalidate()
        rssiTimer = nil
        rssi = nil
    }

    // MARK: - Helpers
    private func addLog(_ kind: LogEntry.Kind, _ text: String) {
        log.append(LogEntry(date: Date(), kind: kind, text: text))
        if log.count > 300 {
            log.removeFirst(log.count - 300)
        }
    }

    private func cleanupAfterDisconnect() {
        stopKeepalive()
        stopRSSIMonitoring()
        connectTimeoutTimer?.invalidate()
        touchPulseWorkItem?.cancel()
        isConnected = false
        connectedDevice = nil
        writeCharacteristic = nil
        activeDirection = nil
        movementSource = nil
        brakeActive = false
        connectedSince = nil
        batteryLevel = nil
        firmwareVersion = nil
    }

    /// Limpieza total cuando el adaptador deja de estar disponible
    /// (apagado, reinicio de bluetoothd, permiso revocado…).
    private func cleanupAdapterUnavailable() {
        scanTimer?.invalidate()
        isScanning = false
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        isReconnecting = false
        pendingPeripheral = nil
        cleanupAfterDisconnect()
    }

    private func handleReceivedMessage(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastReceivedMessage = trimmed
        addLog(.received, trimmed)

        if trimmed.hasPrefix("BAT:"), let value = Int(trimmed.dropFirst(4)) {
            batteryLevel = max(0, min(100, value))
        } else if trimmed.hasPrefix("RT:") {
            firmwareVersion = String(trimmed.dropFirst(3))
        } else if trimmed.hasPrefix("BRK:") {
            // El firmware v2 conserva el freno tras una desconexión;
            // sincroniza el estado real al reconectar.
            brakeActive = trimmed.dropFirst(4) == "1"
        } else if trimmed == "WDG" {
            // El watchdog del firmware detuvo los motores: aceptar ese estado.
            // Si dejáramos activeDirection puesto, el keepalive relanzaría la
            // silla solo, sin que nadie lo pida.
            stopKeepalive()
            activeDirection = nil
            movementSource = nil
            statusMessage = "Movimiento detenido por seguridad (watchdog)"
            sendCommand("S")
            Haptics.warning()
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        switch central.state {
        case .poweredOn:
            statusMessage = "Bluetooth listo"
        case .poweredOff:
            statusMessage = "Bluetooth apagado"
            cleanupAdapterUnavailable()
        case .unauthorized:
            statusMessage = "Bluetooth no autorizado"
            cleanupAdapterUnavailable()
        case .unsupported:
            statusMessage = "Bluetooth no soportado"
        case .resetting:
            statusMessage = "Bluetooth reiniciándose…"
            cleanupAdapterUnavailable()
        default:
            statusMessage = "Bluetooth no disponible"
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? ""
        guard !name.isEmpty else { return }

        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let isRuedaTec = serviceUUIDs.contains(Self.serviceUUID)

        if let index = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
            discoveredDevices[index].rssi = RSSI.intValue
            if isRuedaTec {
                discoveredDevices[index].advertisesRuedaTecService = true
            }
        } else {
            discoveredDevices.append(
                DiscoveredDevice(
                    id: peripheral.identifier,
                    peripheral: peripheral,
                    name: name,
                    rssi: RSSI.intValue,
                    advertisesRuedaTecService: isRuedaTec
                )
            )
        }
        // Los dispositivos RuedaTec primero, luego por intensidad de señal.
        discoveredDevices.sort {
            if $0.advertisesRuedaTecService != $1.advertisesRuedaTecService {
                return $0.advertisesRuedaTecService
            }
            return $0.rssi > $1.rssi
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Ignora conexiones de periféricos que ya no nos interesan.
        guard peripheral === pendingPeripheral || peripheral === connectedDevice else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        connectTimeoutTimer?.invalidate()
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        connectedDevice = peripheral
        pendingPeripheral = nil
        isConnected = true
        isReconnecting = false
        reconnectAttempts = 0
        connectedSince = Date()
        brakeActive = false
        writeCharacteristic = nil
        statusMessage = "Conectado a \(peripheral.name ?? "dispositivo")"
        addLog(.event, "Conectado a \(peripheral.name ?? "?")")

        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Keys.lastPeripheralUUID)
        UserDefaults.standard.set(peripheral.name ?? "RuedaTec", forKey: Keys.lastPeripheralName)
        lastKnownDeviceName = peripheral.name ?? "RuedaTec"

        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
        startRSSIMonitoring()
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard peripheral === pendingPeripheral else { return }
        connectTimeoutTimer?.invalidate()
        pendingPeripheral = nil

        // Reintenta si fue un intento de reconexión automática.
        if !userInitiatedDisconnect,
           settings.autoReconnect,
           isReconnecting,
           reconnectAttempts < maxReconnectAttempts {
            scheduleReconnect(to: peripheral)
            return
        }

        isReconnecting = false
        statusMessage = "Error al conectar"
        addLog(.event, "Error al conectar")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        // Solo nos afecta la desconexión del periférico activo.
        guard peripheral === connectedDevice || peripheral === pendingPeripheral else { return }
        if peripheral === pendingPeripheral {
            pendingPeripheral = nil
        }
        cleanupAfterDisconnect()
        addLog(.event, "Desconectado")

        // Reconexión automática ante cortes inesperados.
        if !userInitiatedDisconnect,
           settings.autoReconnect,
           error != nil,
           reconnectAttempts < maxReconnectAttempts {
            scheduleReconnect(to: peripheral)
        } else {
            isReconnecting = false
            statusMessage = "Desconectado"
        }
    }

    private func scheduleReconnect(to peripheral: CBPeripheral) {
        reconnectAttempts += 1
        isReconnecting = true
        statusMessage = "Conexión perdida. Reconectando (\(reconnectAttempts)/\(maxReconnectAttempts))…"
        addLog(.event, "Reintento de conexión \(reconnectAttempts)")
        reconnectWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.isConnected else { return }
            self.pendingPeripheral = peripheral
            self.centralManager.connect(peripheral, options: nil)
            self.startConnectTimeout()
        }
        reconnectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === connectedDevice, let services = peripheral.services else { return }
        for service in services where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics([Self.rxUUID, Self.txUUID], for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard peripheral === connectedDevice, let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == Self.rxUUID {
                writeCharacteristic = characteristic
                // Establece la velocidad inicial en cuanto el canal está listo.
                setSpeed(settings.defaultSpeed)
            }
            if characteristic.uuid == Self.txUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard peripheral === connectedDevice,
              characteristic.uuid == Self.txUUID,
              let data = characteristic.value,
              let message = String(data: data, encoding: .utf8) else { return }
        handleReceivedMessage(message)
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard peripheral === connectedDevice, error == nil else { return }
        rssi = RSSI.intValue
    }
}
