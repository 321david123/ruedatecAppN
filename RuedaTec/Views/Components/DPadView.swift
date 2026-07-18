import SwiftUI

struct DPadView: View {
    let activeDirection: DriveDirection?
    var size: CGFloat = 270
    /// Se invoca en cada evento de arrastre (aunque la dirección no cambie):
    /// así el toque reclama la propiedad del movimiento aunque la voz ya
    /// hubiera puesto la misma dirección.
    let onDirectionChanged: (DriveDirection?) -> Void

    private var buttonSize: CGFloat { size * 0.222 }
    private var deadZone: CGFloat { size * 0.104 }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.rtCard)
                .overlay(
                    Circle()
                        .stroke(Color.rtBorder, lineWidth: 1)
                )

            ForEach(DriveDirection.allCases, id: \.self) { direction in
                directionArrow(direction)
            }

            Circle()
                .fill(activeDirection == nil ? Color.rtSurface : Color.rtAccent.opacity(0.2))
                .frame(width: size * 0.185, height: size * 0.185)
                .overlay(
                    Circle()
                        .stroke(activeDirection == nil ? Color.rtBorder : Color.rtAccent.opacity(0.5), lineWidth: 1.5)
                )
                .overlay(
                    Image(systemName: activeDirection?.icon ?? "circle.fill")
                        .font(.system(size: activeDirection == nil ? 10 : 18, weight: .medium))
                        .foregroundColor(activeDirection == nil ? Color.rtTextSecondary : .rtAccent)
                )
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let center = CGPoint(x: size / 2, y: size / 2)
                    let newDirection = resolveDirection(from: value.location, center: center)
                    if newDirection != activeDirection, newDirection != nil {
                        Haptics.tap(.light)
                    }
                    onDirectionChanged(newDirection)
                }
                .onEnded { _ in
                    onDirectionChanged(nil)
                }
        )
        .accessibilityLabel("Pad direccional")
        .accessibilityHint("Mantén presionada una dirección para mover la silla")
    }

    // MARK: - Arrow Buttons
    private func directionArrow(_ direction: DriveDirection) -> some View {
        let isActive = activeDirection == direction
        let radius = (size - buttonSize) / 2 - size * 0.037
        let angleRad = (direction.angle - 90) * .pi / 180
        let x = size / 2 + radius * CGFloat(cos(angleRad))
        let y = size / 2 + radius * CGFloat(sin(angleRad))

        return ZStack {
            Circle()
                .fill(isActive ? Color.rtAccent : Color.rtSurface)
                .frame(width: buttonSize, height: buttonSize)
                .shadow(color: isActive ? Color.rtAccent.opacity(0.4) : .clear, radius: 8)

            Image(systemName: direction.icon)
                .font(.system(size: buttonSize * 0.33, weight: .semibold))
                .foregroundColor(isActive ? Color.rtBackground : Color.rtTextSecondary)
        }
        .position(x: x, y: y)
        .animation(.easeOut(duration: 0.1), value: isActive)
    }

    // MARK: - Direction Resolution
    private func resolveDirection(from point: CGPoint, center: CGPoint) -> DriveDirection? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)

        guard distance > deadZone else { return nil }

        var angle = atan2(dx, -dy) * 180 / .pi
        if angle < 0 { angle += 360 }

        let sector = Int((angle + 22.5).truncatingRemainder(dividingBy: 360) / 45)
        let directions: [DriveDirection] = [
            .forward, .forwardRight, .right, .backRight,
            .back, .backLeft, .left, .forwardLeft
        ]
        return directions[sector]
    }
}
