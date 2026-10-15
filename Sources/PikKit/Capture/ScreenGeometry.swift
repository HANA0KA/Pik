import AppKit
import CoreGraphics

/// Conversión entre el espacio de AppKit (origen abajo-izquierda de la pantalla principal)
/// y el espacio de Quartz / ScreenCaptureKit (origen arriba-izquierda de la pantalla principal).
public enum ScreenGeometry {
    public static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    public static func quartz(fromAppKit r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    public static func appKit(fromQuartz r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    public static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }

    public static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { self.displayID(of: $0) == displayID }
    }

    /// Pantalla bajo el mouse (o la principal).
    public static func screenUnderMouse() -> NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    public static func screenContaining(window: NSWindow) -> NSScreen {
        window.screen ?? screenUnderMouse()
    }

    /// Ajusta dimensiones al límite de resolución (sin ampliar) y las deja pares.
    public static func outputSize(sourcePixels: CGSize, maxHeight: Int?) -> (width: Int, height: Int) {
        var w = sourcePixels.width, h = sourcePixels.height
        if let maxH = maxHeight, h > CGFloat(maxH) {
            let f = CGFloat(maxH) / h
            w *= f; h *= f
        }
        return (max(2, Int(w.rounded()) & ~1), max(2, Int(h.rounded()) & ~1))
    }
}
