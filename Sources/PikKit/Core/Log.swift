import Foundation
import OSLog

/// Registro de eventos en archivo (~/Library/Logs/Pik/pik.log) + os.Logger.
public final class Log {
    public static let shared = Log()
    private let logger = Logger(subsystem: "com.pik.desktop", category: "app")
    private let queue = DispatchQueue(label: "pik.log")
    private var handle: FileHandle?
    public let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Pik", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("pik.log")
        // Rotación simple: si pasa de 2 MB, se guarda como .1
        if let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 2_000_000 {
            let old = dir.appendingPathComponent("pik.1.log")
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: fileURL, to: old)
        }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: fileURL)
        _ = try? handle?.seekToEnd()
    }

    private static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public func info(_ message: String, file: String = #fileID) { write("INFO", message, file) }
    public func warn(_ message: String, file: String = #fileID) { write("WARN", message, file) }
    public func error(_ message: String, file: String = #fileID) { write("ERROR", message, file) }

    private func write(_ level: String, _ message: String, _ file: String) {
        switch level {
        case "ERROR": logger.error("\(message, privacy: .public)")
        case "WARN": logger.warning("\(message, privacy: .public)")
        default: logger.info("\(message, privacy: .public)")
        }
        let line = "\(Log.stamp.string(from: Date())) [\(level)] \(file.split(separator: "/").last ?? ""): \(message)\n"
        queue.async { [weak self] in
            if let data = line.data(using: .utf8) { try? self?.handle?.write(contentsOf: data) }
        }
    }
}

public func plog(_ message: String) { Log.shared.info(message) }
public func plogError(_ message: String) { Log.shared.error(message) }
