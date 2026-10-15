import AppKit
import CoreGraphics
import ImageIO
import PikKit
import UniformTypeIdentifiers

// Uso: PikIconGen <directorio-salida>
// Genera Pik.iconset (para iconutil) y los PNG del ícono de barra de menú.

func renderPNG(size: Int, to url: URL, draw: (CGContext, CGFloat) -> Void) throws {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                              space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw NSError(domain: "PikIconGen", code: 1)
    }
    ctx.interpolationQuality = .high
    draw(ctx, CGFloat(size))
    guard let img = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "PikIconGen", code: 2)
    }
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "PikIconGen", code: 3) }
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("uso: PikIconGen <directorio-salida>\n".utf8))
    exit(2)
}
let out = URL(fileURLWithPath: args[1], isDirectory: true)
let iconset = out.appendingPathComponent("Pik.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]
for (px, name) in sizes {
    try renderPNG(size: px, to: iconset.appendingPathComponent(name)) { ctx, s in
        FoxArt.drawAppIcon(in: ctx, size: s)
    }
}
// Vista previa grande para revisar a ojo.
try renderPNG(size: 1024, to: out.appendingPathComponent("AppIcon-1024.png")) { ctx, s in
    FoxArt.drawAppIcon(in: ctx, size: s)
}
// Ícono de barra de menú (template: negro + alfa). 18pt @1x/@2x/@3x.
for (scale, suffix) in [(1, ""), (2, "@2x"), (3, "@3x")] {
    try renderPNG(size: 18 * scale, to: out.appendingPathComponent("MenuBarIconTemplate\(suffix).png")) { ctx, s in
        // y arriba en CG: voltear.
        ctx.translateBy(x: 0, y: s); ctx.scaleBy(x: 1, y: -1)
        FoxArt.draw(in: ctx, rect: CGRect(x: s * 0.04, y: s * 0.04, width: s * 0.92, height: s * 0.92), style: .silhouette)
    }
}
print("ok: \(out.path)")
