import SwiftUI

@main
struct RuedaTecApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var bluetooth: BluetoothManager
    @StateObject private var voice: VoiceControlManager
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let settings = SettingsStore()
        let bluetooth = BluetoothManager(settings: settings)
        let voice = VoiceControlManager(bluetooth: bluetooth, settings: settings)
        _settings = StateObject(wrappedValue: settings)
        _bluetooth = StateObject(wrappedValue: bluetooth)
        _voice = StateObject(wrappedValue: voice)
        Haptics.isEnabled = settings.hapticsEnabled
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    HomeView()
                } else {
                    OnboardingView {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            hasCompletedOnboarding = true
                        }
                    }
                }
            }
            .environmentObject(bluetooth)
            .environmentObject(settings)
            .environmentObject(voice)
            .preferredColorScheme(.dark)
            .onChange(of: scenePhase) { phase in
                // Seguridad: si la app deja de estar activa, la silla se detiene
                // y el micrófono se apaga.
                if phase != .active {
                    bluetooth.safetyStop()
                    voice.stop()
                }
            }
        }
    }
}
