import AppKit

public enum PikLevel {
    public static let background = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
    public static let overlay = NSWindow.Level(rawValue: 3)         // resaltado de clics, dibujo
    public static let bubble = NSWindow.Level(rawValue: 4)
    public static let selection = NSWindow.Level(rawValue: 5)       // debajo de la barra para poder apretar "Grabar"
    public static let notes = NSWindow.Level(rawValue: 6)
    public static let controls = NSWindow.Level(rawValue: 7)
    public static let modal = NSWindow.Level(rawValue: 8)
    public static let top = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) - 1)
}

/// Ventana que cubre una pantalla completa (para selección, dibujo, cuenta regresiva…).
public final class OverlayWindow: NSWindow {
    public var wantsKey = true
    public var onKeyDown: ((NSEvent) -> Bool)?

    public init(screen: NSScreen, level: NSWindow.Level, wantsKey: Bool = true, clickThrough: Bool = false) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        self.wantsKey = wantsKey
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = clickThrough
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        animationBehavior = .none
        setFrame(screen.frame, display: false)
    }

    public override var canBecomeKey: Bool { wantsKey }
    public override var canBecomeMain: Bool { false }

    public override func keyDown(with event: NSEvent) {
        if let onKeyDown, onKeyDown(event) { return }
        super.keyDown(with: event)
    }
}

extension NSScreen {
    var pikDisplayID: CGDirectDisplayID { ScreenGeometry.displayID(of: self) }
}
