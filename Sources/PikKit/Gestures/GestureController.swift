import Combine
import Foundation

/// Detector de gestos: con la opción activada, mira la cámara y ejecuta la acción del gesto guardado que reconozca
/// (iniciar con Pik en reposo; pausar/reanudar y detener mientras graba).
public final class GestureController {
    public static let shared = GestureController()

    public var onAction: (GestureAction) -> Void = { _ in }

    private let owner = "detector"
    private let lock = NSLock()
    private var trigger = GestureTrigger()
    private var phase: RecordingPhase = .idle
    private var templates: [GestureTemplate] = []
    private var sensitivity = 1.0
    private var suspended = 0
    private var wanted = false
    private var running = false

    /// El detector necesita saber en qué fase está la grabación para elegir qué gestos valen.
    public func update(phase: RecordingPhase) { lock.lock(); self.phase = phase; lock.unlock(); reconcile() }
    public func update(templates: [GestureTemplate], sensitivity: Double) { lock.lock(); self.templates = templates; self.sensitivity = sensitivity; lock.unlock() }
    public func setEnabled(_ on: Bool) { lock.lock(); wanted = on; lock.unlock(); reconcile() }

    /// La pantalla de grabar un gesto pausa el detector para que no dispare acciones mientras ensayás.
    public func suspend() { lock.lock(); suspended += 1; trigger = GestureTrigger(); lock.unlock() }
    public func resume() { lock.lock(); suspended = max(0, suspended - 1); lock.unlock() }

    private func reconcile() {
        lock.lock()
        let should = wanted && !templates.isEmpty
        let was = running
        running = should
        lock.unlock()
        if should, !was {
            HandGestureService.shared.request(owner: owner, deviceID: Preferences.shared.cameraDeviceID) { [weak self] in self?.handle($0) }
        } else if !should, was {
            HandGestureService.shared.release(owner: owner)
        }
    }

    private func relevant(_ phase: RecordingPhase) -> Set<GestureAction> {
        switch phase {
        case .idle, .armed: return [.start]
        case .recording, .paused: return [.pause, .stop]
        default: return []
        }
    }

    /// Hilo de vídeo, ~10 veces por segundo.
    private func handle(_ shape: HandShape?) {
        lock.lock()
        let active = relevant(phase), tpls = templates.filter { active.contains($0.action) }, sens = sensitivity, paused = suspended > 0
        var match: GestureTemplate?
        if !paused, let shape { match = GestureMatcher.best(for: shape, in: tpls, sensitivity: sens) }
        let fired = paused ? nil : trigger.feed(match)
        lock.unlock()
        guard let fired else { return }
        DispatchQueue.main.async { [weak self] in self?.onAction(fired.action) }
    }
}
