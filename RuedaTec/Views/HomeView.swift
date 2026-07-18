import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var settings: SettingsStore
    @State private var showControls = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.rtBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        headerSection

                        switch bluetooth.bluetoothState {
                        case .poweredOff:
                            bluetoothOffCard
                        case .unauthorized:
                            bluetoothUnauthorizedCard
                        default:
                            connectionCard
                            if !bluetooth.isConnected, bluetooth.lastKnownDeviceName != nil {
                                reconnectCard
                            }
                            if !bluetooth.discoveredDevices.isEmpty {
                                devicesSection
                            }
                            if bluetooth.isConnected {
                                goToControlsButton
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.rtAccent)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .navigationDestination(isPresented: $showControls) {
                ControlsView()
            }
            .onChange(of: bluetooth.isConnected) { connected in
                if connected {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showControls = true
                    }
                }
            }
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 8) {
            if bluetooth.isScanning {
                RadarView()
                    .padding(.bottom, 4)
            } else {
                Image(systemName: "figure.roll")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.rtAccent, .rtAccentDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.bottom, 4)
                    .frame(width: 70, height: 70)
            }

            Text("RuedaTec")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.rtTextPrimary)

            Text("Control de movilidad inteligente")
                .font(.system(size: 15))
                .foregroundColor(.rtTextSecondary)
        }
        .padding(.vertical, 16)
    }

    // MARK: - Bluetooth State Cards
    private var bluetoothOffCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 32))
                .foregroundColor(.rtWarning)
            Text("Bluetooth apagado")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.rtTextPrimary)
            Text("Activa Bluetooth en el Centro de Control o en Ajustes para conectarte a tu silla.")
                .font(.system(size: 14))
                .foregroundColor(.rtTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .rtCard()
    }

    private var bluetoothUnauthorizedCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 32))
                .foregroundColor(.rtWarning)
            Text("Bluetooth no autorizado")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.rtTextPrimary)
            Text("RuedaTec necesita permiso de Bluetooth para controlar tu silla.")
                .font(.system(size: 14))
                .foregroundColor(.rtTextSecondary)
                .multilineTextAlignment(.center)
            Button("Abrir Ajustes") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(RTButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .rtCard()
    }

    // MARK: - Connection Card
    private var connectionCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                statusDot
                VStack(alignment: .leading, spacing: 2) {
                    Text(bluetooth.isConnected ? "Conectado" : "Sin conexión")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.rtTextPrimary)
                    Text(bluetooth.statusMessage)
                        .font(.system(size: 13))
                        .foregroundColor(.rtTextSecondary)
                }
                Spacer()
                if bluetooth.isConnected {
                    SignalBarsView(rssi: bluetooth.rssi)
                }
            }

            if bluetooth.isConnected {
                Button("Desconectar") {
                    bluetooth.disconnect()
                }
                .buttonStyle(RTButtonStyle(isPrimary: false))
            } else {
                Button {
                    bluetooth.startScan()
                } label: {
                    HStack(spacing: 8) {
                        if bluetooth.isScanning {
                            ProgressView()
                                .tint(Color.rtBackground)
                        }
                        Text(bluetooth.isScanning ? "Buscando…" : "Buscar dispositivos")
                    }
                }
                .buttonStyle(RTButtonStyle())
                .disabled(bluetooth.isScanning || bluetooth.bluetoothState != .poweredOn)
            }
        }
        .rtCard()
    }

    private var statusDot: some View {
        Circle()
            .fill(bluetooth.isConnected ? Color.rtSuccess : Color.rtDanger)
            .frame(width: 12, height: 12)
            .shadow(color: (bluetooth.isConnected ? Color.rtSuccess : Color.rtDanger).opacity(0.6), radius: 4)
    }

    // MARK: - Quick Reconnect
    private var reconnectCard: some View {
        Button {
            bluetooth.reconnectToLastDevice()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18))
                    .foregroundColor(.rtAccent)
                    .frame(width: 36, height: 36)
                    .background(Color.rtAccent.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(bluetooth.lastKnownDeviceName ?? "Último dispositivo")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.rtTextPrimary)
                    Text("Reconexión rápida")
                        .font(.system(size: 12))
                        .foregroundColor(.rtTextSecondary)
                }

                Spacer()

                if bluetooth.isReconnecting {
                    ProgressView()
                        .tint(.rtAccent)
                } else {
                    Text("Conectar")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.rtAccent)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.rtCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.rtAccent.opacity(0.35), lineWidth: 1)
                    )
            )
        }
        .disabled(bluetooth.isReconnecting)
    }

    // MARK: - Devices List
    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dispositivos encontrados")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.rtTextSecondary)
                .padding(.leading, 4)

            VStack(spacing: 1) {
                ForEach(bluetooth.discoveredDevices) { device in
                    deviceRow(device)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func deviceRow(_ device: BluetoothManager.DiscoveredDevice) -> some View {
        Button {
            bluetooth.connect(to: device)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: device.advertisesRuedaTecService ? "figure.roll" : "antenna.radiowaves.left.and.right")
                    .font(.system(size: 18))
                    .foregroundColor(.rtAccent)
                    .frame(width: 36, height: 36)
                    .background(Color.rtAccent.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(device.name)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.rtTextPrimary)
                        if device.advertisesRuedaTecService {
                            Text("RuedaTec")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.rtBackground)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.rtAccent))
                        }
                    }
                    Text(signalDescription(device.rssi))
                        .font(.system(size: 12))
                        .foregroundColor(.rtTextSecondary)
                }

                Spacer()

                SignalBarsView(rssi: device.rssi)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.rtTextSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.rtCard)
        }
    }

    private func signalDescription(_ rssi: Int) -> String {
        switch rssi {
        case -50...0: return "Señal excelente"
        case -70 ..< -50: return "Señal buena"
        case -85 ..< -70: return "Señal media"
        default: return "Señal débil"
        }
    }

    // MARK: - Controls Button
    private var goToControlsButton: some View {
        Button {
            showControls = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gamecontroller.fill")
                Text("Ir a Controles")
            }
        }
        .buttonStyle(RTButtonStyle())
        .padding(.top, 8)
    }
}
