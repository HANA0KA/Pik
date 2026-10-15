import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

public enum MovieWriterError: LocalizedError {
    case cannotCreate(String)
    case failed(String)
    public var errorDescription: String? {
        switch self {
        case .cannotCreate(let m), .failed(let m): return m
        }
    }
}

/// Escribe MP4 (H.264/HEVC + AAC) en tiempo real. Maneja pausa (recorta los tiempos), audio ya mezclado y
/// "latido" de fotogramas para pantallas estáticas. Escribe en fragmentos para poder recuperar tras un cierre inesperado.
public final class MovieWriter {
    public struct Config {
        public var url: URL
        public var width: Int
        public var height: Int
        public var fps: Int
        public var hevc: Bool
        public var withAudio: Bool
        public init(url: URL, width: Int, height: Int, fps: Int = 30, hevc: Bool = false, withAudio: Bool = true) {
            self.url = url; self.width = width & ~1; self.height = height & ~1
            self.fps = fps; self.hevc = hevc; self.withAudio = withAudio
        }
    }

    public static let audioSampleRate: Double = 48_000
    public static let audioChannels = 2

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let queue = DispatchQueue(label: "pik.movie.writer", qos: .userInteractive)
    public let config: Config

    // Estado (solo se toca dentro de `queue`)
    private var firstPTS: CMTime?
    private var skew = CMTime.zero
    private var pauseStart: CMTime?
    private var lastVideoAdj = CMTime(value: -1, timescale: 600)
    private var lastAudioAdj = CMTime(value: -1, timescale: 600)
    private var lastPixelBuffer: CVPixelBuffer?
    private var lastFrameHost = CMTime.zero
    private var droppedVideo = 0
    private var finished = false
    private var started = false
    private var heartbeat: DispatchSourceTimer?

    public private(set) var lastError: String?

    public init(config: Config) throws {
        self.config = config
        try? FileManager.default.removeItem(at: config.url)
        do {
            writer = try AVAssetWriter(outputURL: config.url, fileType: .mp4)
        } catch {
            throw MovieWriterError.cannotCreate(t("Creating recording directory failed: ", "No se pudo crear el archivo de grabación: ") + error.localizedDescription)
        }
        let pixels = config.width * config.height
        let bitrate = max(1_500_000, Int(Double(pixels) * Double(config.fps) * (config.hevc ? 0.045 : 0.075)))
        var props: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: config.fps,
            AVVideoMaxKeyFrameIntervalKey: config.fps * 2,
            AVVideoAllowFrameReorderingKey: false,
        ]
        if !config.hevc { props[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
        let vSettings: [String: Any] = [
            AVVideoCodecKey: config.hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height,
            AVVideoCompressionPropertiesKey: props,
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
        videoInput.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(videoInput) else { throw MovieWriterError.cannotCreate("Invalid recorder configuration: \(config.width)x\(config.height)") }
        writer.add(videoInput)

        if config.withAudio {
            let aSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: Self.audioChannels,
                AVSampleRateKey: Self.audioSampleRate,
                AVEncoderBitRateKey: 192_000,
                AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue,
            ]
            let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: aSettings)
            ai.expectsMediaDataInRealTime = true
            if writer.canAdd(ai) { writer.add(ai); audioInput = ai } else { audioInput = nil }
        } else {
            audioInput = nil
        }
        writer.movieFragmentInterval = CMTime(seconds: 4, preferredTimescale: 1)
        writer.shouldOptimizeForNetworkUse = false
    }

    public func start() throws {
        guard writer.startWriting() else {
            throw MovieWriterError.failed(writer.error?.localizedDescription ?? "startWriting falló")
        }
        started = true
        // Latido: si la pantalla está quieta (SCK no manda fotogramas), repetir el último cada 0,5 s.
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in self?.heartbeatTick() }
        timer.resume()
        heartbeat = timer
    }

    public static func hostNow() -> CMTime { CMClockGetTime(CMClockGetHostTimeClock()) }

    // MARK: Video

    public func appendVideo(_ pb: CVPixelBuffer, pts: CMTime) {
        queue.async { [weak self] in self?.writeVideo(pb, pts: pts, fromHeartbeat: false) }
    }

    public func appendVideo(sampleBuffer sb: CMSampleBuffer) {
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        appendVideo(pb, pts: CMSampleBufferGetPresentationTimeStamp(sb))
    }

    private func writeVideo(_ pb: CVPixelBuffer, pts: CMTime, fromHeartbeat: Bool) {
        guard started, !finished, writer.status == .writing, pauseStart == nil else { return }
        if firstPTS == nil {
            firstPTS = pts
            writer.startSession(atSourceTime: .zero)
        }
        guard let first = firstPTS else { return }
        let adj = CMTimeSubtract(CMTimeSubtract(pts, first), skew)
        guard CMTimeCompare(adj, lastVideoAdj) > 0 else { return }   // monótono estricto
        guard videoInput.isReadyForMoreMediaData else { droppedVideo += 1; return }
        if adaptor.append(pb, withPresentationTime: adj) {
            lastVideoAdj = adj
            if !fromHeartbeat { lastPixelBuffer = pb; lastFrameHost = Self.hostNow() }
        } else {
            lastError = writer.error?.localizedDescription
        }
    }

    private func heartbeatTick() {
        guard started, !finished, pauseStart == nil, let pb = lastPixelBuffer, firstPTS != nil else { return }
        let now = Self.hostNow()
        if CMTimeGetSeconds(CMTimeSubtract(now, lastFrameHost)) >= 0.45 {
            writeVideo(pb, pts: now, fromHeartbeat: true)
            lastFrameHost = now
        }
    }

    // MARK: Audio (PCM float32 intercalado, 48 kHz estéreo, ya mezclado)

    public func appendAudio(samples: UnsafePointer<Float>, frames: Int, pts: CMTime) {
        guard audioInput != nil, frames > 0,
              let sb = Self.makeAudioSampleBuffer(samples: samples, frames: frames, pts: pts) else { return }
        queue.async { [weak self] in self?.writeAudio(sb) }
    }

    private func writeAudio(_ sb: CMSampleBuffer) {
        guard let audioInput, started, !finished, writer.status == .writing, pauseStart == nil, let first = firstPTS else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        if CMTimeCompare(pts, first) < 0 { return }            // audio anterior al primer fotograma
        var adj = CMTimeSubtract(CMTimeSubtract(pts, first), skew)
        if CMTimeCompare(adj, lastAudioAdj) <= 0 {
            // Solape de unos milisegundos: se encadena al bloque anterior (descartarlo producía chasquidos).
            guard CMTimeGetSeconds(CMTimeSubtract(lastAudioAdj, adj)) < 0.05 else { return }
            adj = lastAudioAdj
        }
        guard audioInput.isReadyForMoreMediaData else { return }
        var timing = CMSampleTimingInfo(duration: CMSampleBufferGetDuration(sb), presentationTimeStamp: adj, decodeTimeStamp: .invalid)
        var retimed: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sb, sampleTimingEntryCount: 1,
                                                    sampleTimingArray: &timing, sampleBufferOut: &retimed) == noErr,
              let r = retimed else { return }
        if audioInput.append(r) {
            lastAudioAdj = CMTimeAdd(adj, CMSampleBufferGetDuration(sb))
        }
    }

    static func makeAudioSampleBuffer(samples: UnsafePointer<Float>, frames: Int, pts: CMTime) -> CMSampleBuffer? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: audioSampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(4 * audioChannels), mFramesPerPacket: 1, mBytesPerFrame: UInt32(4 * audioChannels),
            mChannelsPerFrame: UInt32(audioChannels), mBitsPerChannel: 32, mReserved: 0)
        var fd: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
                                             magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &fd) == noErr,
              let fd else { return nil }
        let bytes = frames * 4 * audioChannels
        var bb: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes,
                                                 blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                                                 dataLength: bytes, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &bb) == noErr,
              let bb else { return nil }
        guard CMBlockBufferReplaceDataBytes(with: samples, blockBuffer: bb, offsetIntoDestination: 0, dataLength: bytes) == noErr else { return nil }
        var sb: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault, dataBuffer: bb, formatDescription: fd,
                                                                   sampleCount: frames, presentationTimeStamp: pts,
                                                                   packetDescriptions: nil, sampleBufferOut: &sb) == noErr else { return nil }
        return sb
    }

    // MARK: Pausa

    public func pause() {
        queue.async { [weak self] in
            guard let self, self.pauseStart == nil else { return }
            self.pauseStart = Self.hostNow()
        }
    }

    public func resume() {
        queue.async { [weak self] in
            guard let self, let ps = self.pauseStart else { return }
            self.skew = CMTimeAdd(self.skew, CMTimeSubtract(Self.hostNow(), ps))
            self.pauseStart = nil
        }
    }

    // MARK: Cierre

    public struct Result {
        public let url: URL
        public let duration: TimeInterval
        public let droppedFrames: Int
    }

    public func finish() async throws -> Result {
        // 1) Cerrar la sesión en la cola (calcula la hora de fin según el reloj).
        let endTime: CMTime = await withCheckedContinuation { cont in
            queue.async { [self] in
                heartbeat?.cancel(); heartbeat = nil
                var end = lastVideoAdj
                if let first = firstPTS {
                    let pausedExtra = pauseStart.map { CMTimeSubtract(Self.hostNow(), $0) } ?? .zero
                    let wall = CMTimeSubtract(CMTimeSubtract(CMTimeSubtract(Self.hostNow(), first), skew), pausedExtra)
                    if CMTimeCompare(wall, end) > 0 { end = wall }
                }
                finished = true
                cont.resume(returning: CMTimeMaximum(end, .zero))
            }
        }
        guard firstPTS != nil, writer.status == .writing else {
            writer.cancelWriting()
            throw MovieWriterError.failed(t("Recorder failed to start: ", "La grabación no llegó a iniciar") + (writer.error?.localizedDescription ?? ""))
        }
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        writer.endSession(atSourceTime: endTime)
        await writer.finishWriting()
        if writer.status != .completed {
            throw MovieWriterError.failed(writer.error?.localizedDescription ?? "finishWriting: \(writer.status.rawValue)")
        }
        return Result(url: config.url, duration: CMTimeGetSeconds(endTime), droppedFrames: droppedVideo)
    }

    /// Cancela y borra el archivo parcial.
    public func cancel() {
        queue.async { [self] in
            heartbeat?.cancel(); heartbeat = nil
            finished = true
        }
        if writer.status == .writing { writer.cancelWriting() }
        try? FileManager.default.removeItem(at: config.url)
    }
}
