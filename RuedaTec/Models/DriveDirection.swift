import Foundation

/// Las 8 direcciones de movimiento de la silla.
/// Cada una corresponde a un comando de un carácter del protocolo RuedaTec.
enum DriveDirection: CaseIterable {
    case forward, forwardRight, right, backRight
    case back, backLeft, left, forwardLeft

    var command: Character {
        switch self {
        case .forward:      return "F"
        case .back:         return "B"
        case .left:         return "L"
        case .right:        return "R"
        case .forwardLeft:  return "G"
        case .forwardRight: return "I"
        case .backLeft:     return "H"
        case .backRight:    return "J"
        }
    }

    var label: String {
        switch self {
        case .forward:      return "Adelante"
        case .back:         return "Atrás"
        case .left:         return "Izquierda"
        case .right:        return "Derecha"
        case .forwardLeft:  return "↖ Adelante-Izq"
        case .forwardRight: return "↗ Adelante-Der"
        case .backLeft:     return "↙ Atrás-Izq"
        case .backRight:    return "↘ Atrás-Der"
        }
    }

    /// Palabra corta que se pronuncia como confirmación por voz.
    var spokenConfirmation: String {
        switch self {
        case .forward:      return "Adelante"
        case .back:         return "Atrás"
        case .left:         return "Izquierda"
        case .right:        return "Derecha"
        case .forwardLeft:  return "Adelante izquierda"
        case .forwardRight: return "Adelante derecha"
        case .backLeft:     return "Atrás izquierda"
        case .backRight:    return "Atrás derecha"
        }
    }

    var icon: String {
        switch self {
        case .forward:      return "arrow.up"
        case .back:         return "arrow.down"
        case .left:         return "arrow.left"
        case .right:        return "arrow.right"
        case .forwardLeft:  return "arrow.up.left"
        case .forwardRight: return "arrow.up.right"
        case .backLeft:     return "arrow.down.left"
        case .backRight:    return "arrow.down.right"
        }
    }

    /// Ángulo desde el centro (0° = arriba/adelante, sentido horario)
    var angle: Double {
        switch self {
        case .forward:      return 0
        case .forwardRight: return 45
        case .right:        return 90
        case .backRight:    return 135
        case .back:         return 180
        case .backLeft:     return 225
        case .left:         return 270
        case .forwardLeft:  return 315
        }
    }

    /// Combina dos direcciones cardinales en una diagonal (p. ej. voz: "adelante" + "izquierda").
    static func combining(_ a: DriveDirection, _ b: DriveDirection) -> DriveDirection? {
        let pair = Set([a, b])
        if pair == [.forward, .left]  { return .forwardLeft }
        if pair == [.forward, .right] { return .forwardRight }
        if pair == [.back, .left]     { return .backLeft }
        if pair == [.back, .right]    { return .backRight }
        return nil
    }
}
