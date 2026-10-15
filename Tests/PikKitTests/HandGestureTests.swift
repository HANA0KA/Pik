import XCTest
import CoreMedia
import CoreVideo
@testable import PikKit

final class HandGestureTests: XCTestCase {
    /// Mano sintética mirando hacia arriba. `curl` 0 = dedos abiertos, 1 = puño.
    private func hand(curl: Double, thumbOut: Bool = true, left: Bool = false) -> HandShape {
        var pts = [CGPoint](repeating: .zero, count: 21)
        pts[0] = CGPoint(x: 0, y: 0)
        // pulgar (índices 1…4)
        for k in 0..<4 {
            let f = Double(k + 1) / 4
            pts[1 + k] = thumbOut ? CGPoint(x: -0.35 - 0.5 * f, y: 0.25 + 0.45 * f * (1 - curl * 0.6)) : CGPoint(x: -0.3 + 0.2 * f, y: 0.3 + 0.2 * f)
        }
        // cuatro dedos: base en y = 1 y abanico en x
        let xs = [-0.30, -0.10, 0.10, 0.30]
        for (i, x) in xs.enumerated() {
            let base = 5 + i * 4
            for k in 0..<4 {
                let f = Double(k) / 3
                let length = 0.9 * (1 - curl * 0.85)
                pts[base + k] = CGPoint(x: x + 0.05 * Double(i - 1) * f, y: 1.0 + length * f - curl * 0.5 * f * f)
            }
        }
        return HandShape(points: pts, isLeft: left)
    }

    private func transformed(_ s: HandShape, scale: Double, angleDeg: Double, dx: Double, dy: Double) -> HandShape {
        let a = angleDeg * .pi / 180
        let pts = s.points.map { p -> CGPoint in
            let x = Double(p.x) * scale, y = Double(p.y) * scale
            return CGPoint(x: x * cos(a) - y * sin(a) + dx, y: x * sin(a) + y * cos(a) + dy)
        }
        return HandShape(points: pts, isLeft: s.isLeft)
    }

    func testSameGestureMatchesWhenMovedScaledAndTilted() {
        let open = hand(curl: 0)
        let live = transformed(open, scale: 0.4, angleDeg: 18, dx: 0.5, dy: 0.3)
        XCTAssertTrue(GestureMatcher.matches(live, open))
        XCTAssertLessThan(GestureMatcher.distance(live, open) ?? 9, 0.02)
    }

    func testDifferentGesturesDoNotMatch() {
        let open = hand(curl: 0), fist = hand(curl: 1), half = hand(curl: 0.5)
        XCTAssertFalse(GestureMatcher.matches(fist, open))
        XCTAssertFalse(GestureMatcher.matches(open, fist))
        XCTAssertFalse(GestureMatcher.matches(half, open))
        XCTAssertFalse(GestureMatcher.matches(half, fist))
    }

    func testOppositeHandOrBigRotationDoNotMatch() {
        let open = hand(curl: 0)
        XCTAssertFalse(GestureMatcher.matches(hand(curl: 0, left: true), open))
        XCTAssertFalse(GestureMatcher.matches(transformed(open, scale: 1, angleDeg: 120, dx: 0, dy: 0), open), "mano girada 120° no debe valer")
    }

    func testBestPicksClosestTemplate() {
        let a = GestureTemplate(action: .start, shape: hand(curl: 0))
        let b = GestureTemplate(action: .pause, shape: hand(curl: 1))
        let live = transformed(hand(curl: 0.97), scale: 0.3, angleDeg: -10, dx: 0.2, dy: 0.6)
        XCTAssertEqual(GestureMatcher.best(for: live, in: [a, b])?.action, .pause)
        XCTAssertNil(GestureMatcher.best(for: hand(curl: 0.5), in: [a, b]))
    }

    func testAverageNeedsSteadyHand() {
        let steady = (0..<10).map { i in transformed(hand(curl: 0.0), scale: 0.4, angleDeg: Double(i % 3), dx: 0.01 * Double(i), dy: 0) }
        let avg = GestureMatcher.average(steady)
        XCTAssertNotNil(avg)
        XCTAssertTrue(GestureMatcher.matches(hand(curl: 0), avg!))
        let shaky = (0..<10).map { i in hand(curl: Double(i) / 9) }
        XCTAssertNil(GestureMatcher.average(shaky), "una mano que cambia de pose no se puede guardar")
        XCTAssertNil(GestureMatcher.average(Array(steady.prefix(3))), "muy pocos cuadros")
    }

    func testTriggerNeedsHoldAndCooldown() {
        let tpl = GestureTemplate(action: .start, shape: hand(curl: 0))
        var trig = GestureTrigger(holdFrames: 3, cooldown: 2)
        let t0 = Date()
        XCTAssertNil(trig.feed(tpl, now: t0))
        XCTAssertNil(trig.feed(tpl, now: t0))
        XCTAssertNotNil(trig.feed(tpl, now: t0))
        for _ in 0..<5 { XCTAssertNil(trig.feed(tpl, now: t0.addingTimeInterval(0.5)), "enfriamiento") }
        XCTAssertNil(trig.feed(nil, now: t0.addingTimeInterval(1)))
        for _ in 0..<2 { XCTAssertNil(trig.feed(tpl, now: t0.addingTimeInterval(3))) }
        XCTAssertNotNil(trig.feed(tpl, now: t0.addingTimeInterval(3)))
    }

    func testStorePersistsAndDetectsConflicts() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gestures-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = GestureStore(url: url)
        store.set(hand(curl: 0), for: .start)
        store.set(hand(curl: 1), for: .pause)
        store.set(hand(curl: 0.02), for: .start)           // reemplaza
        XCTAssertEqual(store.templates.count, 2)
        XCTAssertEqual(GestureStore(url: url).templates.count, 2)
        XCTAssertNotNil(store.conflict(for: hand(curl: 0.98), excluding: .stop))
        XCTAssertNil(store.conflict(for: transformed(hand(curl: 0.5, thumbOut: false), scale: 1, angleDeg: 90, dx: 0, dy: 0), excluding: .stop))
        store.remove(.pause)
        XCTAssertNil(GestureStore(url: url).template(for: .pause))
    }
}

final class HandVisionPlumbingTests: XCTestCase {
    /// Un cuadro sin mano debe dar nil (y no romper): comprueba que Vision corre sobre un CMSampleBuffer real.
    func testBlankFrameHasNoHand() throws {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 640, 480, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb)
        let buffer = try XCTUnwrap(pb)
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer)!, 128, CVPixelBufferGetBytesPerRow(buffer) * 480)
        CVPixelBufferUnlockBaseAddress(buffer, [])
        var fd: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &fd)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sb: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: fd!, sampleTiming: &timing, sampleBufferOut: &sb)
        XCTAssertNil(HandGestureService.detect(in: try XCTUnwrap(sb)))
    }
}
