import SwiftUI

struct SpeedControlView: View {
    let speed: Int
    let onSpeedChanged: (Int) -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(1...9, id: \.self) { level in
                    speedSegment(level)
                }
            }
            .frame(height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack {
                Text("Lenta")
                    .font(.system(size: 11))
                    .foregroundColor(.rtTextSecondary)
                Spacer()
                Text("Rápida")
                    .font(.system(size: 11))
                    .foregroundColor(.rtTextSecondary)
            }
            .padding(.horizontal, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Velocidad")
        .accessibilityValue("\(speed) de 9")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSpeedChanged(min(9, speed + 1))
            case .decrement: onSpeedChanged(max(1, speed - 1))
            @unknown default: break
            }
        }
    }

    private func speedSegment(_ level: Int) -> some View {
        let isActive = level <= speed
        let isSelected = level == speed

        return Button {
            onSpeedChanged(level)
            Haptics.tap(.light)
        } label: {
            ZStack {
                Rectangle()
                    .fill(segmentColor(level: level, active: isActive))

                if isSelected {
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                }

                Text("\(level)")
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundColor(isActive ? Color.rtBackground : Color.rtTextSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func segmentColor(level: Int, active: Bool) -> Color {
        guard active else { return Color.rtSurface }
        let fraction = Double(level) / 9.0
        if fraction < 0.4 {
            return Color.rtAccent.opacity(0.6 + fraction)
        } else if fraction < 0.7 {
            return Color.rtWarning.opacity(0.6 + fraction * 0.4)
        } else {
            return Color.rtDanger.opacity(0.6 + fraction * 0.3)
        }
    }
}
