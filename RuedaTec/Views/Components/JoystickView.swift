import SwiftUI

/// Joystick virtual: arrastra la perilla en cualquier dirección.
/// Si `proportionalSpeed` está activo, la distancia al centro modula la velocidad.
struct JoystickView: View {
    let activeDirection: DriveDirection?
    var size: CGFloat = 270
    let proportionalSpeed: Bool
    /// Se invoca en cada evento de arrastre (aunque la dirección no cambie):
    /// así el toque reclama la propiedad del movimiento frente a la voz.
    let onDirectionChanged: (DriveDirection?) -> Void
    let onSpeedChanged: (Int) -> Void

    @State private var thumbOffset: CGSize = .zero
    @State private var lastProportionalLevel: Int?

    private var thumbSize: CGFloat { size * 0.33 }
    private let deadZoneFraction: CGFloat = 0.22

    private var maxRadius: CGFloat { (size - thumbSize) / 2 }

    var body: some View {
        ZStack {
            // Base
            Circle()
                .fill(Color.rtCard)
                .overlay(
                    Circle().stroke(Color.rtBorder, lineWidth: 1)
                )

            // Marcas de dirección
            ForEach(DriveDirection.allCases, id: \.self) { direction in
                tickMark(direction)
            }

            // Anillo de zona muerta
            Circle()
                .stroke(Color.rtBorder.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                .frame(width: size * deadZoneFraction * 2, height: size * deadZoneFraction * 2)

            // Perilla
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: activeDirection == nil
                                ? [Color.rtSurface, Color.rtCard]
                                : [Color.rtAccent, Color.rtAccentDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: activeDirection == nil ? .black.opacity(0.3) : Color.rtAccent.opacity(0.5), radius: 10)

                Image(systemName: activeDirection?.icon ?? "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: thumbSize * 0.28, weight: .semibold))
                    .foregroundColor(activeDirection == nil ? Color.rtTextSecondary : Color.rtBackground)
            }
            .frame(width: thumbSize, height: thumbSize)
            .overlay(
                Circle().stroke(Color.rtBorder, lineWidth: activeDirection == nil ? 1 : 0)
            )
            .offset(thumbOffset)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: thumbOffset == .zero)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    handleDrag(value)
                }
                .onEnded { _ in
                    thumbOffset = .zero
                    lastProportionalLevel = nil
                    onDirectionChanged(nil)
                }
        )
        .accessibilityLabel("Joystick")
        .accessibilityHint("Arrastra la perilla para mover la silla; suéltala para detenerte")
    }

    private func handleDrag(_ value: DragGesture.Value) {
        let center = CGPoint(x: size / 2, y: size / 2)
        let dx = value.location.x - center.x
        let dy = value.location.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        let clampedDistance = min(distance, maxRadius)

        if distance > 0 {
            thumbOffset = CGSize(
                width: dx / distance * clampedDistance,
                height: dy / distance * clampedDistance
            )
        }

        let deadZone = size * deadZoneFraction

        guard distance > deadZone else {
            onDirectionChanged(nil)
            return
        }

        // Dirección por ángulo (8 sectores)
        var angle = atan2(dx, -dy) * 180 / .pi
        if angle < 0 { angle += 360 }
        let sector = Int((angle + 22.5).truncatingRemainder(dividingBy: 360) / 45)
        let directions: [DriveDirection] = [
            .forward, .forwardRight, .right, .backRight,
            .back, .backLeft, .left, .forwardLeft
        ]
        let newDirection = directions[sector]

        // Velocidad proporcional a la distancia (niveles 1…9)
        if proportionalSpeed {
            let fraction = (clampedDistance - deadZone) / (maxRadius - deadZone)
            let level = max(1, min(9, 1 + Int(fraction * 8)))
            if level != lastProportionalLevel {
                lastProportionalLevel = level
                onSpeedChanged(level)
            }
        }

        if newDirection != activeDirection {
            Haptics.tap(.light)
        }
        onDirectionChanged(newDirection)
    }

    private func tickMark(_ direction: DriveDirection) -> some View {
        let radius = size / 2 - size * 0.067
        let angleRad = (direction.angle - 90) * .pi / 180
        let x = size / 2 + radius * CGFloat(cos(angleRad))
        let y = size / 2 + radius * CGFloat(sin(angleRad))
        let isActive = activeDirection == direction

        return Image(systemName: direction.icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(isActive ? .rtAccent : .rtTextSecondary.opacity(0.5))
            .position(x: x, y: y)
            .animation(.easeOut(duration: 0.1), value: isActive)
    }
}
