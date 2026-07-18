import SwiftUI

struct ControlsView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var voice: VoiceControlManager
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var showManual = false
    @State private var showSettings = false
    @State private var showBrakeHint = false
    @StateObject private var shakeDetector = ShakeDetector()

    var body: some View {
        ZStack {
            Color.rtBackground.ignoresSafeArea()

            if settings.controlMode == .eyeControl {
                EyeControlView()
                    .padding(.horizontal, 16)
            } else {
                GeometryReader { geo in
                    if geo.size.width > geo.size.height {
                        landscapeLayout(geo: geo)
                    } else {
                        portraitLayout(geo: geo)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    bluetooth.setDirection(nil)
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Inicio")
                            .font(.system(size: 16))
                    }
                    .foregroundColor(.rtAccent)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        showManual = true
                    } label: {
                        Image(systemName: "book.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.rtAccent)
                    }
                    .accessibilityLabel("Manual de uso")
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.rtAccent)
                    }
                    .accessibilityLabel("Ajustes")
                }
            }
        }
        .sheet(isPresented: $showManual) {
            ManualView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onChange(of: bluetooth.isConnected) { _ in
            dismissIfDisconnected()
        }
        .onChange(of: bluetooth.isReconnecting) { _ in
            dismissIfDisconnected()
        }
        .onChange(of: bluetooth.brakeActive) { _ in
            updateBrakeHint()
        }
        .onChange(of: settings.shakeToStop) { enabled in
            applyShakeSetting(enabled)
        }
        .onChange(of: settings.keepScreenAwake) { keepAwake in
            UIApplication.shared.isIdleTimerDisabled = keepAwake
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = settings.keepScreenAwake
            applyShakeSetting(settings.shakeToStop)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            shakeDetector.stop()
            voice.stop()
        }
    }

    // MARK: - Layouts
    private func portraitLayout(geo: GeometryProxy) -> some View {
        let surfaceSize = min(270, max(176, geo.size.height - 400))

        return VStack(spacing: 0) {
            topBar
                .padding(.top, 8)

            VoiceControlView(voice: voice)
                .padding(.top, 12)

            Spacer(minLength: 8)

            surfaceWithHint(size: surfaceSize)

            Spacer(minLength: 8)

            speedSection

            Spacer(minLength: 10)

            bottomButtons(compact: false)
                .padding(.bottom, 16)
        }
    }

    /// Horizontal: superficie de control a la derecha (bajo el pulgar),
    /// estado + voz + velocidad + botones de seguridad en columna izquierda.
    private func landscapeLayout(geo: GeometryProxy) -> some View {
        let surfaceSize = min(300, max(170, geo.size.height - 16))

        return HStack(spacing: 20) {
            VStack(spacing: 0) {
                topBar
                    .padding(.top, 4)

                VoiceControlView(voice: voice)
                    .padding(.top, 8)

                Spacer(minLength: 4)

                speedSection

                Spacer(minLength: 4)

                bottomButtons(compact: true)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)

            surfaceWithHint(size: surfaceSize)
                .frame(width: surfaceSize)
                .frame(maxHeight: .infinity)
        }
    }

    private func surfaceWithHint(size: CGFloat) -> some View {
        controlSurface(size: size)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) {
                if showBrakeHint {
                    Text("Desactiva el freno para moverte")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.rtWarning)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.rtWarning.opacity(0.15)))
                        .transition(.opacity)
                }
            }
    }

    private func dismissIfDisconnected() {
        if !bluetooth.isConnected && !bluetooth.isReconnecting {
            dismiss()
        }
    }

    private func applyShakeSetting(_ enabled: Bool) {
        if enabled {
            shakeDetector.start { [weak bluetooth] in
                bluetooth?.emergencyStop()
            }
        } else {
            shakeDetector.stop()
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(bluetooth.isConnected ? Color.rtSuccess : Color.rtDanger)
                .frame(width: 10, height: 10)
                .shadow(color: (bluetooth.isConnected ? Color.rtSuccess : Color.rtDanger).opacity(0.5), radius: 3)

            Text(bluetooth.connectedDevice?.name ?? "RuedaTec")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.rtTextPrimary)
                .lineLimit(1)

            SignalBarsView(rssi: bluetooth.rssi)

            if let battery = bluetooth.batteryLevel {
                BatteryIndicatorView(level: battery)
            }

            Spacer()

            if let direction = bluetooth.activeDirection {
                Text(direction.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.rtAccent)
                    .lineLimit(1)
                    .transition(.opacity)
            } else if let since = bluetooth.connectedSince {
                ConnectionTimerView(since: since)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.rtCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.rtBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Control Surface
    @ViewBuilder
    private func controlSurface(size: CGFloat) -> some View {
        Group {
            switch settings.controlMode {
            case .dpad:
                DPadView(activeDirection: bluetooth.activeDirection, size: size) { direction in
                    setDirectionWithBrakeCheck(direction)
                }
            case .joystick, .eyeControl:
                // .eyeControl se renderiza como EyeControlView antes de llegar
                // aquí; el joystick es el respaldo para cualquier otro caso.
                JoystickView(
                    activeDirection: bluetooth.activeDirection,
                    size: size,
                    proportionalSpeed: settings.proportionalSpeed,
                    onDirectionChanged: { direction in
                        setDirectionWithBrakeCheck(direction)
                    },
                    onSpeedChanged: { level in
                        bluetooth.setSpeed(level)
                    }
                )
            }
        }
        // Alternativa accesible al arrastre: VoiceOver expone impulsos con
        // auto-paro, igual que los comandos de voz.
        .accessibilityAction(named: "Adelante") { accessiblePulse(.forward) }
        .accessibilityAction(named: "Atrás") { accessiblePulse(.back) }
        .accessibilityAction(named: "Izquierda") { accessiblePulse(.left) }
        .accessibilityAction(named: "Derecha") { accessiblePulse(.right) }
        .accessibilityAction(named: "Adelante izquierda") { accessiblePulse(.forwardLeft) }
        .accessibilityAction(named: "Adelante derecha") { accessiblePulse(.forwardRight) }
        .accessibilityAction(named: "Atrás izquierda") { accessiblePulse(.backLeft) }
        .accessibilityAction(named: "Atrás derecha") { accessiblePulse(.backRight) }
        .accessibilityAction(named: "Detener") { bluetooth.setDirection(nil) }
    }

    private func accessiblePulse(_ direction: DriveDirection) {
        if bluetooth.brakeActive {
            updateBrakeHint(force: true)
        }
        bluetooth.pulseMove(direction, duration: settings.voiceMoveDuration)
    }

    private func setDirectionWithBrakeCheck(_ direction: DriveDirection?) {
        if direction != nil && bluetooth.brakeActive {
            updateBrakeHint(force: true)
        }
        bluetooth.setDirection(direction)
    }

    private func updateBrakeHint(force: Bool = false) {
        if force || bluetooth.brakeActive {
            withAnimation { showBrakeHint = bluetooth.brakeActive }
            if force {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation { showBrakeHint = false }
                }
            }
        } else {
            withAnimation { showBrakeHint = false }
        }
    }

    // MARK: - Speed (con selector de modo integrado)
    private var speedSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("Velocidad")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.rtTextSecondary)
                Text("\(bluetooth.currentSpeed)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.rtAccent)

                Spacer()

                modeToggle
            }

            SpeedControlView(speed: bluetooth.currentSpeed) { newSpeed in
                bluetooth.setSpeed(newSpeed)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.rtCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.rtBorder, lineWidth: 1)
                )
        )
    }

    private var modeToggle: some View {
        HStack(spacing: 2) {
            ForEach(SettingsStore.ControlMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        settings.controlMode = mode
                    }
                    Haptics.tap(.light)
                } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(settings.controlMode == mode ? .rtBackground : .rtTextSecondary)
                        .frame(width: 38, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(settings.controlMode == mode ? Color.rtAccent : Color.clear)
                        )
                }
                .accessibilityLabel(mode.label)
                .accessibilityAddTraits(settings.controlMode == mode ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.rtSurface)
        )
    }

    // MARK: - Brake + Emergency Stop
    private func bottomButtons(compact: Bool) -> some View {
        let verticalPadding: CGFloat = compact ? 12 : 18

        return HStack(spacing: 12) {
            // Freno (toggle)
            Button {
                bluetooth.setBrake(!bluetooth.brakeActive)
                Haptics.tap(.heavy)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: bluetooth.brakeActive ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text(bluetooth.brakeActive ? "FRENO ✓" : "FRENO")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(bluetooth.brakeActive ? .white : .rtWarning)
                .frame(maxWidth: .infinity)
                .padding(.vertical, verticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(bluetooth.brakeActive ? Color.rtWarning.opacity(0.85) : Color.rtWarning.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.rtWarning, lineWidth: bluetooth.brakeActive ? 0 : 1.5)
                )
            }
            .accessibilityLabel(bluetooth.brakeActive ? "Desactivar freno" : "Activar freno")

            // Paro de emergencia
            Button {
                bluetooth.emergencyStop()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("PARO")
                        .font(.system(size: 15, weight: .heavy))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, verticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.rtDanger)
                        .shadow(color: Color.rtDanger.opacity(0.35), radius: 8, y: 2)
                )
            }
            .accessibilityLabel("Paro de emergencia")
            .accessibilityHint("Detiene la silla y activa el freno")
        }
    }
}
