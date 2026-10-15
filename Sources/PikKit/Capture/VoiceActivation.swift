import AVFoundation
import Foundation
import Speech

/// Activación por voz (opcional): escucha el micrófono en el equipo mientras Pik está en reposo y, al oír «Pik»,
/// abre la barra y empieza a grabar. No guarda audio ni texto; se detiene al grabar y en cuanto se desactiva.
@available(macOS 26.0, *)
public final class VoiceActivation {
    public static let shared = VoiceActivation()

    public private(set) var isListening = false
    public var onWake: () -> Void = {}

    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var task: Task<Void, Never>?
    private var cooldown = WakeCooldown()
    private var generation = 0

    public func start() {
        guard !isListening else { return }
        guard Permissions.shared.isGranted(.microphone), SpeechTranscriber.isAvailable else {
            plogError("Activación por voz: falta el permiso de micrófono o el reconocimiento no está disponible")
            return
        }
        isListening = true
        generation += 1
        let gen = generation
        task = Task { [weak self] in
            while let self, self.isListening, self.generation == gen, !Task.isCancelled {
                do { try await self.listen(generation: gen) }
                catch { plogError("Activación por voz: \(error.localizedDescription)") }
                guard self.isListening, self.generation == gen else { break }
                try? await Task.sleep(nanoseconds: 3_000_000_000)      // reintenta (cambio de micrófono, error, reinicio periódico)
            }
        }
    }

    public func stop() {
        guard isListening else { return }
        isListening = false
        generation += 1
        task?.cancel(); task = nil
        teardown()
    }

    private func teardown() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        let a = analyzer; analyzer = nil
        if let a { Task { await a.cancelAndFinishNow() } }
    }

    private func listen(generation gen: Int) async throws {
        let wanted = L10n.speechLocale(for: L10n.language)
        var found = await SpeechTranscriber.supportedLocale(equivalentTo: wanted)
        if found == nil { found = await SpeechTranscriber.supportedLocale(equivalentTo: L10n.speechLocale(for: L10n.language)) }
        guard let locale = found else { throw TranscriberError.unavailable }

        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
        if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) { try await req.downloadAndInstall() }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let micFormat = input.outputFormat(forBus: 0)
        guard micFormat.sampleRate > 0, let target = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: micFormat) else {
            throw TranscriberError.unavailable
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let context = AnalysisContext()
        context.contextualStrings[.general] = ["Pik"]         // sesga el reconocimiento hacia la palabra
        try await analyzer.setContext(context)

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(8))
        let converter = micFormat == target ? nil : AVAudioConverter(from: micFormat, to: target)
        input.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { buffer, _ in
            if let converter {
                let ratio = target.sampleRate / micFormat.sampleRate
                guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64) else { return }
                var consumed = false
                var err: NSError?
                converter.convert(to: out, error: &err) { _, status in
                    if consumed { status.pointee = .noDataNow; return nil }
                    consumed = true; status.pointee = .haveData; return buffer
                }
                if err == nil, out.frameLength > 0 { continuation.yield(AnalyzerInput(buffer: out)) }
            } else {
                continuation.yield(AnalyzerInput(buffer: buffer))
            }
        }
        self.engine = engine
        self.analyzer = analyzer
        try engine.start()
        plog("Activación por voz: escuchando «Pik»")

        let results = Task { [weak self] in
            do {
                for try await r in transcriber.results {
                    guard let self, self.isListening, self.generation == gen else { return }
                    if WakeWord.matches(String(r.text.characters)), self.cooldown.fire() {
                        await MainActor.run { self.onWake() }
                    }
                }
            } catch { plogError("Activación por voz (resultados): \(error.localizedDescription)") }
        }
        // Reinicio periódico para no acumular estado en sesiones largas.
        let session = Task { try await analyzer.start(inputSequence: stream) }
        let deadline = Date().addingTimeInterval(15 * 60)
        while isListening, generation == gen, Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        continuation.finish()
        results.cancel(); session.cancel()
        teardown()
    }
}
