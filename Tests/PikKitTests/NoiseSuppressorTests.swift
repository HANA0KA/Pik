import XCTest
@testable import PikKit

final class NoiseSuppressorTests: XCTestCase {
    private func rms(_ a: ArraySlice<Float>) -> Float {
        sqrtf(a.reduce(0) { $0 + $1 * $1 } / Float(max(1, a.count)))
    }

    /// Ruido blanco + "voz" (tono) en la segunda mitad: el ruido solo debe bajar bastante y la voz casi no.
    func testAttenuatesHissButKeepsTone() {
        let sr: Float = 48_000
        let total = Int(sr) * 4
        var rng = SystemRandomNumberGenerator()
        var x = [Float](repeating: 0, count: total)
        for i in 0..<total {
            let hiss = Float.random(in: -1...1, using: &rng) * 0.02
            let tone: Float = i > total / 2 ? 0.25 * sinf(2 * .pi * 440 * Float(i) / sr) + 0.12 * sinf(2 * .pi * 1500 * Float(i) / sr) : 0
            x[i] = hiss + tone
        }
        let original = x
        let ns = NoiseSuppressor()
        var pos = 0
        while pos < total {                      // bloques de tamaño irregular, como el micrófono real
            let n = min(1411, total - pos)
            x.withUnsafeMutableBufferPointer { ns.process($0.baseAddress! + pos, count: n) }
            pos += n
        }
        let lat = NoiseSuppressor.latency
        let hissBefore = rms(original[Int(sr)..<Int(sr) * 2])
        let hissAfter = rms(x[Int(sr)..<Int(sr) * 2])
        XCTAssertLessThan(hissAfter, hissBefore * 0.55, "el ruido debería caer al menos ~5 dB")

        let toneRange = (total * 3 / 4)..<(total * 3 / 4 + Int(sr))
        let toneBefore = rms(original[toneRange])
        let toneAfter = rms(x[toneRange])
        XCTAssertGreaterThan(toneAfter, toneBefore * 0.8, "la voz no debe perder más de ~2 dB")
        XCTAssertGreaterThan(lat, 0)
        XCTAssertTrue(x.allSatisfy { $0.isFinite })
    }
}
