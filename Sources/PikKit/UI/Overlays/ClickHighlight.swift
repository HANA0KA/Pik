import AppKit
import QuartzCore

/// Anillo que se expande en cada clic del mouse (aparece en la grabación porque es una ventana de pantalla completa sin interacción).
public final class ClickHighlightController {
    private var windows: [(OverlayWindow, CALayer, NSScreen)] = []
    private var globalMonitor: Any?
    private var localMonitor: Any?
    public private(set) var isActive = false

    public init() {}

    public var windowNumbers: [Int] { windows.map { $0.0.windowNumber } }

    public func start() {
        guard !isActive else { return }
        isActive = true
        for screen in NSScreen.screens {
            let w = OverlayWindow(screen: screen, level: PikLevel.overlay, wantsKey: false, clickThrough: true)
            let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            w.contentView = view
            w.orderFrontRegardless()
            windows.append((w, view.layer!, screen))
        }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in self?.ring(at: NSEvent.mouseLocation) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in
            self?.ring(at: NSEvent.mouseLocation); return e
        }
    }

    public func stop() {
        isActive = false
        if let g = globalMonitor { NSEvent.removeMonitor(g) }
        if let l = localMonitor { NSEvent.removeMonitor(l) }
        globalMonitor = nil; localMonitor = nil
        windows.forEach { $0.0.orderOut(nil) }
        windows.removeAll()
    }

    private func ring(at p: CGPoint) {
        guard let (_, layer, screen) = windows.first(where: { NSMouseInRect(p, $0.2.frame, false) }) else { return }
        let local = CGPoint(x: p.x - screen.frame.minX, y: p.y - screen.frame.minY)
        let r: CGFloat = 22
        let ring = CAShapeLayer()
        ring.frame = CGRect(x: local.x - r, y: local.y - r, width: r * 2, height: r * 2)
        ring.path = CGPath(ellipseIn: ring.bounds.insetBy(dx: 2, dy: 2), transform: nil)
        ring.fillColor = Theme.nsAccent.withAlphaComponent(0.28).cgColor
        ring.strokeColor = Theme.nsAccent.cgColor
        ring.lineWidth = 3
        layer.addSublayer(ring)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.55; scale.toValue = 1.9
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1; fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.55
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards
        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
        ring.add(group, forKey: "pulse")
        CATransaction.commit()
    }
}
