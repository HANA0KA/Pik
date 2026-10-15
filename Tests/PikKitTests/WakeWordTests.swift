import XCTest
@testable import PikKit

final class WakeWordTests: XCTestCase {
    func testMatchesPikAndVariants() {
        for s in ["Pik", "pik.", "Oye, PIK, grabá", "hey pic", "Pick!", "peek", "Big.", "Oye, Vic", "hey big", "Vic", "Pi", "Pi.", "oye pi", "Beak", "Pic Graba"] { XCTAssertTrue(WakeWord.matches(s), s) }
    }

    func testIgnoresOtherWords() {
        for s in ["pikachu", "picnic", "hola mundo", "esto es una prueba", "pico", "that is a big problem", "el peak de la montaña es alto", "my friend Vic called me yesterday", "el valor de pi es tres coma uno cuatro", "a bit of a problem"] { XCTAssertFalse(WakeWord.matches(s), s) }
    }

    func testCooldownBlocksRepeats() {
        var c = WakeCooldown(interval: 4)
        let t0 = Date()
        XCTAssertTrue(c.fire(now: t0))
        XCTAssertFalse(c.fire(now: t0.addingTimeInterval(1)))
        XCTAssertTrue(c.fire(now: t0.addingTimeInterval(5)))
    }

    /// Voz sintética diciendo «Pik» → reconocedor del sistema → detector. Una voz sintética no es una voz real:
    /// basta con que algunas de las variantes lleguen al detector.
    func testSpokenPikReachesDetector() async throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("SpeechAnalyzer necesita macOS 26") }
        var heard: [String] = []
        var hits = 0
        for (voice, phrase, locale) in [("Alex", "Pik", "en-US"), ("Alex", "Hey Pik", "en-US"), ("Monica", "Oye Pik", "es-ES"), ("Jorge", "Pik", "es-ES")] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("pik-wake-\(UUID().uuidString).aiff")
            defer { try? FileManager.default.removeItem(at: url) }
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/say"); p.arguments = ["-v", voice, "-o", url.path, phrase]
            try p.run(); p.waitUntilExit()
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let segs: [TranscriptSegment]
            do { segs = try await Transcriber.transcribeWithAnalyzer(fileURL: url, localeID: locale) }   // sin el respaldo clásico: pediría permisos de voz y xctest no tiene Info.plist
            catch { throw XCTSkip("Reconocimiento no disponible: \(error.localizedDescription)") }
            let text = segs.map(\.text).joined(separator: " ")
            heard.append("\(phrase) → \(text)")
            if WakeWord.matches(text) { hits += 1 }
        }
        print("WAKE:", heard)
        if heard.isEmpty { throw XCTSkip("`say` no generó audio") }
        XCTAssertGreaterThanOrEqual(hits, heard.count - 1, "oído: \(heard)")
    }
}
