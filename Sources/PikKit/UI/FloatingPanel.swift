import AppKit
import SwiftUI

/// Panel flotante sin marco (barras de controles, burbuja de cámara, HUD, avisos…).
public final class FloatingPanel: NSPanel {
    public var allowsKey = false
    /// Cierra con Esc cuando es la ventana activa.
    public var onEscape: (() -> Void)?

    public init(size: CGSize = CGSize(width: 100, height: 100), level: NSWindow.Level = .floating,
                allowsKey: Bool = false, excludedFromCapture: Bool = false) {
        super.init(contentRect: CGRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.allowsKey = allowsKey
        isFloatingPanel = true      // ojo: esto fuerza el nivel .floating, por eso el nivel real va después
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = !allowsKey
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        if excludedFromCapture { sharingType = .none }
        animationBehavior = .none
    }

    /// Si está puesto, cada cambio de tamaño se corrige aquí mismo (en el mismo `setFrame`), así nunca se llega a
    /// dibujar el marco intermedio que SwiftUI deja con el borde de arriba fijo (eso se veía como un salto).
    var resizeAdjuster: ((_ proposed: NSRect, _ current: NSRect) -> NSRect?)?
    /// Solo para diagnóstico (`--probe-panel`).
    var onFrameSet: ((NSRect) -> Void)?

    private func adjusted(_ f: NSRect) -> NSRect {
        var r = f
        if f.size != frame.size, let adjust = resizeAdjuster, let a = adjust(f, frame) { r = a }
        onFrameSet?(r)
        return r
    }
    public override func setFrame(_ frameRect: NSRect, display flag: Bool) { super.setFrame(adjusted(frameRect), display: flag) }
    public override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
        super.setFrame(adjusted(frameRect), display: displayFlag, animate: false)
    }

    public override var canBecomeKey: Bool { allowsKey }
    public override var canBecomeMain: Bool { false }

    public override func cancelOperation(_ sender: Any?) {
        if let onEscape { onEscape() } else { super.cancelOperation(sender) }
    }

    /// Número de ventana de AppKit = CGWindowID (sirve para incluir/excluir en ScreenCaptureKit).
    public var captureID: Int { windowNumber }
}

/// Mide el tamaño del contenido SwiftUI para que el panel se ajuste solo.
private struct SizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct SizeReader: ViewModifier {
    let onChange: (CGSize) -> Void
    func body(content: Content) -> some View {
        content.background(GeometryReader { g in
            Color.clear.preference(key: SizeKey.self, value: g.size)
        })
        .onPreferenceChange(SizeKey.self) { onChange($0) }
    }
}

public extension View {
    func onSizeChange(_ f: @escaping (CGSize) -> Void) -> some View { modifier(SizeReader(onChange: f)) }
}

/// Contiene un panel + vista SwiftUI cuyo tamaño dicta el del panel.
///
/// SwiftUI redimensiona la ventana dejando fijo el borde de arriba (crece hacia abajo). Para que los menús
/// desplegables de una barra pegada al borde inferior crezcan hacia arriba, cada vez que cambia el tamaño
/// recolocamos el marco para que el borde "ancla" (abajo, arriba, centro…) quede donde estaba.
public final class PanelHost {
    public enum Anchor { case bottomCenter, topCenter, bottomLeading, topLeading, center }

    public let panel: FloatingPanel
    private var anchor: Anchor
    private var anchorFrame: CGRect = .zero      // último marco "estable" (o movido por el usuario)
    private var observers: [NSObjectProtocol] = []

    public init<Content: View>(level: NSWindow.Level = .floating, allowsKey: Bool = false,
                               excludedFromCapture: Bool = false, anchor: Anchor = .bottomCenter,
                               @ViewBuilder content: () -> Content) {
        self.anchor = anchor
        panel = FloatingPanel(level: level, allowsKey: allowsKey, excludedFromCapture: excludedFromCapture)
        let hosting = NSHostingView(rootView: AnyView(content()))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        let fit = hosting.fittingSize
        if fit.width > 1, fit.height > 1 { panel.setContentSize(fit) }
        anchorFrame = panel.frame
        panel.resizeAdjuster = { [weak self] proposed, _ in self?.anchored(size: proposed.size) }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.didResizeNotification, object: panel, queue: .main) { [weak self] _ in self?.reanchor() })
        observers.append(nc.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            guard let self, self.panel.frame.size == self.anchorFrame.size else { return }   // un cambio de tamaño lo maneja reanchor()
            self.anchorFrame = self.panel.frame
        })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    /// Marco con el tamaño pedido y el borde "ancla" donde estaba.
    private func anchored(size: CGSize) -> NSRect? {
        guard size.width > 1, size.height > 1 else { return nil }
        let old = anchorFrame
        var f = CGRect(origin: .zero, size: size)
        switch anchor {
        case .bottomCenter: f.origin = CGPoint(x: old.midX - size.width / 2, y: old.minY)
        case .topCenter: f.origin = CGPoint(x: old.midX - size.width / 2, y: old.maxY - size.height)
        case .bottomLeading: f.origin = CGPoint(x: old.minX, y: old.minY)
        case .topLeading: f.origin = CGPoint(x: old.minX, y: old.maxY - size.height)
        case .center: f.origin = CGPoint(x: old.midX - size.width / 2, y: old.midY - size.height / 2)
        }
        anchorFrame = f
        return f
    }

    /// Respaldo: si algo cambió el tamaño sin pasar por `setFrame` (no debería), se corrige igual.
    private func reanchor() {
        let size = panel.frame.size
        guard size != panel.frame.size || anchorFrame.size != size, let f = anchored(size: size) else { return }
        if f != panel.frame { panel.setFrame(f, display: true) }
    }

    public var size: CGSize { panel.frame.size }

    public func show(at origin: CGPoint? = nil, centeredOn screen: NSScreen? = nil, bottomInset: CGFloat = 0) {
        if let origin {
            panel.setFrameOrigin(origin)
        } else if let screen {
            let s = size
            let vf = screen.visibleFrame
            panel.setFrameOrigin(CGPoint(x: vf.midX - s.width / 2, y: vf.minY + bottomInset))
        }
        panel.orderFrontRegardless()
    }

    public func close() { panel.orderOut(nil) }
}
