import AVFoundation
import CoreMedia
import Foundation

enum AudioLevel {
    /// Pico normalizado (0...1) de un CMSampleBuffer de audio (Float32 o Int16).
    static func peak(of sb: CMSampleBuffer) -> Float {
        guard let fd = CMSampleBufferGetFormatDescription(sb),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee,
              let bb = CMSampleBufferGetDataBuffer(sb) else { return 0 }
        var length = 0
        var ptr: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: &length, totalLengthOut: nil, dataPointerOut: &ptr) == noErr,
              let ptr, length > 0 else { return 0 }
        var peak: Float = 0
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        if isFloat && asbd.mBitsPerChannel == 32 {
            ptr.withMemoryRebound(to: Float.self, capacity: length / 4) { p in
                let n = length / 4
                var i = 0
                while i < n { peak = max(peak, abs(p[i])); i += 4 }   // submuestreo: basta para un medidor
            }
        } else if asbd.mBitsPerChannel == 16 {
            ptr.withMemoryRebound(to: Int16.self, capacity: length / 2) { p in
                let n = length / 2
                var i = 0
                while i < n { peak = max(peak, abs(Float(p[i])) / 32768); i += 4 }
            }
        }
        return min(1, peak)
    }
}

/// Micrófono: abre una AVCaptureSession de audio, mide el nivel (para la barra) y entrega buffers a quien graba.
public final class AudioInputController: NSObject, ObservableObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    public static let shared = AudioInputController()

    @Published public private(set) var level: Float = 0
    @Published public private(set) var isRunning = false
    @Published public private(set) var lowVolume = false
    @Published public private(set) var deviceName: String?

    /// Se asigna mientras se graba. Se llama en una cola de fondo.
    public var onSampleBuffer: ((CMSampleBuffer) -> Void)?
    /// Se asigna mientras se dicta (reconocimiento en vivo).

    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "pik.audio.input", qos: .userInteractive)
    private var currentDeviceID: String?
    private var lastPublish = Date.distantPast
    private var startedAt = Date()
    private var recentPeak: Float = 0
    private var recentPeakSince = Date()

    private override init() {
        super.init()
        output.setSampleBufferDelegate(self, queue: queue)
    }

    public func start(deviceID: String?) {
        guard Permissions.shared.isGranted(.microphone) else { return }
        queue.async { [weak self] in
            guard let self else { return }
            guard let device = DeviceCatalog.microphone(id: deviceID) else {
                DispatchQueue.main.async { self.isRunning = false }
                return
            }
            if self.session.isRunning, self.currentDeviceID == device.uniqueID { return }
            self.session.beginConfiguration()
            for i in self.session.inputs { self.session.removeInput(i) }
            if self.session.outputs.contains(self.output) == false, self.session.canAddOutput(self.output) {
                self.session.addOutput(self.output)
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) { self.session.addInput(input) }
            } catch {
                plogError("No se pudo abrir el micrófono \(device.localizedName): \(error.localizedDescription)")
            }
            self.session.commitConfiguration()
            self.currentDeviceID = device.uniqueID
            if !self.session.isRunning { self.session.startRunning() }
            self.startedAt = Date()
            self.recentPeak = 0; self.recentPeakSince = Date()
            DispatchQueue.main.async { self.isRunning = true; self.deviceName = device.localizedName }
            plog("Micrófono activo: \(device.localizedName)")
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            self.currentDeviceID = nil
            DispatchQueue.main.async { self.isRunning = false; self.level = 0; self.lowVolume = false }
        }
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onSampleBuffer?(sampleBuffer)
        let p = AudioLevel.peak(of: sampleBuffer)
        recentPeak = max(recentPeak, p)
        let now = Date()
        if now.timeIntervalSince(lastPublish) > 0.05 {
            lastPublish = now
            var warn = false
            if now.timeIntervalSince(recentPeakSince) > 5 {
                warn = recentPeak < 0.02 && now.timeIntervalSince(startedAt) > 5
                recentPeak = 0; recentPeakSince = now
            }
            DispatchQueue.main.async {
                self.level = max(p, self.level * 0.82)
                if warn != self.lowVolume, now.timeIntervalSince(self.startedAt) > 5 { self.lowVolume = warn }
            }
        }
    }
}
