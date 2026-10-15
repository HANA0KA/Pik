import Foundation

/// Rutas del disco y chequeo de espacio libre.
public enum Storage {
    public static let appSupport: URL = {
        // PIK_DATA_DIR permite aislar los datos (pruebas y capturas de interfaz sin tocar tu biblioteca).
        let u = ProcessInfo.processInfo.environment["PIK_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Pik", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    /// Carpeta donde viven los videos (por defecto ~/Movies/Pik).
    public static func videosFolder(_ prefs: Preferences = .shared) -> URL {
        let base: URL
        if let p = prefs.libraryFolderPath, !p.isEmpty {
            base = URL(fileURLWithPath: p, isDirectory: true)
        } else {
            base = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Pik", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    public static var thumbnailsFolder: URL { sub("Thumbnails") }
    public static var backgroundsFolder: URL { sub("Backgrounds") }
    public static var transcriptsFolder: URL { sub("Transcripts") }
    public static var contextFolder: URL { sub("Context") }
    public static var recordingsInProgress: URL { sub("InProgress") }

    public static var notesJSON: URL { appSupport.appendingPathComponent("notes.json") }
    public static var libraryJSON: URL { appSupport.appendingPathComponent("library.json") }

    private static func sub(_ name: String) -> URL {
        let u = appSupport.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// Bytes libres en el volumen de `url` (para importantes, que es lo que macOS puede liberar).
    public static func freeBytes(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? Int64.max
    }

    /// Menos de ~1 GB libre: avisar antes de grabar.
    public static func isLowOnSpace(_ prefs: Preferences = .shared) -> Bool {
        freeBytes(at: videosFolder(prefs)) < 1_000_000_000
    }

    public static func uniqueURL(in folder: URL, baseName: String, ext: String) -> URL {
        let safe = Fmt.safeFileName(baseName)
        var url = folder.appendingPathComponent(safe).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(safe) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return url
    }
}
