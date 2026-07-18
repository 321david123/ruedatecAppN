import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var bluetooth: BluetoothManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                controlSection
                voiceSection
                connectionSection
                feedbackSection
                diagnosticsSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.rtBackground)
            .tint(.rtAccent)
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.rtTextSecondary)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Secciones
    private var controlSection: some View {
        Section {
            Picker("Modo de control", selection: $settings.controlMode) {
                ForEach(SettingsStore.ControlMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.icon).tag(mode)
                }
            }

            Toggle("Velocidad proporcional (joystick)", isOn: $settings.proportionalSpeed)

            Picker("Velocidad inicial", selection: $settings.defaultSpeed) {
                ForEach(1...9, id: \.self) { level in
                    Text("\(level)").tag(level)
                }
            }

            Toggle("Mantener pantalla encendida", isOn: $settings.keepScreenAwake)
            Toggle("Sacudir para paro de emergencia", isOn: $settings.shakeToStop)
        } header: {
            Text("Control")
        } footer: {
            Text("Con velocidad proporcional, alejar la perilla del centro aumenta la velocidad.")
        }
        .listRowBackground(Color.rtCard)
    }

    private var voiceSection: some View {
        Section {
            Toggle("Confirmaciones habladas", isOn: $settings.voiceConfirmations)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Duración del impulso")
                    Spacer()
                    Text(String(format: "%.1f s", settings.voiceMoveDuration))
                        .foregroundColor(.rtTextSecondary)
                        .font(.system(.body, design: .rounded))
                }
                Slider(value: $settings.voiceMoveDuration, in: 1...5, step: 0.5)
            }

            Toggle("Movimiento continuo", isOn: $settings.voiceContinuousMovement)
        } header: {
            Text("Control por voz")
        } footer: {
            if settings.voiceContinuousMovement {
                Label(
                    "Con movimiento continuo la silla NO se detiene sola: debes decir «alto» o usar el paro de emergencia. Úsalo con precaución.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundColor(.rtWarning)
            } else {
                Text("Cada comando de voz mueve la silla durante el impulso configurado y luego se detiene sola.")
            }
        }
        .listRowBackground(Color.rtCard)
    }

    private var connectionSection: some View {
        Section {
            Toggle("Reconexión automática", isOn: $settings.autoReconnect)
            if let name = bluetooth.lastKnownDeviceName {
                HStack {
                    Text("Último dispositivo")
                    Spacer()
                    Text(name)
                        .foregroundColor(.rtTextSecondary)
                }
            }
            if let version = bluetooth.firmwareVersion {
                HStack {
                    Text("Firmware")
                    Spacer()
                    Text("v\(version)")
                        .foregroundColor(.rtTextSecondary)
                }
            }
        } header: {
            Text("Conexión")
        } footer: {
            Text("Si la conexión se pierde de forma inesperada, la app intentará reconectarse sola.")
        }
        .listRowBackground(Color.rtCard)
    }

    private var feedbackSection: some View {
        Section("Respuesta táctil") {
            Toggle("Vibraciones", isOn: $settings.hapticsEnabled)
                .onChange(of: settings.hapticsEnabled) { enabled in
                    Haptics.isEnabled = enabled
                }
        }
        .listRowBackground(Color.rtCard)
    }

    private var diagnosticsSection: some View {
        Section("Diagnóstico") {
            NavigationLink {
                ConsoleView()
            } label: {
                Label("Consola de comandos", systemImage: "terminal.fill")
            }
        }
        .listRowBackground(Color.rtCard)
    }

    private var aboutSection: some View {
        Section("Acerca de") {
            HStack {
                Text("Versión")
                Spacer()
                Text(appVersion)
                    .foregroundColor(.rtTextSecondary)
            }
            HStack {
                Text("Protocolo")
                Spacer()
                Text("Nordic UART (BLE)")
                    .foregroundColor(.rtTextSecondary)
            }
        }
        .listRowBackground(Color.rtCard)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0"
        return version
    }
}
