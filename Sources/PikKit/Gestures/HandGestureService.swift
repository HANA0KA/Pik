import AVFoundation
import Combine
import Foundation
import Vision

/// Cámara + Vision: entrega la forma de la mano (una sola) unas 10 veces por segundo. Se enciende cuando alguien
/// la pide (detector de gestos o pantalla de grabar un gesto) y se apaga cuando nadie la necesita.
public final class HandGestureService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    public static let shared = HandGestureService()

    /// Última forma detectada (nil = no hay mano). Publicada en el hilo principal.
    @Published public private(set) var liveShape: HandShape?
    @Published public private(set) var isRunning = false
    @Published public private(set) var failure: String?

    public let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "pik.hand.vision", qos: .userInitiated)
    private var owners = Set<String>()
    private var consumers: [String: (HandShape?) -> Void] = [:]   // se llaman en la cola de vídeo
    private var lastFrame = Date.distantPast
    private let frameInterval: TimeInterval = 0.1
    private var configuredDeviceID: String?

    private static let joints: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip,
    ]

    private override init() {
        super.init()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
    }

    /// Pide la cámara para `owner`; `onShape` recibe cada cuadro analizado (hilo de vídeo).
    public func request(owner: String, deviceID: String?, onShape: ((HandShape?) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            self.owners.insert(owner)
            if let onShape { self.consumers[owner] = onShape }
            self.startIfNeeded(deviceID: deviceID)
        }
    }

    public func release(owner: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.owners.remove(owner)
            self.consumers[owner] = nil
            if self.owners.isEmpty, self.session.isRunning {
                self.session.stopRunning()
                DispatchQueue.main.async { self.isRunning = false; self.liveShape = nil }
            }
        }
    }

    private func startIfNeeded(deviceID: String?) {
        guard Permissions.shared.isGranted(.camera) else {
            DispatchQueue.main.async { self.failure = t("Allow camera access to use gestures.", "Permití el acceso a la cámara para usar gestos.") }
            return
        }
        guard let device = DeviceCatalog.camera(id: deviceID) else {
            DispatchQueue.main.async { self.failure = t("No camera found.", "No se encontró una cámara.") }
            return
        }
        if session.isRunning, configuredDeviceID == device.uniqueID { return }
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        for i in session.inputs { session.removeInput(i) }
        if !session.outputs.contains(output), session.canAddOutput(output) { session.addOutput(output) }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
        } catch {
            plogError("Gestos: no se pudo abrir la cámara \(device.localizedName): \(error.localizedDescription)")
        }
        session.commitConfiguration()
        configuredDeviceID = device.uniqueID
        if !session.isRunning { session.startRunning() }
        plog("Gestos: cámara activa (\(device.localizedName))")
        DispatchQueue.main.async { self.isRunning = true; self.failure = nil }
    }

    // MARK: Cuadros

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastFrame) >= frameInterval else { return }
        lastFrame = now
        let shape = Self.detect(in: sampleBuffer)
        for c in consumers.values { c(shape) }
        DispatchQueue.main.async { self.liveShape = shape }
    }

    static func detect(in sampleBuffer: CMSampleBuffer) -> HandShape? {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil, let obs = request.results?.first,
              let all = try? obs.recognizedPoints(.all) else { return nil }
        var pts: [CGPoint] = []
        for j in joints {
            guard let p = all[j], p.confidence > 0.3 else { return nil }     // mano a medias: mejor no adivinar
            pts.append(p.location)
        }
        return HandShape(points: pts, isLeft: obs.chirality == .left)
    }
}
