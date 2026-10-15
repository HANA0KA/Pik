import AppKit

/// Fondo detrás de todo mientras grabás (cambia el fondo de escritorio solo durante la grabación;
/// en modo ventana/área sale detrás de lo grabado).
public final class RecordingBackgroundController {
    private var windows: [(OverlayWindow, NSImageView, NSScreen)] = []
    public private(set) var currentID: String?

    public init() {}

    public var windowNumbers: [Int] { windows.map { $0.0.windowNumber } }
    public var isShown: Bool { !windows.isEmpty }

    public func show(id: String, onlyOn displayID: CGDirectDisplayID? = nil) {
        hide()
        currentID = id
        for screen in NSScreen.screens {
            if let d = displayID, screen.pikDisplayID != d { continue }
            let w = OverlayWindow(screen: screen, level: PikLevel.background, wantsKey: false, clickThrough: true)
            let view = NSImageView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.imageScaling = .scaleAxesIndependently
            let px = CGSize(width: screen.frame.width * min(screen.backingScaleFactor, 2) / 1.5, height: screen.frame.height * min(screen.backingScaleFactor, 2) / 1.5)
            if let cg = BackgroundStore.shared.cgImage(for: id, size: px) {
                view.image = NSImage(cgImage: cg, size: screen.frame.size)
            }
            w.contentView = view
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            w.orderFront(nil)
            windows.append((w, view, screen))
        }
    }

    public func hide() {
        windows.forEach { $0.0.orderOut(nil) }
        windows.removeAll()
        currentID = nil
    }
}
