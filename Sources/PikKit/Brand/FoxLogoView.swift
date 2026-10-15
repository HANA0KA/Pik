import AppKit
import SwiftUI

/// Zorrito de Pik como vista SwiftUI (usa el mismo dibujo que el ícono de la app).
public struct FoxLogoView: View {
    public var size: CGFloat
    public var style: FoxArt.Style
    public var tint: Color?

    public init(size: CGFloat = 64, style: FoxArt.Style = .color, tint: Color? = nil) {
        self.size = size; self.style = style; self.tint = tint
    }

    public var body: some View {
        Canvas { ctx, sz in
            ctx.withCGContext { cg in
                // SwiftUI ya usa y hacia abajo: coincide con FoxArt.
                FoxArt.draw(in: cg, rect: CGRect(origin: .zero, size: sz), style: style,
                            tint: tint.map { NSColor($0).cgColor })
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Pik")
    }
}

/// Ícono grande tipo app (baldosa + zorro + visor + punto REC) para bienvenida y "Acerca de".
public struct PikAppIconView: View {
    public var size: CGFloat
    public init(size: CGFloat = 96) { self.size = size }

    public var body: some View {
        Canvas { ctx, sz in
            ctx.withCGContext { cg in
                // drawAppIcon espera y hacia arriba (CGContext "puro").
                cg.translateBy(x: 0, y: sz.height)
                cg.scaleBy(x: 1, y: -1)
                FoxArt.drawAppIcon(in: cg, size: sz.width)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Pik")
    }
}

public enum MenuBarIcon {
    /// Ícono template de la barra de menú (negro + alfa → macOS lo tiñe solo).
    public static func template() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            FoxArt.draw(in: cg, rect: rect.insetBy(dx: 0.6, dy: 0.6), style: .silhouette)
            return true
        }
        img.isTemplate = true
        return img
    }

    /// Versión grabando: zorro + punto rojo (no template, para conservar el rojo).
    public static func recording(paused: Bool = false) -> NSImage {
        let img = NSImage(size: NSSize(width: 22, height: 18), flipped: true) { rect in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let fg = isDark ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0, alpha: 1)
            FoxArt.draw(in: cg, rect: CGRect(x: 0.6, y: 0.6, width: 16.8, height: 16.8), style: .silhouette, tint: fg)
            cg.setFillColor(paused ? CGColor(srgbRed: 1, green: 0.78, blue: 0.1, alpha: 1) : FoxArt.recRed)
            cg.fillEllipse(in: CGRect(x: 14.5, y: 0.5, width: 7, height: 7))
            return true
        }
        img.isTemplate = false
        return img
    }
}
