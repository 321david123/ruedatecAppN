import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var currentPage = 0
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private let pages: [(icon: String, title: String, subtitle: String)] = [
        (
            "figure.roll",
            "Bienvenido a RuedaTec",
            "El control inteligente para tu movilidad. Diseñado para darte libertad y precisión."
        ),
        (
            "antenna.radiowaves.left.and.right",
            "Conecta tu dispositivo",
            "Empareja tu silla RuedaTec vía Bluetooth en segundos. La app la recuerda y se reconecta sola."
        ),
        (
            "gamecontroller.fill",
            "Toma el control",
            "Pad direccional o joystick: tú eliges. Ajusta velocidad, dirección y freno desde tu teléfono."
        ),
        (
            "mic.fill",
            "Habla para moverte",
            "Di «adelante», «izquierda» o «velocidad 5» y la silla obedece. Di «alto» y se detiene al instante."
        ),
        (
            "eye.fill",
            "Controla con la mirada",
            "Con el Seguimiento ocular de iOS puedes conducir con los ojos: mira una flecha para avanzar y el centro para detenerte. Botones grandes, todo más simple."
        ),
        (
            "shield.checkered",
            "Seguridad ante todo",
            "Paro de emergencia siempre visible, auto-paro al perder conexión y sacudida del teléfono para detener la silla."
        )
    ]

    var body: some View {
        ZStack {
            Color.rtBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        onboardingPage(pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)

                pageIndicator
                    .padding(.bottom, verticalSizeClass == .compact ? 12 : 32)

                bottomButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, verticalSizeClass == .compact ? 16 : 48)
            }
        }
    }

    @ViewBuilder
    private func onboardingPage(_ page: (icon: String, title: String, subtitle: String)) -> some View {
        if verticalSizeClass == .compact {
            // Horizontal: icono a la izquierda, texto a la derecha.
            HStack(spacing: 28) {
                pageIcon(page.icon, scale: 0.72)
                VStack(alignment: .leading, spacing: 10) {
                    Text(page.title)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.rtTextPrimary)
                    Text(page.subtitle)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.rtTextSecondary)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 40)
        } else {
            VStack(spacing: 24) {
                Spacer()

                pageIcon(page.icon, scale: 1.0)

                VStack(spacing: 12) {
                    Text(page.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.rtTextPrimary)
                        .multilineTextAlignment(.center)

                    Text(page.subtitle)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.rtTextSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                }

                Spacer()
                Spacer()
            }
        }
    }

    private func pageIcon(_ icon: String, scale: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.rtAccent.opacity(0.1))
                .frame(width: 160 * scale, height: 160 * scale)

            Circle()
                .fill(Color.rtAccent.opacity(0.06))
                .frame(width: 200 * scale, height: 200 * scale)

            Image(systemName: icon)
                .font(.system(size: 56 * scale, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.rtAccent, .rtAccentDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<pages.count, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? Color.rtAccent : Color.rtSurface)
                    .frame(width: index == currentPage ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.25), value: currentPage)
            }
        }
    }

    private var bottomButton: some View {
        Button {
            if currentPage < pages.count - 1 {
                currentPage += 1
            } else {
                onComplete()
            }
        } label: {
            Text(currentPage < pages.count - 1 ? "Siguiente" : "Comenzar")
        }
        .buttonStyle(RTButtonStyle())
    }
}
