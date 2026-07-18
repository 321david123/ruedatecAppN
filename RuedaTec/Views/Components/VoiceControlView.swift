import SwiftUI

/// Panel compacto de control por voz: botón de micrófono, forma de onda,
/// transcripción en vivo y último comando ejecutado.
struct VoiceControlView: View {
    @ObservedObject var voice: VoiceControlManager

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                micButton

                if voice.isListening {
                    WaveformView(level: voice.audioLevel)
                        .frame(height: 30)

                    Spacer(minLength: 0)

                    if let action = voice.lastAction {
                        Text(action)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.rtBackground)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.rtAccent))
                            .transition(.scale.combined(with: .opacity))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Control por voz")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.rtTextPrimary)
                        Text("Di «adelante», «alto», «velocidad 5»…")
                            .font(.system(size: 12))
                            .foregroundColor(.rtTextSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }

            if voice.isListening {
                Text(voice.transcript.isEmpty ? "Escuchando…" : voice.transcript)
                    .font(.system(size: 12))
                    .foregroundColor(.rtTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 16)
                    .transition(.opacity)
            }

            if voice.permissionDenied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Permite el micrófono y el reconocimiento de voz en Ajustes", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.rtWarning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.rtCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(voice.isListening ? Color.rtAccent.opacity(0.6) : Color.rtBorder, lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.2), value: voice.isListening)
        .animation(.easeInOut(duration: 0.2), value: voice.lastAction)
    }

    private var micButton: some View {
        Button {
            voice.toggle()
        } label: {
            ZStack {
                if voice.isListening {
                    Circle()
                        .fill(Color.rtDanger.opacity(0.25))
                        .frame(width: 52, height: 52)
                        .modifier(PulseEffect())
                }

                Circle()
                    .fill(voice.isListening ? Color.rtDanger : Color.rtAccent)
                    .frame(width: 44, height: 44)

                Image(systemName: voice.isListening ? "mic.fill" : "mic")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(voice.isListening ? .white : .rtBackground)
            }
        }
        .accessibilityLabel(voice.isListening ? "Detener control por voz" : "Activar control por voz")
    }
}

// MARK: - Waveform
struct WaveformView: View {
    let level: Double
    @State private var phase = 0.0

    private let barCount = 12

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    let wave = 0.4 + 0.6 * abs(sin(time * 5 + Double(index) * 0.7))
                    let height = 4 + CGFloat(level * wave) * 26
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.rtAccent)
                        .frame(width: 3, height: max(4, height))
                }
            }
        }
    }
}

// MARK: - Pulse Effect
struct PulseEffect: ViewModifier {
    @State private var animate = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(animate ? 1.35 : 1.0)
            .opacity(animate ? 0.0 : 0.8)
            .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: animate)
            .onAppear { animate = true }
    }
}
