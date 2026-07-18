import Foundation
import CoreMotion

/// Detecta una sacudida fuerte del teléfono para disparar el paro de emergencia.
final class ShakeDetector: ObservableObject {
    private let motionManager = CMMotionManager()
    private var lastTrigger: Date = .distantPast
    private var onShake: (() -> Void)?

    /// Aceleración (en g, sin gravedad) que se considera sacudida.
    private let threshold = 2.7
    /// Tiempo mínimo entre disparos.
    private let cooldown: TimeInterval = 1.5

    func start(onShake: @escaping () -> Void) {
        guard motionManager.isDeviceMotionAvailable else { return }
        self.onShake = onShake
        guard !motionManager.isDeviceMotionActive else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let a = motion.userAcceleration
            let magnitude = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            if magnitude > self.threshold, Date().timeIntervalSince(self.lastTrigger) > self.cooldown {
                self.lastTrigger = Date()
                self.onShake?()
            }
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        onShake = nil
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}
