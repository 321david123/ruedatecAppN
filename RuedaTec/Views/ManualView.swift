import SwiftUI

struct ManualView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.rtBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    connectionSection
                    controlsSection
                    eyeControlSection
                    voiceSection
                    voiceCommandsTable
                    speedSection
                    brakeSection
                    safetySection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header
    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.rtTextSecondary)
                }
            }
            .padding(.top, 8)

            HStack(spacing: 10) {
                Image(systemName: "book.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.rtAccent)
                Text("Manual de uso")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.rtTextPrimary)
            }
        }
    }

    // MARK: - Sections
    private var connectionSection: some View {
        manualSection(
            icon: "antenna.radiowaves.left.and.right",
            title: "Conexión",
            items: [
                "Enciende tu silla RuedaTec y asegúrate de que el LED Bluetooth esté parpadeando.",
                "En la pantalla de inicio, pulsa \"Buscar dispositivos\".",
                "Selecciona \"RuedaTecPro\" de la lista de dispositivos encontrados.",
                "Espera a que el indicador cambie a verde (conectado).",
                "La próxima vez, usa la tarjeta de \"Reconexión rápida\": la app recuerda tu silla.",
                "Si la conexión se pierde, la app intenta reconectarse sola (puedes desactivarlo en Ajustes)."
            ]
        )
    }

    private var controlsSection: some View {
        manualSection(
            icon: "gamecontroller.fill",
            title: "Controles de dirección",
            items: [
                "Elige entre Pad direccional o Joystick con el selector sobre el área de control.",
                "Pad: toca y mantén presionada la dirección deseada. Suelta para detenerte.",
                "Joystick: arrastra la perilla hacia donde quieras ir. Al soltarla, la silla se detiene.",
                "Las diagonales (↗ ↖ ↘ ↙) permiten giros suaves mientras avanzas o retrocedes.",
                "Con \"Velocidad proporcional\" (Ajustes), alejar la perilla del centro acelera la silla."
            ]
        )
    }

    private var eyeControlSection: some View {
        manualSection(
            icon: "eye.fill",
            title: "Control por la mirada",
            items: [
                "Activa el seguimiento ocular de iOS en Ajustes › Accesibilidad › Seguimiento ocular (requiere iPhone con Face ID y iOS 18 o superior). Sigue la calibración en pantalla.",
                "En el selector de control elige el modo «Ojos». La pantalla cambia a botones grandes y una retícula sencilla.",
                "Mira una flecha de dirección: al mantener la mirada, iOS la activa y la silla avanza un impulso en esa dirección.",
                "Mira el botón central «ALTO» para detenerte. La mirada en reposo al centro mantiene la silla quieta.",
                "Para seguir avanzando, vuelve a mirar la flecha. Ajusta velocidad y freno con los botones grandes de abajo.",
                "Consejo: activa también el micrófono para tener «alto» por voz como paro adicional."
            ]
        )
    }

    private var voiceSection: some View {
        manualSection(
            icon: "mic.fill",
            title: "Control por voz",
            items: [
                "Pulsa el botón del micrófono en el panel de control para activar la escucha.",
                "Di un comando de movimiento: la silla se mueve durante unos segundos y se detiene sola (configurable en Ajustes).",
                "Di «alto», «para» o «stop» para detenerte de inmediato: siempre tiene prioridad.",
                "Para retroceder di «atrás» (no «para atrás»: la palabra «para» detiene la silla).",
                "Combina direcciones: di «adelante» y luego «izquierda» para ir en diagonal.",
                "La app confirma cada comando con voz (puedes silenciarla en Ajustes)."
            ]
        )
    }

    private var voiceCommandsTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble.fill")
                    .foregroundColor(.rtAccent)
                Text("Comandos de voz")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.rtTextPrimary)
            }

            VStack(spacing: 0) {
                voiceCommandRow("«Adelante» / «Avanza»", "Mover hacia adelante")
                voiceCommandRow("«Atrás» / «Retrocede»", "Mover hacia atrás")
                voiceCommandRow("«Izquierda» / «Derecha»", "Girar")
                voiceCommandRow("«Alto» / «Para» / «Stop»", "Detener ya")
                voiceCommandRow("«Freno»", "Activar freno total")
                voiceCommandRow("«Quitar freno»", "Desactivar freno")
                voiceCommandRow("«Velocidad 5»", "Fijar velocidad (1–9)")
                voiceCommandRow("«Más rápido» / «Más lento»", "Subir o bajar velocidad")
                voiceCommandRow("«Emergencia»", "Paro de emergencia + freno", isLast: true)
            }
            .background(Color.rtSurface.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .rtCard()
    }

    private func voiceCommandRow(_ command: String, _ action: String, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text(command)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.rtAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(action)
                    .font(.system(size: 13))
                    .foregroundColor(.rtTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            if !isLast {
                Divider().background(Color.rtBorder)
            }
        }
    }

    private var speedSection: some View {
        manualSection(
            icon: "speedometer",
            title: "Control de velocidad",
            items: [
                "La barra de segmentos ajusta la velocidad de 1 (mínima) a 9 (máxima).",
                "Comienza con una velocidad baja hasta familiarizarte con los controles.",
                "La velocidad se aplica inmediatamente al cambiar el valor.",
                "En Ajustes puedes definir la velocidad inicial al conectar."
            ]
        )
    }

    private var brakeSection: some View {
        manualSection(
            icon: "lock.fill",
            title: "Freno y paro de emergencia",
            items: [
                "El botón \"FRENO\" activa el freno total de ambos motores.",
                "Con el freno activo, ningún comando de movimiento tendrá efecto.",
                "El botón rojo \"PARO\" detiene la silla Y activa el freno en un solo toque.",
                "También puedes sacudir el teléfono con fuerza para disparar el paro de emergencia."
            ]
        )
    }

    private var safetySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.rtWarning)
                Text("Seguridad")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.rtWarning)
            }

            VStack(alignment: .leading, spacing: 8) {
                safetyItem("Mantén siempre el teléfono al alcance mientras usas la silla.")
                safetyItem("Si pierdes la conexión Bluetooth, la silla se detiene automáticamente. Si el freno estaba activado, permanece activado.")
                safetyItem("Si la app pasa a segundo plano o el teléfono se bloquea, la silla se detiene.")
                safetyItem("Los comandos de voz de movimiento se detienen solos tras unos segundos.")
                safetyItem("Verifica que el área esté despejada antes de moverte.")
                safetyItem("No uses la app mientras caminas o en situaciones de riesgo.")
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.rtWarning.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.rtWarning.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Helpers
    private func manualSection(icon: String, title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.rtAccent)
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.rtTextPrimary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.rtAccent)
                            .frame(width: 22, height: 22)
                            .background(Color.rtAccent.opacity(0.15))
                            .clipShape(Circle())

                        Text(item)
                            .font(.system(size: 14))
                            .foregroundColor(.rtTextSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .rtCard()
    }

    private func safetyItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.rtWarning)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.rtTextSecondary)
                .lineSpacing(3)
        }
    }
}
