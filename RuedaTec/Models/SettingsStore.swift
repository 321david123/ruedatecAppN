import Foundation
import Combine

/// Preferencias del usuario, persistidas en UserDefaults.
/// Se usan @Published + didSet en lugar de @AppStorage porque @AppStorage
/// dentro de un ObservableObject no notifica cambios de forma fiable.
final class SettingsStore: ObservableObject {

    enum ControlMode: String, CaseIterable, Identifiable {
        case dpad, joystick, eyeControl
        var id: String { rawValue }
        var label: String {
            switch self {
            case .dpad:       return "Pad"
            case .joystick:   return "Joystick"
            case .eyeControl: return "Ojos"
            }
        }
        var icon: String {
            switch self {
            case .dpad:       return "dpad.fill"
            case .joystick:   return "circle.circle.fill"
            case .eyeControl: return "eye.fill"
            }
        }
    }

    // MARK: - Control
    @Published var controlMode: ControlMode {
        didSet { defaults.set(controlMode.rawValue, forKey: Keys.controlMode) }
    }
    @Published var defaultSpeed: Int {
        didSet { defaults.set(defaultSpeed, forKey: Keys.defaultSpeed) }
    }
    @Published var proportionalSpeed: Bool {
        didSet { defaults.set(proportionalSpeed, forKey: Keys.proportionalSpeed) }
    }
    @Published var keepScreenAwake: Bool {
        didSet { defaults.set(keepScreenAwake, forKey: Keys.keepScreenAwake) }
    }
    @Published var shakeToStop: Bool {
        didSet { defaults.set(shakeToStop, forKey: Keys.shakeToStop) }
    }

    // MARK: - Voz
    @Published var voiceConfirmations: Bool {
        didSet { defaults.set(voiceConfirmations, forKey: Keys.voiceConfirmations) }
    }
    /// Duración (segundos) de un impulso de movimiento por voz antes del auto-paro.
    @Published var voiceMoveDuration: Double {
        didSet { defaults.set(voiceMoveDuration, forKey: Keys.voiceMoveDuration) }
    }
    /// Si está activo, los comandos de voz de movimiento NO se detienen solos.
    /// Desactivado por defecto por seguridad.
    @Published var voiceContinuousMovement: Bool {
        didSet { defaults.set(voiceContinuousMovement, forKey: Keys.voiceContinuousMovement) }
    }

    // MARK: - Conexión
    @Published var autoReconnect: Bool {
        didSet { defaults.set(autoReconnect, forKey: Keys.autoReconnect) }
    }

    // MARK: - Feedback
    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Keys.hapticsEnabled) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let controlMode = "settings.controlMode"
        static let joystickDefaultMigrated = "settings.joystickDefaultMigrated"
        static let defaultSpeed = "settings.defaultSpeed"
        static let proportionalSpeed = "settings.proportionalSpeed"
        static let keepScreenAwake = "settings.keepScreenAwake"
        static let shakeToStop = "settings.shakeToStop"
        static let voiceConfirmations = "settings.voiceConfirmations"
        static let voiceMoveDuration = "settings.voiceMoveDuration"
        static let voiceContinuousMovement = "settings.voiceContinuousMovement"
        static let autoReconnect = "settings.autoReconnect"
        static let hapticsEnabled = "settings.hapticsEnabled"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // El joystick es el modo predeterminado desde v2.1. La migración se
        // aplica una sola vez para no pisar una elección posterior del usuario.
        if !defaults.bool(forKey: Keys.joystickDefaultMigrated) {
            defaults.set(true, forKey: Keys.joystickDefaultMigrated)
            defaults.set(ControlMode.joystick.rawValue, forKey: Keys.controlMode)
        }
        controlMode = ControlMode(rawValue: defaults.string(forKey: Keys.controlMode) ?? "") ?? .joystick
        // Velocidad mínima conducible = 1: el 0 del protocolo dejaría la silla
        // aceptando comandos sin moverse (estado muerto silencioso).
        defaultSpeed = max(1, min(9, defaults.object(forKey: Keys.defaultSpeed) as? Int ?? 3))
        proportionalSpeed = defaults.object(forKey: Keys.proportionalSpeed) as? Bool ?? false
        keepScreenAwake = defaults.object(forKey: Keys.keepScreenAwake) as? Bool ?? true
        shakeToStop = defaults.object(forKey: Keys.shakeToStop) as? Bool ?? true
        voiceConfirmations = defaults.object(forKey: Keys.voiceConfirmations) as? Bool ?? true
        voiceMoveDuration = defaults.object(forKey: Keys.voiceMoveDuration) as? Double ?? 2.0
        voiceContinuousMovement = defaults.object(forKey: Keys.voiceContinuousMovement) as? Bool ?? false
        autoReconnect = defaults.object(forKey: Keys.autoReconnect) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Keys.hapticsEnabled) as? Bool ?? true
    }
}
