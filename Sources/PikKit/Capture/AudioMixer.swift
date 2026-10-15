import AVFoundation
import CoreMedia
import Foundation

/// Convierte buffers de audio (micrófono / sistema) a Float32 intercalado 48 kHz estéreo.
final class PCMNormalizer {
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: MovieWriter.audioSampleRate,
                                      channels: AVAudioChannelCount(MovieWriter.audioChannels), interleaved: true)!
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    func normalize(_ sb: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let fd = CMSampleBufferGetFormatDescription(sb) else { return nil }
        let frames = CMSampleBufferGetNumSamples(sb)
        guard frames > 0 else { return nil }
        let src = AVAudioFormat(cmAudioFormatDescription: fd)
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: AVAudioFrameCount(frames)) else { return nil }
        inBuf.frameLength = AVAudioFrameCount(frames)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sb, at: 0, frameCount: Int32(frames), into: inBuf.mutableAudioBufferList) == noErr else { return nil }

        if sourceFormat != src || converter == nil {
            converter = AVAudioConverter(from: src, to: Self.format)
            sourceFormat = src
        }
        guard let conv = converter else { return nil }
        let ratio = Self.format.sampleRate / src.sampleRate
        let cap = AVAudioFrameCount(Double(frames) * ratio) + 256
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: cap) else { return nil }
        var consumed = false
        var err: NSError?
        conv.convert(to: outBuf, error: &err) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return inBuf
        }
        if err != nil || outBuf.frameLength == 0 { return nil }
        return outBuf
    }
}

/// Mezcla micrófono + audio del sistema en una sola pista.
/// - Solo micrófono / solo sistema: pasa directo.
/// - Ambos: el micrófono marca el ritmo y se le suma lo que haya acumulado del sistema.
/// Sello de tiempo continuo para el audio de salida: contamos las muestras entregadas en lugar de fiarnos del PTS de
/// cada bloque (que tras remuestrear no cuadra al milisegundo y producía solapes/huecos → chasquidos).
struct ContiguousClock {
    private var base: CMTime?
    private var written: Int64 = 0

    mutating func stamp(input pts: CMTime, frames: Int) -> CMTime {
        let rate = Int32(MovieWriter.audioSampleRate)
        if let b = base {
            let expected = CMTimeAdd(b, CMTime(value: written, timescale: rate))
            if abs(CMTimeGetSeconds(CMTimeSubtract(pts, expected))) > 0.08 { base = pts; written = 0 }   // salto real: re-sincronizar
        } else {
            base = pts; written = 0
        }
        let out = CMTimeAdd(base!, CMTime(value: written, timescale: rate))
        written += Int64(frames)
        return out
    }
}

/// Limitador suave: transparente por debajo de 0.7 y comprime sin recortar duro por encima.
@inline(__always) func softLimit(_ x: Float) -> Float {
    let a = abs(x)
    if a <= 0.7 { return x }
    let y = 0.7 + 0.3 * tanhf((a - 0.7) / 0.3)
    return x < 0 ? -y : y
}

public final class AudioMixer {
    public typealias Sink = (_ samples: UnsafePointer<Float>, _ frames: Int, _ pts: CMTime) -> Void

    private let hasMic: Bool
    private let hasSystem: Bool
    private let sink: Sink
    private let micNorm = PCMNormalizer()
    private let sysNorm = PCMNormalizer()
    private var sysRing: [Float] = []      // estéreo intercalado
    private var sysHead = 0
    private let lock = NSLock()
    public var micGain: Float = 1
    /// Reducción de ruido del micrófono (filtro de rumble + sustracción espectral). Se puede cambiar en caliente.
    public var noiseSuppression = true
    private var micCleaners = [NoiseSuppressor(), NoiseSuppressor()]   // L y R
    private var scratch = [Float]()
    private var micClock = ContiguousClock()
    private var sysClock = ContiguousClock()
    public var systemGain: Float = 0.9

    public init(hasMic: Bool, hasSystem: Bool, sink: @escaping Sink) {
        self.hasMic = hasMic; self.hasSystem = hasSystem; self.sink = sink
    }

    public func pushMic(_ sb: CMSampleBuffer) {
        guard hasMic, let buf = micNorm.normalize(sb), let data = buf.floatChannelData?[0] else { return }
        let frames = Int(buf.frameLength)
        let pts = micClock.stamp(input: CMSampleBufferGetPresentationTimeStamp(sb), frames: frames)
        let n = frames * 2
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n { out[i] = data[i] * micGain }
        if noiseSuppression { suppressNoise(&out, frames: frames) }
        if hasSystem {
            lock.lock()
            let available = (sysRing.count - sysHead)
            let take = min(available, n)
            if take > 0 {
                for i in 0..<take { out[i] += sysRing[sysHead + i] * systemGain }
                sysHead += take
                compactIfNeeded()
            }
            lock.unlock()
        }
        for i in 0..<n { out[i] = max(-1, min(1, softLimit(out[i]))) }
        out.withUnsafeBufferPointer { sink($0.baseAddress!, frames, pts) }
    }

    /// `out` es estéreo intercalado; cada canal pasa por su propio supresor.
    private func suppressNoise(_ out: inout [Float], frames: Int) {
        if scratch.count < frames { scratch = [Float](repeating: 0, count: frames) }
        for ch in 0..<2 {
            for i in 0..<frames { scratch[i] = out[i * 2 + ch] }
            scratch.withUnsafeMutableBufferPointer { micCleaners[ch].process($0.baseAddress!, count: frames) }
            for i in 0..<frames { out[i * 2 + ch] = scratch[i] }
        }
    }

    public func pushSystem(_ sb: CMSampleBuffer) {
        guard hasSystem, let buf = sysNorm.normalize(sb), let data = buf.floatChannelData?[0] else { return }
        let frames = Int(buf.frameLength)
        let n = frames * 2
        if hasMic {
            lock.lock()
            sysRing.append(contentsOf: UnsafeBufferPointer(start: data, count: n))
            // Limitar la latencia: máx. ~1 s acumulado.
            let maxSamples = Int(MovieWriter.audioSampleRate) * 2
            if sysRing.count - sysHead > maxSamples { sysHead = sysRing.count - Int(Double(maxSamples) * 0.2) }
            lock.unlock()
        } else {
            let pts = sysClock.stamp(input: CMSampleBufferGetPresentationTimeStamp(sb), frames: frames)
            var out = [Float](repeating: 0, count: n)
            for i in 0..<n { out[i] = max(-1, min(1, softLimit(data[i] * systemGain))) }
            out.withUnsafeBufferPointer { sink($0.baseAddress!, frames, pts) }
        }
    }

    private func compactIfNeeded() {
        if sysHead > 96_000 {
            sysRing.removeFirst(sysHead)
            sysHead = 0
        }
    }
}
