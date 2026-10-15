import AppKit
import CoreImage
import Foundation

public struct BackgroundItem: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let isCustom: Bool
    fileprivate var colors: [String] = []
    fileprivate var angle: CGFloat = 0
}

/// Fondos para detrás de la grabación y para la cámara: degradados propios, fondo difuminado del escritorio e imágenes del usuario.
public final class BackgroundStore: ObservableObject {
    public static let shared = BackgroundStore()
    public static let wallpaperBlurID = "wallpaper-blur"

    @Published public private(set) var customs: [BackgroundItem] = []
    public let builtins: [BackgroundItem]
    private var cache: [String: CGImage] = [:]

    private init() {
        func g(_ id: String, _ name: String, _ colors: [String], _ angle: CGFloat) -> BackgroundItem {
            var b = BackgroundItem(id: "builtin:\(id)", name: name, isCustom: false)
            b.colors = colors; b.angle = angle
            return b
        }
        builtins = [
            g("aurora", t("Aurora", "Aurora"), ["#1B1464", "#3A6BD1", "#46E6B6"], 35),
            g("sunset", t("Sunset", "Atardecer"), ["#2B1055", "#D4357A", "#FF9A3C"], 60),
            g("ocean", t("Ocean", "Océano"), ["#021B3A", "#0A5C9E", "#5BD1E8"], 80),
            g("forest", t("Forest", "Bosque"), ["#08210F", "#1F6B3A", "#B6E36B"], 50),
            g("midnight", t("Midnight", "Medianoche"), ["#0B0A14", "#241F45", "#5A4FA8"], 70),
            g("fox", t("Fox", "Zorro"), ["#5A1E05", "#E6560C", "#FFC46B"], 40),
            g("lavender", t("Lavender", "Lavanda"), ["#4B2F8F", "#9C7BE8", "#F4D5FF"], 55),
            g("mint", t("Mint", "Menta"), ["#0E4F4A", "#3FBFA0", "#F2FFE0"], 30),
        ]
        loadCustoms()
    }

    public var all: [BackgroundItem] { builtins + customs }

    public func item(id: String?) -> BackgroundItem? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    // MARK: Imágenes personalizadas

    private func loadCustoms() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Storage.backgroundsFolder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        customs = files.filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
            .sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
            .map { BackgroundItem(id: "custom:\($0.lastPathComponent)", name: t("My image", "Mi imagen"), isCustom: true) }
    }

    @discardableResult
    public func importImage(from url: URL) throws -> BackgroundItem {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 3840,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else {
            throw NSError(domain: "Pik", code: 1, userInfo: [NSLocalizedDescriptionKey: t("Failed to import custom background image", "No se pudo importar la imagen de fondo")])
        }
        let name = "\(UUID().uuidString).jpg"
        let dest = Storage.backgroundsFolder.appendingPathComponent(name)
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            throw NSError(domain: "Pik", code: 2)
        }
        try data.write(to: dest)
        let item = BackgroundItem(id: "custom:\(name)", name: t("My image", "Mi imagen"), isCustom: true)
        customs.append(item)
        plog("Fondo personalizado importado: \(name)")
        return item
    }

    public func delete(_ id: String) {
        guard id.hasPrefix("custom:") else { return }
        let name = String(id.dropFirst("custom:".count))
        try? FileManager.default.removeItem(at: Storage.backgroundsFolder.appendingPathComponent(name))
        customs.removeAll { $0.id == id }
        cache = cache.filter { !$0.key.hasPrefix(id) }
        if Preferences.shared.recordingBackgroundID == id { Preferences.shared.recordingBackgroundID = nil }
        if Preferences.shared.cameraEffectImageID == id { Preferences.shared.cameraEffectImageID = nil }
        plog("Fondo personalizado eliminado: \(name)")
    }

    // MARK: Render

    /// Imagen del fondo a tamaño `size` (píxeles). El caché evita recalcular degradados grandes.
    public func cgImage(for id: String, size: CGSize) -> CGImage? {
        let key = "\(id)@\(Int(size.width))x\(Int(size.height))"
        if let c = cache[key] { return c }
        var image: CGImage?
        if id == Self.wallpaperBlurID {
            image = blurredWallpaper(size: size)
        } else if id.hasPrefix("custom:") {
            let url = Storage.backgroundsFolder.appendingPathComponent(String(id.dropFirst(7)))
            if let src = CGImageSourceCreateWithURL(url as CFURL, nil), let raw = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                image = aspectFill(raw, to: size)
            }
        } else if let b = builtins.first(where: { $0.id == id }) {
            image = gradient(b, size: size)
        }
        if let image { if cache.count > 12 { cache.removeAll() }; cache[key] = image }
        return image
    }

    public func thumbnail(for id: String) -> NSImage {
        let s = CGSize(width: 160, height: 100)
        if let cg = cgImage(for: id, size: s) { return NSImage(cgImage: cg, size: s) }
        return NSImage(size: s)
    }

    private func context(_ size: CGSize) -> CGContext? {
        CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private func gradient(_ b: BackgroundItem, size: CGSize) -> CGImage? {
        guard let ctx = context(size) else { return nil }
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let cols = b.colors.map { Theme.nsColor(hex: $0).cgColor }
        guard let grad = CGGradient(colorsSpace: cs, colors: cols as CFArray, locations: nil) else { return nil }
        let rad = b.angle * .pi / 180
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let len = (abs(cos(rad)) * size.width + abs(sin(rad)) * size.height) / 2
        ctx.drawLinearGradient(grad, start: CGPoint(x: c.x - cos(rad) * len, y: c.y - sin(rad) * len),
                               end: CGPoint(x: c.x + cos(rad) * len, y: c.y + sin(rad) * len),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        // Manchas de luz suaves para darle profundidad.
        let glow = CGGradient(colorsSpace: cs, colors: [CGColor(gray: 1, alpha: 0.18), CGColor(gray: 1, alpha: 0)] as CFArray, locations: nil)!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: size.width * 0.2, y: size.height * 0.85), startRadius: 0,
                               endCenter: CGPoint(x: size.width * 0.2, y: size.height * 0.85), endRadius: size.width * 0.5, options: [])
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: size.width * 0.85, y: size.height * 0.2), startRadius: 0,
                               endCenter: CGPoint(x: size.width * 0.85, y: size.height * 0.2), endRadius: size.width * 0.4, options: [])
        return ctx.makeImage()
    }

    private func aspectFill(_ img: CGImage, to size: CGSize) -> CGImage? {
        guard let ctx = context(size) else { return nil }
        let iw = CGFloat(img.width), ih = CGFloat(img.height)
        let scale = max(size.width / iw, size.height / ih)
        let w = iw * scale, h = ih * scale
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
        return ctx.makeImage()
    }

    private func blurredWallpaper(size: CGSize) -> CGImage? {
        guard let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let raw = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let filled = aspectFill(raw, to: size) else {
            return gradient(builtins[4], size: size)
        }
        let ci = CIImage(cgImage: filled)
        let blurred = ci.clampedToExtent().applyingGaussianBlur(sigma: Double(size.width) / 60).cropped(to: ci.extent)
        let darker = blurred.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.08, kCIInputSaturationKey: 1.15])
        return CIContext().createCGImage(darker, from: ci.extent)
    }
}

private extension URL {
    var creationDate: Date? { (try? resourceValues(forKeys: [.creationDateKey]))?.creationDate }
}
