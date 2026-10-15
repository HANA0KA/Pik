import AVFoundation
import Foundation

/// Sonidos propios de Pik, sintetizados en código (sin archivos de audio).
public final class SoundPlayer {
    public static let shared = SoundPlayer()

    public enum Effect: CaseIterable { case start, pause, resume, complete, shutter, error }

    private var players: [Effect: AVAudioPlayer] = [:]

    private init() {
        for e in Effect.allCases {
            if let p = try? AVAudioPlayer(data: Self.wav(for: e)) {
                p.volume = 0.8
                p.prepareToPlay()
                players[e] = p
            }
        }
    }

    public func play(_ effect: Effect, enabled: Bool = true) {
        guard enabled, let p = players[effect] else { return }
        p.currentTime = 0
        p.play()
    }

    /// Duración aproximada, para esperar antes de arrancar la captura (que no grabe su propio sonido).
    public func duration(of effect: Effect) -> TimeInterval { players[effect]?.duration ?? 0 }

    // MARK: Síntesis

    private static let sampleRate = 44_100.0

    private struct Note { var freq: Double; var start: Double; var length: Double; var gain: Double = 0.5 }

    private static func notes(for e: Effect) -> [Note] {
        switch e {
        case .start: return [Note(freq: 660, start: 0, length: 0.12), Note(freq: 990, start: 0.1, length: 0.22)]
        case .pause: return [Note(freq: 520, start: 0, length: 0.16, gain: 0.45)]
        case .resume: return [Note(freq: 520, start: 0, length: 0.08, gain: 0.45), Note(freq: 780, start: 0.08, length: 0.14, gain: 0.45)]
        case .complete: return [Note(freq: 784, start: 0, length: 0.14), Note(freq: 988, start: 0.12, length: 0.14), Note(freq: 1319, start: 0.24, length: 0.3)]
        case .shutter: return [Note(freq: 1800, start: 0, length: 0.025, gain: 0.5), Note(freq: 900, start: 0.045, length: 0.05, gain: 0.35)]
        case .error: return [Note(freq: 300, start: 0, length: 0.14, gain: 0.5), Note(freq: 220, start: 0.12, length: 0.22, gain: 0.5)]
        }
    }

    static func wav(for e: Effect) -> Data {
        let list = notes(for: e)
        let total = (list.map { $0.start + $0.length }.max() ?? 0.2) + 0.05
        let count = Int(total * sampleRate)
        var samples = [Int16](repeating: 0, count: count)
        for n in list {
            let s0 = Int(n.start * sampleRate)
            let len = Int(n.length * sampleRate)
            for i in 0..<len where s0 + i < count {
                let t = Double(i) / sampleRate
                let attack = min(1.0, t / 0.004)
                let release = min(1.0, Double(len - i) / (0.06 * sampleRate))
                let env = attack * release * exp(-2.2 * t / n.length)
                var v = sin(2 * .pi * n.freq * t) + 0.3 * sin(4 * .pi * n.freq * t)
                if e == .shutter { v += Double.random(in: -1...1) * 0.6 }
                let mixed = Double(samples[s0 + i]) + v * env * n.gain * 16_000
                samples[s0 + i] = Int16(max(-32_000, min(32_000, mixed)))
            }
        }
        var data = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 2)) }
        let byteCount = UInt32(count * 2)
        data.append("RIFF".data(using: .ascii)!); u32(36 + byteCount)
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * 2); u16(2); u16(16)
        data.append("data".data(using: .ascii)!); u32(byteCount)
        samples.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        return data
    }
}
