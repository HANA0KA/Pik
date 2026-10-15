import AppKit
import AVFoundation
import Combine
import CoreImage
import Vision

public struct CameraFrame {
    public let pixelBuffer: CVPixelBuffer
    public let pts: CMTime
}

/// Cámara: captura, espejo, y efectos de fondo (difuminado / color / imagen) con segmentación de persona.
public final class CameraController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    public static let shared = CameraController()

    @Published public private(set) var isRunning = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var deviceName: String?
    @Published public private(set) var hasFrame = false

    /// Para grabar "solo cámara": recibe cada fotograma ya procesado (cola de fondo).
    public var onFrame: ((CameraFrame) -> Void)?

    private struct Settings {
        var effect: CameraEffect = .none
        var colorHex = "#FF7A1A"
        var imageID: String?
        var mirror = true
    }

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "pik.camera.session")
    private let videoQueue = DispatchQueue(label: "pik.camera.video", qos: .userInteractive)
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let seqHandler = VNSequenceRequestHandler()
    private let segmentation: VNGeneratePersonSegmentationRequest = {
        let r = VNGeneratePersonSegmentationRequest()
        r.qualityLevel = .balanced
        r.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return r
    }()

    private var settings = Settings()
    private let settingsLock = NSLock()
    private var pool: CVPixelBufferPool?
    private var poolSize = CGSize.zero
    private var bgCache: (key: String, image: CIImage)?
    private var sinks: [UUID: (CVPixelBuffer) -> Void] = [:]
    private let sinksLock = NSLock()
    private var currentDeviceID: String?
    private var firstFrameWatchdog: DispatchWorkItem?
    private var restartedOnce = false
    private var bag = Set<AnyCancellable>()
    private var latest: CVPixelBuffer?

    private override init() {
        super.init()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: videoQueue)
        refreshSettings()
        Preferences.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.refreshSettings() } }
            .store(in: &bag)
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] n in
            plogError("Error de ejecución de la cámara: \(String(describing: n.userInfo?[AVCaptureSessionErrorKey]))")
            self?.restart()
        }
        nc.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) { _ in
            plog("Sesión de cámara interrumpida")
        }
        nc.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main) { _ in
            plog("Interrupción de cámara terminada")
        }
    }

    private func refreshSettings() {
        let p = Preferences.shared
        settingsLock.lock()
        settings = Settings(effect: p.cameraEffect, colorHex: p.cameraEffectColorHex, imageID: p.cameraEffectImageID, mirror: p.cameraMirror)
        settingsLock.unlock()
    }

    // MARK: Suscriptores de vista

    public func addSink(_ f: @escaping (CVPixelBuffer) -> Void) -> UUID {
        let id = UUID()
        sinksLock.lock(); sinks[id] = f; sinksLock.unlock()
        return id
    }

    public func removeSink(_ id: UUID) {
        sinksLock.lock(); sinks[id] = nil; sinksLock.unlock()
    }

    public var latestFrame: CVPixelBuffer? {
        sinksLock.lock(); defer { sinksLock.unlock() }
        return latest
    }

    // MARK: Ciclo de vida

    public func start(deviceID: String?, highQuality: Bool = false) {
        guard Permissions.shared.isGranted(.camera) else {
            errorMessage = t("Camera access needed", "Se necesita acceso a la cámara")
            return
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = DeviceCatalog.camera(id: deviceID) else {
                DispatchQueue.main.async { self.errorMessage = t("Connect a camera or choose a different device to continue.", "Conectá una cámara o elegí otro dispositivo para continuar.") }
                return
            }
            if self.session.isRunning, self.currentDeviceID == device.uniqueID { return }
            self.session.beginConfiguration()
            for i in self.session.inputs { self.session.removeInput(i) }
            let preset: AVCaptureSession.Preset = highQuality ? .hd1920x1080 : .hd1280x720
            self.session.sessionPreset = self.session.canSetSessionPreset(preset) ? preset : .high
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) { self.session.addInput(input) }
                else { throw NSError(domain: "Pik", code: 3, userInfo: [NSLocalizedDescriptionKey: t("The selected camera doesn't support this recording setup. Switch devices or quality.", "La cámara elegida no admite esta configuración. Cambiá de dispositivo o calidad.")]) }
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
                plogError("Cámara no pudo abrirse: \(error.localizedDescription)")
                return
            }
            if !self.session.outputs.contains(self.output), self.session.canAddOutput(self.output) {
                self.session.addOutput(self.output)
            }
            self.session.commitConfiguration()
            self.currentDeviceID = device.uniqueID
            self.session.startRunning()
            DispatchQueue.main.async {
                self.errorMessage = nil
                self.isRunning = self.session.isRunning
                self.deviceName = device.localizedName
                self.hasFrame = false
            }
            plog("Cámara iniciada: \(device.localizedName)")
            self.armWatchdog()
        }
    }

    public func stop() {
        firstFrameWatchdog?.cancel()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            self.currentDeviceID = nil
            DispatchQueue.main.async { self.isRunning = false; self.hasFrame = false }
        }
    }

    private func restart() {
        let id = currentDeviceID
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            self.currentDeviceID = nil
            DispatchQueue.main.async { self.start(deviceID: id) }
        }
    }

    private func armWatchdog() {
        firstFrameWatchdog?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self, !self.hasFrame else { return }
            if !self.restartedOnce {
                self.restartedOnce = true
                plog("La cámara no entregó fotogramas; reiniciando")
                self.restart()
            } else {
                self.errorMessage = t("Camera couldn't start", "La cámara no pudo iniciar")
            }
        }
        firstFrameWatchdog = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: w)
    }

    // MARK: Procesamiento

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let src = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        settingsLock.lock(); let s = settings; settingsLock.unlock()

        var image = CIImage(cvPixelBuffer: src)
        let extent = image.extent

        if s.effect != .none, let bg = backgroundImage(for: s, extent: extent, base: image),
           let mask = personMask(src, extent: extent) {
            image = image.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: bg, kCIInputMaskImageKey: mask,
            ])
        }
        if s.mirror {
            image = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1)).transformed(by: CGAffineTransform(translationX: extent.width, y: 0))
        }
        guard let out = makeBuffer(width: Int(extent.width), height: Int(extent.height)) else { return }
        ciContext.render(image, to: out)

        sinksLock.lock()
        latest = out
        let targets = Array(sinks.values)
        sinksLock.unlock()
        if !targets.isEmpty {
            DispatchQueue.main.async { targets.forEach { $0(out) } }
        }
        onFrame?(CameraFrame(pixelBuffer: out, pts: pts))
        if !hasFrame {
            DispatchQueue.main.async {
                self.hasFrame = true
                self.errorMessage = nil
                self.restartedOnce = false
            }
        }
    }

    private func personMask(_ pb: CVPixelBuffer, extent: CGRect) -> CIImage? {
        do {
            try seqHandler.perform([segmentation], on: pb)
        } catch { return nil }
        guard let maskPB = segmentation.results?.first?.pixelBuffer else { return nil }
        var mask = CIImage(cvPixelBuffer: maskPB)
        mask = mask.transformed(by: CGAffineTransform(scaleX: extent.width / mask.extent.width, y: extent.height / mask.extent.height))
        return mask.clampedToExtent().applyingGaussianBlur(sigma: 1.6).cropped(to: extent)
    }

    private func backgroundImage(for s: Settings, extent: CGRect, base: CIImage) -> CIImage? {
        switch s.effect {
        case .none: return nil
        case .blur:
            return base.clampedToExtent().applyingGaussianBlur(sigma: Double(extent.width) / 50).cropped(to: extent)
        case .color:
            let c = Theme.nsColor(hex: s.colorHex).usingColorSpace(.sRGB) ?? .orange
            return CIImage(color: CIColor(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent)).cropped(to: extent)
        case .image:
            guard let id = s.imageID else { return base.clampedToExtent().applyingGaussianBlur(sigma: 14).cropped(to: extent) }
            let key = "\(id)@\(Int(extent.width))x\(Int(extent.height))"
            if let c = bgCache, c.key == key { return c.image }
            guard let cg = BackgroundStore.shared.cgImage(for: id, size: extent.size) else { return nil }
            let ci = CIImage(cgImage: cg)
            bgCache = (key, ci)
            return ci
        }
    }

    private func makeBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let size = CGSize(width: width, height: height)
        if pool == nil || poolSize != size {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ]
            var p: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, [kCVPixelBufferPoolMinimumBufferCountKey as String: 8] as CFDictionary, attrs as CFDictionary, &p)
            pool = p; poolSize = size
        }
        var pb: CVPixelBuffer?
        guard let pool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess else { return nil }
        return pb
    }
}
