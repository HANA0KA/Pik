import AppKit

/// Vista que dibuja el área elegida y deja moverla/redimensionarla (grabación de tamaño personalizado) o la
/// confirma al soltar el mouse (capturas de pantalla).
final class AreaSelectionView: NSView {
    enum Kind { case recording, screenshot }
    private enum Drag { case none, creating(CGPoint), moving(CGPoint, CGRect), resizing(Handle, CGRect) }
    private enum Handle: CaseIterable { case tl, t, tr, r, br, b, bl, l }

    let kind: Kind
    var rect: CGRect = .zero { didSet { needsDisplay = true; onChange?(rect) } }
    var aspect: CGFloat? = nil { didSet { if let a = aspect, rect.width > 10 { applyAspect(a) } } }
    var onChange: ((CGRect) -> Void)?
    var onConfirm: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var drag: Drag = .none
    private let handleSize: CGFloat = 10
    private let minSize: CGFloat = 80

    init(frame: CGRect, kind: Kind) {
        self.kind = kind
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: Dibujo

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let dim = NSColor.black.withAlphaComponent(kind == .screenshot ? 0.32 : 0.5)
        ctx.setFillColor(dim.cgColor)
        if rect.width > 1 && rect.height > 1 {
            ctx.addRect(bounds); ctx.addRect(rect)
            ctx.fillPath(using: .evenOdd)
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
            ctx.setLineWidth(1.5)
            ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
            if kind == .recording {
                for h in Handle.allCases {
                    let p = point(of: h)
                    let r = CGRect(x: p.x - handleSize / 2, y: p.y - handleSize / 2, width: handleSize, height: handleSize)
                    ctx.setFillColor(Theme.nsAccent.cgColor)
                    ctx.fillEllipse(in: r)
                    ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(1.5); ctx.strokeEllipse(in: r)
                }
            }
            drawLabel("\(Int(rect.width)) × \(Int(rect.height))", below: rect)
        } else {
            ctx.fill(bounds)
        }
        if rect.width <= 1 {
            let hint = kind == .recording
                ? t("Drag to select the area to record · ⏎ confirm · ⎋ cancel · 1–5 aspect ratio", "Arrastrá para elegir el área a grabar · ⏎ confirmar · ⎋ cancelar · 1–5 proporción")
                : t("Drag to capture an area · ⎋ cancel", "Arrastrá para capturar un área · ⎋ cancelar")
            drawCenteredPill(hint, at: CGPoint(x: bounds.midX, y: bounds.midY))
        }
    }

    private func drawLabel(_ s: String, below r: CGRect) {
        var y = r.minY - 30
        if y < 8 { y = r.maxY + 8 }
        drawCenteredPill(s, at: CGPoint(x: r.midX, y: y + 11))
    }

    private func drawCenteredPill(_ s: String, at c: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white]
        let size = (s as NSString).size(withAttributes: attrs)
        let pill = CGRect(x: c.x - size.width / 2 - 10, y: c.y - 11, width: size.width + 20, height: 22)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 11, yRadius: 11).fill()
        (s as NSString).draw(at: CGPoint(x: pill.minX + 10, y: pill.minY + (22 - size.height) / 2), withAttributes: attrs)
    }

    // MARK: Geometría

    private func point(of h: Handle) -> CGPoint {
        switch h {
        case .tl: return CGPoint(x: rect.minX, y: rect.maxY)
        case .t: return CGPoint(x: rect.midX, y: rect.maxY)
        case .tr: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .r: return CGPoint(x: rect.maxX, y: rect.midY)
        case .br: return CGPoint(x: rect.maxX, y: rect.minY)
        case .b: return CGPoint(x: rect.midX, y: rect.minY)
        case .bl: return CGPoint(x: rect.minX, y: rect.minY)
        case .l: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    private func handle(at p: CGPoint) -> Handle? {
        guard kind == .recording, rect.width > 1 else { return nil }
        return Handle.allCases.first { hypot(point(of: $0).x - p.x, point(of: $0).y - p.y) <= handleSize + 4 }
    }

    private func clamp(_ r: CGRect) -> CGRect {
        var o = r
        o.size.width = min(o.width, bounds.width); o.size.height = min(o.height, bounds.height)
        o.origin.x = max(bounds.minX, min(o.minX, bounds.maxX - o.width))
        o.origin.y = max(bounds.minY, min(o.minY, bounds.maxY - o.height))
        return o
    }

    private func applyAspect(_ a: CGFloat) {
        var r = rect
        let h = r.width / a
        r.origin.y += (r.height - h)
        r.size.height = h
        rect = clamp(r)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let h = handle(at: p) { drag = .resizing(h, rect); return }
        if kind == .recording, rect.contains(p), rect.width > 1 { drag = .moving(p, rect); return }
        drag = .creating(p)
        rect = .zero
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch drag {
        case .none: break
        case .creating(let start):
            var r = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
            if let a = aspect, r.width > 0 {
                let h = r.width / a
                if p.y < start.y { r.origin.y = start.y - h }
                r.size.height = h
            }
            rect = clamp(r)
        case .moving(let start, let original):
            rect = clamp(original.offsetBy(dx: p.x - start.x, dy: p.y - start.y))
        case .resizing(let h, let original):
            var minX = original.minX, maxX = original.maxX, minY = original.minY, maxY = original.maxY
            switch h {
            case .tl: minX = p.x; maxY = p.y
            case .t: maxY = p.y
            case .tr: maxX = p.x; maxY = p.y
            case .r: maxX = p.x
            case .br: maxX = p.x; minY = p.y
            case .b: minY = p.y
            case .bl: minX = p.x; minY = p.y
            case .l: minX = p.x
            }
            var r = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: max(minSize, abs(maxX - minX)), height: max(minSize, abs(maxY - minY)))
            if let a = aspect { r.size.height = r.width / a }
            rect = clamp(r)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { drag = .none }
        guard case .creating = drag else { return }
        if rect.width < 12 || rect.height < 12 { rect = .zero; return }
        if kind == .screenshot { onConfirm?(rect) }
    }

    // MARK: Teclado

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onCancel?()                                         // Esc
        case 36, 76: if rect.width > 10 { onConfirm?(rect) }         // Return
        default:
            switch event.charactersIgnoringModifiers {
            case "1": aspect = nil
            case "2": aspect = 16.0 / 9
            case "3": aspect = 4.0 / 3
            case "4": aspect = 1
            case "5": aspect = 9.0 / 16
            default: super.keyDown(with: event)
            }
        }
    }
}

/// Selección de área en todas las pantallas. Devuelve el rectángulo en coordenadas globales de AppKit.
public final class AreaSelectionController {
    public enum Kind { case recording, screenshot }

    private var windows: [OverlayWindow] = []
    private var views: [AreaSelectionView] = []
    private var continuation: CheckedContinuation<CGRect?, Never>?
    private var finished = false
    /// Para modo grabación: se llama al mover/redimensionar (rect global AppKit).
    public var onChange: ((CGRect) -> Void)?

    public init() {}

    @MainActor
    public func select(kind: Kind, initial: CGRect? = nil) async -> CGRect? {
        finished = false
        let level: NSWindow.Level = kind == .recording ? PikLevel.selection : PikLevel.top
        return await withCheckedContinuation { cont in
            continuation = cont
            for screen in NSScreen.screens {
                let w = OverlayWindow(screen: screen, level: level)
                let v = AreaSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size), kind: kind == .recording ? .recording : .screenshot)
                if let initial, screen.frame.intersects(initial) {
                    v.rect = initial.intersection(screen.frame).offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
                }
                let origin = screen.frame.origin
                v.onChange = { [weak self] r in
                    guard r.width > 1 else { return }
                    self?.onChange?(r.offsetBy(dx: origin.x, dy: origin.y))
                }
                v.onConfirm = { [weak self] r in self?.finish(r.offsetBy(dx: origin.x, dy: origin.y)) }
                v.onCancel = { [weak self] in self?.finish(nil) }
                w.contentView = v
                w.orderFrontRegardless()
                windows.append(w); views.append(v)
            }
            if kind == .screenshot { NSCursor.crosshair.push() }
            // El overlay bajo el mouse toma el teclado.
            if let key = windows.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? windows.first {
                NSApp.activate(ignoringOtherApps: true)
                key.makeKeyAndOrderFront(nil)
                key.makeFirstResponder(key.contentView)
            }
            self.kind = kind
        }
    }

    private var kind: Kind = .recording

    public func finish(_ rect: CGRect?) {
        guard !finished else { return }
        finished = true
        if kind == .screenshot { NSCursor.pop() }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll(); views.removeAll()
        continuation?.resume(returning: rect)
        continuation = nil
    }

    public func cancel() { finish(nil) }
}
