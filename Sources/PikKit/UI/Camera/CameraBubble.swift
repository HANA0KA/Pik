import AppKit
import Combine
import CoreVideo
import IOSurface
import SwiftUI

/// Vista que muestra los fotogramas de la cámara (IOSurface directo a la capa: sin copias en CPU).
final class CameraLayerView: NSView {
    private var sinkID: UUID?
    private var current: CVPixelBuffer?
    var onHover: ((Bool) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspectFill
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    func attach() {
        guard sinkID == nil else { return }
        sinkID = CameraController.shared.addSink { [weak self] pb in self?.show(pb) }
        if let last = CameraController.shared.latestFrame { show(last) }
    }

    func detach() {
        if let id = sinkID { CameraController.shared.removeSink(id) }
        sinkID = nil
    }

    private func show(_ pb: CVPixelBuffer) {
        current = pb
        guard let surface = CVPixelBufferGetIOSurface(pb)?.takeUnretainedValue() else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = surface
        CATransaction.commit()
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
}

private struct CameraBubbleHost: NSViewRepresentable {
    let onHover: (Bool) -> Void
    let register: (CameraLayerView) -> Void
    func makeNSView(context: Context) -> CameraLayerView {
        let v = CameraLayerView(frame: .zero)
        v.onHover = onHover
        register(v)
        return v
    }
    func updateNSView(_ nsView: CameraLayerView, context: Context) {}
}

/// Aparece sobre la pantalla; se graba porque es una ventana más del escritorio.
public final class CameraBubbleController: ObservableObject {
    private var panel: FloatingPanel?
    private var layerView: CameraLayerView?
    private var controls: PanelHost?
    private var hoverCount = 0
    private var hideWork: DispatchWorkItem?
    private var moveObserver: NSObjectProtocol?
    private var snapWork: DispatchWorkItem?
    private var bag = Set<AnyCancellable>()
    @Published public private(set) var isFullScreen = false
    private var savedFrame: CGRect?
    private let prefs = Preferences.shared

    public var windowNumber: Int? { panel?.windowNumber }
    public var controlsWindowNumber: Int? { controls?.panel.windowNumber }
    public var isVisible: Bool { panel?.isVisible == true }
    public var frame: CGRect? { panel?.frame }
    public var onClosedByUser: (() -> Void)?

    public init() {}

    // MARK: Mostrar / ocultar

    public func show(on screen: NSScreen = ScreenGeometry.screenUnderMouse(), near area: CGRect? = nil) {
        if panel == nil { build(on: screen, near: area) }
        panel?.orderFrontRegardless()
        layerView?.attach()
        CameraController.shared.start(deviceID: prefs.cameraDeviceID)
        applySize(animated: false)
    }

    public func hide() {
        hideControlsNow()
        layerView?.detach()
        panel?.orderOut(nil)
        panel = nil; layerView = nil
        controls?.close(); controls = nil
        if let o = moveObserver { NotificationCenter.default.removeObserver(o) }
        moveObserver = nil
        isFullScreen = false
    }

    private func build(on screen: NSScreen, near area: CGRect?) {
        let size = bubbleSize()
        let p = FloatingPanel(size: size, level: PikLevel.bubble, allowsKey: false)
        p.isMovableByWindowBackground = true
        p.hasShadow = true
        let host = CameraBubbleHost(onHover: { [weak self] in self?.hover($0) }, register: { [weak self] v in self?.layerView = v })
        let hosting = NSHostingView(rootView: host)
        p.contentView = hosting
        panel = p
        applyShape()
        // Posición inicial: abajo a la izquierda del área grabada (o de la pantalla).
        let region = (area ?? screen.visibleFrame).intersection(screen.frame)
        p.setFrameOrigin(CGPoint(x: region.minX + 28, y: region.minY + 28 + (area == nil ? 0 : 0)))
        moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in
            self?.scheduleSnap()
        }
        prefs.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.applySize(animated: true); self?.applyShape() }
        }.store(in: &bag)
    }

    // MARK: Tamaño y forma

    private func bubbleSize() -> CGSize {
        let s = CGFloat(prefs.cameraSize)
        return CGSize(width: s, height: prefs.cameraShape == .circle ? s : s * 0.82)
    }

    private func applyShape() {
        guard let layer = layerView?.layer, let panel else { return }
        let size = isFullScreen ? panel.frame.size : bubbleSize()
        if isFullScreen { layer.cornerRadius = 0 }
        else { layer.cornerRadius = prefs.cameraShape == .circle ? size.width / 2 : 22 }
        layer.borderWidth = isFullScreen ? 0 : 3
        layer.borderColor = NSColor.white.withAlphaComponent(0.92).cgColor
        panel.hasShadow = !isFullScreen
    }

    private func applySize(animated: Bool) {
        guard let panel, !isFullScreen else { return }
        let size = bubbleSize()
        guard abs(panel.frame.width - size.width) > 0.5 || abs(panel.frame.height - size.height) > 0.5 else { applyShape(); return }
        var f = panel.frame
        // Crece desde el centro para que no "salte".
        f.origin.x -= (size.width - f.width) / 2
        f.origin.y -= (size.height - f.height) / 2
        f.size = size
        panel.setFrame(f, display: true, animate: animated)
        applyShape()
        repositionControls()
    }

    // MARK: Imán a bordes

    private func scheduleSnap() {
        guard !isFullScreen else { return }
        snapWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.snapToEdges() }
        snapWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: w)
        repositionControls()
    }

    private func snapToEdges() {
        guard let panel, NSEvent.pressedMouseButtons & 1 == 0, let screen = panel.screen ?? NSScreen.main else { return }
        let vf = screen.visibleFrame
        var f = panel.frame
        let margin: CGFloat = 24, threshold: CGFloat = 40
        if f.minX - vf.minX < threshold { f.origin.x = vf.minX + margin }
        if vf.maxX - f.maxX < threshold { f.origin.x = vf.maxX - f.width - margin }
        if f.minY - vf.minY < threshold { f.origin.y = vf.minY + margin }
        if vf.maxY - f.maxY < threshold { f.origin.y = vf.maxY - f.height - margin }
        // Nunca fuera de la pantalla.
        f.origin.x = max(vf.minX, min(f.origin.x, vf.maxX - f.width))
        f.origin.y = max(vf.minY, min(f.origin.y, vf.maxY - f.height))
        if f != panel.frame { panel.setFrame(f, display: true, animate: true) }
        repositionControls()
    }

    /// Lleva la burbuja dentro de un rectángulo (p. ej. el área que se va a grabar).
    public func keepInside(_ rect: CGRect) {
        guard let panel, !isFullScreen else { return }
        var f = panel.frame
        if rect.contains(f) { return }
        f.size.width = min(f.width, rect.width); f.size.height = min(f.height, rect.height)
        f.origin.x = max(rect.minX, min(f.origin.x, rect.maxX - f.width))
        f.origin.y = max(rect.minY, min(f.origin.y, rect.maxY - f.height))
        panel.setFrame(f, display: true, animate: true)
        repositionControls()
    }

    // MARK: Pantalla completa de cámara

    public func toggleFullScreen() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        if isFullScreen {
            isFullScreen = false
            if let saved = savedFrame { panel.setFrame(saved, display: true, animate: true) }
            applyShape()
        } else {
            savedFrame = panel.frame
            isFullScreen = true
            panel.setFrame(screen.frame, display: true, animate: true)
            panel.level = PikLevel.bubble
            applyShape()
        }
        repositionControls()
    }

    // MARK: Controles al pasar el mouse (ventana aparte, excluida de la grabación)

    private func hover(_ inside: Bool) {
        hoverCount += inside ? 1 : -1
        if inside { showControls() } else { scheduleHideControls() }
    }

    private func showControls() {
        hideWork?.cancel()
        if controls == nil {
            let host = PanelHost(level: PikLevel.controls, excludedFromCapture: true, anchor: .topCenter) {
                CameraHoverControls(
                    bubble: self,
                    onHover: { [weak self] inside in if inside { self?.hideWork?.cancel() } else { self?.scheduleHideControls() } })
            }
            controls = host
        }
        repositionControls()
        controls?.panel.orderFrontRegardless()
    }

    private func scheduleHideControls() {
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.hideControlsNow() }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: w)
    }

    private func hideControlsNow() { controls?.panel.orderOut(nil) }

    private func repositionControls() {
        guard let panel, let controls else { return }
        let cs = controls.size == .zero ? CGSize(width: 330, height: 56) : controls.size
        guard let screen = panel.screen ?? NSScreen.main else { return }
        var origin: CGPoint
        if isFullScreen {
            origin = CGPoint(x: screen.frame.midX - cs.width / 2, y: screen.frame.maxY - cs.height - 40)
        } else {
            origin = CGPoint(x: panel.frame.midX - cs.width / 2, y: panel.frame.minY - cs.height + 6)
            if origin.y < screen.visibleFrame.minY { origin.y = panel.frame.maxY - 6 }
            origin.x = max(screen.frame.minX + 6, min(origin.x, screen.frame.maxX - cs.width - 6))
        }
        controls.panel.setFrameOrigin(origin)
    }

    // MARK: Acciones de los controles

    fileprivate func closeCamera() {
        prefs.cameraEnabled = false
        hide()
        onClosedByUser?()
    }
}

private struct CameraHoverControls: View {
    @ObservedObject var bubble: CameraBubbleController
    @ObservedObject private var prefs = Preferences.shared
    let onHover: (Bool) -> Void

    var body: some View {
        HStack(spacing: 2) {
            if bubble.isFullScreen {
                Button { bubble.toggleFullScreen() } label: {
                    Label(t("Exit full-screen", "Salir de pantalla completa"), systemImage: "arrow.down.right.and.arrow.up.left")
                        .labelStyle(.titleAndIcon).font(.system(size: 12, weight: .medium)).padding(.horizontal, 10)
                }
                .buttonStyle(PillIconButtonStyle(size: 34))
            } else {
                ForEach([("S", 150.0), ("M", 220.0), ("L", 320.0)], id: \.0) { label, size in
                    Button { prefs.cameraSize = size } label: {
                        Text(label).font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(PillIconButtonStyle(selected: abs(prefs.cameraSize - size) < 20, size: 32))
                    .help(t("Reset camera to its default size", "Cambiar el tamaño de la cámara"))
                }
                divider
                Button { prefs.cameraShape = prefs.cameraShape == .circle ? .roundedSquare : .circle } label: {
                    Image(systemName: prefs.cameraShape == .circle ? "circle" : "square")
                }
                .buttonStyle(PillIconButtonStyle(size: 32)).help(t("Shape", "Forma"))
                Button { prefs.cameraEffect = prefs.cameraEffect == .blur ? .none : .blur } label: {
                    Image(systemName: "person.and.background.dotted")
                }
                .buttonStyle(PillIconButtonStyle(selected: prefs.cameraEffect != .none, size: 32)).help(t("Blurred background", "Fondo difuminado"))
                Button { prefs.cameraMirror.toggle() } label: { Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                    .buttonStyle(PillIconButtonStyle(selected: prefs.cameraMirror, size: 32)).help(t("Mirror video", "Espejar video"))
                divider
                Button { bubble.toggleFullScreen() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(PillIconButtonStyle(size: 32)).help(t("Expand camera to full screen", "Expandir cámara a pantalla completa"))
                Button { bubble.closeCamera() } label: { Image(systemName: "xmark") }
                    .buttonStyle(PillIconButtonStyle(size: 32)).help(t("Close and dock camera controls", "Apagar la cámara"))
            }
        }
        .environment(\.colorScheme, .dark)
        .padding(6)
        .background(Capsule().fill(Theme.barBackground.opacity(0.95)).overlay(Capsule().stroke(Theme.barStroke)))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .padding(14)
        .onHover(perform: onHover)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 18).padding(.horizontal, 3)
    }
}
