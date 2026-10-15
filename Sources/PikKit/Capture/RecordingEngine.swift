import AppKit
import AVFoundation
import CoreMedia
import Foundation

public struct RecordingRequest {
    public var mode: RecordingMode
    public var displayID: CGDirectDisplayID
    public var windowID: CGWindowID?
    public var area: CGRect?                    // Quartz global
    public var micOn: Bool
    public var micDeviceID: String?
    public var systemAudio: Bool
    public var cameraOn: Bool
    public var cameraDeviceID: String?
    public var resolution: VideoResolution
    public var fps: Int
    public var hevc: Bool
    public var hideSystemUI: Bool
    public var hideDesktopIcons: Bool
    public var windowPadding: CGFloat
    public var title: String?
    public var privacy: PrivacyLevel
    public var excludedWindowNumbers: [Int]
    public var overlayWindowNumbers: [Int]

    public init(mode: RecordingMode, displayID: CGDirectDisplayID, prefs: Preferences = .shared) {
        self.mode = mode; self.displayID = displayID
        windowID = nil; area = nil
        micOn = prefs.micEnabled; micDeviceID = prefs.micDeviceID
        systemAudio = prefs.includeSystemAudio
        cameraOn = prefs.cameraEnabled; cameraDeviceID = prefs.cameraDeviceID
        resolution = prefs.resolution; fps = prefs.fps; hevc = prefs.useHEVC
        hideSystemUI = prefs.hideSystemUI; hideDesktopIcons = prefs.hideDesktopIcons
        windowPadding = 0
        title = nil; privacy = prefs.defaultPrivacy
        excludedWindowNumbers = []; overlayWindowNumbers = []
    }
}

/// Orquesta una grabación: captura (pantalla o cámara) + micrófono + audio del sistema → MP4 → biblioteca.
public final class RecordingEngine: ObservableObject {
    public static let shared = RecordingEngine()

    @Published public private(set) var phase: RecordingPhase = .idle
    @Published public private(set) var elapsed: TimeInterval = 0
    @Published public private(set) var lastError: String?

    public private(set) var currentItemID: UUID?
    public private(set) var currentRequest: RecordingRequest?
    public var onUnexpectedStop: ((Error?) -> Void)?

    private let screen = ScreenRecorder()
    private var writer: MovieWriter?
    private var mixer: AudioMixer?
    private var timer: Timer?
    private var startedAt = Date()
    private var pausedAccum: TimeInterval = 0
    private var pauseBegan: Date?
    private var item: LibraryEntry?
    private let library: LibraryStore

    public init(library: LibraryStore = .shared) {
        self.library = library
        screen.onStop = { [weak self] err in
            DispatchQueue.main.async { self?.onUnexpectedStop?(err) }
        }
    }

    /// Solo para capturas de pantalla de pruebas/promoción (`--render-promo`): fija fase y tiempo sin grabar.
    func setPreviewState(phase: RecordingPhase, elapsed: TimeInterval) { self.phase = phase; self.elapsed = elapsed }

    public var isActive: Bool { phase == .recording || phase == .paused || phase == .finishing }

    public static func canRecordMicrophone(_ req: RecordingRequest) -> Bool {
        req.micOn && Permissions.shared.isGranted(.microphone)
    }

    // MARK: Inicio

    public func start(_ req: RecordingRequest) async throws {
        guard !isActive else { return }
        lastError = nil
        currentRequest = req
        let prefs = Preferences.shared
        let title = (req.title?.isEmpty == false ? req.title! : nil) ?? Fmt.defaultTitle()
        let url = Storage.uniqueURL(in: Storage.videosFolder(prefs), baseName: title, ext: "mp4")

        let micOn = Self.canRecordMicrophone(req)
        let sysOn = req.systemAudio && req.mode != .cameraOnly

        // 1) Fuente de video y tamaño de salida
        var plan: ScreenRecorder.Plan?
        var width = 0, height = 0
        if req.mode == .cameraOnly {
            CameraController.shared.start(deviceID: req.cameraDeviceID, highQuality: true)
            let size = try await Self.waitForCameraFrameSize()
            width = size.width; height = size.height
        } else {
            var p = ScreenRecorder.Params(target: .display(req.displayID))
            switch req.mode {
            case .window:
                guard let wid = req.windowID else { throw ScreenRecorderError.windowGone }
                p.target = .window(wid, req.displayID)
            case .custom:
                guard let area = req.area else { throw ScreenRecorderError.noDisplay }
                p.target = .area(area, req.displayID)
            default: break
            }
            p.excludedWindowNumbers = req.excludedWindowNumbers
            p.overlayWindowNumbers = req.overlayWindowNumbers
            p.hideSystemUI = req.hideSystemUI
            p.hideDesktopIcons = req.hideDesktopIcons
            p.resolution = req.resolution
            p.fps = req.fps
            p.systemAudio = sysOn
            p.windowPadding = req.windowPadding
            let made = try await ScreenRecorder.makePlan(p)
            plan = made; width = made.width; height = made.height
        }

        // 2) Escritor + mezclador
        let w = try MovieWriter(config: .init(url: url, width: width, height: height, fps: req.fps, hevc: req.hevc, withAudio: micOn || sysOn))
        try w.start()
        writer = w
        let mx = AudioMixer(hasMic: micOn, hasSystem: sysOn) { samples, frames, pts in
            w.appendAudio(samples: samples, frames: frames, pts: pts)
        }
        mx.noiseSuppression = await MainActor.run { Preferences.shared.noiseSuppression }
        mixer = mx

        // 3) Biblioteca (en progreso, para poder recuperar si la app se cierra)
        var it = LibraryEntry(kind: .video, title: title,
                             filePath: url.path, width: width, height: height, mode: req.mode,
                             hasCamera: req.cameraOn || req.mode == .cameraOnly, hasMic: micOn, hasSystemAudio: sysOn, privacy: req.privacy)
        it.inProgress = true
        item = it
        currentItemID = it.id
        await MainActor.run { self.library.add(it) }

        // 4) Conectar fuentes
        if micOn {
            AudioInputController.shared.start(deviceID: req.micDeviceID)
            AudioInputController.shared.onSampleBuffer = { [weak mx] sb in mx?.pushMic(sb) }
        }
        if req.mode == .cameraOnly {
            CameraController.shared.onFrame = { [weak w] frame in w?.appendVideo(frame.pixelBuffer, pts: frame.pts) }
        } else if let plan {
            screen.onVideo = { [weak w] pb, pts in w?.appendVideo(pb, pts: pts) }
            screen.onSystemAudio = { [weak mx] sb in mx?.pushSystem(sb) }
            do { try await screen.start(plan: plan) }
            catch {
                await teardownAfterFailure()
                throw error
            }
        }

        startedAt = Date(); pausedAccum = 0; pauseBegan = nil; elapsed = 0
        await MainActor.run {
            self.phase = .recording
            self.startTimer()
        }
        plog("Grabando (\(req.mode.rawValue)) → \(url.lastPathComponent) \(width)x\(height)")
    }

    private static func waitForCameraFrameSize() async throws -> (width: Int, height: Int) {
        for _ in 0..<40 {
            if let pb = CameraController.shared.latestFrame {
                return (CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb))
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw NSError(domain: "Pik", code: 10, userInfo: [NSLocalizedDescriptionKey: t("Camera did not deliver a frame within 4 seconds", "La cámara no entregó imagen en 4 segundos")])
    }

    private func teardownAfterFailure() async {
        writer?.cancel()
        writer = nil; mixer = nil
        AudioInputController.shared.onSampleBuffer = nil
        CameraController.shared.onFrame = nil
        if let id = currentItemID { await MainActor.run { self.library.delete(id, trashFile: false) } }
        currentItemID = nil; item = nil
        await MainActor.run { self.phase = .idle }
    }

    // MARK: Pausa / reanudar

    public func pause() {
        guard phase == .recording else { return }
        writer?.pause()
        pauseBegan = Date()
        phase = .paused
        plog("Grabación en pausa")
    }

    public func resume() {
        guard phase == .paused else { return }
        writer?.resume()
        if let p = pauseBegan { pausedAccum += Date().timeIntervalSince(p) }
        pauseBegan = nil
        phase = .recording
        plog("Grabación reanudada")
    }

    public func togglePause() { phase == .paused ? resume() : pause() }

    // MARK: Fin

    /// Detiene, cierra el archivo y registra el resultado en la biblioteca.
    public func stop() async -> LibraryEntry? {
        guard isActive, phase != .finishing, let writer else { return nil }
        await MainActor.run { self.phase = .finishing; self.stopTimer() }
        if pauseBegan != nil { writer.resume(); pauseBegan = nil }
        await detachSources()
        let id = currentItemID
        do {
            let result = try await writer.finish()
            self.writer = nil; self.mixer = nil
            let size = (try? result.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            await MainActor.run {
                if let id {
                    self.library.update(id) {
                        $0.inProgress = false
                        $0.duration = result.duration
                        $0.fileSize = Int64(size)
                    }
                }
                self.phase = .idle
            }
            plog("Grabación guardada: \(result.url.lastPathComponent) \(Int(result.duration)) s, \(result.droppedFrames) fotogramas descartados")
            currentItemID = nil
            if let id, let final = library.item(id: id) {
                library.makeThumbnail(for: final)
                return final
            }
            return nil
        } catch {
            plogError("Error al cerrar la grabación: \(error.localizedDescription)")
            await MainActor.run {
                self.lastError = error.localizedDescription
                if let id { self.library.delete(id, trashFile: false) }
                self.phase = .idle
            }
            writer.cancel()
            self.writer = nil; self.mixer = nil; currentItemID = nil
            return nil
        }
    }

    /// Descarta la grabación en curso (archivo y registro).
    public func cancel() async {
        guard isActive else { return }
        await MainActor.run { self.stopTimer() }
        await detachSources()
        writer?.cancel(); writer = nil; mixer = nil
        let id = currentItemID
        await MainActor.run {
            if let id { self.library.delete(id, trashFile: false) }
            self.phase = .idle
            self.elapsed = 0
        }
        currentItemID = nil; item = nil
        plog("Grabación cancelada")
    }

    private func detachSources() async {
        AudioInputController.shared.onSampleBuffer = nil
        CameraController.shared.onFrame = nil
        screen.onVideo = nil
        screen.onSystemAudio = nil
        if currentRequest?.mode != .cameraOnly { await screen.stop() }
    }

    // MARK: Cronómetro

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, self.phase == .recording || self.phase == .paused else { return }
            let paused = self.pauseBegan.map { Date().timeIntervalSince($0) } ?? 0
            self.elapsed = Date().timeIntervalSince(self.startedAt) - self.pausedAccum - paused
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func stopTimer() { timer?.invalidate(); timer = nil }
}
