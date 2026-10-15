import AVFoundation
import Foundation
import Speech

public enum TranscriberError: LocalizedError {
    case notAuthorized, unavailable, failed(String)
    public var errorDescription: String? {
        switch self {
        case .notAuthorized: return t("Speech recognition isn't allowed. Enable it in System Settings.", "El reconocimiento de voz no está permitido. Activalo en Ajustes del Sistema.")
        case .unavailable: return t("Speech transcription is not available on this Mac.", "La transcripción de voz no está disponible en este Mac.")
        case .failed(let m): return m
        }
    }
}

/// Transcribe archivos de audio/video con el reconocimiento de voz de macOS (en el equipo cuando es posible).
public final class Transcriber {
    public static let shared = Transcriber()

    public static func recognizer(for localeID: String) -> SFSpeechRecognizer? {
        let locale = localeID == "system" ? L10n.systemLocale : Locale(identifier: localeID)
        if let r = SFSpeechRecognizer(locale: locale), r.isAvailable { return r }
        if let r = SFSpeechRecognizer(locale: L10n.speechLocale(for: L10n.language)), r.isAvailable { return r }
        return SFSpeechRecognizer()
    }

    /// Transcribe según el idioma elegido: «es», «en» o «auto» (detecta si se habló en español o en inglés).
    /// En automático prueba primero el idioma de la app; si el texto no parece estar en ese idioma, prueba el otro y se queda con el que cuadra mejor.
    public func transcribe(fileURL: URL, language: String) async throws -> [TranscriptSegment] {
        guard language == "auto" else { return try await transcribe(fileURL: fileURL, localeID: L10n.speechLocale(for: language).identifier) }
        let first = L10n.language, second = first == "es" ? "en" : "es"
        let a = try await transcribe(fileURL: fileURL, localeID: L10n.speechLocale(for: first).identifier)
        let textA = a.map(\.text).joined(separator: " ")
        let scoreA = textA.isEmpty ? 0 : SpokenLanguage.probability(of: first, in: textA)
        if scoreA >= Self.autoAcceptScore { return a }
        guard let b = try? await transcribe(fileURL: fileURL, localeID: L10n.speechLocale(for: second).identifier), !b.isEmpty else { return a }
        let scoreB = SpokenLanguage.probability(of: second, in: b.map(\.text).joined(separator: " "))
        plog("Transcripción automática: \(first)=\(String(format: "%.2f", scoreA)) \(second)=\(String(format: "%.2f", scoreB))")
        return scoreB > scoreA || a.isEmpty ? b : a
    }

    static let autoAcceptScore = 0.9

    /// Usa `SpeechAnalyzer` (macOS 26+, en el equipo, no necesita que el Dictado esté activado) y, si no está
    /// disponible o falla, el reconocedor clásico (`SFSpeechRecognizer`, que sí exige Dictado).
    public func transcribe(fileURL: URL, localeID: String = "system") async throws -> [TranscriptSegment] {
        if #available(macOS 26.0, *) {
            do {
                let segs = try await Self.transcribeWithAnalyzer(fileURL: fileURL, localeID: localeID)
                if !segs.isEmpty { return segs }
            } catch {
                plogError("SpeechAnalyzer falló, uso el reconocedor clásico: \(error.localizedDescription)")
            }
        }
        return try await transcribeClassic(fileURL: fileURL, localeID: localeID)
    }

    @available(macOS 26.0, *)
    static func transcribeWithAnalyzer(fileURL: URL, localeID: String) async throws -> [TranscriptSegment] {
        guard SpeechTranscriber.isAvailable else { throw TranscriberError.unavailable }
        let wanted = localeID == "system" ? L10n.systemLocale : Locale(identifier: localeID)
        var found = await SpeechTranscriber.supportedLocale(equivalentTo: wanted)
        if found == nil { found = await SpeechTranscriber.supportedLocale(equivalentTo: L10n.speechLocale(for: L10n.language)) }
        guard let locale = found else { throw TranscriberError.unavailable }
        let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedTranscriptionWithAlternatives)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            plog("Descargando el modelo de voz de macOS para \(locale.identifier)…")
            try await request.downloadAndInstall()
        }
        let file = try AVAudioFile(forReading: fileURL)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collector = Task { () -> [TranscriptSegment] in
            var out: [TranscriptSegment] = []
            for try await r in transcriber.results {
                let text = String(r.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                out.append(TranscriptSegment(id: out.count, start: r.range.start.seconds, duration: max(0.1, r.range.duration.seconds), text: text))
            }
            return out
        }
        do {
            if let last = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            collector.cancel()
            throw TranscriberError.failed(error.localizedDescription)
        }
        return mergeShort(try await collector.value)
    }

    /// Junta trozos muy cortos (una palabra suelta) con el siguiente para que se lea bien.
    static func mergeShort(_ segs: [TranscriptSegment]) -> [TranscriptSegment] {
        var out: [TranscriptSegment] = []
        for s in segs {
            if var last = out.last, last.text.split(separator: " ").count < 4, s.start - (last.start + last.duration) < 0.8 {
                last.text += " " + s.text
                last.duration = s.start + s.duration - last.start
                out[out.count - 1] = last
            } else {
                out.append(s)
            }
        }
        return out.enumerated().map { TranscriptSegment(id: $0.offset, start: $0.element.start, duration: $0.element.duration, text: $0.element.text) }
    }

    private func transcribeClassic(fileURL: URL, localeID: String) async throws -> [TranscriptSegment] {
        let granted: Bool = await withCheckedContinuation { cont in
            if SFSpeechRecognizer.authorizationStatus() == .authorized { cont.resume(returning: true); return }
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        guard granted else { throw TranscriberError.notAuthorized }
        guard let recognizer = Self.recognizer(for: localeID), recognizer.isAvailable else { throw TranscriberError.unavailable }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        let result: SFTranscription = try await withCheckedThrowingContinuation { cont in
            var resumed = false
            recognizer.recognitionTask(with: request) { res, error in
                if resumed { return }
                if let res, res.isFinal {
                    resumed = true
                    cont.resume(returning: res.bestTranscription)
                } else if let error {
                    resumed = true
                    cont.resume(throwing: TranscriberError.failed(error.localizedDescription))
                }
            }
        }
        return Self.group(result.segments)
    }

    /// Agrupa palabras en frases de lectura cómoda (corta por pausas, puntuación o ~14 palabras).
    static func group(_ words: [SFTranscriptionSegment]) -> [TranscriptSegment] {
        var out: [TranscriptSegment] = []
        var cur: [SFTranscriptionSegment] = []
        func flush() {
            guard let f = cur.first, let l = cur.last else { return }
            let text = cur.map(\.substring).joined(separator: " ")
            out.append(TranscriptSegment(id: out.count, start: f.timestamp, duration: l.timestamp + l.duration - f.timestamp, text: text))
            cur.removeAll()
        }
        for w in words {
            if let last = cur.last, w.timestamp - (last.timestamp + last.duration) > 0.9 { flush() }
            cur.append(w)
            let endsSentence = w.substring.last.map { ".?!…".contains($0) } ?? false
            if endsSentence || cur.count >= 14 { flush() }
        }
        flush()
        return out
    }
}
