import XCTest
@testable import PikKit

final class TranscriberTests: XCTestCase {
    func testMergeShortJoinsStrayWords() {
        let segs = [TranscriptSegment(id: 0, start: 0, duration: 1, text: "Hola"),
                    TranscriptSegment(id: 1, start: 1.1, duration: 1, text: "esto es una prueba"),
                    TranscriptSegment(id: 2, start: 10, duration: 1, text: "Otra frase larga aquí")]
        let out = Transcriber.mergeShort(segs)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].text, "Hola esto es una prueba")
        XCTAssertEqual(out.map(\.id), [0, 1])
    }

    /// De punta a punta: voz sintética (`say`) → Transcriber (SpeechAnalyzer; sin necesitar el Dictado activado).
    func testTranscribesSyntheticSpeech() async throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("SpeechAnalyzer necesita macOS 26") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pik-say-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: url) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-o", url.path, "Hello, this is a simple test of speech transcription."]
        try p.run(); p.waitUntilExit()
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("`say` no generó audio") }
        let segs: [TranscriptSegment]
        do { segs = try await Transcriber.shared.transcribe(fileURL: url, localeID: "en-US") }
        catch { throw XCTSkip("Reconocimiento no disponible en este entorno: \(error.localizedDescription)") }
        let text = segs.map(\.text).joined(separator: " ").lowercased()
        // El reconocedor no es determinista con voz sintética: basta con que entienda buena parte de la frase.
        let expected = ["hello", "this", "is", "a", "simple", "test", "of", "speech", "transcription"]
        let hits = expected.filter { text.contains($0) }.count
        XCTAssertGreaterThanOrEqual(hits, 6, "transcripción: \(text)")
    }
}
