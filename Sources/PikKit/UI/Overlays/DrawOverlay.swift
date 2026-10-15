import AppKit

/// Herramienta de dibujo para marcar la pantalla mientras grabás. Los trazos se desvanecen solos (o se quedan hasta borrarlos).
final class DrawCanvasView: NSView {
    struct Stroke {
        var points: [CGPoint]
        var color: NSColor
        var created: Date
        var width: CGFloat
    }
    var strokes: [Stroke] = []
    var current: Stroke?
    var color: NSColor = Theme.nsRec
    var persistent = false
    var isDrawingEnabled = false {
        didSet {
            window?.ignoresMouseEvents = !isDrawingEnabled
            if isDrawingEnabled { NSCursor.crosshair.set() } else { cancelStroke(); NSCursor.arrow.set() }
        }
    }
    private var timer: Timer?
    private let lifetime: TimeInterval = 4

    override init(frame: NSRect) {
        super.init(frame: frame)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { timer?.invalidate() }

    override func resetCursorRects() { if isDrawingEnabled { addCursorRect(bounds, cursor: .crosshair) } }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func tick() {
        guard !strokes.isEmpty || current != nil else { return }
        if !persistent { strokes.removeAll { Date().timeIntervalSince($0.created) > lifetime + 0.6 } }
        needsDisplay = true
    }

    func clear() { strokes.removeAll(); current = nil; needsDisplay = true }

    /// Cierra el trazo en curso (si el usuario desactiva el lápiz con el botón apretado).
    private func cancelStroke() {
        guard var s = current else { return }
        s.created = Date()
        strokes.append(s); current = nil; needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isDrawingEnabled else { return }
        current = Stroke(points: [convert(event.locationInWindow, from: nil)], color: color, created: Date(), width: 5)
    }
    override func mouseDragged(with event: NSEvent) {
        guard isDrawingEnabled, current != nil else { return }
        current?.points.append(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard var s = current else { return }
        s.created = Date()
        strokes.append(s); current = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        func render(_ s: Stroke, alpha: CGFloat) {
            guard s.points.count > 1 else {
                if let p = s.points.first {
                    ctx.setFillColor(s.color.withAlphaComponent(alpha).cgColor)
                    ctx.fillEllipse(in: CGRect(x: p.x - s.width / 2, y: p.y - s.width / 2, width: s.width, height: s.width))
                }
                return
            }
            ctx.setStrokeColor(s.color.withAlphaComponent(alpha).cgColor)
            ctx.setLineWidth(s.width)
            ctx.beginPath()
            ctx.move(to: s.points[0])
            for i in 1..<s.points.count {
                let mid = CGPoint(x: (s.points[i - 1].x + s.points[i].x) / 2, y: (s.points[i - 1].y + s.points[i].y) / 2)
                ctx.addQuadCurve(to: mid, control: s.points[i - 1])
            }
            ctx.addLine(to: s.points.last!)
            ctx.strokePath()
        }
        for s in strokes {
            let age = Date().timeIntervalSince(s.created)
            let alpha: CGFloat = persistent ? 1 : max(0, min(1, 1 - (age - lifetime) / 0.6))
            render(s, alpha: alpha)
        }
        if let c = current { render(c, alpha: 1) }
    }
}

public final class DrawOverlayController {
    private var windows: [(OverlayWindow, DrawCanvasView)] = []
    public private(set) var isEnabled = false
    public var color: NSColor = Theme.nsRec { didSet { windows.forEach { $0.1.color = color } } }
    public var persistent = false { didSet { windows.forEach { $0.1.persistent = persistent } } }

    public init() {}

    public var windowNumbers: [Int] { windows.map { $0.0.windowNumber } }

    public func show() {
        guard windows.isEmpty else { return }
        for screen in NSScreen.screens {
            let w = OverlayWindow(screen: screen, level: PikLevel.overlay, wantsKey: false, clickThrough: true)
            let v = DrawCanvasView(frame: CGRect(origin: .zero, size: screen.frame.size))
            v.color = color; v.persistent = persistent
            w.contentView = v
            w.orderFrontRegardless()
            windows.append((w, v))
        }
    }

    public func setEnabled(_ on: Bool) {
        if on { show() }
        isEnabled = on
        windows.forEach { $0.1.isDrawingEnabled = on; $0.0.ignoresMouseEvents = !on; $0.0.invalidateCursorRects(for: $0.1) }
        if on { NSCursor.crosshair.set() } else { NSCursor.arrow.set() }
    }

    public func clear() { windows.forEach { $0.1.clear() } }

    public func hide() {
        isEnabled = false
        windows.forEach { $0.0.orderOut(nil) }
        windows.removeAll()
    }
}
