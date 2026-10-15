import XCTest
@testable import PikKit

final class ShareServerTests: XCTestCase {
    private func makeItem(privacy: PrivacyLevel, file: URL?) -> LibraryEntry {
        var it = LibraryEntry(kind: .video, title: "Demo <b>", filePath: file?.path, duration: 12, privacy: privacy)
        it.transcript = [TranscriptSegment(id: 0, start: 1, duration: 2, text: "hola mundo")]
        return it
    }

    func testRouterPrivacyAndOwner() {
        let item = makeItem(privacy: .onlyMe, file: nil)
        let guest = ShareRouter(lookup: { $0 == item.shareToken ? item : nil }, isOwner: false)
        let owner = ShareRouter(lookup: { $0 == item.shareToken ? item : nil }, isOwner: true)
        let req = HTTPRequest(method: "GET", path: "/v/\(item.shareToken)", headers: [:])
        if case let .page(status, _) = guest.route(req) { XCTAssertEqual(status, 403) } else { XCTFail() }
        if case let .page(status, html) = owner.route(req) {
            XCTAssertEqual(status, 200)
            XCTAssertTrue(html.contains("Demo &lt;b&gt;"), "el título debe escaparse")
            XCTAssertTrue(html.contains("hola mundo"))
        } else { XCTFail() }
        let missing = HTTPRequest(method: "GET", path: "/v/nope", headers: [:])
        if case let .page(status, _) = owner.route(missing) { XCTAssertEqual(status, 404) } else { XCTFail() }
    }

    func testByteRangeParsing() {
        let r = HTTPRequest(method: "GET", path: "/", headers: ["range": "bytes=10-19"])
        XCTAssertEqual(r.byteRange(fileSize: 100)?.start, 10)
        XCTAssertEqual(r.byteRange(fileSize: 100)?.end, 19)
        let open = HTTPRequest(method: "GET", path: "/", headers: ["range": "bytes=90-"])
        XCTAssertEqual(open.byteRange(fileSize: 100)?.end, 99)
        let suffix = HTTPRequest(method: "GET", path: "/", headers: ["range": "bytes=-5"])
        XCTAssertEqual(suffix.byteRange(fileSize: 100)?.start, 95)
        let bad = HTTPRequest(method: "GET", path: "/", headers: ["range": "bytes=500-"])
        XCTAssertNil(bad.byteRange(fileSize: 100))
    }

    func testLiveServerServesPageAndRanges() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pik-share-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("v.mp4")
        let payload = Data((0..<5000).map { UInt8($0 % 251) })
        try payload.write(to: file)
        let item = makeItem(privacy: .anyoneWithLink, file: file)

        let server = ShareServer()
        server.lookupOverride = { $0 == item.shareToken ? item : nil }
        let port = server.start(preferredPort: 18_420)
        XCTAssertNotEqual(port, 0)
        defer { server.stop() }

        func get(_ path: String, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
            var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            let (d, r) = try await URLSession(configuration: .ephemeral).data(for: req)
            return (d, r as! HTTPURLResponse)
        }
        let (page, pr) = try await get("/v/\(item.shareToken)")
        XCTAssertEqual(pr.statusCode, 200)
        XCTAssertTrue(String(decoding: page, as: UTF8.self).contains("<video"))

        let (full, fr) = try await get("/media/\(item.shareToken).mp4")
        XCTAssertEqual(fr.statusCode, 200)
        XCTAssertEqual(full, payload)

        let (part, rr) = try await get("/media/\(item.shareToken).mp4", headers: ["Range": "bytes=100-199"])
        XCTAssertEqual(rr.statusCode, 206)
        XCTAssertEqual(part, payload.subdata(in: 100..<200))
        XCTAssertEqual(rr.value(forHTTPHeaderField: "Content-Range"), "bytes 100-199/5000")

        let (_, nf) = try await get("/media/zzzz")
        XCTAssertEqual(nf.statusCode, 404)
    }
}
