import SwiftUI

/// Modo de control por la mirada.
///
/// Aprovecha el **Seguimiento ocular integrado de iOS** (Ajustes >
/// Accesibilidad > Seguimiento ocular, iOS 18+): el sistema calibra la mirada
/// del usuario, mueve un puntero y, con el Control de permanencia (Dwell),
/// "toca" el elemento que se mira de forma sostenida. Esta vista solo aporta
/// lo que ese sistema necesita: objetivos GRANDES, muy contrastados, bien
/// separados y una retícula espacial (mira hacia donde quieres ir).
///
/// Modelo de seguridad idéntico al de la voz: cada permanencia = un IMPULSO
/// que mueve la silla unos segundos y se detiene solo. El centro es ALTO, así
/// que la mirada en reposo (al centro) mantiene la silla quieta. Mirar una
/// flecha de nuevo la vuelve a impulsar.
///
/// El diseño de objetivos grandes también lo hace ideal para control por
/// interruptor (Switch Control) o para dedos con poca precisión.
struct EyeControlView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var voice: VoiceControlManager
    @AppStorage("eyeControlHintDismissed") private var hintDismissed = false

    @State private var brakeHintUntil = Date.distantPast

    /// Duración del impulso de movimiento por mirada.
    private var pulseDuration: TimeInterval { max(1.4, settings.voiceMoveDuration) }

    // Distribución de la retícula 3×3: 8 direcciones + ALTO al centro.
    private let grid: [[DriveDirection?]] = [
        [.forwardLeft, .forward, .forwardRight],
        [.left,        nil,      .right],
        [.backLeft,    .back,    .backRight]
    ]

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            VStack(spacing: 12) {
                if !hintDismissed {
                    setupBanner
                }
                header
                if landscape {
                    HStack(spacing: 16) {
                        movementGrid(side: min(geo.size.height - 120, geo.size.width * 0.52))
                        secondaryControls(vertical: true)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    movementGrid(side: min(geo.size.width, geo.size.height * 0.55))
                    secondaryControls(vertical: false)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Setup Banner
    private var setupBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "eye.fill")
                .foregroundColor(.rtAccent)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text("Control por la mirada")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.rtTextPrimary)
                Text("Actívalo en Ajustes › Accesibilidad › Seguimiento ocular. Luego mira una flecha para avanzar y mira el centro (ALTO) para detenerte.")
                    .font(.system(size: 12))
                    .foregroundColor(.rtTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    Button("Abrir Ajustes") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.rtAccent)
                    Button("Entendido") {
                        withAnimation { hintDismissed = true }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.rtTextSecondary)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.rtCard)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.rtAccent.opacity(0.35), lineWidth: 1))
        )
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(bluetooth.isConnected ? Color.rtSuccess : Color.rtDanger)
                .frame(width: 10, height: 10)
            Text(bluetooth.connectedDevice?.name ?? "RuedaTec")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.rtTextPrimary)
                .lineLimit(1)
            SignalBarsView(rssi: bluetooth.rssi)
            if let battery = bluetooth.batteryLevel {
                BatteryIndicatorView(level: battery)
            }
            Spacer()
            micButton
            modeToggle
        }
    }

    private var micButton: some View {
        Button {
            voice.toggle()
        } label: {
            Image(systemName: voice.isListening ? "mic.fill" : "mic")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(voice.isListening ? .white : .rtAccent)
                .frame(width: 40, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(voice.isListening ? Color.rtDanger : Color.rtAccent.opacity(0.15))
                )
        }
        .accessibilityLabel(voice.isListening ? "Detener voz" : "Activar voz")
    }

    private var modeToggle: some View {
        HStack(spacing: 2) {
            ForEach(SettingsStore.ControlMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { settings.controlMode = mode }
                    Haptics.tap(.light)
                } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(settings.controlMode == mode ? .rtBackground : .rtTextSecondary)
                        .frame(width: 36, height: 30)
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
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.rtSurface))
    }

    // MARK: - Movement Grid
    private func movementGrid(side: CGFloat) -> some View {
        let spacing: CGFloat = 8
        let cell = max(64, (side - spacing * 2) / 3)
        return VStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<3, id: \.self) { col in
                        gridCell(grid[row][col], size: cell)
                    }
                }
            }
        }
        .frame(width: cell * 3 + spacing * 2, height: cell * 3 + spacing * 2)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func gridCell(_ direction: DriveDirection?, size: CGFloat) -> some View {
        if let direction {
            directionCell(direction, size: size)
        } else {
            stopCell(size: size)
        }
    }

    private func directionCell(_ direction: DriveDirection, size: CGFloat) -> some View {
        let isActive = bluetooth.activeDirection == direction
        return Button {
            triggerMove(direction)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(isActive ? Color.rtAccent : Color.rtCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(isActive ? Color.clear : Color.rtBorder, lineWidth: 1.5)
                    )
                Image(systemName: direction.icon)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundColor(isActive ? .rtBackground : .rtAccent)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(direction.label)
        .accessibilityHint("Mira aquí para mover la silla en esta dirección")
    }

    private func stopCell(size: CGFloat) -> some View {
        Button {
            bluetooth.setDirection(nil)
            Haptics.tap(.heavy)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.rtDanger)
                    .shadow(color: Color.rtDanger.opacity(0.4), radius: 8)
                VStack(spacing: 2) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: size * 0.3, weight: .bold))
                    Text("ALTO")
                        .font(.system(size: max(13, size * 0.16), weight: .heavy))
                }
                .foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Detener")
        .accessibilityHint("Mira aquí para detener la silla")
    }

    private func triggerMove(_ direction: DriveDirection) {
        if bluetooth.brakeActive {
            withAnimation { brakeHintUntil = Date().addingTimeInterval(2.5) }
            Haptics.warning()
            return
        }
        bluetooth.pulseMove(direction, duration: pulseDuration)
    }

    private var showBrakeHint: Bool { Date() < brakeHintUntil }

    // MARK: - Secondary Controls
    @ViewBuilder
    private func secondaryControls(vertical: Bool) -> some View {
        let speedRow = HStack(spacing: 10) {
            bigActionButton(icon: "minus", label: "Lento", tint: .rtAccent) {
                bluetooth.setSpeed(bluetooth.currentSpeed - 1)
            }
            VStack(spacing: 0) {
                Text("\(bluetooth.currentSpeed)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.rtAccent)
                Text("Velocidad")
                    .font(.system(size: 11))
                    .foregroundColor(.rtTextSecondary)
            }
            .frame(maxWidth: .infinity)
            bigActionButton(icon: "plus", label: "Rápido", tint: .rtAccent) {
                bluetooth.setSpeed(bluetooth.currentSpeed + 1)
            }
        }

        let safetyRow = HStack(spacing: 10) {
            bigActionButton(
                icon: bluetooth.brakeActive ? "lock.fill" : "lock.open.fill",
                label: bluetooth.brakeActive ? "Freno ✓" : "Freno",
                tint: .rtWarning,
                filled: bluetooth.brakeActive
            ) {
                bluetooth.setBrake(!bluetooth.brakeActive)
            }
            bigActionButton(icon: "exclamationmark.octagon.fill", label: "Paro", tint: .rtDanger, filled: true) {
                bluetooth.emergencyStop()
            }
        }

        VStack(spacing: 10) {
            if showBrakeHint {
                Text("Desactiva el freno para moverte")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.rtWarning)
                    .transition(.opacity)
            }
            if vertical {
                speedRow
                safetyRow
            } else {
                speedRow
                safetyRow
            }
        }
        .frame(maxWidth: vertical ? 320 : .infinity)
    }

    private func bigActionButton(
        icon: String,
        label: String,
        tint: Color,
        filled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            Haptics.tap(.medium)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold))
                Text(label)
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundColor(filled ? .white : tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(filled ? tint : tint.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(tint, lineWidth: filled ? 0 : 1.5)
                    )
            )
        }
        .accessibilityLabel(label)
    }
}
