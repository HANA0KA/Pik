import Foundation

/// Reducción de ruido de micrófono en streaming (un canal): filtro pasa-altos + sustracción espectral tipo Wiener.
///
/// - Ventana STFT de 512 muestras con 50 % de solape (raíz de Hann → reconstrucción perfecta sin ganancia).
/// - El piso de ruido por banda se sigue con un mínimo móvil (baja al instante, sube despacio), así que se adapta
///   al ruido de fondo sin calibrar y no se come la voz aunque la grabación empiece hablando.
/// - La ganancia nunca baja de `floorGain` y se suaviza en tiempo y frecuencia para evitar el "ruido musical".
///
/// Devuelve exactamente tantas muestras como recibe; introduce `latency` muestras de retraso (~16 ms a 48 kHz).
final class NoiseSuppressor {
    static let frameSize = 512
    static let hop = 256
    static let latency = frameSize + hop

    /// Cuánto se atenúa como máximo (0.25 ≈ −12 dB).
    var floorGain: Float = 0.25
    /// Cuánto de la estimación de ruido se resta (mayor = más agresivo).
    var overSubtraction: Float = 2.2

    private let n = NoiseSuppressor.frameSize
    private let hop = NoiseSuppressor.hop
    private let bins = NoiseSuppressor.frameSize / 2 + 1
    private let window: [Float]
    private let cosTable: [Float]
    private let sinTable: [Float]
    private let bitReverse: [Int]

    private var inFifo: [Float] = []
    private var outFifo: [Float]
    private var ola = [Float](repeating: 0, count: NoiseSuppressor.frameSize)
    private var noise: [Float]
    private var smoothPower: [Float]
    private var noisePower: [Float]      // potencia muy suavizada, solo para seguir el piso de ruido
    private var gainPrev: [Float]
    private var primed = false
    private var frameCount = 0
    // pasa-altos de 1er orden (~76 Hz a 48 kHz)
    private var hpX: Float = 0
    private var hpY: Float = 0
    private let hpCoef: Float = 0.99

    // buffers de trabajo
    private var re: [Float]
    private var im: [Float]
    private var gain: [Float]

    init() {
        let n = NoiseSuppressor.frameSize
        window = (0..<n).map { i in sqrtf(0.5 - 0.5 * cosf(2 * .pi * Float(i) / Float(n))) }
        cosTable = (0..<n / 2).map { cosf(2 * .pi * Float($0) / Float(n)) }
        sinTable = (0..<n / 2).map { -sinf(2 * .pi * Float($0) / Float(n)) }
        var rev = [Int](repeating: 0, count: n)
        let bits = Int(log2(Double(n)))
        for i in 0..<n {
            var r = 0, x = i
            for _ in 0..<bits { r = (r << 1) | (x & 1); x >>= 1 }
            rev[i] = r
        }
        bitReverse = rev
        let bins = n / 2 + 1
        outFifo = [Float](repeating: 0, count: NoiseSuppressor.latency)
        noise = [Float](repeating: 0, count: bins)
        smoothPower = [Float](repeating: 0, count: bins)
        noisePower = [Float](repeating: 0, count: bins)
        gainPrev = [Float](repeating: 1, count: bins)
        re = [Float](repeating: 0, count: n)
        im = [Float](repeating: 0, count: n)
        gain = [Float](repeating: 1, count: bins)
    }

    /// Procesa `count` muestras (mono) en sitio.
    func process(_ x: UnsafeMutablePointer<Float>, count: Int) {
        guard count > 0 else { return }
        for i in 0..<count {                       // pasa-altos: quita retumbos y DC
            let y = x[i] - hpX + hpCoef * hpY
            hpX = x[i]; hpY = y
            inFifo.append(y)
        }
        while inFifo.count >= n {
            processFrame()
            inFifo.removeFirst(hop)
        }
        for i in 0..<count { x[i] = outFifo[i] }
        outFifo.removeFirst(count)
    }

    // MARK: - Un cuadro

    private func processFrame() {
        for i in 0..<n { re[i] = inFifo[i] * window[i]; im[i] = 0 }
        fft(inverse: false)

        let maxG: Float = 1
        for k in 0..<bins {
            let p = re[k] * re[k] + im[k] * im[k]
            smoothPower[k] = primed ? 0.6 * smoothPower[k] + 0.4 * p : p
            noisePower[k] = primed ? 0.9 * noisePower[k] + 0.1 * p : p
            if !primed { noise[k] = noisePower[k] * 0.3 }   // arranque prudente: si ya estás hablando, no te apaga
            // mínimo móvil: baja de inmediato, sube ~1.5 dB/s
            noise[k] = min(noisePower[k], noise[k] * 1.0017)
            let est = noise[k] * overSubtraction
            let sp = max(smoothPower[k], 1e-12)
            gain[k] = min(maxG, max(floorGain, 1 - est / sp))
        }
        primed = true
        frameCount += 1
        if frameCount < 20 { for k in 0..<bins { gain[k] = 1 } }      // ~0,1 s para aprender el piso antes de actuar

        // suavizado en frecuencia (3 bandas) y en tiempo (sube rápido, baja despacio)
        for k in 0..<bins {
            let a = gain[max(0, k - 1)], b = gain[k], c = gain[min(bins - 1, k + 1)]
            let g = 0.25 * a + 0.5 * b + 0.25 * c
            let s = g > gainPrev[k] ? 0.3 * gainPrev[k] + 0.7 * g : 0.6 * gainPrev[k] + 0.4 * g
            gainPrev[k] = s
        }
        for k in 0..<bins {
            re[k] *= gainPrev[k]; im[k] *= gainPrev[k]
            if k > 0, k < n / 2 { re[n - k] = re[k]; im[n - k] = -im[k] }
        }
        fft(inverse: true)

        for i in 0..<n { ola[i] += re[i] * window[i] }
        outFifo.append(contentsOf: ola[0..<hop])
        ola.removeFirst(hop)
        ola.append(contentsOf: [Float](repeating: 0, count: hop))
    }

    // MARK: - FFT radix-2 (n = 512)

    private func fft(inverse: Bool) {
        for i in 0..<n {
            let j = bitReverse[i]
            if j > i { re.swapAt(i, j); im.swapAt(i, j) }
        }
        var len = 2
        while len <= n {
            let half = len / 2, step = n / len
            var start = 0
            while start < n {
                for k in 0..<half {
                    let wr = cosTable[k * step]
                    let wi = inverse ? -sinTable[k * step] : sinTable[k * step]
                    let a = start + k, b = a + half
                    let tr = re[b] * wr - im[b] * wi
                    let ti = re[b] * wi + im[b] * wr
                    re[b] = re[a] - tr; im[b] = im[a] - ti
                    re[a] += tr; im[a] += ti
                }
                start += len
            }
            len <<= 1
        }
        if inverse {
            let s = 1 / Float(n)
            for i in 0..<n { re[i] *= s; im[i] *= s }
        }
    }
}
