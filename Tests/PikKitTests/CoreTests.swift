import XCTest
@testable import PikKit

final class CoreTests: XCTestCase {
    func testDurationFormatting() {
        XCTAssertEqual(Fmt.duration(0), "0:00")
        XCTAssertEqual(Fmt.duration(83), "1:23")
        XCTAssertEqual(Fmt.duration(3723), "1:02:03")
    }

    func testSafeFileName() {
        XCTAssertEqual(Fmt.safeFileName("a/b:c"), "a-b-c")
        XCTAssertEqual(Fmt.safeFileName("   "), "Pik")
    }

    func testOutputSizeNeverUpscalesAndIsEven() {
        let a = ScreenGeometry.outputSize(sourcePixels: CGSize(width: 3024, height: 1964), maxHeight: 1080)
        XCTAssertEqual(a.height, 1080)
        XCTAssertEqual(a.width % 2, 0)
        let b = ScreenGeometry.outputSize(sourcePixels: CGSize(width: 1280, height: 720), maxHeight: 2160)
        XCTAssertEqual(b.width, 1280); XCTAssertEqual(b.height, 720)
        let c = ScreenGeometry.outputSize(sourcePixels: CGSize(width: 1001, height: 501), maxHeight: nil)
        XCTAssertEqual(c.width, 1000); XCTAssertEqual(c.height, 500)
    }

    func testShortcutDisplayAndModifiers() {
        let s = ShortcutAction.startStop.defaultShortcut
        XCTAssertEqual(s.display, "⌃⌥R")
        XCTAssertNotEqual(ShortcutAction.startStop.defaultShortcut, ShortcutAction.pauseResume.defaultShortcut)
    }

    func testBilingualText() {
        L10n.override = "es"; XCTAssertEqual(t("Record", "Grabar"), "Grabar")
        L10n.override = "en"; XCTAssertEqual(t("Record", "Grabar"), "Record")
        L10n.override = nil
    }

}

