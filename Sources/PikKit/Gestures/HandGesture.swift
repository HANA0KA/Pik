import CoreGraphics
import Foundation

/// Acciones que se pueden disparar con un gesto de mano.
public enum GestureAction: String, Codable, CaseIterable, Identifiable {
    case start, pause, stop
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .start: return t("Start recording", "Iniciar grabación")
        case .pause: return t("Pause / resume", "Pausar / reanudar")
        case .stop: return t("Stop recording", "Detener grabación")
        }
    }
    public var symbol: String {
        switch self {
        case .start: return "record.circle"
        case .pause: return "pause.circle"
        case .stop: return "stop.circle"
        }
    }
}

/// Los 21 puntos de una mano (orden de Vision: muñeca, pulgar ×4, índice ×4, medio ×4, anular ×4, meñique ×4).
public struct HandShape: Codable, Equatable {
    public static let jointCount = 21
    /// Posiciones normalizadas de la imagen (0…1), y no de la pantalla: da igual dónde esté la mano en el cuadro.
    public var points: [CGPoint]
    public var isLeft: Bool

    public init(points: [CGPoint], isLeft: Bool) { self.points = points; self.isLeft = isLeft }
    public var isValid: Bool { points.count == Self.jointCount }

    /// Forma independiente de posición, tamaño y giro: se centra en la muñeca, se escala por el tamaño de la palma
    /// y se gira para que muñeca → base del dedo medio apunte hacia arriba.
    public struct Normalized {
        public let points: [CGPoint]
        /// Giro original de la mano en grados (−180…180; 0 = dedos hacia arriba).
        public let tilt: Double
    }

    public func normalized() -> Normalized? {
        guard isValid else { return nil }
        let wrist = points[0], middleBase = points[9]
        let dx = Double(middleBase.x - wrist.x), dy = Double(middleBase.y - wrist.y)
        let palm = hypot(dx, dy)
        guard palm > 1e-4 else { return nil }
        let angle = atan2(dy, dx)                         // dirección actual de la palma
        let rot = Double.pi / 2 - angle                   // para llevarla a «arriba»
        let c = cos(rot), s = sin(rot)
        let out = points.map { p -> CGPoint in
            let x = Double(p.x - wrist.x) / palm, y = Double(p.y - wrist.y) / palm
            return CGPoint(x: x * c - y * s, y: x * s + y * c)
        }
        var tilt = (angle - Double.pi / 2) * 180 / .pi
        while tilt > 180 { tilt -= 360 }
        while tilt < -180 { tilt += 360 }
        return Normalized(points: out, tilt: tilt)
    }
}

/// Un gesto guardado por el usuario.
public struct GestureTemplate: Codable, Identifiable, Equatable {
    public var id: UUID
    public var action: GestureAction
    public var shape: HandShape
    public var createdAt: Date

    public init(id: UUID = UUID(), action: GestureAction, shape: HandShape, createdAt: Date = Date()) {
        self.id = id; self.action = action; self.shape = shape; self.createdAt = createdAt
    }
}

public enum GestureMatcher {
    /// Distancia media entre las dos formas (en unidades de palma). 0 = idénticas.
    public static func distance(_ a: HandShape, _ b: HandShape) -> Double? {
        guard a.isLeft == b.isLeft, let na = a.normalized(), let nb = b.normalized() else { return nil }
        var sum = 0.0
        for i in 0..<HandShape.jointCount { sum += hypot(Double(na.points[i].x - nb.points[i].x), Double(na.points[i].y - nb.points[i].y)) }
        return sum / Double(HandShape.jointCount)
    }

    /// Diferencia de giro de la mano en grados (0…180).
    public static func tiltDifference(_ a: HandShape, _ b: HandShape) -> Double? {
        guard let na = a.normalized(), let nb = b.normalized() else { return nil }
        var d = abs(na.tilt - nb.tilt)
        if d > 180 { d = 360 - d }
        return d
    }

    /// Umbrales: forma (unidades de palma) y giro permitido (grados).
    public static let maxShapeDistance = 0.22
    public static let maxTilt = 40.0

    public static func matches(_ live: HandShape, _ template: HandShape, sensitivity: Double = 1) -> Bool {
        guard let d = distance(live, template), let tilt = tiltDifference(live, template) else { return false }
        return d <= maxShapeDistance * sensitivity && tilt <= maxTilt
    }

    /// El gesto guardado más parecido (si alguno cumple los umbrales).
    public static func best(for live: HandShape, in templates: [GestureTemplate], sensitivity: Double = 1) -> GestureTemplate? {
        templates.compactMap { tpl -> (GestureTemplate, Double)? in
            guard matches(live, tpl.shape, sensitivity: sensitivity), let d = distance(live, tpl.shape) else { return nil }
            return (tpl, d)
        }.min { $0.1 < $1.1 }?.0
    }

    /// Promedia varios cuadros de la misma pose. Devuelve nil si la mano se movió demasiado (pose inestable).
    public static func average(_ shapes: [HandShape], maxSpread: Double = 0.12) -> HandShape? {
        guard let first = shapes.first, shapes.count >= 5, shapes.allSatisfy({ $0.isValid && $0.isLeft == first.isLeft }) else { return nil }
        // Se promedian las formas ya normalizadas (en el mismo marco) y se reconstruye como una mano «mirando arriba».
        let norms = shapes.compactMap { $0.normalized() }
        guard norms.count == shapes.count else { return nil }
        var mean = [CGPoint](repeating: .zero, count: HandShape.jointCount)
        for n in norms { for i in 0..<HandShape.jointCount { mean[i].x += n.points[i].x / Double(norms.count); mean[i].y += n.points[i].y / Double(norms.count) } }
        let tilts = norms.map(\.tilt)
        let meanTilt = tilts.reduce(0, +) / Double(tilts.count)
        let spread = norms.map { n -> Double in
            (0..<HandShape.jointCount).reduce(0.0) { $0 + hypot(Double(n.points[$1].x - mean[$1].x), Double(n.points[$1].y - mean[$1].y)) } / Double(HandShape.jointCount)
        }.max() ?? 1
        guard spread <= maxSpread, tilts.allSatisfy({ abs($0 - meanTilt) < 25 }) else { return nil }
        // Se deshace la normalización con el giro medio: la palma queda con su inclinación original.
        let rot = (meanTilt) * Double.pi / 180
        let c = cos(rot), s = sin(rot)
        let pts = mean.map { p -> CGPoint in CGPoint(x: Double(p.x) * c - Double(p.y) * s, y: Double(p.x) * s + Double(p.y) * c) }
        return HandShape(points: pts, isLeft: first.isLeft)
    }
}

/// Exige que el gesto se mantenga unos cuadros seguidos y evita repeticiones.
struct GestureTrigger {
    let holdFrames: Int
    let cooldown: TimeInterval
    private var streakID: UUID?
    private var streak = 0
    private var lastFire = Date.distantPast

    init(holdFrames: Int = 8, cooldown: TimeInterval = 2.5) { self.holdFrames = holdFrames; self.cooldown = cooldown }

    /// Llamar una vez por cuadro con el gesto reconocido (o nil). Devuelve el gesto cuando se completa la espera.
    mutating func feed(_ match: GestureTemplate?, now: Date = Date()) -> GestureTemplate? {
        guard let match else { streakID = nil; streak = 0; return nil }
        if match.id == streakID { streak += 1 } else { streakID = match.id; streak = 1 }
        guard streak >= holdFrames, now.timeIntervalSince(lastFire) >= cooldown else { return nil }
        lastFire = now; streak = 0
        return match
    }
}
