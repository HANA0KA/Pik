import AppKit
import AVFoundation
import CoreMedia
import ScreenCaptureKit

public enum ScreenRecorderError: LocalizedError {
    case noDisplay, windowGone, noPermission
    public var errorDescription: String? {
        switch self {
        case .noDisplay: return t("Couldn't determine display for window", "No se pudo determinar la pantalla")
        case .windowGone: return t("The selected window is no longer available.", "La ventana elegida ya no está disponible.")
        case .noPermission: return t("Allow screen recording access in System Settings to continue.", "Permití la grabación de pantalla en Ajustes del Sistema para continuar.")
        }
    }
}

/// Captura de pantalla con ScreenCaptureKit (pantalla completa, ventana o área).
public final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    public enum Target {
        case display(CGDirectDisplayID)
        case window(CGWindowID, CGDirectDisplayID)
        case area(CGRect, CGDirectDisplayID)      // rect en coordenadas Quartz globales
    }

    public struct Params {
        public var target: Target
        public var excludedWindowNumbers: [Int] = []     // ventanas de Pik que NO deben salir (barra, HUD, notas…)
        public var overlayWindowNumbers: [Int] = []      // ventanas de Pik que SÍ deben salir en modo ventana (burbuja, fondo…)
        public var hideSystemUI = true
        public var hideDesktopIcons = true
        public var resolution: VideoResolution = .p1080
        public var fps = 30
        public var systemAudio = false
        public var windowPadding: CGFloat = 0
        public init(target: Target) { self.target = target }
    }

    public struct Plan {
        public let filter: SCContentFilter
        public let config: SCStreamConfiguration
        public let width: Int
        public let height: Int
        public let windowID: CGWindowID?
        public let displayOrigin: CGPoint
        public let padding: CGFloat
    }

    public var onVideo: ((CVPixelBuffer, CMTime) -> Void)?
    public var onSystemAudio: ((CMSampleBuffer) -> Void)?
    public var onStop: ((Error?) -> Void)?

    private var stream: SCStream?
    private var plan: Plan?
    private var trackTimer: DispatchSourceTimer?
    private var lastTrackedFrame: CGRect = .zero
    private let sampleQueue = DispatchQueue(label: "pik.screen.samples", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "pik.screen.audio", qos: .userInteractive)
    private var stopping = false

    // MARK: Plan

    public static func makePlan(_ p: Params) async throws -> Plan {
        guard CGPreflightScreenCaptureAccess() else { throw ScreenRecorderError.noPermission }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let wantedID: CGDirectDisplayID
        switch p.target {
        case .display(let d), .window(_, let d), .area(_, let d): wantedID = d
        }
        guard let display = content.displays.first(where: { $0.displayID == wantedID }) ?? content.displays.first else {
            throw ScreenRecorderError.noDisplay
        }
        let scale = ScreenGeometry.screen(for: display.displayID)?.backingScaleFactor ?? 2
        let excludedIDs = Set(p.excludedWindowNumbers.map { CGWindowID($0) })
        var excluded = content.windows.filter { excludedIDs.contains($0.windowID) }
        if p.hideSystemUI { excluded += systemUIWindows(content) }
        if p.hideDesktopIcons { excluded += desktopIconWindows(content) }

        var filter: SCContentFilter
        var sourceRect: CGRect?
        var windowID: CGWindowID?
        let displayBounds = CGRect(origin: .zero, size: display.frame.size)

        switch p.target {
        case .display:
            filter = SCContentFilter(display: display, excludingWindows: excluded)
        case .area(let rect, _):
            filter = SCContentFilter(display: display, excludingWindows: excluded)
            sourceRect = rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY).intersection(displayBounds).integral
        case .window(let wid, _):
            guard let win = content.windows.first(where: { $0.windowID == wid }) else { throw ScreenRecorderError.windowGone }
            let overlayIDs = Set(p.overlayWindowNumbers.map { CGWindowID($0) })
            let overlays = content.windows.filter { overlayIDs.contains($0.windowID) && $0.windowID != wid }
            filter = SCContentFilter(display: display, including: [win] + overlays)
            windowID = wid
            sourceRect = win.frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
                .insetBy(dx: -p.windowPadding, dy: -p.windowPadding)
                .intersection(displayBounds).integral
        }

        let srcPoints = sourceRect?.size ?? display.frame.size
        let (w, h) = ScreenGeometry.outputSize(sourcePixels: CGSize(width: srcPoints.width * scale, height: srcPoints.height * scale),
                                               maxHeight: p.resolution.maxHeight)
        let cfg = SCStreamConfiguration()
        cfg.width = w
        cfg.height = h
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, p.fps)))
        cfg.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        cfg.showsCursor = true
        cfg.queueDepth = 6
        cfg.scalesToFit = true
        cfg.colorSpaceName = CGColorSpace.sRGB
        if let r = sourceRect { cfg.sourceRect = r }
        if p.systemAudio {
            cfg.capturesAudio = true
            cfg.excludesCurrentProcessAudio = true
            cfg.sampleRate = Int(MovieWriter.audioSampleRate)
            cfg.channelCount = MovieWriter.audioChannels
        }
        return Plan(filter: filter, config: cfg, width: w, height: h, windowID: windowID,
                    displayOrigin: display.frame.origin, padding: p.windowPadding)
    }

    private static func systemUIWindows(_ content: SCShareableContent) -> [SCWindow] {
        let bundles: Set<String> = ["com.apple.controlcenter", "com.apple.systemuiserver", "com.apple.notificationcenterui", "com.apple.WindowManager"]
        return content.windows.filter { w in
            guard let app = w.owningApplication else { return false }
            let id = app.bundleIdentifier
            if id == "com.apple.dock" { return w.windowLayer == 20 }          // la barra del Dock, no el fondo de pantalla
            if app.applicationName == "Window Server" { return w.windowLayer >= 20 && (w.title ?? "").lowercased().contains("menu") }
            return bundles.contains(id) && w.windowLayer > 0
        }
    }

    private static func desktopIconWindows(_ content: SCShareableContent) -> [SCWindow] {
        content.windows.filter { $0.owningApplication?.bundleIdentifier == "com.apple.finder" && $0.windowLayer < 0 }
    }

    // MARK: Ejecución

    public func start(plan: Plan) async throws {
        self.plan = plan
        stopping = false
        let s = SCStream(filter: plan.filter, configuration: plan.config, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        if plan.config.capturesAudio {
            try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        }
        try await s.startCapture()
        stream = s
        if let wid = plan.windowID { startTracking(windowID: wid) }
        plog("Captura iniciada \(plan.width)x\(plan.height)")
    }

    public func stop() async {
        stopping = true
        trackTimer?.cancel(); trackTimer = nil
        guard let s = stream else { return }
        stream = nil
        do { try await s.stopCapture() } catch { plogError("stopCapture: \(error.localizedDescription)") }
    }

    // MARK: Seguimiento de ventana (si se mueve durante la grabación)

    private func startTracking(windowID: CGWindowID) {
        lastTrackedFrame = Self.frame(of: windowID) ?? .zero
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        t.schedule(deadline: .now() + 0.2, repeating: 0.125)
        t.setEventHandler { [weak self] in
            guard let self, let plan = self.plan, let stream = self.stream, let f = Self.frame(of: windowID),
                  f != self.lastTrackedFrame else { return }
            self.lastTrackedFrame = f
            let cfg = plan.config
            cfg.sourceRect = f.offsetBy(dx: -plan.displayOrigin.x, dy: -plan.displayOrigin.y)
                .insetBy(dx: -plan.padding, dy: -plan.padding)
            stream.updateConfiguration(cfg) { err in
                if let err { plogError("updateConfiguration: \(err.localizedDescription)") }
            }
        }
        t.resume()
        trackTimer = t
    }

    private static func frame(of windowID: CGWindowID) -> CGRect? {
        guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let b = info.first?[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
        return CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
    }

    // MARK: SCStreamOutput / Delegate

    public func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sb.isValid else { return }
        switch type {
        case .screen:
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
                  let pb = CMSampleBufferGetImageBuffer(sb) else { return }
            onVideo?(pb, CMSampleBufferGetPresentationTimeStamp(sb))
        case .audio:
            onSystemAudio?(sb)
        default:
            break
        }
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        if stopping { return }
        plogError("El flujo de captura se detuvo: \(error.localizedDescription)")
        onStop?(error)
    }
}
