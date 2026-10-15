import AVFoundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

enum MediaExportError: LocalizedError {
    case failed(String)
    var errorDescription: String? { if case .failed(let m) = self { return m }; return nil }
}

/// Recorte, copia MP4, GIF, audio y subtítulos.
enum MediaExport {
    /// Exporta un rango del video con la misma codificación (sin recomprimir).
    static func exportRange(_ url: URL, start: CMTime, end: CMTime, to dest: URL) async throws {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw MediaExportError.failed(t("Couldn't prepare the export.", "No se pudo preparar la exportación."))
        }
        try? FileManager.default.removeItem(at: dest)
        session.outputURL = dest
        session.outputFileType = .mp4
        session.timeRange = CMTimeRange(start: start, end: end)
        session.shouldOptimizeForNetworkUse = true
        await session.export()
        if session.status != .completed {
            throw MediaExportError.failed(session.error?.localizedDescription ?? t("Export failed.", "Falló la exportación."))
        }
    }

    static func exportAudio(_ url: URL, to dest: URL) async throws {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw MediaExportError.failed(t("This video has no audio to export.", "Este video no tiene audio para exportar."))
        }
        try? FileManager.default.removeItem(at: dest)
        session.outputURL = dest
        session.outputFileType = .m4a
        await session.export()
        if session.status != .completed {
            throw MediaExportError.failed(session.error?.localizedDescription ?? t("Export failed.", "Falló la exportación."))
        }
    }

    /// GIF animado (10 fps, hasta 720 px de ancho y 60 s).
    static func exportGIF(_ url: URL, to dest: URL, fps: Double = 10, maxWidth: CGFloat = 720, progress: @escaping (Double) -> Void) async throws {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let total = min(duration, 60)
        let count = max(1, Int(total * fps))
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxWidth, height: maxWidth)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
        guard let dst = CGImageDestinationCreateWithURL(dest as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw MediaExportError.failed(t("Couldn't create the GIF.", "No se pudo crear el GIF."))
        }
        CGImageDestinationSetProperties(dst, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / fps]] as CFDictionary
        let times = (0..<count).map { CMTime(seconds: Double($0) / fps, preferredTimescale: 600) }
        var done = 0
        for await result in gen.images(for: times) {
            if case .success(_, let image, _) = result {
                CGImageDestinationAddImage(dst, image, frameProps)
            }
            done += 1
            progress(Double(done) / Double(count))
        }
        guard CGImageDestinationFinalize(dst) else { throw MediaExportError.failed(t("Couldn't write the GIF.", "No se pudo escribir el GIF.")) }
    }

    // MARK: Subtítulos y texto

    static func srt(_ segments: [TranscriptSegment]) -> String {
        func stamp(_ s: TimeInterval) -> String {
            let ms = Int((s * 1000).rounded())
            return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
        }
        return segments.enumerated().map { i, seg in
            "\(i + 1)\n\(stamp(seg.start)) --> \(stamp(seg.start + max(seg.duration, 0.5)))\n\(seg.text)\n"
        }.joined(separator: "\n")
    }

    @MainActor
    static func savePanel(name: String, type: UTType) -> URL? {
        let p = NSSavePanel()
        p.nameFieldStringValue = name
        p.allowedContentTypes = [type]
        p.canCreateDirectories = true
        return p.runModal() == .OK ? p.url : nil
    }
}
