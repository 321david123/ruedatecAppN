import SwiftUI

extension Color {
    static let rtBackground = Color(hex: "0D1117")
    static let rtCard = Color(hex: "161B22")
    static let rtSurface = Color(hex: "21262D")
    static let rtBorder = Color(hex: "30363D")
    static let rtAccent = Color(hex: "00C9A7")
    static let rtAccentDark = Color(hex: "00A88A")
    static let rtDanger = Color(hex: "F85149")
    static let rtWarning = Color(hex: "D29922")
    static let rtTextPrimary = Color(hex: "F0F6FC")
    static let rtTextSecondary = Color(hex: "8B949E")
    static let rtSuccess = Color(hex: "3FB950")

    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleaned.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct RTButtonStyle: ButtonStyle {
    var isPrimary: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(isPrimary ? .rtBackground : .rtAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isPrimary ? Color.rtAccent : Color.rtAccent.opacity(0.12))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct RTCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.rtCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.rtBorder, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func rtCard() -> some View {
        modifier(RTCardModifier())
    }
}
