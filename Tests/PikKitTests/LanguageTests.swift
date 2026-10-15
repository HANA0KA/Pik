import XCTest
@testable import PikKit

final class LanguageTests: XCTestCase {
    func testSystemLanguagePicksFirstSupported() {
        XCTAssertEqual(L10n.systemLanguage(preferred: ["es-MX", "en-US"]), "es")
        XCTAssertEqual(L10n.systemLanguage(preferred: ["fr-FR", "en-GB", "es-ES"]), "en")
        XCTAssertEqual(L10n.systemLanguage(preferred: ["fr-FR", "es-419"]), "es")
        XCTAssertEqual(L10n.systemLanguage(preferred: ["ja-JP"]), "en")
        XCTAssertEqual(L10n.systemLanguage(preferred: []), "en")
    }

    func testSpeechLocaleKeepsTheUsersVariant() {
        XCTAssertEqual(L10n.speechLocale(for: "es", preferred: ["en-US", "es-MX"]).identifier, "es-MX")
        XCTAssertEqual(L10n.speechLocale(for: "es", preferred: ["en-US"]).identifier, "es-ES")
        XCTAssertEqual(L10n.speechLocale(for: "en", preferred: ["es-MX"]).identifier, "en-US")
    }

    func testOverrideBeatsSystem() {
        let saved = L10n.override; defer { L10n.override = saved }
        L10n.override = "es"; XCTAssertTrue(L10n.isSpanish); XCTAssertEqual(t("Record", "Grabar"), "Grabar")
        L10n.override = "en"; XCTAssertFalse(L10n.isSpanish); XCTAssertEqual(t("Record", "Grabar"), "Record")
    }

    func testPreferencesApplyLanguageOverrideAndTranscriptionDefault() {
        let saved = L10n.override; defer { L10n.override = saved }
        let prefs = Preferences(defaults: UserDefaults(suiteName: "pik.test.\(UUID().uuidString)")!)
        XCTAssertEqual(prefs.language, "system")
        XCTAssertEqual(prefs.transcriptionLanguage, "auto")
        prefs.language = "es"; XCTAssertEqual(L10n.override, "es")
        prefs.language = "system"; XCTAssertNil(L10n.override)
    }

    func testSpokenLanguageDetection() {
        let es = "Hola, gracias por acompañarme. Les muestro cómo grabo mi pantalla con Pik y dibujo para resaltar lo importante."
        let en = "Hi everyone, thanks for joining. Let me show you how I record my screen and draw to highlight what matters."
        XCTAssertGreaterThan(SpokenLanguage.probability(of: "es", in: es), 0.9)
        XCTAssertLessThan(SpokenLanguage.probability(of: "en", in: es), 0.1)
        XCTAssertGreaterThan(SpokenLanguage.probability(of: "en", in: en), 0.9)
        XCTAssertLessThan(SpokenLanguage.probability(of: "es", in: en), 0.1)
    }
}

final class NotesStoreTests: XCTestCase {
    private func tempURL() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("notes-\(UUID().uuidString).json") }

    func testAddEditChooseActiveAndPersist() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = NotesStore(fileURL: url)
        XCTAssertNil(store.active)
        let a = store.add(title: "Guion", text: "Hola")
        let b = store.add(title: "Tutorial", text: "Paso 1")
        XCTAssertEqual(store.activeID, a.id)                     // la primera queda activa
        store.setActive(b.id)
        store.update(b.id, text: "Paso 1\nPaso 2")
        store.saveNow()
        let again = NotesStore(fileURL: url)
        XCTAssertEqual(again.notes.map(\.title), ["Tutorial", "Guion"])
        XCTAssertEqual(again.active?.id, b.id)
        XCTAssertEqual(again.active?.text, "Paso 1\nPaso 2")
        XCTAssertEqual(again.active?.wordCount, 4)
    }

    func testDeleteActiveFallsBackToAnotherNote() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = NotesStore(fileURL: url)
        let a = store.add(title: "A"), b = store.add(title: "B")
        store.setActive(a.id)
        store.delete(a.id)
        XCTAssertEqual(store.activeID, b.id)
        store.delete(b.id)
        XCTAssertNil(store.activeID)
        XCTAssertEqual(store.ensureActive().title.isEmpty, false)
        XCTAssertNotNil(store.activeID)
    }

    func testLegacySingleNoteIsMigratedOnce() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let first = NotesStore(fileURL: url, legacyText: "Mi guion viejo")
        XCTAssertEqual(first.notes.count, 1)
        XCTAssertEqual(first.active?.text, "Mi guion viejo")
        first.delete(first.notes[0].id)
        XCTAssertEqual(NotesStore(fileURL: url, legacyText: "Mi guion viejo").notes.count, 0)   // ya no se vuelve a migrar
    }

    func testSearchAndDisplayTitle() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = NotesStore(fileURL: url)
        store.add(title: "", text: "Primera línea\nsegunda")
        store.add(title: "Lanzamiento", text: "precio y fecha")
        XCTAssertEqual(store.filtered("fecha").map(\.displayTitle), ["Lanzamiento"])
        XCTAssertEqual(store.filtered("").count, 2)
        XCTAssertEqual(store.notes.last?.displayTitle, "Primera línea")
    }
}
