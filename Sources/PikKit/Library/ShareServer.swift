import Foundation
import Network
import SystemConfiguration
import Darwin

/// Pedido HTTP mínimo (solo lo necesario para servir páginas y archivos con Range).
struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]

    static func parse(_ data: Data) -> HTTPRequest? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let idx = line.firstIndex(of: ":") else { continue }
            let k = line[..<idx].lowercased()
            let v = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
            headers[String(k)] = v
        }
        let rawPath = String(parts[1])
        let path = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath
        return HTTPRequest(method: String(parts[0]).uppercased(), path: path.removingPercentEncoding ?? path, headers: headers)
    }

    /// "bytes=100-" / "bytes=0-499" → (inicio, fin?)
    func byteRange(fileSize: Int64) -> (start: Int64, end: Int64)? {
        guard let h = headers["range"], h.hasPrefix("bytes=") else { return nil }
        let spec = h.dropFirst(6).split(separator: ",").first ?? ""
        let bounds = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard bounds.count == 2 else { return nil }
        if bounds[0].isEmpty {                       // bytes=-500 → últimos 500
            guard let n = Int64(bounds[1]), n > 0 else { return nil }
            return (max(0, fileSize - n), fileSize - 1)
        }
        guard let s = Int64(bounds[0]), s < fileSize else { return nil }
        let e = Int64(bounds[1]) ?? (fileSize - 1)
        return (s, min(e, fileSize - 1))
    }
}

enum ShareResponse {
    case page(status: Int, html: String)
    case data(contentType: String, body: Data)
    case file(url: URL, contentType: String)
    case notFound
}

/// Resuelve rutas → respuestas. Separado del servidor para poder probarlo sin red.
struct ShareRouter {
    var lookup: (String) -> LibraryEntry?
    var isOwner: Bool

    func route(_ req: HTTPRequest) -> ShareResponse {
        let comps = req.path.split(separator: "/").map(String.init)
        guard let head = comps.first else { return .page(status: 200, html: SharePages.landing()) }
        switch head {
        case "health": return .data(contentType: "text/plain", body: Data("ok".utf8))
        case "v" where comps.count >= 2:
            guard let item = lookup(comps[1]) else { return .page(status: 404, html: SharePages.message(t("Not found", "No encontrado"), t("This link doesn't exist or was deleted.", "Este enlace no existe o fue eliminado."))) }
            guard allowed(item) else { return .page(status: 403, html: SharePages.message(t("Private video", "Video privado"), t("Only the owner can view this. Ask them to change the privacy to “Anyone with the link”.", "Solo su dueño puede verlo. Pedile que cambie la privacidad a «Cualquiera con el enlace»."))) }
            return .page(status: 200, html: SharePages.viewer(item))
        case "media" where comps.count >= 2:
            let token = comps[1].components(separatedBy: ".").first ?? comps[1]
            guard let item = lookup(token), allowed(item), let url = item.fileURL,
                  FileManager.default.fileExists(atPath: url.path) else { return .notFound }
            return .file(url: url, contentType: Self.contentType(for: url))
        case "thumb" where comps.count >= 2:
            let token = comps[1].components(separatedBy: ".").first ?? comps[1]
            guard let item = lookup(token), allowed(item),
                  let data = try? Data(contentsOf: item.thumbnailURL) else { return .notFound }
            return .data(contentType: "image/jpeg", body: data)
        case "vtt" where comps.count >= 2:
            let token = comps[1].components(separatedBy: ".").first ?? comps[1]
            guard let item = lookup(token), allowed(item), !item.transcript.isEmpty else { return .notFound }
            return .data(contentType: "text/vtt; charset=utf-8", body: Data(SharePages.vtt(item.transcript).utf8))
        default:
            return .notFound
        }
    }

    func allowed(_ item: LibraryEntry) -> Bool {
        isOwner || item.privacy == .anyoneWithLink
    }

    static func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "m4a": return "audio/mp4"
        default: return "application/octet-stream"
        }
    }
}

/// Servidor HTTP local para "Copiar enlace": reproduce tus videos en el navegador de quien tenga el enlace (misma red).
public final class ShareServer {
    public static let shared = ShareServer()

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "pik.share.server", qos: .userInitiated)
    public private(set) var port: UInt16 = 0
    public var isRunning: Bool { listener != nil && port != 0 }
    public var lookupOverride: ((String) -> LibraryEntry?)?

    public var onStateChange: (() -> Void)?

    // MARK: Ciclo de vida

    /// Arranca en `preferred` (o el siguiente puerto libre hasta +20). Devuelve el puerto real.
    @discardableResult
    public func start(preferredPort: Int) -> UInt16 {
        stop()
        for offset in 0...20 {
            let p = UInt16(clamping: preferredPort + offset)
            guard let nwPort = NWEndpoint.Port(rawValue: p) else { continue }
            do {
                let l = try NWListener(using: .tcp, on: nwPort)
                let sem = DispatchSemaphore(value: 0)
                var ready = false
                l.stateUpdateHandler = { state in
                    switch state {
                    case .ready: ready = true; sem.signal()
                    case .failed, .cancelled: sem.signal()
                    default: break
                    }
                }
                l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
                l.start(queue: queue)
                _ = sem.wait(timeout: .now() + 2)
                if ready {
                    listener = l
                    port = p
                    plog("Servidor de enlaces escuchando en el puerto \(p)")
                    DispatchQueue.main.async { self.onStateChange?() }
                    return p
                }
                l.cancel()
            } catch { continue }
        }
        plogError("No se pudo abrir ningún puerto para el servidor de enlaces")
        return 0
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        port = 0
        DispatchQueue.main.async { self.onStateChange?() }
    }

    // MARK: Enlaces

    public func link(for item: LibraryEntry) -> URL? {
        guard isRunning, item.kind != .dictation else { return nil }
        return URL(string: "http://\(Self.hostName):\(port)/v/\(item.shareToken)")
    }

    public func lanLink(for item: LibraryEntry) -> URL? {
        guard isRunning, item.kind != .dictation, let ip = Self.lanIPv4() else { return nil }
        return URL(string: "http://\(ip):\(port)/v/\(item.shareToken)")
    }

    public static var hostName: String {
        if let n = SCDynamicStoreCopyLocalHostName(nil) as String? { return "\(n).local" }
        return "localhost"
    }

    public static func lanIPv4() -> String? {
        var result: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard ifa.ifa_addr.pointee.sa_family == UInt8(AF_INET),
                  (ifa.ifa_flags & UInt32(IFF_UP)) != 0, (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(ifa.ifa_addr, socklen_t(ifa.ifa_addr.pointee.sa_len), &host, socklen_t(host.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                result = String(cString: host)
                if name == "en0" { break }
            }
        }
        return result
    }

    // MARK: Conexiones

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { conn.cancel(); return }
            var buf = buffer
            if let data { buf.append(data) }
            if let range = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = buf.subdata(in: 0..<range.lowerBound)
                self.respond(conn, head: head)
            } else if error != nil || isComplete || buf.count > 32_768 {
                conn.cancel()
            } else {
                self.receive(conn, buffer: buf)
            }
        }
    }

    private func isOwner(_ conn: NWConnection) -> Bool {
        guard case let .hostPort(host, _) = conn.endpoint else { return false }
        let s = "\(host)"
        if s.hasPrefix("127.") || s.hasPrefix("::1") || s.contains("::ffff:127.") { return true }
        if let lan = Self.lanIPv4(), s.contains(lan) { return true }
        return false
    }

    private func respond(_ conn: NWConnection, head: Data) {
        guard let req = HTTPRequest.parse(head), req.method == "GET" || req.method == "HEAD" else {
            send(conn, status: 405, headers: [:], body: Data("Method Not Allowed".utf8))
            return
        }
        let lookup: (String) -> LibraryEntry? = lookupOverride ?? { token in
            if Thread.isMainThread { return LibraryStore.shared.item(token: token) }
            return DispatchQueue.main.sync { LibraryStore.shared.item(token: token) }
        }
        let router = ShareRouter(lookup: lookup, isOwner: isOwner(conn))
        let isHead = req.method == "HEAD"
        switch router.route(req) {
        case let .page(status, html):
            send(conn, status: status, headers: ["Content-Type": "text/html; charset=utf-8"], body: isHead ? Data() : Data(html.utf8))
        case let .data(type, body):
            send(conn, status: 200, headers: ["Content-Type": type, "Cache-Control": "no-store"], body: isHead ? Data() : body)
        case .notFound:
            send(conn, status: 404, headers: ["Content-Type": "text/plain"], body: Data("Not found".utf8))
        case let .file(url, type):
            sendFile(conn, req: req, url: url, contentType: type, headOnly: isHead)
        }
    }

    private func statusText(_ s: Int) -> String {
        switch s {
        case 200: return "OK"; case 206: return "Partial Content"; case 403: return "Forbidden"
        case 404: return "Not Found"; case 405: return "Method Not Allowed"; case 416: return "Range Not Satisfiable"
        default: return "OK"
        }
    }

    private func send(_ conn: NWConnection, status: Int, headers: [String: String], body: Data) {
        var h = headers
        h["Content-Length"] = "\(body.count)"
        h["Connection"] = "close"
        var head = "HTTP/1.1 \(status) \(statusText(status))\r\n"
        for (k, v) in h { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        var out = Data(head.utf8); out.append(body)
        conn.send(content: out, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in conn.cancel() })
    }

    private func sendFile(_ conn: NWConnection, req: HTTPRequest, url: URL, contentType: String, headOnly: Bool) {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) else {
            send(conn, status: 404, headers: [:], body: Data()); return
        }
        var start: Int64 = 0, end = size - 1, status = 200
        var headers = ["Content-Type": contentType, "Accept-Ranges": "bytes", "Connection": "close"]
        if req.headers["range"] != nil {
            if let r = req.byteRange(fileSize: size) {
                start = r.start; end = r.end; status = 206
                headers["Content-Range"] = "bytes \(start)-\(end)/\(size)"
            } else {
                headers["Content-Range"] = "bytes */\(size)"
                send(conn, status: 416, headers: headers, body: Data()); return
            }
        }
        let length = max(0, end - start + 1)
        headers["Content-Length"] = "\(length)"
        var head = "HTTP/1.1 \(status) \(statusText(status))\r\n"
        for (k, v) in headers { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        if headOnly {
            conn.send(content: Data(head.utf8), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in conn.cancel() })
            return
        }
        guard let fh = try? FileHandle(forReadingFrom: url) else { conn.cancel(); return }
        try? fh.seek(toOffset: UInt64(start))
        let toSend = length
        conn.send(content: Data(head.utf8), completion: .contentProcessed { [weak self] err in
            guard err == nil else { try? fh.close(); conn.cancel(); return }
            self?.pump(conn, fh: fh, remaining: toSend)
        })
    }

    private func pump(_ conn: NWConnection, fh: FileHandle, remaining: Int64) {
        if remaining <= 0 {
            try? fh.close()
            conn.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in conn.cancel() })
            return
        }
        let chunk = (try? fh.read(upToCount: Int(min(remaining, 512 * 1024)))) ?? Data()
        if chunk.isEmpty {
            try? fh.close(); conn.cancel(); return
        }
        conn.send(content: chunk, completion: .contentProcessed { [weak self] err in
            if err != nil { try? fh.close(); conn.cancel(); return }
            self?.pump(conn, fh: fh, remaining: remaining - Int64(chunk.count))
        })
    }
}
