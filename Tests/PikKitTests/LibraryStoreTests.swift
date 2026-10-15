import XCTest
@testable import PikKit

final class LibraryStoreTests: XCTestCase {
    func testPersistsAndSearches() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lib-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LibraryStore(jsonURL: url)
        var a = LibraryEntry(kind: .video, title: "Demo del producto")
        a.transcript = [TranscriptSegment(id: 0, start: 0, duration: 1, text: "presupuesto trimestral")]
        store.add(a)
        store.add(LibraryEntry(kind: .screenshot, title: "Captura"))
        store.flush()

        let again = LibraryStore(jsonURL: url)
        XCTAssertEqual(again.items.count, 2)
        XCTAssertEqual(again.items(of: [.video], matching: "presupuesto").count, 1)
        XCTAssertEqual(again.items(of: [.video], matching: "xyz").count, 0)
        XCTAssertEqual(again.items(of: [.screenshot]).count, 1)

        again.rename(a.id, to: "  Nuevo título ")
        XCTAssertEqual(again.item(id: a.id)?.title, "Nuevo título")
        again.delete(a.id, trashFile: false)
        XCTAssertNil(again.item(id: a.id))
    }
}
