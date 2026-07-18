import SwiftUI

/// Barras de intensidad de señal Bluetooth (estilo cobertura de celular).
struct SignalBarsView: View {
    let rssi: Int?

    private var bars: Int {
        guard let rssi else { return 0 }
        switch rssi {
        case (-55)...: return 4
        case (-67)...: return 3
        case (-80)...: return 2
        default:       return 1
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(bar <= bars ? barColor : Color.rtSurface)
                    .frame(width: 3, height: 4 + CGFloat(bar) * 3)
            }
        }
        .accessibilityLabel("Señal Bluetooth")
        .accessibilityValue(rssi != nil ? "\(bars) de 4 barras" : "sin señal")
    }

    private var barColor: Color {
        switch bars {
        case 4, 3: return .rtSuccess
        case 2:    return .rtWarning
        default:   return .rtDanger
        }
    }
}

/// Indicador de batería reportada por el firmware (si hay telemetría).
struct BatteryIndicatorView: View {
    let level: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: batteryIcon)
                .font(.system(size: 13))
                .foregroundColor(batteryColor)
            Text("\(level)%")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.rtTextSecondary)
        }
        .accessibilityLabel("Batería de la silla")
        .accessibilityValue("\(level) por ciento")
    }

    private var batteryIcon: String {
        switch level {
        case 80...: return "battery.100"
        case 55...: return "battery.75"
        case 30...: return "battery.50"
        case 12...: return "battery.25"
        default:    return "battery.0"
        }
    }

    private var batteryColor: Color {
        switch level {
        case 30...: return .rtSuccess
        case 12...: return .rtWarning
        default:    return .rtDanger
        }
    }
}

/// Animación de radar durante el escaneo BLE.
struct RadarView: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<3) { index in
                Circle()
                    .stroke(Color.rtAccent.opacity(0.5), lineWidth: 1.5)
                    .scaleEffect(animate ? 2.2 : 0.4)
                    .opacity(animate ? 0 : 0.7)
                    .animation(
                        .easeOut(duration: 2.0)
                        .repeatForever(autoreverses: false)
                        .delay(Double(index) * 0.65),
                        value: animate
                    )
            }
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 22))
                .foregroundColor(.rtAccent)
        }
        .frame(width: 70, height: 70)
        .onAppear { animate = true }
    }
}

/// Cronómetro de tiempo conectado.
struct ConnectionTimerView: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            Text(formatted(timeline.date.timeIntervalSince(since)))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.rtTextSecondary)
        }
    }

    private func formatted(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
