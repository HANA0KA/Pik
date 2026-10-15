import AppKit
import AVFoundation
import Foundation

/// Biblioteca persistente (JSON en Application Support) con miniaturas y recuperación de grabaciones interrumpidas.
public final class LibraryStore: ObservableObject {
    public static let shared = LibraryStore()

    @Published public private(set) var items: [LibraryEntry] = []
    private let jsonURL: URL
    private let ioQueue = DispatchQueue(label: "pik.library.io")
    private var saveWork: DispatchWorkItem?

    public init(jsonURL: URL = Storage.libraryJSON) {
        self.jsonURL = jsonURL
        load()
    }

    // MARK: Persistencia

    private func load() {
        guard let data = try? Data(contentsOf: jsonURL) else { return }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let list = try? dec.decode([LibraryEntry].self, from: data) {
            items = list.sorted { $0.createdAt > $1.createdAt }
        } else {
            plogError("library.json ilegible; se respalda y se empieza de cero")
            try? FileManager.default.copyItem(at: jsonURL, to: jsonURL.appendingPathExtension("corrupt"))
        }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let snapshot = items
        let url = jsonURL
        let work = DispatchWorkItem {
            let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? enc.encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
        saveWork = work
        ioQueue.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// Fuerza el guardado inmediato (al cerrar la app).
    public func flush() {
        saveWork?.cancel()
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(items) { try? data.write(to: jsonURL, options: .atomic) }
    }

    // MARK: Consultas

    public func item(id: UUID) -> LibraryEntry? { items.first { $0.id == id } }
    public func item(token: String) -> LibraryEntry? { items.first { $0.shareToken == token } }

    public func items(of kinds: Set<ItemKind>, matching query: String = "") -> [LibraryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { kinds.contains($0.kind) && (q.isEmpty || $0.searchBlob.contains(q)) }
    }

    // MARK: Cambios

    public func add(_ item: LibraryEntry) {
        items.insert(item, at: 0)
        scheduleSave()
    }

    public func update(_ id: UUID, _ change: (inout LibraryEntry) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
        scheduleSave()
    }

    public func rename(_ id: UUID, to title: String) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        update(id) { $0.title = clean }
    }

    public func setPrivacy(_ id: UUID, _ p: PrivacyLevel) { update(id) { $0.privacy = p } }

    /// Elimina el elemento y sus archivos (mueve el video/imagen a la papelera).
    public func delete(_ id: UUID, trashFile: Bool = true) {
        guard let it = item(id: id) else { return }
        if trashFile, let url = it.fileURL, FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        try? FileManager.default.removeItem(at: it.thumbnailURL)
        items.removeAll { $0.id == id }
        scheduleSave()
    }

    // MARK: Miniaturas

    public func makeThumbnail(for item: LibraryEntry, completion: (() -> Void)? = nil) {
        guard let url = item.fileURL else { completion?(); return }
        let dest = item.thumbnailURL
        DispatchQueue.global(qos: .utility).async {
            var cg: CGImage?
            if item.kind == .screenshot {
                if let src = CGImageSourceCreateWithURL(url as CFURL, nil) {
                    cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 640,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                    ] as CFDictionary)
                }
            } else {
                let asset = AVURLAsset(url: url)
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true
                gen.maximumSize = CGSize(width: 640, height: 640)
                let t = CMTime(seconds: min(1.0, max(0, item.duration / 2)), preferredTimescale: 600)
                cg = try? gen.copyCGImage(at: t, actualTime: nil)
                if cg == nil { cg = try? gen.copyCGImage(at: .zero, actualTime: nil) }
            }
            if let cg {
                let rep = NSBitmapImageRep(cgImage: cg)
                if let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                    try? jpg.write(to: dest, options: .atomic)
                }
            }
            DispatchQueue.main.async {
                self.objectWillChange.send()
                completion?()
            }
        }
    }

    public func thumbnail(for item: LibraryEntry) -> NSImage? {
        NSImage(contentsOf: item.thumbnailURL)
    }

    // MARK: Recuperación

    /// Busca grabaciones que quedaron "en progreso" tras un cierre inesperado y las recupera si el archivo es reproducible.
    @discardableResult
    public func recoverInterrupted() async -> [LibraryEntry] {
        var recovered: [LibraryEntry] = []
        for it in items where it.inProgress {
            guard let url = it.fileURL, FileManager.default.fileExists(atPath: url.path) else {
                await MainActor.run { self.delete(it.id, trashFile: false) }
                continue
            }
            let asset = AVURLAsset(url: url)
            let dur = (try? await asset.load(.duration).seconds) ?? 0
            if dur.isFinite, dur > 0.5 {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                await MainActor.run {
                    self.update(it.id) {
                        $0.inProgress = false; $0.recovered = true; $0.duration = dur; $0.fileSize = Int64(size)
                    }
                    if let r = self.item(id: it.id) { recovered.append(r); self.makeThumbnail(for: r) }
                }
                plog("Grabación recuperada: \(it.title) (\(Int(dur)) s)")
            } else {
                await MainActor.run { self.delete(it.id, trashFile: true) }
                plog("Grabación interrumpida sin contenido útil; descartada: \(it.title)")
            }
        }
        return recovered
    }
}
