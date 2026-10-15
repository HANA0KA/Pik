import CoreGraphics
import Foundation

/// Fuente única del dibujo del zorrito Pik. Coordenadas 0...100 (y hacia abajo).
/// La usan el ícono de la app (PikIconGen), el ícono de la barra de menú y las vistas SwiftUI.
public enum FoxArt {
    public enum Style {
        /// Zorro a todo color.
        case color
        /// Silueta de un solo color con ojos y nariz recortados (para íconos "template").
        case silhouette
    }

    public static let orange = CGColor(srgbRed: 1.00, green: 0.478, blue: 0.102, alpha: 1)
    public static let orangeDeep = CGColor(srgbRed: 0.86, green: 0.33, blue: 0.05, alpha: 1)
    public static let cream = CGColor(srgbRed: 1.00, green: 0.96, blue: 0.90, alpha: 1)
    public static let ink = CGColor(srgbRed: 0.13, green: 0.09, blue: 0.20, alpha: 1)
    public static let recRed = CGColor(srgbRed: 1.00, green: 0.23, blue: 0.19, alpha: 1)

    // MARK: Geometría

    static func headPath() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 50, y: 33))
        p.addLine(to: CGPoint(x: 35, y: 29))
        p.addLine(to: CGPoint(x: 16, y: 3))
        p.addLine(to: CGPoint(x: 6, y: 43))
        p.addLine(to: CGPoint(x: 2, y: 58))
        p.addLine(to: CGPoint(x: 50, y: 97))
        p.addLine(to: CGPoint(x: 98, y: 58))
        p.addLine(to: CGPoint(x: 94, y: 43))
        p.addLine(to: CGPoint(x: 84, y: 3))
        p.addLine(to: CGPoint(x: 65, y: 29))
        p.closeSubpath()
        return p
    }

    static func muzzlePath() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 2, y: 58))
        p.addQuadCurve(to: CGPoint(x: 50, y: 56), control: CGPoint(x: 27, y: 68))
        p.addQuadCurve(to: CGPoint(x: 98, y: 58), control: CGPoint(x: 73, y: 68))
        p.addLine(to: CGPoint(x: 50, y: 97))
        p.closeSubpath()
        return p
    }

    static func innerEar(mirrored: Bool) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 18, y: 15))
        p.addLine(to: CGPoint(x: 29, y: 29))
        p.addLine(to: CGPoint(x: 11, y: 38))
        p.closeSubpath()
        return mirrored ? mirror(p) : p
    }

    static func eye(mirrored: Bool) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 24, y: 49))
        p.addQuadCurve(to: CGPoint(x: 43, y: 52), control: CGPoint(x: 34, y: 43))
        p.addQuadCurve(to: CGPoint(x: 24, y: 49), control: CGPoint(x: 33, y: 60))
        p.closeSubpath()
        return mirrored ? mirror(p) : p
    }

    static func nose() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 43, y: 86))
        p.addQuadCurve(to: CGPoint(x: 57, y: 86), control: CGPoint(x: 50, y: 83))
        p.addQuadCurve(to: CGPoint(x: 50, y: 95), control: CGPoint(x: 57, y: 92))
        p.addQuadCurve(to: CGPoint(x: 43, y: 86), control: CGPoint(x: 43, y: 92))
        p.closeSubpath()
        return p
    }

    private static func mirror(_ path: CGPath) -> CGPath {
        var t = CGAffineTransform(translationX: 100, y: 0).scaledBy(x: -1, y: 1)
        return path.copy(using: &t) ?? path
    }

    // MARK: Dibujo

    /// Dibuja el zorro dentro de `rect` (se ajusta manteniendo proporción 1:1, centrado).
    public static func draw(in ctx: CGContext, rect: CGRect, style: Style, tint: CGColor? = nil) {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        ctx.saveGState()
        ctx.translateBy(x: origin.x, y: origin.y)
        ctx.scaleBy(x: side / 100, y: side / 100)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)

        switch style {
        case .color:
            // Sombra suave bajo la cabeza.
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 5,
                          color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28))
            ctx.setFillColor(orange)
            ctx.addPath(headPath())
            ctx.fillPath()
            ctx.restoreGState()
            ctx.setStrokeColor(orange); ctx.setLineWidth(3)
            ctx.addPath(headPath()); ctx.strokePath()

            ctx.setFillColor(cream)
            ctx.addPath(muzzlePath()); ctx.fillPath()
            ctx.setStrokeColor(cream); ctx.setLineWidth(2.5)
            ctx.addPath(muzzlePath()); ctx.strokePath()

            ctx.setFillColor(ink)
            ctx.addPath(innerEar(mirrored: false)); ctx.fillPath()
            ctx.addPath(innerEar(mirrored: true)); ctx.fillPath()
            ctx.addPath(eye(mirrored: false)); ctx.fillPath()
            ctx.addPath(eye(mirrored: true)); ctx.fillPath()
            ctx.addPath(nose()); ctx.fillPath()

            // Brillos de los ojos.
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
            for cx in [35.0, 65.0] {
                ctx.fillEllipse(in: CGRect(x: cx - 1.0, y: 47.0, width: 3.6, height: 3.6))
            }
        case .silhouette:
            ctx.setFillColor(tint ?? CGColor(gray: 0, alpha: 1))
            let all = CGMutablePath()
            all.addPath(headPath())
            all.addPath(eye(mirrored: false))
            all.addPath(eye(mirrored: true))
            all.addPath(nose())
            ctx.addPath(all)
            ctx.fillPath(using: .evenOdd)
            ctx.setStrokeColor(tint ?? CGColor(gray: 0, alpha: 1))
            ctx.setLineWidth(3)
            ctx.addPath(headPath()); ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// Ícono completo de app: baldosa con degradado, zorro, marcas de visor y punto REC.
    public static func drawAppIcon(in ctx: CGContext, size: CGFloat) {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        // Margen estándar de macOS (~10%) alrededor de la baldosa.
        let tile = rect.insetBy(dx: size * 0.098, dy: size * 0.098)
        let radius = tile.width * 0.2237
        let tilePath = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.03,
                      color: CGColor(gray: 0, alpha: 0.35))
        ctx.addPath(tilePath)
        ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.08, blue: 0.2, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(tilePath); ctx.clip()
        let space = CGColorSpaceCreateDeviceRGB()
        let grad = CGGradient(colorsSpace: space, colors: [
            CGColor(srgbRed: 0.27, green: 0.20, blue: 0.52, alpha: 1),
            CGColor(srgbRed: 0.09, green: 0.07, blue: 0.19, alpha: 1),
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: tile.midX, y: tile.maxY),
                               end: CGPoint(x: tile.midX, y: tile.minY), options: [])
        // Resplandor cálido detrás del zorro.
        let glow = CGGradient(colorsSpace: space, colors: [
            CGColor(srgbRed: 1, green: 0.55, blue: 0.2, alpha: 0.38),
            CGColor(srgbRed: 1, green: 0.55, blue: 0.2, alpha: 0),
        ] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: tile.midX, y: tile.midY - tile.height * 0.02),
                               startRadius: 0, endCenter: CGPoint(x: tile.midX, y: tile.midY),
                               endRadius: tile.width * 0.55, options: [])
        ctx.restoreGState()

        // Marcas de visor de cámara.
        let m = tile.width * 0.14
        let arm = tile.width * 0.13
        let lw = tile.width * 0.028
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.62))
        ctx.setLineWidth(lw); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        // Tres esquinas de visor; la cuarta (arriba a la derecha) la ocupa el punto REC.
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: tile.minX + m, y: tile.maxY - m), 1, -1),
            (CGPoint(x: tile.minX + m, y: tile.minY + m), 1, 1),
            (CGPoint(x: tile.maxX - m, y: tile.minY + m), -1, 1),
        ]
        for (pt, dx, dy) in corners {
            ctx.move(to: CGPoint(x: pt.x + dx * arm, y: pt.y))
            ctx.addLine(to: pt)
            ctx.addLine(to: CGPoint(x: pt.x, y: pt.y + dy * arm))
            ctx.strokePath()
        }
        ctx.restoreGState()

        // Zorro (el contexto de CG tiene y hacia arriba: voltear para el espacio 0...100 con y hacia abajo).
        let foxSide = tile.width * 0.60
        let foxRect = CGRect(x: tile.midX - foxSide / 2, y: tile.midY - foxSide / 2 - tile.height * 0.01,
                             width: foxSide, height: foxSide)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: foxRect.midY * 2)
        ctx.scaleBy(x: 1, y: -1)
        draw(in: ctx, rect: foxRect, style: .color)
        ctx.restoreGState()

        // Punto REC con halo.
        let dotR = tile.width * 0.052
        let dotC = CGPoint(x: tile.maxX - m - dotR * 1.1, y: tile.maxY - m - dotR * 1.1)
        ctx.saveGState()
        let halo = CGGradient(colorsSpace: space, colors: [
            CGColor(srgbRed: 1, green: 0.23, blue: 0.19, alpha: 0.55),
            CGColor(srgbRed: 1, green: 0.23, blue: 0.19, alpha: 0),
        ] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(halo, startCenter: dotC, startRadius: 0, endCenter: dotC,
                               endRadius: dotR * 3, options: [])
        ctx.setFillColor(recRed)
        ctx.fillEllipse(in: CGRect(x: dotC.x - dotR, y: dotC.y - dotR, width: dotR * 2, height: dotR * 2))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        ctx.setLineWidth(lw * 0.55)
        ctx.strokeEllipse(in: CGRect(x: dotC.x - dotR, y: dotC.y - dotR, width: dotR * 2, height: dotR * 2))
        ctx.restoreGState()
    }
}
